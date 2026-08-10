BeforeAll {
    $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $repositoryRoot 'Modules/Collector.ReadOnlyGuard.psm1') -Force
}

Describe 'Collector read-only guard' {
    It 'accepts the current repository as read-only' {
        $result = Test-CollectorReadOnlyCompliance -RepositoryRoot $repositoryRoot

        $result.verified | Should -BeTrue
        $result.status | Should -Be 'READ-ONLY VERIFIED'
        @($result.violations).Count | Should -Be 0
    }

    It 'blocks an unapproved Azure cmdlet' {
        $testRoot = Join-Path $TestDrive 'UnapprovedAzureCommand'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $testRoot 'bad.ps1') -Encoding UTF8 -Value "Set-AzVM -Name 'vm01'"

        $result = Test-CollectorReadOnlyCompliance -RepositoryRoot $testRoot

        $result.verified | Should -BeFalse
        @($result.violations.code) | Should -Contain 'UNAPPROVED_AZURE_COMMAND'
    }

    It 'blocks dynamic command execution' {
        $testRoot = Join-Path $TestDrive 'DynamicCommand'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $testRoot 'bad.ps1') -Encoding UTF8 -Value '$command = Get-Item env:TEMP; & $command'

        $result = Test-CollectorReadOnlyCompliance -RepositoryRoot $testRoot

        $result.verified | Should -BeFalse
        @($result.violations.code) | Should -Contain 'DYNAMIC_COMMAND'
    }

    It 'blocks direct REST execution even when the method looks read-only' {
        $testRoot = Join-Path $TestDrive 'DirectRest'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $testRoot 'bad.ps1') -Encoding UTF8 -Value "Invoke-RestMethod -Method Get -Uri 'https://example.invalid/'"

        $result = Test-CollectorReadOnlyCompliance -RepositoryRoot $testRoot

        $result.verified | Should -BeFalse
        @($result.violations.code) | Should -Contain 'BLOCKED_EXECUTION_PATH'
    }

    It 'blocks self-elevation via Start-Process RunAs' {
        $testRoot = Join-Path $TestDrive 'Elevation'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $testRoot 'bad.ps1') -Encoding UTF8 -Value "Start-Process pwsh -Verb RunAs"

        $result = Test-CollectorReadOnlyCompliance -RepositoryRoot $testRoot

        $result.verified | Should -BeFalse
        @($result.violations.code) | Should -Contain 'BLOCKED_EXECUTION_PATH'
    }

    It 'allows local CurrentUser dependency installation code' {
        $testRoot = Join-Path $TestDrive 'CurrentUserDependency'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $testRoot 'good.ps1') -Encoding UTF8 -Value "Install-Module Az.Accounts -Repository PSGallery -Scope CurrentUser -Force"

        $result = Test-CollectorReadOnlyCompliance -RepositoryRoot $testRoot

        $result.verified | Should -BeTrue
        @($result.violations).Count | Should -Be 0
    }

    It 'requires Set-AzContext to use process scope' {
        $testRoot = Join-Path $TestDrive 'ContextScope'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $testRoot 'bad.ps1') -Encoding UTF8 -Value "Set-AzContext -Subscription '00000000-0000-0000-0000-000000000000'"

        $result = Test-CollectorReadOnlyCompliance -RepositoryRoot $testRoot

        $result.verified | Should -BeFalse
        @($result.violations.code) | Should -Contain 'AZ_CONTEXT_SCOPE'
    }

    It 'allows the explicitly verified Azure command set' {
        $testRoot = Join-Path $TestDrive 'ApprovedCommands'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        $source = @'
Get-AzContext
Connect-AzAccount
Get-AzTenant
Get-AzSubscription
Set-AzContext -Tenant '00000000-0000-0000-0000-000000000000' -Subscription '11111111-1111-1111-1111-111111111111' -Scope Process
Search-AzGraph -Query 'Resources | project id'
'@
        Set-Content -LiteralPath (Join-Path $testRoot 'good.ps1') -Encoding UTF8 -Value $source

        $result = Test-CollectorReadOnlyCompliance -RepositoryRoot $testRoot

        $result.verified | Should -BeTrue
        @($result.violations).Count | Should -Be 0
    }
}
