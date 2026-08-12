BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.Backup.psm1') -Force
    $topLevelQueryPath = Join-Path $PSScriptRoot '../../Queries/Backup.TopLevel.kql'
    $backupQueryPath = Join-Path $PSScriptRoot '../../Queries/Backup.Resources.kql'
}

Describe 'P6 Backup Resource Graph safety boundary' {
    It 'keeps Resources and RecoveryServicesResources in separate read-only queries' {
        $top = Get-Content $topLevelQueryPath -Raw
        $backup = Get-Content $backupQueryPath -Raw

        $top | Should -Match '(?im)^\s*Resources\s*$'
        $top | Should -Not -Match '(?im)^\s*RecoveryServicesResources\s*$'
        $backup | Should -Match '(?im)^\s*RecoveryServicesResources\s*$'
        $backup | Should -Not -Match '(?im)^\s*Resources\s*$'
        $top | Should -Not -Match '(?i)\|\s*union\b'
        $backup | Should -Not -Match '(?i)\|\s*union\b'
    }

    It 'excludes backup credential and CMK secret paths' {
        $top = Get-Content $topLevelQueryPath -Raw
        $backup = Get-Content $backupQueryPath -Raw
        ($top + "`n" + $backup) | Should -Not -Match '(?i)datasourceAuthCredentials|secretStoreResource|secretStoreResource\.value|keyUri|kekIdentity|identityDetails|connectionString|accessToken|sharedKey'
    }
}

Describe 'P6 Recovery Services normalization' {
    It 'links a vault, policy, protected VM and last recovery point by ARM IDs' {
        $vaultId = '/subscriptions/sub/resourceGroups/RG-BACKUP/providers/Microsoft.RecoveryServices/vaults/rsv01'
        $policyId = "$vaultId/backupPolicies/daily"
        $itemId = "$vaultId/backupFabrics/Azure/protectionContainers/IaasVMContainer;iaasvmcontainerv2;rg-vm;vm01/protectedItems/VM;iaasvmcontainerv2;rg-vm;vm01"
        $vmId = '/subscriptions/sub/resourceGroups/RG-VM/providers/Microsoft.Compute/virtualMachines/vm01'

        $top = [pscustomobject]@{
            id = $vaultId; name = 'rsv01'; type = 'microsoft.recoveryservices/vaults'; subscriptionId = 'sub'; resourceGroup = 'RG-BACKUP'; location = 'westeurope'; tags = $null
            skuName = 'RS0'; skuTier = 'Standard'; recoveryPublicNetworkAccess = 'Enabled'; recoveryStandardTierStorageRedundancy = 'GeoRedundant'
            recoveryCrossRegionRestore = 'Enabled'; recoveryCrossSubscriptionRestoreState = 'Enabled'; recoverySoftDeleteState = 'Enabled'
            recoverySoftDeleteRetentionDays = 14; recoveryEnhancedSecurityState = 'Enabled'; recoveryImmutabilityState = 'Unlocked'
        }
        $policy = [pscustomobject]@{
            id = $policyId; name = 'daily'; type = 'microsoft.recoveryservices/vaults/backuppolicies'; subscriptionId = 'sub'; resourceGroup = 'RG-BACKUP'
            recoveryBackupManagementType = 'AzureIaasVM'; recoveryProtectedItemsCount = 1; recoveryScheduleRunFrequency = 'Daily'; recoveryRetentionPolicyType = 'LongTermRetentionPolicy'
        }
        $item = [pscustomobject]@{
            id = $itemId; name = 'vm01'; type = 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems'; subscriptionId = 'sub'; resourceGroup = 'RG-BACKUP'
            recoveryFriendlyName = 'vm01'; recoverySourceResourceId = $vmId; recoveryPolicyId = $policyId; recoveryPolicyName = 'daily'; recoveryBackupManagementType = 'AzureIaasVM'
            recoveryWorkloadType = 'VM'; recoveryProtectionState = 'Protected'; recoveryLastRecoveryPoint = [datetime]'2026-08-12T12:34:56Z'
        }

        $result = ConvertTo-CollectorBackupInventory -TopLevelRows @($top) -BackupRows @($policy, $item)

        $result.summary.recoveryServicesVaults | Should -Be 1
        $result.summary.backupPolicies | Should -Be 1
        $result.summary.recoveryProtectedItems | Should -Be 1
        $result.backupPolicies[0].vaultId | Should -BeExactly $vaultId
        ($result.backupPolicies[0].dataSourceTypes -is [System.Array]) | Should -BeTrue
        @($result.backupPolicies[0].dataSourceTypes).Count | Should -Be 1
        $result.recoveryProtectedItems[0].lastRecoveryPoint | Should -BeExactly '2026-08-12T12:34:56.0000000Z'
        @($result.relationships | Where-Object { $_.sourceId -eq $itemId -and $_.relationship -eq 'ProtectsResource' -and $_.targetId -eq $vmId }).Count | Should -Be 1
        @($result.relationships | Where-Object { $_.sourceId -eq $itemId -and $_.relationship -eq 'UsesBackupPolicy' -and $_.targetId -eq $policyId }).Count | Should -Be 1
    }
}

Describe 'P6 Data Protection normalization' {
    It 'normalizes Backup Vault storage settings, policy and backup instance without credentials' {
        $vaultId = '/subscriptions/sub/resourceGroups/RG-BACKUP/providers/Microsoft.DataProtection/backupVaults/bv01'
        $policyId = "$vaultId/backupPolicies/policy01"
        $instanceId = "$vaultId/backupInstances/instance01"
        $storageId = '/subscriptions/sub/resourceGroups/RG-STO/providers/Microsoft.Storage/storageAccounts/sto01'

        $top = [pscustomobject]@{
            id = $vaultId; name = 'bv01'; type = 'microsoft.dataprotection/backupvaults'; subscriptionId = 'sub'; resourceGroup = 'RG-BACKUP'; location = 'westeurope'; tags = $null
            backupVaultStorageSettings = @([pscustomobject]@{ datastoreType = 'VaultStore'; type = 'GeoRedundant' })
            backupVaultSoftDeleteState = 'On'; backupVaultSoftDeleteRetentionDays = 14; backupVaultImmutabilityState = 'Unlocked'
            backupVaultCrossRegionRestoreState = 'Enabled'; backupVaultCrossSubscriptionRestoreState = 'Enabled'
        }
        $policy = [pscustomobject]@{
            id = $policyId; name = 'policy01'; type = 'microsoft.dataprotection/backupvaults/backuppolicies'; subscriptionId = 'sub'; resourceGroup = 'RG-BACKUP'
            dataProtectionDatasourceTypes = @('Microsoft.Storage/storageAccounts/blobServices'); dataProtectionPolicyObjectType = 'BackupPolicy'
        }
        $instance = [pscustomobject]@{
            id = $instanceId; name = 'instance01'; type = 'microsoft.dataprotection/backupvaults/backupinstances'; subscriptionId = 'sub'; resourceGroup = 'RG-BACKUP'
            dataProtectionFriendlyName = 'storage'; dataProtectionSourceResourceId = $storageId; dataProtectionSourceResourceLocation = 'westeurope'
            dataProtectionDatasourceType = 'Microsoft.Storage/storageAccounts/blobServices'; dataProtectionPolicyId = $policyId; dataProtectionPolicyName = 'policy01'
            dataProtectionProtectionState = 'ProtectionConfigured'; dataProtectionLastRecoveryPoint = [datetimeoffset]'2026-08-12T11:00:00+00:00'
            datasourceAuthCredentials = [pscustomobject]@{ secretStoreResource = [pscustomobject]@{ value = 'must-not-export' } }
        }

        $result = ConvertTo-CollectorBackupInventory -TopLevelRows @($top) -BackupRows @($policy, $instance)
        $vault = $result.backupVaults[0]
        $backupInstance = $result.dataProtectionBackupInstances[0]

        $result.summary.backupVaults | Should -Be 1
        $result.summary.dataProtectionBackupInstances | Should -Be 1
        $vault.storageSettings[0].redundancy | Should -BeExactly 'GeoRedundant'
        ($result.backupPolicies[0].dataSourceTypes -is [System.Array]) | Should -BeTrue
        @($result.backupPolicies[0].dataSourceTypes).Count | Should -Be 1
        $backupInstance.lastRecoveryPoint | Should -BeExactly '2026-08-12T11:00:00.0000000Z'
        @($backupInstance.PSObject.Properties.Name) | Should -Not -Contain 'datasourceAuthCredentials'
        @($result.relationships | Where-Object { $_.sourceId -eq $instanceId -and $_.relationship -eq 'ProtectsResource' -and $_.targetId -eq $storageId }).Count | Should -Be 1
    }

    It 'keeps all collections stable when no backup resources exist' {
        $result = ConvertTo-CollectorBackupInventory -TopLevelRows @() -BackupRows @()
        @($result.recoveryServicesVaults).Count | Should -Be 0
        @($result.backupVaults).Count | Should -Be 0
        @($result.backupPolicies).Count | Should -Be 0
        @($result.recoveryProtectedItems).Count | Should -Be 0
        @($result.dataProtectionBackupInstances).Count | Should -Be 0
        @($result.relationships).Count | Should -Be 0
    }
}
