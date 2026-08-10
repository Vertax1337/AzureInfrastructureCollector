[CmdletBinding()]
param(
    [string]$TenantId,

    [string[]]$SubscriptionId,

    [string[]]$ResourceGroup,

    [string]$OutputPath = './Output',

    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$startedAt = Get-Date
$scriptRoot = $PSScriptRoot
$coreModulePath = Join-Path $scriptRoot 'Modules/Collector.Core.psm1'
$configPath = Join-Path $scriptRoot 'Config/collector.config.json'
$resourcesQueryPath = Join-Path $scriptRoot 'Queries/Resources.kql'
$resourceGroupsQueryPath = Join-Path $scriptRoot 'Queries/ResourceGroups.kql'

Import-Module $coreModulePath -Force -ErrorAction Stop

$config = Get-CollectorConfig -Path $configPath
$prerequisites = Test-CollectorPrerequisites -MinimumPowerShellVersion ([version]$config.requirements.minimumPowerShellVersion) -RequiredModules @($config.requirements.requiredModules)
$azureContext = Get-CollectorAzureContext -NonInteractive:$NonInteractive
$tenants = Get-CollectorTenants
$tenant = Select-CollectorTenant -Tenants $tenants -TenantId $TenantId -NonInteractive:$NonInteractive
$subscriptions = Get-CollectorSubscriptions -TenantId ([string]$tenant.Id)
$selectedSubscriptions = @(Select-CollectorSubscriptions -Subscriptions $subscriptions -SubscriptionId $SubscriptionId -NonInteractive:$NonInteractive)

if ($selectedSubscriptions.Count -eq 0) {
    throw 'No subscriptions selected.'
}

$azureContext = Set-CollectorAzureContext -TenantId ([string]$tenant.Id) -SubscriptionId ([string]$selectedSubscriptions[0].Id)
$tenantDisplayName = Get-CollectorTenantDisplayName -Tenant $tenant
$run = Initialize-CollectorExport -OutputPath $OutputPath -TenantDisplayName $tenantDisplayName -StartedAt $startedAt
$errors = [System.Collections.Generic.List[object]]::new()

Write-Host ''
Write-Host ("AzureInfrastructureCollector {0}" -f $config.collector.version)
Write-Host ("Tenant: {0}" -f $tenantDisplayName)
Write-Host ("Subscriptions: {0}" -f $selectedSubscriptions.Count)
Write-Host ("Export: {0}" -f $run.rootPath)
Write-Host ''

Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Collector {0} started." -f $config.collector.version)
Write-CollectorLog -Path $run.logPath -Level INFO -Message ("PowerShell {0}; modules: {1}" -f $prerequisites.powerShellVersion, (($prerequisites.modules | ForEach-Object { '{0} {1}' -f $_.name, $_.version }) -join ', '))
Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Tenant '{0}' ({1}); subscriptions: {2}" -f $tenantDisplayName, $tenant.Id, (($selectedSubscriptions.Id) -join ', '))

$subscriptionIds = @($selectedSubscriptions | ForEach-Object { [string]$_.Id })
$pageSize = [int]$config.resourceGraph.pageSize
$sensitivePattern = [string]$config.security.sensitivePropertyPattern
$jsonDepth = [int]$config.export.jsonDepth

$resourceGroups = @()
try {
    $resourceGroupsQuery = Get-Content -LiteralPath $resourceGroupsQueryPath -Raw -Encoding UTF8
    $resourceGroupRows = @(Invoke-CollectorResourceGraph -Query $resourceGroupsQuery -SubscriptionId $subscriptionIds -PageSize $pageSize)
    $resourceGroups = @(
        $resourceGroupRows |
            ConvertTo-CollectorResourceGroup -SensitivePropertyPattern $sensitivePattern |
            Sort-Object subscriptionId, name
    )
    Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Collected {0} resource groups." -f $resourceGroups.Count)
}
catch {
    $errorItem = [pscustomobject][ordered]@{
        module  = 'Core.ResourceGroups'
        message = $_.Exception.Message
    }
    $errors.Add($errorItem)
    Write-CollectorLog -Path $run.logPath -Level ERROR -Message ("Resource-group collection failed: {0}" -f $_.Exception.Message)
}

$resourceGroupFilter = @(Select-CollectorResourceGroups -ResourceGroups $resourceGroups -RequestedResourceGroup $ResourceGroup -NonInteractive:$NonInteractive)
if ($resourceGroupFilter.Count -gt 0) {
    $resourceGroups = @($resourceGroups | Where-Object { $resourceGroupFilter -contains $_.name })
    Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Resource-group filter active: {0}" -f ($resourceGroupFilter -join ', '))
}

$resources = @()
try {
    $resourcesQuery = Get-Content -LiteralPath $resourcesQueryPath -Raw -Encoding UTF8
    $resourceRows = @(Invoke-CollectorResourceGraph -Query $resourcesQuery -SubscriptionId $subscriptionIds -PageSize $pageSize)
    $resources = @(
        $resourceRows |
            ConvertTo-CollectorResource -SensitivePropertyPattern $sensitivePattern |
            Where-Object { $resourceGroupFilter.Count -eq 0 -or $resourceGroupFilter -contains $_.resourceGroup } |
            Sort-Object subscriptionId, type, resourceGroup, name, id
    )
    Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Collected {0} resources." -f $resources.Count)
}
catch {
    $errorItem = [pscustomobject][ordered]@{
        module  = 'Core.Resources'
        message = $_.Exception.Message
    }
    $errors.Add($errorItem)
    Write-CollectorLog -Path $run.logPath -Level ERROR -Message ("Resource collection failed: {0}" -f $_.Exception.Message)
}

Export-CollectorJson -InputObject @($resourceGroups) -Path (Join-Path $run.inventoryPath 'resourceGroups.json') -Depth $jsonDepth
Export-CollectorJson -InputObject @($resources) -Path (Join-Path $run.inventoryPath 'resources.json') -Depth $jsonDepth

$summary = New-CollectorSummary -Resources @($resources) -ResourceGroups @($resourceGroups) -Subscriptions @($selectedSubscriptions) -ResourceGroupFilter $resourceGroupFilter
Export-CollectorJson -InputObject $summary -Path (Join-Path $run.rootPath 'summary.json') -Depth $jsonDepth

$completedAt = Get-Date
$status = if ($errors.Count -eq 0) { 'Success' } elseif ($resources.Count -gt 0 -or $resourceGroups.Count -gt 0) { 'PartialSuccess' } else { 'Failed' }
$manifest = New-CollectorManifest -Config $config -Tenant $tenant -Subscriptions @($selectedSubscriptions) -AzureContext $azureContext -StartedAt $startedAt -CompletedAt $completedAt -Status $status -Summary $summary -Errors @($errors) -ResourceGroupFilter $resourceGroupFilter
Export-CollectorJson -InputObject $manifest -Path (Join-Path $run.rootPath 'manifest.json') -Depth $jsonDepth

Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Collector completed with status '{0}'. Resources: {1}; resource groups: {2}; errors: {3}." -f $status, $resources.Count, $resourceGroups.Count, $errors.Count)

Write-Host ("Status: {0}" -f $status)
Write-Host ("Resource Groups: {0}" -f $resourceGroups.Count)
Write-Host ("Resources: {0}" -f $resources.Count)
Write-Host ("Errors: {0}" -f $errors.Count)
Write-Host ("Export completed: {0}" -f $run.rootPath)

if ($status -eq 'Failed') {
    exit 1
}
