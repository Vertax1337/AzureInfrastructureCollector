BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.Storage.psm1') -Force
    $queryPath = Join-Path $PSScriptRoot '../../Queries/Storage.kql'
}

Describe 'P6 Storage query safety boundary' {
    It 'projects storage metadata without keys, SAS tokens or connection strings' {
        $query = Get-Content $queryPath -Raw
        $query | Should -Match '(?i)microsoft\.storage/storageaccounts'
        $query | Should -Match '(?i)allowSharedKeyAccess'
        $query | Should -Not -Match '(?i)listKeys|accountKey|connectionString|sharedAccessSignature|\bsasToken\b|\bsig\s*='
    }
}

Describe 'P6 Storage normalization' {
    It 'normalizes safe account settings and subnet relationships' {
        $accountId = '/subscriptions/sub/resourceGroups/RG-STO/providers/Microsoft.Storage/storageAccounts/sto01'
        $subnetId = '/subscriptions/sub/resourceGroups/RG-NET/providers/Microsoft.Network/virtualNetworks/vnet01/subnets/storage'
        $row = [pscustomobject]@{
            id = $accountId; name = 'sto01'; type = 'microsoft.storage/storageaccounts'; subscriptionId = 'sub'; resourceGroup = 'RG-STO'; location = 'westeurope'; tags = $null
            kind = 'StorageV2'; skuName = 'Standard_GRS'; skuTier = 'Standard'; accessTier = 'Hot'
            allowBlobPublicAccess = $false; allowSharedKeyAccess = $false; defaultToOAuthAuthentication = $true
            isHnsEnabled = $false; isNfsV3Enabled = $false; isSftpEnabled = $false; isLocalUserEnabled = $false
            minimumTlsVersion = 'TLS1_2'; publicNetworkAccess = 'Enabled'; supportsHttpsTrafficOnly = $true; largeFileSharesState = 'Enabled'
            networkDefaultAction = 'Deny'; networkBypass = 'AzureServices'
            networkVirtualNetworkRules = @([pscustomobject]@{ id = $subnetId })
            networkIpRules = @([pscustomobject]@{ value = '203.0.113.10' })
        }

        $result = ConvertTo-CollectorStorageInventory -Rows @($row)
        $account = $result.storageAccounts[0]

        $result.summary.storageAccounts | Should -Be 1
        $result.summary.sharedKeyDisabledAccounts | Should -Be 1
        $result.summary.subnetReferences | Should -Be 1
        $account.minimumTlsVersion | Should -BeExactly 'TLS1_2'
        $account.networkAcls.virtualNetworkRules | Should -Contain $subnetId
        $account.networkAcls.ipRules | Should -Contain '203.0.113.10'
        @($result.relationships | Where-Object { $_.sourceId -eq $accountId -and $_.relationship -eq 'AllowsSubnet' -and $_.targetId -eq $subnetId }).Count | Should -Be 1
    }

    It 'keeps empty collections as arrays' {
        $result = ConvertTo-CollectorStorageInventory -Rows @()
        @($result.storageAccounts).Count | Should -Be 0
        @($result.relationships).Count | Should -Be 0
    }
}
