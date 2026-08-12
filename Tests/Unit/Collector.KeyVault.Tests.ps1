BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.KeyVault.psm1') -Force
    $queryPath = Join-Path $PSScriptRoot '../../Queries/KeyVault.kql'
}

Describe 'P6 Key Vault query safety boundary' {
    It 'projects vault configuration without access policies or data-plane objects' {
        $query = Get-Content $queryPath -Raw
        $query | Should -Match '(?i)microsoft\.keyvault/vaults'
        $query | Should -Match '(?i)enableRbacAuthorization'
        $query | Should -Not -Match '(?i)accessPolicies|tenantId|vaultUri|/secrets|/keys|/certificates|secretValue|keyUri|privateKey'
    }
}

Describe 'P6 Key Vault normalization' {
    It 'normalizes authorization, protection and network metadata' {
        $vaultId = '/subscriptions/sub/resourceGroups/RG-SEC/providers/Microsoft.KeyVault/vaults/kv01'
        $subnetId = '/subscriptions/sub/resourceGroups/RG-NET/providers/Microsoft.Network/virtualNetworks/vnet01/subnets/private'
        $row = [pscustomobject]@{
            id = $vaultId; name = 'kv01'; type = 'microsoft.keyvault/vaults'; subscriptionId = 'sub'; resourceGroup = 'RG-SEC'; location = 'westeurope'; tags = $null
            skuName = 'standard'; skuFamily = 'A'; enableRbacAuthorization = $true; enableSoftDelete = $true; enablePurgeProtection = $true
            softDeleteRetentionInDays = 90; publicNetworkAccess = 'Disabled'; enabledForDeployment = $false; enabledForDiskEncryption = $false; enabledForTemplateDeployment = $false
            networkDefaultAction = 'Deny'; networkBypass = 'AzureServices'
            networkVirtualNetworkRules = @([pscustomobject]@{ id = $subnetId })
            networkIpRules = @([pscustomobject]@{ value = '203.0.113.11' })
        }

        $result = ConvertTo-CollectorKeyVaultInventory -Rows @($row)
        $vault = $result.keyVaults[0]

        $result.summary.keyVaults | Should -Be 1
        $result.summary.rbacAuthorizedVaults | Should -Be 1
        $result.summary.purgeProtectionEnabledVaults | Should -Be 1
        $vault.authorizationModel | Should -BeExactly 'RBAC'
        $vault.networkAcls.virtualNetworkRules | Should -Contain $subnetId
        @($result.relationships | Where-Object { $_.sourceId -eq $vaultId -and $_.relationship -eq 'AllowsSubnet' -and $_.targetId -eq $subnetId }).Count | Should -Be 1
        @($vault.PSObject.Properties.Name) | Should -Not -Contain 'accessPolicies'
        @($vault.PSObject.Properties.Name) | Should -Not -Contain 'tenantId'
    }

    It 'keeps empty collections as arrays' {
        $result = ConvertTo-CollectorKeyVaultInventory -Rows @()
        @($result.keyVaults).Count | Should -Be 0
        @($result.relationships).Count | Should -Be 0
    }
}
