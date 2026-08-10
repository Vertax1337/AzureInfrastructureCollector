BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.Network.psm1') -Force
}

Describe 'P3 Network query safety boundary' {
    It 'never projects the VPN connection shared key' {
        $query = Get-Content (Join-Path $PSScriptRoot '../../Queries/Network.kql') -Raw

        $query | Should -Not -Match '(?i)sharedKey'
        $query | Should -Match '(?i)connectionVirtualNetworkGateway1Id'
        $query | Should -Match '(?i)connectionLocalNetworkGateway2Id'
    }
}

Describe 'ConvertTo-CollectorNetworkInventory' {
    It 'normalizes VNets, subnets and peerings with stable relationships' {
        $vnetId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/virtualNetworks/vnet-hub'
        $subnetId = "$vnetId/subnets/snet-app"
        $remoteVnetId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/virtualNetworks/vnet-spoke'
        $nsgId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/networkSecurityGroups/nsg-app'
        $routeTableId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/routeTables/rt-app'

        $row = [pscustomobject]@{
            id = $vnetId
            name = 'vnet-hub'
            type = 'microsoft.network/virtualnetworks'
            subscriptionId = 'sub'
            resourceGroup = 'RG-Network'
            location = 'westeurope'
            tags = [ordered]@{ Environment = 'Production' }
            vnetAddressPrefixes = @('10.0.0.0/16')
            vnetDnsServers = @('10.0.0.4')
            vnetEnableDdosProtection = $false
            vnetDdosProtectionPlanId = ''
            vnetSubnets = @(
                [pscustomobject]@{
                    id = $subnetId
                    name = 'snet-app'
                    properties = [pscustomobject]@{
                        addressPrefix = '10.0.1.0/24'
                        networkSecurityGroup = [pscustomobject]@{ id = $nsgId }
                        routeTable = [pscustomobject]@{ id = $routeTableId }
                        natGateway = $null
                        privateEndpointNetworkPolicies = 'Disabled'
                        privateLinkServiceNetworkPolicies = 'Enabled'
                        serviceEndpoints = @([pscustomobject]@{ service = 'Microsoft.Storage' })
                        delegations = @()
                    }
                }
            )
            vnetPeerings = @(
                [pscustomobject]@{
                    id = "$vnetId/virtualNetworkPeerings/to-spoke"
                    name = 'to-spoke'
                    properties = [pscustomobject]@{
                        remoteVirtualNetwork = [pscustomobject]@{ id = $remoteVnetId }
                        peeringState = 'Connected'
                        peeringSyncLevel = 'FullyInSync'
                        allowVirtualNetworkAccess = $true
                        allowForwardedTraffic = $true
                        allowGatewayTransit = $false
                        useRemoteGateways = $false
                    }
                }
            )
        }

        $result = ConvertTo-CollectorNetworkInventory -Rows @($row)

        $result.summary.virtualNetworks | Should -Be 1
        $result.summary.subnets | Should -Be 1
        $result.summary.peerings | Should -Be 1
        $result.subnets[0].networkSecurityGroupId | Should -Be $nsgId
        $result.subnets[0].routeTableId | Should -Be $routeTableId
        $result.peerings[0].remoteVirtualNetworkId | Should -Be $remoteVnetId
        @($result.relationships | Where-Object { $_.sourceId -eq $vnetId -and $_.relationship -eq 'PeeredWith' -and $_.targetId -eq $remoteVnetId }).Count | Should -Be 1
    }

    It 'normalizes NIC IP configuration and topology references' {
        $nicId = '/subscriptions/sub/resourceGroups/RG-Compute/providers/Microsoft.Network/networkInterfaces/nic01'
        $ipConfigId = "$nicId/ipConfigurations/ipconfig1"
        $subnetId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/virtualNetworks/vnet01/subnets/snet01'
        $publicIpId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/publicIPAddresses/pip01'
        $vmId = '/subscriptions/sub/resourceGroups/RG-Compute/providers/Microsoft.Compute/virtualMachines/vm01'

        $row = [pscustomobject]@{
            id = $nicId
            name = 'nic01'
            type = 'microsoft.network/networkinterfaces'
            subscriptionId = 'sub'
            resourceGroup = 'RG-Compute'
            location = 'westeurope'
            tags = $null
            nicNetworkSecurityGroupId = ''
            nicEnableAcceleratedNetworking = $true
            nicEnableIpForwarding = $false
            nicMacAddress = '00-00-00-00-00-00'
            nicDnsServers = @()
            nicVirtualMachineId = $vmId
            nicIpConfigurations = @(
                [pscustomobject]@{
                    id = $ipConfigId
                    name = 'ipconfig1'
                    properties = [pscustomobject]@{
                        privateIPAddress = '10.0.1.4'
                        privateIPAllocationMethod = 'Dynamic'
                        privateIPAddressVersion = 'IPv4'
                        primary = $true
                        subnet = [pscustomobject]@{ id = $subnetId }
                        publicIPAddress = [pscustomobject]@{ id = $publicIpId }
                    }
                }
            )
        }

        $result = ConvertTo-CollectorNetworkInventory -Rows @($row)

        $result.summary.networkInterfaces | Should -Be 1
        $result.summary.ipConfigurations | Should -Be 1
        $result.ipConfigurations[0].privateIpAddress | Should -Be '10.0.1.4'
        $result.ipConfigurations[0].subnetId | Should -Be $subnetId
        $result.ipConfigurations[0].publicIpAddressId | Should -Be $publicIpId
        @($result.relationships | Where-Object { $_.sourceId -eq $nicId -and $_.relationship -eq 'AttachedToVm' -and $_.targetId -eq $vmId }).Count | Should -Be 1
    }

    It 'normalizes custom NSG rules without exporting descriptions' {
        $nsgId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/networkSecurityGroups/nsg01'
        $row = [pscustomobject]@{
            id = $nsgId
            name = 'nsg01'
            type = 'microsoft.network/networksecuritygroups'
            subscriptionId = 'sub'
            resourceGroup = 'RG-Network'
            location = 'westeurope'
            tags = $null
            nsgFlushConnection = $false
            nsgSecurityRules = @(
                [pscustomobject]@{
                    id = "$nsgId/securityRules/Allow-HTTPS"
                    name = 'Allow-HTTPS'
                    properties = [pscustomobject]@{
                        description = 'This field must not be part of the normalized schema.'
                        priority = 100
                        direction = 'Inbound'
                        access = 'Allow'
                        protocol = 'Tcp'
                        sourceAddressPrefix = 'Internet'
                        sourceAddressPrefixes = @()
                        sourcePortRange = '*'
                        sourcePortRanges = @()
                        destinationAddressPrefix = '*'
                        destinationAddressPrefixes = @()
                        destinationPortRange = '443'
                        destinationPortRanges = @()
                        sourceApplicationSecurityGroups = @()
                        destinationApplicationSecurityGroups = @()
                    }
                }
            )
        }

        $result = ConvertTo-CollectorNetworkInventory -Rows @($row)

        $result.summary.networkSecurityGroups | Should -Be 1
        $result.summary.securityRules | Should -Be 1
        $result.securityRules[0].destinationPortRanges | Should -Contain '443'
        @($result.securityRules[0].PSObject.Properties.Name) | Should -Not -Contain 'description'
    }

    It 'normalizes VPN connection references without a shared-key field' {
        $gatewayId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/virtualNetworkGateways/vgw01'
        $localGatewayId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/localNetworkGateways/lng01'
        $connectionId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/connections/cn01'

        $row = [pscustomobject]@{
            id = $connectionId
            name = 'cn01'
            type = 'microsoft.network/connections'
            subscriptionId = 'sub'
            resourceGroup = 'RG-Network'
            location = 'westeurope'
            tags = $null
            connectionType = 'IPsec'
            connectionProtocol = 'IKEv2'
            connectionEnableBgp = $false
            connectionRoutingWeight = 10
            connectionUsePolicyBasedTrafficSelectors = $false
            connectionDpdTimeoutSeconds = 45
            connectionVirtualNetworkGateway1Id = $gatewayId
            connectionVirtualNetworkGateway2Id = ''
            connectionLocalNetworkGateway2Id = $localGatewayId
        }

        $result = ConvertTo-CollectorNetworkInventory -Rows @($row)

        $result.summary.connections | Should -Be 1
        @($result.connections[0].PSObject.Properties.Name) | Should -Not -Contain 'sharedKey'
        $result.connections[0].virtualNetworkGateway1Id | Should -Be $gatewayId
        $result.connections[0].localNetworkGateway2Id | Should -Be $localGatewayId
    }

    It 'preserves empty collection types for a tenant without network resources' {
        $result = ConvertTo-CollectorNetworkInventory -Rows @()

        $result.summary.relationships | Should -Be 0
        ($result.virtualNetworks -is [System.Array]) | Should -BeTrue
        ($result.subnets -is [System.Array]) | Should -BeTrue
        ($result.relationships -is [System.Array]) | Should -BeTrue
        @($result.virtualNetworks).Count | Should -Be 0
        @($result.relationships).Count | Should -Be 0
    }
}
