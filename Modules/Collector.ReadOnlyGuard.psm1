Set-StrictMode -Version Latest

$script:ApprovedAzureCommands = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
@(
    'Connect-AzAccount',
    'Get-AzContext',
    'Get-AzTenant',
    'Get-AzSubscription',
    'Set-AzContext',
    'Search-AzGraph'
) | ForEach-Object { [void]$script:ApprovedAzureCommands.Add($_) }

$script:BlockedExecutionCommands = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
@(
    'Invoke-Expression', 'iex',
    'Invoke-Command',
    'Start-Process',
    'Start-Job',
    'Start-ThreadJob',
    'Invoke-RestMethod', 'irm',
    'Invoke-WebRequest', 'iwr',
    'curl', 'curl.exe',
    'wget', 'wget.exe',
    'az', 'az.cmd', 'az.exe'
) | ForEach-Object { [void]$script:BlockedExecutionCommands.Add($_) }

# Patterns are deliberately assembled from fragments so the guard can scan its own source
# without matching the policy definitions themselves.
$script:BlockedSourcePatterns = @(
    ('(?i)System\.Net\.Http\.' + 'HttpClient'),
    ('(?i)System\.Net\.' + 'WebRequest'),
    ('(?i)management\.' + 'azure\.com'),
    ('(?i)graph\.' + 'microsoft\.com'),
    ('(?i)vault\.' + 'azure\.net'),
    ('(?i)\.blob\.core\.' + 'windows\.net')
)

function New-ReadOnlyViolation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$File,
        [Parameter(Mandatory)] [string]$Code,
        [Parameter(Mandatory)] [string]$Message,
        [int]$Line = 0,
        [int]$Column = 0
    )

    [pscustomobject][ordered]@{
        file    = $File
        line    = $Line
        column  = $Column
        code    = $Code
        message = $Message
    }
}

function Get-CollectorReadOnlyScopeFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    $resolvedRoot = (Resolve-Path -LiteralPath $RepositoryRoot -ErrorAction Stop).Path

    return @(
        Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -ErrorAction Stop |
            Where-Object {
                $_.Extension -in @('.ps1', '.psm1') -and
                $_.FullName -notmatch '[\\/]\.git[\\/]' -and
                $_.FullName -notmatch '[\\/]Output[\\/]'
            } |
            Sort-Object FullName
    )
}

function Test-SetAzContextScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    $elements = @($CommandAst.CommandElements)
    for ($index = 0; $index -lt $elements.Count; $index++) {
        if ($elements[$index].Extent.Text -ieq '-Scope') {
            if (($index + 1) -ge $elements.Count) {
                return $false
            }

            $scopeText = $elements[$index + 1].Extent.Text.Trim("'\"")
            return $scopeText -ieq 'Process'
        }
    }

    return $false
}

function Test-CollectorReadOnlyCompliance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [switch]$ThrowOnFailure
    )

    $root = (Resolve-Path -LiteralPath $RepositoryRoot -ErrorAction Stop).Path
    $files = @(Get-CollectorReadOnlyScopeFiles -RepositoryRoot $root)
    $violations = [System.Collections.Generic.List[object]]::new()
    $observedAzureCommands = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($file in $files) {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName,
            [ref]$tokens,
            [ref]$parseErrors
        )

        foreach ($parseError in @($parseErrors)) {
            $relativePath = [IO.Path]::GetRelativePath($root, $file.FullName)
            $violations.Add((New-ReadOnlyViolation -File $relativePath -Code 'PARSE_ERROR' -Message $parseError.Message -Line $parseError.Extent.StartLineNumber -Column $parseError.Extent.StartColumnNumber))
        }

        $source = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        foreach ($pattern in $script:BlockedSourcePatterns) {
            if ($source -match $pattern) {
                $relativePath = [IO.Path]::GetRelativePath($root, $file.FullName)
                $violations.Add((New-ReadOnlyViolation -File $relativePath -Code 'DIRECT_AZURE_HTTP_OR_SDK' -Message "Direct Azure/HTTP SDK access matched a blocked pattern. Direct API access is fail-closed until explicitly reviewed."))
            }
        }

        $commandAsts = @(
            $ast.FindAll(
                {
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst]
                },
                $true
            )
        )

        foreach ($commandAst in $commandAsts) {
            $commandName = $commandAst.GetCommandName()
            $relativePath = [IO.Path]::GetRelativePath($root, $file.FullName)

            if ([string]::IsNullOrWhiteSpace($commandName)) {
                $violations.Add((New-ReadOnlyViolation -File $relativePath -Code 'DYNAMIC_COMMAND' -Message 'A dynamically resolved command was found. Dynamic command execution cannot be proven read-only and is blocked.' -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber))
                continue
            }

            if ($script:BlockedExecutionCommands.Contains($commandName)) {
                $violations.Add((New-ReadOnlyViolation -File $relativePath -Code 'BLOCKED_EXECUTION_PATH' -Message "Command '$commandName' is blocked by the fail-closed read-only policy." -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber))
                continue
            }

            if ($commandName -match '(?i)^[A-Za-z]+-Az') {
                [void]$observedAzureCommands.Add($commandName)

                if (-not $script:ApprovedAzureCommands.Contains($commandName)) {
                    $violations.Add((New-ReadOnlyViolation -File $relativePath -Code 'UNAPPROVED_AZURE_COMMAND' -Message "Azure command '$commandName' is not in the explicitly verified read-only allowlist." -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber))
                    continue
                }

                if ($commandName -ieq 'Set-AzContext' -and -not (Test-SetAzContextScope -CommandAst $commandAst)) {
                    $violations.Add((New-ReadOnlyViolation -File $relativePath -Code 'AZ_CONTEXT_SCOPE' -Message "Set-AzContext is allowed only with an explicit '-Scope Process' in this project." -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber))
                }
            }
        }
    }

    $verified = $violations.Count -eq 0
    $result = [pscustomobject][ordered]@{
        status                     = if ($verified) { 'READ-ONLY VERIFIED' } else { 'BLOCKED' }
        verified                   = $verified
        verifiedAt                 = (Get-Date).ToString('o')
        repositoryRoot             = $root
        filesScanned               = $files.Count
        approvedAzureCommandsFound = @($observedAzureCommands | Sort-Object)
        azureResourceMutations     = if ($verified) { 'NONE DETECTED' } else { 'NOT VERIFIED' }
        azureDataMutations         = if ($verified) { 'NONE DETECTED' } else { 'NOT VERIFIED' }
        controlPlaneWrites         = if ($verified) { 'NONE DETECTED' } else { 'NOT VERIFIED' }
        dataPlaneWrites            = if ($verified) { 'NONE DETECTED' } else { 'NOT VERIFIED' }
        localWrites                = 'Allowed for collector output, logs and local processing only'
        violations                 = @($violations)
    }

    if ($ThrowOnFailure -and -not $verified) {
        $details = ($violations | ForEach-Object { '{0}:{1}:{2} [{3}] {4}' -f $_.file, $_.line, $_.column, $_.code, $_.message }) -join [Environment]::NewLine
        throw "READ-ONLY VERIFICATION FAILED. Collector execution is blocked.$([Environment]::NewLine)$details"
    }

    return $result
}

Export-ModuleMember -Function @(
    'Get-CollectorReadOnlyScopeFiles',
    'Test-CollectorReadOnlyCompliance'
)
