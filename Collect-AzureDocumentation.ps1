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
$computeModulePath = Join-Path $scriptRoot 'Modules/Collector.Compute.psm1'
$avdModulePath = Join-Path $scriptRoot 'Modules/Collector.AVD.psm1'
$storageModulePath = Join-Path $scriptRoot 'Modules/Collector.Storage.psm1'
$backupModulePath = Join-Path $scriptRoot 'Modules/Collector.Backup.psm1'
$keyVaultModulePath = Join-Path $scriptRoot 'Modules/Collector.KeyVault.psm1'
$configPath = Join-Path $scriptRoot 'Config/collector.config.json'
$resourcesQueryPath = Join-Path $scriptRoot 'Queries/Resources.kql'
$resourceGroupsQueryPath = Join-Path $scriptRoot 'Queries/ResourceGroups.kql'
$networkQueryPath = Join-Path $scriptRoot 'Queries/Network.kql'
$computeQueryPath = Join-Path $scriptRoot 'Queries/Compute.kql'
$avdQueryPath = Join-Path $scriptRoot 'Queries/AVD.kql'
$avdSessionHostsQueryPath = Join-Path $scriptRoot 'Queries/AVD.SessionHosts.kql'
$storageQueryPath = Join-Path $scriptRoot 'Queries/Storage.kql'
$keyVaultQueryPath = Join-Path $scriptRoot 'Queries/KeyVault.kql'
$backupTopLevelQueryPath = Join-Path $scriptRoot 'Queries/Backup.TopLevel.kql'
$backupResourcesQueryPath = Join-Path $scriptRoot 'Queries/Backup.Resources.kql'

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
Import-Module $computeModulePath -Force -ErrorAction Stop
Import-Module $avdModulePath -Force -ErrorAction Stop
Import-Module $storageModulePath -Force -ErrorAction Stop
Import-Module $backupModulePath -Force -ErrorAction Stop
Import-Module $keyVaultModulePath -Force -ErrorAction Stop

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
$totalStages = 8

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

$computeInventory = ConvertTo-CollectorComputeInventory -Rows @()
Write-CollectorStage -Step 4 -Total $totalStages -Message 'Collecting P4 compute inventory from Azure Resource Graph...'
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Compute: waiting for Azure Resource Graph response...'
try {
    $computeQuery = Get-Content -LiteralPath $computeQueryPath -Raw -Encoding UTF8
    $computeRows = @(Invoke-CollectorResourceGraph -Query $computeQuery -SubscriptionId $subscriptionIds -PageSize $pageSize)
    $computeRows = @($computeRows | Where-Object { $resourceGroupFilter.Count -eq 0 -or $resourceGroupFilter -contains $_.resourceGroup })

    # Keep Resource Group casing aligned with the canonical Core inventory.
    foreach ($computeRow in $computeRows) {
        $canonicalResourceGroup = $resourceGroups |
            Where-Object {
                [string]$_.subscriptionId -eq [string]$computeRow.subscriptionId -and
                [string]$_.name -eq [string]$computeRow.resourceGroup
            } |
            Select-Object -First 1

        if ($canonicalResourceGroup) {
            $computeRow.resourceGroup = [string]$canonicalResourceGroup.name
        }
    }

    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status ("Compute: normalizing {0} resource rows and relationships..." -f $computeRows.Count)
    $computeInventory = ConvertTo-CollectorComputeInventory -Rows $computeRows
    $computeInventory = Protect-CollectorExportValue `
        -Value $computeInventory `
        -SensitivePropertyPattern $sensitivePattern `
        -SensitiveValuePatterns $sensitiveValuePatterns

    Write-CollectorLog -Path $run.logPath -Level INFO -Message ("P4 compute inventory collected. Source resources: {0}; VMs: {1}; managed disks: {2}; availability sets: {3}; relationships: {4}." -f $computeRows.Count, $computeInventory.summary.virtualMachines, $computeInventory.summary.managedDisks, $computeInventory.summary.availabilitySets, $computeInventory.summary.relationships)
    Write-Host ("[{0}]       Compute source resources: {1}" -f (Get-Date).ToString('HH:mm:ss'), $computeRows.Count)
    Write-Host ("[{0}]       VMs/Managed Disks/Availability Sets: {1}/{2}/{3}" -f (Get-Date).ToString('HH:mm:ss'), $computeInventory.summary.virtualMachines, $computeInventory.summary.managedDisks, $computeInventory.summary.availabilitySets)
    Write-Host ("[{0}]       NIC/OS Disk/Data Disk refs: {1}/{2}/{3}" -f (Get-Date).ToString('HH:mm:ss'), $computeInventory.summary.networkInterfaceReferences, $computeInventory.summary.osDiskReferences, $computeInventory.summary.dataDiskReferences)
    Write-Host ("[{0}]       Compute relationships: {1}" -f (Get-Date).ToString('HH:mm:ss'), $computeInventory.summary.relationships)
}
catch {
    $errorItem = [pscustomobject][ordered]@{
        module  = 'Compute.P4'
        message = $_.Exception.Message
    }
    $errors.Add($errorItem)
    Write-CollectorLog -Path $run.logPath -Level ERROR -Message ("P4 compute collection failed: {0}" -f $_.Exception.Message)
    Write-Warning ("P4 compute collection failed: {0}" -f $_.Exception.Message)
}
finally {
    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Completed
}

$avdInventory = ConvertTo-CollectorAvdInventory -Rows @()
Write-CollectorStage -Step 5 -Total $totalStages -Message 'Collecting P5 Azure Virtual Desktop inventory from Azure Resource Graph...'
try {
    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'AVD: querying top-level resources from Resources...'
    $avdQuery = Get-Content -LiteralPath $avdQueryPath -Raw -Encoding UTF8
    $avdTopLevelRows = @(Invoke-CollectorResourceGraph -Query $avdQuery -SubscriptionId $subscriptionIds -PageSize $pageSize)

    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'AVD: querying session hosts from DesktopVirtualizationResources...'
    $avdSessionHostsQuery = Get-Content -LiteralPath $avdSessionHostsQueryPath -Raw -Encoding UTF8
    $avdSessionHostRows = @(Invoke-CollectorResourceGraph -Query $avdSessionHostsQuery -SubscriptionId $subscriptionIds -PageSize $pageSize)

    $avdRows = @($avdTopLevelRows) + @($avdSessionHostRows)
    $avdRows = @($avdRows | Where-Object { $resourceGroupFilter.Count -eq 0 -or $resourceGroupFilter -contains $_.resourceGroup })

    # Session hosts are returned from DesktopVirtualizationResources while the
    # top-level AVD resources come from Resources. Canonicalize RG casing for both.
    foreach ($avdRow in $avdRows) {
        $canonicalResourceGroup = $resourceGroups |
            Where-Object {
                [string]$_.subscriptionId -eq [string]$avdRow.subscriptionId -and
                [string]$_.name -eq [string]$avdRow.resourceGroup
            } |
            Select-Object -First 1

        if ($canonicalResourceGroup) {
            $avdRow.resourceGroup = [string]$canonicalResourceGroup.name
        }
    }

    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status ("AVD: normalizing {0} resource rows and relationships..." -f $avdRows.Count)
    $avdInventory = ConvertTo-CollectorAvdInventory -Rows $avdRows
    $avdInventory = Protect-CollectorExportValue `
        -Value $avdInventory `
        -SensitivePropertyPattern $sensitivePattern `
        -SensitiveValuePatterns $sensitiveValuePatterns

    Write-CollectorLog -Path $run.logPath -Level INFO -Message ("P5 AVD inventory collected. Top-level resources: {0}; session hosts: {1}; combined source rows: {2}; workspaces: {3}; host pools: {4}; application groups: {5}; scaling plans: {6}; relationships: {7}." -f $avdTopLevelRows.Count, $avdSessionHostRows.Count, $avdRows.Count, $avdInventory.summary.workspaces, $avdInventory.summary.hostPools, $avdInventory.summary.applicationGroups, $avdInventory.summary.scalingPlans, $avdInventory.summary.relationships)
    Write-Host ("[{0}]       AVD source resources: {1} top-level + {2} session hosts = {3}" -f (Get-Date).ToString('HH:mm:ss'), $avdTopLevelRows.Count, $avdSessionHostRows.Count, $avdRows.Count)
    Write-Host ("[{0}]       Workspaces/Host Pools/Application Groups: {1}/{2}/{3}" -f (Get-Date).ToString('HH:mm:ss'), $avdInventory.summary.workspaces, $avdInventory.summary.hostPools, $avdInventory.summary.applicationGroups)
    Write-Host ("[{0}]       Session Hosts/Scaling Plans: {1}/{2}" -f (Get-Date).ToString('HH:mm:ss'), $avdInventory.summary.sessionHosts, $avdInventory.summary.scalingPlans)
    Write-Host ("[{0}]       Session Host VM refs: {1}" -f (Get-Date).ToString('HH:mm:ss'), $avdInventory.summary.sessionHostVmReferences)
    Write-Host ("[{0}]       AVD relationships: {1}" -f (Get-Date).ToString('HH:mm:ss'), $avdInventory.summary.relationships)
}
catch {
    $errorItem = [pscustomobject][ordered]@{
        module  = 'AVD.P5'
        message = $_.Exception.Message
    }
    $errors.Add($errorItem)
    Write-CollectorLog -Path $run.logPath -Level ERROR -Message ("P5 AVD collection failed: {0}" -f $_.Exception.Message)
    Write-Warning ("P5 AVD collection failed: {0}" -f $_.Exception.Message)
}
finally {
    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Completed
}

$storageInventory = ConvertTo-CollectorStorageInventory -Rows @()
$backupInventory = ConvertTo-CollectorBackupInventory -TopLevelRows @() -BackupRows @()
$keyVaultInventory = ConvertTo-CollectorKeyVaultInventory -Rows @()
Write-CollectorStage -Step 6 -Total $totalStages -Message 'Collecting P6 Storage / Backup / Key Vault inventory from Azure Resource Graph...'

try {
    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'P6 Storage: querying Resources...'
    $storageQuery = Get-Content -LiteralPath $storageQueryPath -Raw -Encoding UTF8
    $storageRows = @(Invoke-CollectorResourceGraph -Query $storageQuery -SubscriptionId $subscriptionIds -PageSize $pageSize)
    $storageRows = @($storageRows | Where-Object { $resourceGroupFilter.Count -eq 0 -or $resourceGroupFilter -contains $_.resourceGroup })
    foreach ($storageRow in $storageRows) {
        $canonicalResourceGroup = $resourceGroups | Where-Object { [string]$_.subscriptionId -eq [string]$storageRow.subscriptionId -and [string]$_.name -eq [string]$storageRow.resourceGroup } | Select-Object -First 1
        if ($canonicalResourceGroup) { $storageRow.resourceGroup = [string]$canonicalResourceGroup.name }
    }
    $storageInventory = ConvertTo-CollectorStorageInventory -Rows $storageRows
    $storageInventory = Protect-CollectorExportValue -Value $storageInventory -SensitivePropertyPattern $sensitivePattern -SensitiveValuePatterns $sensitiveValuePatterns
    Write-CollectorLog -Path $run.logPath -Level INFO -Message ("P6 Storage collected. Accounts: {0}; relationships: {1}." -f $storageInventory.summary.storageAccounts, $storageInventory.summary.relationships)
    Write-Host ("[{0}]       Storage Accounts: {1}; relationships: {2}" -f (Get-Date).ToString('HH:mm:ss'), $storageInventory.summary.storageAccounts, $storageInventory.summary.relationships)
}
catch {
    $errors.Add([pscustomobject][ordered]@{ module = 'Storage.P6'; message = $_.Exception.Message })
    Write-CollectorLog -Path $run.logPath -Level ERROR -Message ("P6 Storage collection failed: {0}" -f $_.Exception.Message)
    Write-Warning ("P6 Storage collection failed: {0}" -f $_.Exception.Message)
}

try {
    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'P6 Key Vault: querying Resources...'
    $keyVaultQuery = Get-Content -LiteralPath $keyVaultQueryPath -Raw -Encoding UTF8
    $keyVaultRows = @(Invoke-CollectorResourceGraph -Query $keyVaultQuery -SubscriptionId $subscriptionIds -PageSize $pageSize)
    $keyVaultRows = @($keyVaultRows | Where-Object { $resourceGroupFilter.Count -eq 0 -or $resourceGroupFilter -contains $_.resourceGroup })
    foreach ($keyVaultRow in $keyVaultRows) {
        $canonicalResourceGroup = $resourceGroups | Where-Object { [string]$_.subscriptionId -eq [string]$keyVaultRow.subscriptionId -and [string]$_.name -eq [string]$keyVaultRow.resourceGroup } | Select-Object -First 1
        if ($canonicalResourceGroup) { $keyVaultRow.resourceGroup = [string]$canonicalResourceGroup.name }
    }
    $keyVaultInventory = ConvertTo-CollectorKeyVaultInventory -Rows $keyVaultRows
    $keyVaultInventory = Protect-CollectorExportValue -Value $keyVaultInventory -SensitivePropertyPattern $sensitivePattern -SensitiveValuePatterns $sensitiveValuePatterns
    Write-CollectorLog -Path $run.logPath -Level INFO -Message ("P6 Key Vault collected. Vaults: {0}; relationships: {1}." -f $keyVaultInventory.summary.keyVaults, $keyVaultInventory.summary.relationships)
    Write-Host ("[{0}]       Key Vaults: {1}; relationships: {2}" -f (Get-Date).ToString('HH:mm:ss'), $keyVaultInventory.summary.keyVaults, $keyVaultInventory.summary.relationships)
}
catch {
    $errors.Add([pscustomobject][ordered]@{ module = 'KeyVault.P6'; message = $_.Exception.Message })
    Write-CollectorLog -Path $run.logPath -Level ERROR -Message ("P6 Key Vault collection failed: {0}" -f $_.Exception.Message)
    Write-Warning ("P6 Key Vault collection failed: {0}" -f $_.Exception.Message)
}

try {
    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'P6 Backup: querying vaults from Resources...'
    $backupTopLevelQuery = Get-Content -LiteralPath $backupTopLevelQueryPath -Raw -Encoding UTF8
    $backupTopLevelRows = @(Invoke-CollectorResourceGraph -Query $backupTopLevelQuery -SubscriptionId $subscriptionIds -PageSize $pageSize)

    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'P6 Backup: querying policies and protected items from RecoveryServicesResources...'
    $backupResourcesQuery = Get-Content -LiteralPath $backupResourcesQueryPath -Raw -Encoding UTF8
    $backupRows = @(Invoke-CollectorResourceGraph -Query $backupResourcesQuery -SubscriptionId $subscriptionIds -PageSize $pageSize)

    $backupTopLevelRows = @($backupTopLevelRows | Where-Object { $resourceGroupFilter.Count -eq 0 -or $resourceGroupFilter -contains $_.resourceGroup })
    $backupRows = @($backupRows | Where-Object { $resourceGroupFilter.Count -eq 0 -or $resourceGroupFilter -contains $_.resourceGroup })
    foreach ($backupRow in @($backupTopLevelRows) + @($backupRows)) {
        $canonicalResourceGroup = $resourceGroups | Where-Object { [string]$_.subscriptionId -eq [string]$backupRow.subscriptionId -and [string]$_.name -eq [string]$backupRow.resourceGroup } | Select-Object -First 1
        if ($canonicalResourceGroup) { $backupRow.resourceGroup = [string]$canonicalResourceGroup.name }
    }
    $backupInventory = ConvertTo-CollectorBackupInventory -TopLevelRows $backupTopLevelRows -BackupRows $backupRows
    $backupInventory = Protect-CollectorExportValue -Value $backupInventory -SensitivePropertyPattern $sensitivePattern -SensitiveValuePatterns $sensitiveValuePatterns
    Write-CollectorLog -Path $run.logPath -Level INFO -Message ("P6 Backup collected. Recovery Services vaults: {0}; Backup Vaults: {1}; policies: {2}; Recovery protected items: {3}; Data Protection instances: {4}; relationships: {5}." -f $backupInventory.summary.recoveryServicesVaults, $backupInventory.summary.backupVaults, $backupInventory.summary.backupPolicies, $backupInventory.summary.recoveryProtectedItems, $backupInventory.summary.dataProtectionBackupInstances, $backupInventory.summary.relationships)
    Write-Host ("[{0}]       Recovery Services/Backup Vaults: {1}/{2}" -f (Get-Date).ToString('HH:mm:ss'), $backupInventory.summary.recoveryServicesVaults, $backupInventory.summary.backupVaults)
    Write-Host ("[{0}]       Backup Policies/Protected Items/Backup Instances: {1}/{2}/{3}" -f (Get-Date).ToString('HH:mm:ss'), $backupInventory.summary.backupPolicies, $backupInventory.summary.recoveryProtectedItems, $backupInventory.summary.dataProtectionBackupInstances)
    Write-Host ("[{0}]       Backup relationships: {1}" -f (Get-Date).ToString('HH:mm:ss'), $backupInventory.summary.relationships)
}
catch {
    $errors.Add([pscustomobject][ordered]@{ module = 'Backup.P6'; message = $_.Exception.Message })
    Write-CollectorLog -Path $run.logPath -Level ERROR -Message ("P6 Backup collection failed: {0}" -f $_.Exception.Message)
    Write-Warning ("P6 Backup collection failed: {0}" -f $_.Exception.Message)
}
finally {
    Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Completed
}

Write-CollectorStage -Step 7 -Total $totalStages -Message 'Writing normalized inventory JSON files...'
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Writing resourceGroups.json...'
Export-CollectorJson -InputObject @($resourceGroups) -Path (Join-Path $run.inventoryPath 'resourceGroups.json') -Depth $jsonDepth
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Writing resources.json...'
Export-CollectorJson -InputObject @($resources) -Path (Join-Path $run.inventoryPath 'resources.json') -Depth $jsonDepth
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Writing network.json...'
Export-CollectorJson -InputObject $networkInventory -Path (Join-Path $run.inventoryPath 'network.json') -Depth $jsonDepth
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Writing compute.json...'
Export-CollectorJson -InputObject $computeInventory -Path (Join-Path $run.inventoryPath 'compute.json') -Depth $jsonDepth
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Writing avd.json...'
Export-CollectorJson -InputObject $avdInventory -Path (Join-Path $run.inventoryPath 'avd.json') -Depth $jsonDepth
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Writing storage.json...'
Export-CollectorJson -InputObject $storageInventory -Path (Join-Path $run.inventoryPath 'storage.json') -Depth $jsonDepth
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Writing backup.json...'
Export-CollectorJson -InputObject $backupInventory -Path (Join-Path $run.inventoryPath 'backup.json') -Depth $jsonDepth
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Writing keyVault.json...'
Export-CollectorJson -InputObject $keyVaultInventory -Path (Join-Path $run.inventoryPath 'keyVault.json') -Depth $jsonDepth
Write-Host ("[{0}]       Inventory JSON written (resourceGroups.json, resources.json, network.json, compute.json, avd.json, storage.json, backup.json, keyVault.json)." -f (Get-Date).ToString('HH:mm:ss'))

Write-CollectorStage -Step 8 -Total $totalStages -Message 'Building summary and manifest...'
Write-Progress -Id 1 -Activity 'AzureInfrastructureCollector' -Status 'Building summary.json...'
$summary = New-CollectorSummary -Resources @($resources) -ResourceGroups @($resourceGroups) -Subscriptions @($selectedSubscriptions) -ResourceGroupFilter $resourceGroupFilter
Add-Member -InputObject $summary -NotePropertyName network -NotePropertyValue $networkInventory.summary -Force
Add-Member -InputObject $summary -NotePropertyName compute -NotePropertyValue $computeInventory.summary -Force
Add-Member -InputObject $summary -NotePropertyName avd -NotePropertyValue $avdInventory.summary -Force
Add-Member -InputObject $summary -NotePropertyName storage -NotePropertyValue $storageInventory.summary -Force
Add-Member -InputObject $summary -NotePropertyName backup -NotePropertyValue $backupInventory.summary -Force
Add-Member -InputObject $summary -NotePropertyName keyVault -NotePropertyValue $keyVaultInventory.summary -Force
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
Write-CollectorLog -Path $run.logPath -Level INFO -Message ("Collector completed with status '{0}'. Resources: {1}; resource groups: {2}; network relationships: {3}; compute relationships: {4}; AVD relationships: {5}; storage relationships: {6}; backup relationships: {7}; Key Vault relationships: {8}; errors: {9}; duration: {10}." -f $status, $resources.Count, $resourceGroups.Count, $networkInventory.summary.relationships, $computeInventory.summary.relationships, $avdInventory.summary.relationships, $storageInventory.summary.relationships, $backupInventory.summary.relationships, $keyVaultInventory.summary.relationships, $errors.Count, $duration)

Write-Host ''
Write-Host 'COLLECTION COMPLETE'
Write-Host ("Status: {0}" -f $status)
Write-Host ("Resource Groups: {0}" -f $resourceGroups.Count)
Write-Host ("Resources: {0}" -f $resources.Count)
Write-Host ("Network Relationships: {0}" -f $networkInventory.summary.relationships)
Write-Host ("Compute Relationships: {0}" -f $computeInventory.summary.relationships)
Write-Host ("AVD Relationships: {0}" -f $avdInventory.summary.relationships)
Write-Host ("Storage Relationships: {0}" -f $storageInventory.summary.relationships)
Write-Host ("Backup Relationships: {0}" -f $backupInventory.summary.relationships)
Write-Host ("Key Vault Relationships: {0}" -f $keyVaultInventory.summary.relationships)
Write-Host ("Errors: {0}" -f $errors.Count)
Write-Host ("Duration: {0:mm\:ss}" -f $duration)
Write-Host ("Export completed: {0}" -f $run.rootPath)

if ($status -eq 'Failed') {
    exit 1
}
