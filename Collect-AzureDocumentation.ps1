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
$readOnlyGuardModulePath = Join-Path $scriptRoot 'Modules/Collector.ReadOnlyGuard.psm1'
$coreModulePath = Join-Path $scriptRoot 'Modules/Collector.Core.psm1'
$exportSecurityModulePath = Join-Path $scriptRoot 'Modules/Collector.ExportSecurity.psm1'
$networkModulePath = Join-Path $scriptRoot 'Modules/Collector.Network.psm1'
$configPath = Join-Path $scriptRoot 'Config/collector.config.json'
$resourcesQueryPath = Join-Path $scriptRoot 'Queries/Resources.kql'
$resourceGroupsQueryPath = Join-Path $scriptRoot 'Queries/ResourceGroups.kql'
$networkQueryPath = Join-Path $scriptRoot 'Queries/Network.kql'

function Write-CollectorStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 20)]
        [int]$Step,

        [Parameter(Mandatory)]
        [ValidateRange(1, 20)]
        [int]$Total,

        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host ("[{0}] [{1}/{2}] {3}" -f (Get-Date).ToString('HH:mm:ss'), $Step, $Total, $Message)
}

# Supreme safety rule: no Azure collection starts unless the current executable
# repository scope has passed the fail-closed read-only verification.
Import-Module $readOnlyGuardModulePath -Force -ErrorAction Stop
$readOnlyVerification = Test-CollectorReadOnlyCompliance -RepositoryRoot $scriptRoot -ThrowOnFailure

Write-Host ''
Write-Host 'READ-ONLY VERIFICATION'
Write-Host ("Status: {0}" -f $readOnlyVerification.status)
Write-Host ("Azure resource mutations: {0}" -f $readOnlyVerification.azureResourceMutations)
Write-Host ("Azure data mutations: {0}" -f $readOnlyVerification.azureDataMutations)
Write-Host ("Control-plane write operations: {0}" -f $readOnlyVerification.controlPlaneWrites)
Write-Host ("Data-plane write operations: {0}" -f $readOnlyVerification.dataPlaneWrites)
Write-Host ''

Import-Module $coreModulePath -Force -ErrorAction Stop
Import-Module $exportSecurityModulePath -Force -ErrorAction Stop
Import-Module $networkModulePath -Force -ErrorAction Stop

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

Write-Host ("AzureInfrastructureCollector {0}" -f $config.collector.version)
Write-Host ("Tenant: {0}" -f $tenantDisplayName)
Write-Host ("Subscriptions: {0}" -f $selectedSubscriptions.Count)
Write-Host ("Export: {0}" -f $run.rootPath)
Write-Host ''

Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Read-only gate: {0}; Azure resource/data/control-plane/data-plane writes: none detected." -f $readOnlyVerification.status)
Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Collector {0} started." -f $config.collector.version)
Write-CollectorLog -Path $run.logPath -Level INFO -Message ("PowerShell {0}; modules: {1}" -f $prerequisites.powerShellVersion, (($prerequisites.modules | ForEach-Object { '{0} {1}' -f $_.name, $_.version }) -join ', '))
Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Tenant '{0}' ({1}); subscriptions: {2}" -f $tenantDisplayName, $tenant.Id, (($selectedSubscriptions.Id) -join ', '))

$subscriptionIds = @($selectedSubscriptions | ForEach-Object { [string]$_.Id })
$pageSize = [int]$config.resourceGraph.pageSize
$sensitivePattern = [string]$config.security.sensitivePropertyPattern
$sensitiveValuePatterns = @($config.security.sensitiveValuePatterns | ForEach-Object { [string]$_ })
$jsonDepth = [int]$config.export.jsonDepth
$totalStages = 5

$publicReadOnlyVerification = New-CollectorPublicReadOnlyVerification -Verification $readOnlyVerification
$publicReadOnlyVerification = Protect-CollectorExportValue `
    -Value $publicReadOnlyVerification `
    -SensitivePropertyPattern $sensitivePattern `
    -SensitiveValuePatterns $sensitiveValuePatterns
Export-CollectorJson -InputObject $publicReadOnlyVerification -Path (Join-Path $run.rootPath 'readOnlyVerification.json') -Depth $jsonDepth

$resourceGroups = @()
Write-CollectorStage -Step 1 -Total $totalStages -Message 'Collecting Resource Groups from Azure Resource Graph...'
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Resource Groups: waiting for Azure Resource Graph response...'
try {
    $resourceGroupsQuery = Get-Content -LiteralPath $resourceGroupsQueryPath -Raw -Encoding UTF8
    $resourceGroupRows = @(Invoke-CollectorResourceGraph -Query $resourceGroupsQuery -SubscriptionId $subscriptionIds -PageSize $pageSize)
    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status ("Resource Groups: normalizing {0} rows..." -f $resourceGroupRows.Count)
    $resourceGroups = @(
        $resourceGroupRows |
            ConvertTo-CollectorResourceGroup -SensitivePropertyPattern $sensitivePattern |
            ForEach-Object {
                Protect-CollectorExportValue `
                    -Value $_ `
                    -SensitivePropertyPattern $sensitivePattern `
                    -SensitiveValuePatterns $sensitiveValuePatterns
            } |
            Sort-Object subscriptionId, name
    )
    Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Collected {0} resource groups." -f $resourceGroups.Count)
    Write-Host ("[{0}]       Resource Groups collected: {1}" -f (Get-Date).ToString('HH:mm:ss'), $resourceGroups.Count)
}
catch {
    $errorItem = [pscustomobject][ordered]@{
        module  = 'Core.ResourceGroups'
        message = $_.Exception.Message
    }
    $errors.Add($errorItem)
    Write-CollectorLog -Path $run.logPath -Level ERROR -Message ("Resource-group collection failed: {0}" -f $_.Exception.Message)
    Write-Warning ("Resource Group collection failed: {0}" -f $_.Exception.Message)
}
finally {
    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Completed
}

# Default collector behavior is full selected-subscription inventory. Resource-group
# filtering is opt-in via -ResourceGroup; the normal run must never pause on a hidden
# Read-Host prompt after Resource Group discovery.
if ($ResourceGroup -and $ResourceGroup.Count -gt 0) {
    $resourceGroupFilter = @(Select-CollectorResourceGroups -ResourceGroups $resourceGroups -RequestedResourceGroup $ResourceGroup -NonInteractive:$NonInteractive)
}
else {
    $resourceGroupFilter = @()
    Write-Host ("[{0}]       Resource Group scope: ALL ({1})" -f (Get-Date).ToString('HH:mm:ss'), $resourceGroups.Count)
    Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Resource-group scope: all discovered groups ({0}); no filter requested." -f $resourceGroups.Count)
}

if ($resourceGroupFilter.Count -gt 0) {
    $resourceGroups = @($resourceGroups | Where-Object { $resourceGroupFilter -contains $_.name })
    Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Resource-group filter active: {0}" -f ($resourceGroupFilter -join ', '))
    Write-Host ("[{0}]       Resource Group filter: {1}" -f (Get-Date).ToString('HH:mm:ss'), ($resourceGroupFilter -join ', '))
}

$resources = @()
Write-CollectorStage -Step 2 -Total $totalStages -Message 'Collecting Azure resources from Azure Resource Graph...'
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Resources: waiting for Azure Resource Graph response...'
try {
    $resourcesQuery = Get-Content -LiteralPath $resourcesQueryPath -Raw -Encoding UTF8
    $resourceRows = @(Invoke-CollectorResourceGraph -Query $resourcesQuery -SubscriptionId $subscriptionIds -PageSize $pageSize)
    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status ("Resources: normalizing {0} rows..." -f $resourceRows.Count)
    $resources = @(
        $resourceRows |
            ConvertTo-CollectorResource -SensitivePropertyPattern $sensitivePattern |
            ForEach-Object {
                Protect-CollectorExportValue `
                    -Value $_ `
                    -SensitivePropertyPattern $sensitivePattern `
                    -SensitiveValuePatterns $sensitiveValuePatterns
            } |
            Where-Object { $resourceGroupFilter.Count -eq 0 -or $resourceGroupFilter -contains $_.resourceGroup }
    )

    $resources = @(
        Resolve-CollectorResourceGroupReferences -Resources $resources -ResourceGroups $resourceGroups |
            Sort-Object subscriptionId, type, resourceGroup, name, id
    )

    Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Collected {0} resources; Resource Group references canonicalized against ResourceGroups inventory." -f $resources.Count)
    Write-Host ("[{0}]       Resources collected: {1}" -f (Get-Date).ToString('HH:mm:ss'), $resources.Count)
    Write-Host ("[{0}]       Resource Group references: CANONICALIZED" -f (Get-Date).ToString('HH:mm:ss'))
}
catch {
    $errorItem = [pscustomobject][ordered]@{
        module  = 'Core.Resources'
        message = $_.Exception.Message
    }
    $errors.Add($errorItem)
    Write-CollectorLog -Path $run.logPath -Level ERROR -Message ("Resource collection failed: {0}" -f $_.Exception.Message)
    Write-Warning ("Resource collection failed: {0}" -f $_.Exception.Message)
}
finally {
    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Completed
}

$networkInventory = ConvertTo-CollectorNetworkInventory -Rows @()
Write-CollectorStage -Step 3 -Total $totalStages -Message 'Collecting P3 network topology from Azure Resource Graph...'
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Network: waiting for Azure Resource Graph response...'
try {
    $networkQuery = Get-Content -LiteralPath $networkQueryPath -Raw -Encoding UTF8
    $networkRows = @(Invoke-CollectorResourceGraph -Query $networkQuery -SubscriptionId $subscriptionIds -PageSize $pageSize)
    $networkRows = @($networkRows | Where-Object { $resourceGroupFilter.Count -eq 0 -or $resourceGroupFilter -contains $_.resourceGroup })

    # Resource Graph can return different Resource Group casing between tables/resource types.
    # Canonicalize the local network rows against the already normalized RG inventory.
    foreach ($networkRow in $networkRows) {
        $canonicalResourceGroup = $resourceGroups |
            Where-Object {
                [string]$_.subscriptionId -eq [string]$networkRow.subscriptionId -and
                [string]$_.name -eq [string]$networkRow.resourceGroup
            } |
            Select-Object -First 1

        if ($canonicalResourceGroup) {
            $networkRow.resourceGroup = [string]$canonicalResourceGroup.name
        }
    }

    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status ("Network: normalizing {0} resource rows and relationships..." -f $networkRows.Count)
    $networkInventory = ConvertTo-CollectorNetworkInventory -Rows $networkRows
    $networkInventory = Protect-CollectorExportValue `
        -Value $networkInventory `
        -SensitivePropertyPattern $sensitivePattern `
        -SensitiveValuePatterns $sensitiveValuePatterns

    Write-CollectorLog -Path $run.logPath -Level INFO -Message ("P3 network inventory collected. Source resources: {0}; VNets: {1}; subnets: {2}; NICs: {3}; NSGs: {4}; connections: {5}; relationships: {6}." -f $networkRows.Count, $networkInventory.summary.virtualNetworks, $networkInventory.summary.subnets, $networkInventory.summary.networkInterfaces, $networkInventory.summary.networkSecurityGroups, $networkInventory.summary.connections, $networkInventory.summary.relationships)
    Write-Host ("[{0}]       Network source resources: {1}" -f (Get-Date).ToString('HH:mm:ss'), $networkRows.Count)
    Write-Host ("[{0}]       VNets/Subnets/Peerings: {1}/{2}/{3}" -f (Get-Date).ToString('HH:mm:ss'), $networkInventory.summary.virtualNetworks, $networkInventory.summary.subnets, $networkInventory.summary.peerings)
    Write-Host ("[{0}]       NICs/NSGs/Public IPs: {1}/{2}/{3}" -f (Get-Date).ToString('HH:mm:ss'), $networkInventory.summary.networkInterfaces, $networkInventory.summary.networkSecurityGroups, $networkInventory.summary.publicIpAddresses)
    Write-Host ("[{0}]       Network relationships: {1}" -f (Get-Date).ToString('HH:mm:ss'), $networkInventory.summary.relationships)
}
catch {
    $errorItem = [pscustomobject][ordered]@{
        module  = 'Network.P3a'
        message = $_.Exception.Message
    }
    $errors.Add($errorItem)
    Write-CollectorLog -Path $run.logPath -Level ERROR -Message ("P3 network collection failed: {0}" -f $_.Exception.Message)
    Write-Warning ("P3 network collection failed: {0}" -f $_.Exception.Message)
}
finally {
    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Completed
}

Write-CollectorStage -Step 4 -Total $totalStages -Message 'Writing normalized inventory JSON files...'
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Writing resourceGroups.json...'
Export-CollectorJson -InputObject @($resourceGroups) -Path (Join-Path $run.inventoryPath 'resourceGroups.json') -Depth $jsonDepth
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Writing resources.json...'
Export-CollectorJson -InputObject @($resources) -Path (Join-Path $run.inventoryPath 'resources.json') -Depth $jsonDepth
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Writing network.json...'
Export-CollectorJson -InputObject $networkInventory -Path (Join-Path $run.inventoryPath 'network.json') -Depth $jsonDepth
Write-Host ("[{0}]       Inventory JSON written (resourceGroups.json, resources.json, network.json)." -f (Get-Date).ToString('HH:mm:ss'))

Write-CollectorStage -Step 5 -Total $totalStages -Message 'Building summary and manifest...'
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Building summary.json...'
$summary = New-CollectorSummary -Resources @($resources) -ResourceGroups @($resourceGroups) -Subscriptions @($selectedSubscriptions) -ResourceGroupFilter $resourceGroupFilter
Add-Member -InputObject $summary -NotePropertyName network -NotePropertyValue $networkInventory.summary -Force
$summary = Protect-CollectorExportValue `
    -Value $summary `
    -SensitivePropertyPattern $sensitivePattern `
    -SensitiveValuePatterns $sensitiveValuePatterns
Export-CollectorJson -InputObject $summary -Path (Join-Path $run.rootPath 'summary.json') -Depth $jsonDepth

$completedAt = Get-Date
$status = if ($errors.Count -eq 0) { 'Success' } elseif ($resources.Count -gt 0 -or $resourceGroups.Count -gt 0) { 'PartialSuccess' } else { 'Failed' }
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Building manifest.json...'
$manifest = New-CollectorManifest -Config $config -Tenant $tenant -Subscriptions @($selectedSubscriptions) -AzureContext $azureContext -StartedAt $startedAt -CompletedAt $completedAt -Status $status -Summary $summary -Errors @($errors) -ResourceGroupFilter $resourceGroupFilter
$manifest = New-CollectorPublicManifest -Manifest $manifest
$manifest = Protect-CollectorExportValue `
    -Value $manifest `
    -SensitivePropertyPattern $sensitivePattern `
    -SensitiveValuePatterns $sensitiveValuePatterns
Export-CollectorJson -InputObject $manifest -Path (Join-Path $run.rootPath 'manifest.json') -Depth $jsonDepth
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Completed

$duration = $completedAt - $startedAt
Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Collector completed with status '{0}'. Resources: {1}; resource groups: {2}; network relationships: {3}; errors: {4}; duration: {5}." -f $status, $resources.Count, $resourceGroups.Count, $networkInventory.summary.relationships, $errors.Count, $duration)

Write-Host ''
Write-Host 'COLLECTION COMPLETE'
Write-Host ("Status: {0}" -f $status)
Write-Host ("Resource Groups: {0}" -f $resourceGroups.Count)
Write-Host ("Resources: {0}" -f $resources.Count)
Write-Host ("Network Relationships: {0}" -f $networkInventory.summary.relationships)
Write-Host ("Errors: {0}" -f $errors.Count)
Write-Host ("Duration: {0:mm\:ss}" -f $duration)
Write-Host ("Export completed: {0}" -f $run.rootPath)

if ($status -eq 'Failed') {
    exit 1
}
