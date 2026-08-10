BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.Network.psm1') -Force
}

Describe 'P3a Local Network Gateway FQDN support' {
    It 'projects the FQDN property without introducing the connection shared key' {
        $query = Get-Content (Join-Path $PSScriptRoot '../../Queries/Network.kql') -Raw

        $query | Should -Match '(?i)localGatewayFqdn\s*=\s*tostring\(properties\.fqdn\)'
        $query | Should -Not -Match '(?i)sharedKey'
    }

    It 'normalizes an FQDN endpoint independently from gatewayIpAddress' {
        $row = [pscustomobject]@{
            id = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/localNetworkGateways/lng01'
            name = 'lng01'
            type = 'microsoft.network/localnetworkgateways'
            subscriptionId = 'sub'
            resourceGroup = 'RG-Network'
            location = 'westeurope'
            tags = $null
            localGatewayIpAddress = ''
            localGatewayFqdn = 'vpn.partner.example.test'
            localGatewayAddressPrefixes = @('192.0.2.0/24')
            localGatewayBgpAsn = $null
            localGatewayBgpPeerWeight = $null
            localGatewayBgpPeeringAddress = ''
        }

        $result = ConvertTo-CollectorNetworkInventory -Rows @($row)

        $result.summary.localNetworkGateways | Should -Be 1
        $result.localNetworkGateways[0].gatewayIpAddress | Should -BeExactly ''
        $result.localNetworkGateways[0].fqdn | Should -BeExactly 'vpn.partner.example.test'
        @($result.localNetworkGateways[0].addressPrefixes).Count | Should -Be 1
        $result.localNetworkGateways[0].addressPrefixes[0] | Should -BeExactly '192.0.2.0/24'
    }
}
