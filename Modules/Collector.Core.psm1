Set-StrictMode -Version Latest

$script:DefaultSensitivePropertyPattern = '(?i)(secret|password|passwd|token|credential|connectionstring|connection_string|sastoken|accesskey|accountkey|privatekey|clientsecret|apikey)'

function Get-CollectorConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Collector configuration not found: $Path"
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    }
    catch {
        throw "Collector configuration is invalid JSON: $Path. $($_.Exception.Message)"
    }
}

function Test-CollectorPrerequisites {
    [CmdletBinding()]
    param(
        [version]$MinimumPowerShellVersion = [version]'7.2.0',
        [string[]]$RequiredModules = @('Az.Accounts', 'Az.ResourceGraph')
    )

    if ($PSVersionTable.PSVersion -lt $MinimumPowerShellVersion) {
        throw "PowerShell $MinimumPowerShellVersion or newer is required. Current version: $($PSVersionTable.PSVersion)."
    }

    $modules = foreach ($moduleName in $RequiredModules) {
        $module = Get-Module -ListAvailable -Name $moduleName |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if (-not $module) {
            throw "Required PowerShell module '$moduleName' is not installed."
        }

        Import-Module $moduleName -ErrorAction Stop

        [pscustomobject][ordered]@{
            name    = $moduleName
            version = $module.Version.ToString()
        }
    }

    [pscustomobject][ordered]@{
        powerShellVersion = $PSVersionTable.PSVersion.ToString()
        modules           = @($modules)
    }
}

function Get-CollectorAzureContext {
    [CmdletBinding()]
    param(
        [switch]$NonInteractive
    )

    $context = Get-AzContext -ErrorAction SilentlyContinue
    if ($context -and $context.Account -and $context.Account.Id) {
        return $context
    }

    if ($NonInteractive) {
        throw 'No Azure context is available. Authenticate before using -NonInteractive.'
    }

    Write-Host 'No active Azure context found. Starting interactive Azure login...'
    Connect-AzAccount -ErrorAction Stop | Out-Null

    $context = Get-AzContext -ErrorAction Stop
    if (-not $context -or -not $context.Account -or -not $context.Account.Id) {
        throw 'Azure authentication completed without a usable Azure context.'
    }

    return $context
}

function Get-CollectorTenants {
    [CmdletBinding()]
    param()

    try {
        return @(Get-AzTenant -ErrorAction Stop | Sort-Object Name, Id)
    }
    catch {
        throw "Unable to enumerate Azure tenants. Re-authenticate if the current context is expired. $($_.Exception.Message)"
    }
}

function Get-CollectorTenantDisplayName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Tenant
    )

    if ($Tenant.PSObject.Properties.Name -contains 'Name' -and -not [string]::IsNullOrWhiteSpace([string]$Tenant.Name)) {
        return [string]$Tenant.Name
    }

    return [string]$Tenant.Id
}

function Select-CollectorTenant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Tenants,

        [string]$TenantId,

        [switch]$NonInteractive
    )

    if ($Tenants.Count -eq 0) {
        throw 'No authorized Azure tenants were found.'
    }

    if ($TenantId) {
        $tenant = $Tenants | Where-Object { [string]$_.Id -eq $TenantId } | Select-Object -First 1
        if (-not $tenant) {
            throw "Tenant '$TenantId' is not available to the current account."
        }
        return $tenant
    }

    if ($NonInteractive) {
        throw '-TenantId is required in NonInteractive mode.'
    }

    if ($Tenants.Count -eq 1) {
        return $Tenants[0]
    }

    Write-Host ''
    Write-Host 'Available Azure tenants:'
    for ($index = 0; $index -lt $Tenants.Count; $index++) {
        $displayName = Get-CollectorTenantDisplayName -Tenant $Tenants[$index]
        Write-Host ("[{0}] {1} ({2})" -f ($index + 1), $displayName, $Tenants[$index].Id)
    }

    while ($true) {
        $selection = Read-Host 'Select tenant number'
        $selectionNumber = 0
        if ([int]::TryParse($selection, [ref]$selectionNumber) -and $selectionNumber -ge 1 -and $selectionNumber -le $Tenants.Count) {
            return $Tenants[$selectionNumber - 1]
        }
        Write-Warning 'Invalid tenant selection.'
    }
}

function Get-CollectorSubscriptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId
    )

    try {
        return @(Get-AzSubscription -TenantId $TenantId -ErrorAction Stop | Sort-Object Name, Id)
    }
    catch {
        throw "Unable to enumerate subscriptions for tenant '$TenantId'. $($_.Exception.Message)"
    }
}

function Select-CollectorSubscriptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Subscriptions,

        [string[]]$SubscriptionId,

        [switch]$NonInteractive
    )

    if ($Subscriptions.Count -eq 0) {
        throw 'No accessible subscriptions were found in the selected tenant.'
    }

    if ($SubscriptionId -and $SubscriptionId.Count -gt 0) {
        $selected = [System.Collections.Generic.List[object]]::new()
        foreach ($id in $SubscriptionId) {
            $match = $Subscriptions | Where-Object { [string]$_.Id -eq $id } | Select-Object -First 1
            if (-not $match) {
                throw "Subscription '$id' is not available in the selected tenant."
            }
            $selected.Add($match)
        }
        return @($selected)
    }

    if ($NonInteractive) {
        throw '-SubscriptionId is required in NonInteractive mode.'
    }

    $enabledSubscriptions = @($Subscriptions | Where-Object { [string]$_.State -eq 'Enabled' })
    if ($Subscriptions.Count -eq 1 -and $enabledSubscriptions.Count -eq 1) {
        return @($Subscriptions[0])
    }

    Write-Host ''
    Write-Host 'Available subscriptions:'
    for ($index = 0; $index -lt $Subscriptions.Count; $index++) {
        Write-Host ("[{0}] {1} ({2}) [{3}]" -f ($index + 1), $Subscriptions[$index].Name, $Subscriptions[$index].Id, $Subscriptions[$index].State)
    }
    Write-Host '[*] All enabled subscriptions'

    while ($true) {
        $selection = (Read-Host 'Select subscription number(s), comma-separated, or *').Trim()

        if ($selection -eq '*') {
            if ($enabledSubscriptions.Count -eq 0) {
                Write-Warning 'No enabled subscriptions are available.'
                continue
            }
            return @($enabledSubscriptions)
        }

        $indexes = @($selection -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($indexes.Count -eq 0) {
            Write-Warning 'No subscription selected.'
            continue
        }

        $selected = [System.Collections.Generic.List[object]]::new()
        $isValid = $true
        foreach ($item in $indexes) {
            $number = 0
            if (-not [int]::TryParse($item, [ref]$number) -or $number -lt 1 -or $number -gt $Subscriptions.Count) {
                $isValid = $false
                break
            }
            $candidate = $Subscriptions[$number - 1]
            if ($selected.Id -notcontains $candidate.Id) {
                $selected.Add($candidate)
            }
        }

        if ($isValid -and $selected.Count -gt 0) {
            return @($selected)
        }

        Write-Warning 'Invalid subscription selection.'
    }
}

function Select-CollectorResourceGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$ResourceGroups,

        [string[]]$RequestedResourceGroup,

        [switch]$NonInteractive
    )

    $availableNames = @($ResourceGroups | ForEach-Object { [string]$_.name } | Sort-Object -Unique)

    if ($RequestedResourceGroup -and $RequestedResourceGroup.Count -gt 0) {
        foreach ($name in $RequestedResourceGroup) {
            if ($availableNames -notcontains $name) {
                throw "Resource group '$name' was not found in the selected subscriptions."
            }
        }
        return @($RequestedResourceGroup | Sort-Object -Unique)
    }

    if ($NonInteractive -or $availableNames.Count -eq 0) {
        return @()
    }

    $filter = (Read-Host 'Optional: enter resource-group names comma-separated, or press Enter for all').Trim()
    if ([string]::IsNullOrWhiteSpace($filter)) {
        return @()
    }

    $requested = @($filter -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    foreach ($name in $requested) {
        if ($availableNames -notcontains $name) {
            throw "Resource group '$name' was not found in the selected subscriptions."
        }
    }

    return @($requested)
}

function Set-CollectorAzureContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$SubscriptionId
    )

    return Set-AzContext -Tenant $TenantId -Subscription $SubscriptionId -Scope Process -ErrorAction Stop
}

function ConvertTo-CollectorSafeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $invalidChars = [IO.Path]::GetInvalidFileNameChars()
    $safeValue = $Value
    foreach ($char in $invalidChars) {
        $safeValue = $safeValue.Replace([string]$char, '_')
    }
    $safeValue = ($safeValue -replace '\s+', '_').Trim('_')

    if ([string]::IsNullOrWhiteSpace($safeValue)) {
        return 'Tenant'
    }

    return $safeValue
}

function Initialize-CollectorExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string]$TenantDisplayName,

        [datetime]$StartedAt = (Get-Date)
    )

    $rootOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    if (-not (Test-Path -LiteralPath $rootOutputPath)) {
        New-Item -ItemType Directory -Path $rootOutputPath -Force | Out-Null
    }

    $safeTenantName = ConvertTo-CollectorSafeName -Value $TenantDisplayName
    $runFolderName = '{0}_{1}' -f $safeTenantName, $StartedAt.ToString('yyyy-MM-dd_HHmmss')
    $runPath = Join-Path $rootOutputPath $runFolderName
    $inventoryPath = Join-Path $runPath 'Inventory'
    $logsPath = Join-Path $runPath 'Logs'

    New-Item -ItemType Directory -Path $inventoryPath -Force | Out-Null
    New-Item -ItemType Directory -Path $logsPath -Force | Out-Null

    [pscustomobject][ordered]@{
        startedAt     = $StartedAt
        rootPath      = $runPath
        inventoryPath = $inventoryPath
        logsPath      = $logsPath
        logPath       = (Join-Path $logsPath 'collector.log')
    }
}

function Write-CollectorLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $timestamp = (Get-Date).ToString('o')
    $line = '[{0}] [{1}] {2}' -f $timestamp, $Level, $Message
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

function Invoke-CollectorResourceGraph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Query,

        [Parameter(Mandatory)]
        [string[]]$SubscriptionId,

        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $skipToken = $null

    do {
        $parameters = @{
            Query        = $Query
            Subscription = $SubscriptionId
            First        = $PageSize
            ErrorAction  = 'Stop'
        }

        if ($skipToken) {
            $parameters.SkipToken = $skipToken
        }

        $response = Search-AzGraph @parameters
        foreach ($item in $response) {
            $results.Add($item)
        }

        $skipToken = $response.SkipToken
    } while ($skipToken)

    return @($results)
}

function Protect-CollectorValue {
    [CmdletBinding()]
    param(
        $Value,

        [string]$SensitivePropertyPattern = $script:DefaultSensitivePropertyPattern
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $sanitized = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object)) {
            if ([string]$key -match $SensitivePropertyPattern) {
                $sanitized[[string]$key] = '[REDACTED]'
            }
            else {
                $sanitized[[string]$key] = Protect-CollectorValue -Value $Value[$key] -SensitivePropertyPattern $SensitivePropertyPattern
            }
        }
        return $sanitized
    }

    if ($Value -is [pscustomobject]) {
        $sanitized = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
            if ($property.Name -match $SensitivePropertyPattern) {
                $sanitized[$property.Name] = '[REDACTED]'
            }
            else {
                $sanitized[$property.Name] = Protect-CollectorValue -Value $property.Value -SensitivePropertyPattern $SensitivePropertyPattern
            }
        }
        return [pscustomobject]$sanitized
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { Protect-CollectorValue -Value $_ -SensitivePropertyPattern $SensitivePropertyPattern })
    }

    return $Value
}

function ConvertTo-CollectorTags {
    [CmdletBinding()]
    param(
        $Tags,

        [string]$SensitivePropertyPattern = $script:DefaultSensitivePropertyPattern
    )

    if ($null -eq $Tags) {
        return [ordered]@{}
    }

    $protected = Protect-CollectorValue -Value $Tags -SensitivePropertyPattern $SensitivePropertyPattern
    if ($protected -is [System.Collections.IDictionary]) {
        return $protected
    }

    $result = [ordered]@{}
    foreach ($property in @($protected.PSObject.Properties | Sort-Object Name)) {
        $result[$property.Name] = $property.Value
    }
    return $result
}

function ConvertTo-CollectorResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [string]$SensitivePropertyPattern = $script:DefaultSensitivePropertyPattern
    )

    process {
        [pscustomobject][ordered]@{
            id             = [string]$InputObject.id
            name           = [string]$InputObject.name
            type           = [string]$InputObject.type
            subscriptionId = [string]$InputObject.subscriptionId
            resourceGroup  = [string]$InputObject.resourceGroup
            location       = [string]$InputObject.location
            tags           = ConvertTo-CollectorTags -Tags $InputObject.tags -SensitivePropertyPattern $SensitivePropertyPattern
        }
    }
}

function ConvertTo-CollectorResourceGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [string]$SensitivePropertyPattern = $script:DefaultSensitivePropertyPattern
    )

    process {
        [pscustomobject][ordered]@{
            id             = [string]$InputObject.id
            name           = [string]$InputObject.name
            type           = [string]$InputObject.type
            subscriptionId = [string]$InputObject.subscriptionId
            location       = [string]$InputObject.location
            tags           = ConvertTo-CollectorTags -Tags $InputObject.tags -SensitivePropertyPattern $SensitivePropertyPattern
        }
    }
}

function Export-CollectorJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateRange(2, 100)]
        [int]$Depth = 20
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $json = ConvertTo-Json -InputObject $InputObject -Depth $Depth
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function New-CollectorSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Resources,

        [Parameter(Mandatory)]
        [object[]]$ResourceGroups,

        [Parameter(Mandatory)]
        [object[]]$Subscriptions,

        [string[]]$ResourceGroupFilter = @()
    )

    $resourceTypes = @(
        $Resources |
            Group-Object type |
            Sort-Object Name |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    type  = $_.Name
                    count = $_.Count
                }
            }
    )

    $locations = @(
        $Resources |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.location) } |
            Group-Object location |
            Sort-Object Name |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    location = $_.Name
                    count    = $_.Count
                }
            }
    )

    [pscustomobject][ordered]@{
        subscriptions       = $Subscriptions.Count
        resourceGroups      = $ResourceGroups.Count
        resources           = $Resources.Count
        resourceGroupFilter = @($ResourceGroupFilter)
        resourceTypes       = $resourceTypes
        locations           = $locations
    }
}

function New-CollectorManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        $Tenant,

        [Parameter(Mandatory)]
        [object[]]$Subscriptions,

        [Parameter(Mandatory)]
        $AzureContext,

        [Parameter(Mandatory)]
        [datetime]$StartedAt,

        [Parameter(Mandatory)]
        [datetime]$CompletedAt,

        [Parameter(Mandatory)]
        [ValidateSet('Success', 'PartialSuccess', 'Failed')]
        [string]$Status,

        [Parameter(Mandatory)]
        $Summary,

        [object[]]$Errors = @(),

        [string[]]$ResourceGroupFilter = @()
    )

    $subscriptionManifest = @(
        $Subscriptions |
            Sort-Object Name, Id |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    id    = [string]$_.Id
                    name  = [string]$_.Name
                    state = [string]$_.State
                }
            }
    )

    [pscustomobject][ordered]@{
        schemaVersion = [string]$Config.collector.schemaVersion
        collector     = [pscustomobject][ordered]@{
            name    = [string]$Config.collector.name
            version = [string]$Config.collector.version
        }
        execution     = [pscustomobject][ordered]@{
            startedAt   = $StartedAt.ToString('o')
            completedAt = $CompletedAt.ToString('o')
            account     = [string]$AzureContext.Account.Id
            status      = $Status
        }
        tenant        = [pscustomobject][ordered]@{
            id          = [string]$Tenant.Id
            displayName = Get-CollectorTenantDisplayName -Tenant $Tenant
        }
        subscriptions = $subscriptionManifest
        scope         = [pscustomobject][ordered]@{
            type                = if ($ResourceGroupFilter.Count -gt 0) { 'ResourceGroup' } else { 'Subscription' }
            resourceGroupFilter = @($ResourceGroupFilter)
        }
        result        = [pscustomobject][ordered]@{
            resources      = [int]$Summary.resources
            resourceGroups = [int]$Summary.resourceGroups
            errors         = $Errors.Count
        }
        errors        = @($Errors)
    }
}

Export-ModuleMember -Function @(
    'Get-CollectorConfig',
    'Test-CollectorPrerequisites',
    'Get-CollectorAzureContext',
    'Get-CollectorTenants',
    'Get-CollectorTenantDisplayName',
    'Select-CollectorTenant',
    'Get-CollectorSubscriptions',
    'Select-CollectorSubscriptions',
    'Select-CollectorResourceGroups',
    'Set-CollectorAzureContext',
    'ConvertTo-CollectorSafeName',
    'Initialize-CollectorExport',
    'Write-CollectorLog',
    'Invoke-CollectorResourceGraph',
    'Protect-CollectorValue',
    'ConvertTo-CollectorTags',
    'ConvertTo-CollectorResource',
    'ConvertTo-CollectorResourceGroup',
    'Export-CollectorJson',
    'New-CollectorSummary',
    'New-CollectorManifest'
)
