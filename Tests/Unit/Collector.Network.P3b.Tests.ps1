BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.Network.psm1') -Force
}

Describe 'P3b Network query safety boundary' {
    It 'collects the planned P3b resource types without sensitive configuration bodies' {
        $query = Get-Content (Join-Path $PSScriptRoot '../../Queries/Network.kql') -Raw

        foreach ($resourceType in @(
            'microsoft.network/privateendpoints',
            'microsoft.network/privatednszones',
            'microsoft.network/privatednszones/virtualnetworklinks',
            'microsoft.network/natgateways',
            'microsoft.network/loadbalancers',
            'microsoft.network/applicationgateways',
            'microsoft.network/azurefirewalls',
            'microsoft.network/firewallpolicies'
        )) {
            $query | Should -Match ([regex]::Escape($resourceType))
        }

        $query | Should -Not -Match '(?i)sharedKey'
        $query | Should -Not -Match '(?i)sslCertificates'
        $query | Should -Not -Match '(?i)authenticationCertificates'
        $query | Should -Not -Match '(?i)applicationRuleCollections'
        $query | Should -Not -Match '(?i)networkRuleCollections'
        $query | Should -Not -Match '(?i)natRuleCollections'
        $query | Should -Not -Match '(?i)transportSecurity'
        $query | Should -Not -Match '(?i)requestMessage'
    }
}

Describe 'P3b Private Link and Private DNS normalization' {
    It 'normalizes a private endpoint without exporting free-form request data' {
        $peId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/privateEndpoints/pe01'
        $subnetId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/virtualNetworks/vnet01/subnets/snet01'
        $targetId = '/subscriptions/sub/resourceGroups/RG-Data/providers/Microsoft.Storage/storageAccounts/storage01'
        $connectionId = "$peId/privateLinkServiceConnections/storage"

        $row = [pscustomobject]@{
            id = $peId
            name = 'pe01'
            type = 'microsoft.network/privateendpoints'
            subscriptionId = 'sub'
            resourceGroup = 'RG-Network'
            location = 'westeurope'
            tags = $null
            zones = @()
            privateEndpointSubnetId = $subnetId
            privateEndpointConnections = @(
                [pscustomobject]@{
                    id = $connectionId
                    name = 'storage'
                    properties = [pscustomobject]@{
                        privateLinkServiceId = $targetId
                        groupIds = @('blob')
                        requestMessage = 'must not be normalized'
                        privateLinkServiceConnectionState = [pscustomobject]@{
                            status = 'Approved'
                            actionsRequired = 'None'
                            description = 'must not be normalized'
                        }
                    }
                }
            )
            privateEndpointManualConnections = @()
        }

        $result = ConvertTo-CollectorNetworkInventory -Rows @($row)

        $result.summary.privateEndpoints | Should -Be 1
        $result.summary.privateLinkConnections | Should -Be 1
        $result.privateEndpoints[0].subnetId | Should -Be $subnetId
        $result.privateLinkConnections[0].privateLinkServiceId | Should -Be $targetId
        $result.privateLinkConnections[0].groupIds | Should -Contain 'blob'
        @($result.privateLinkConnections[0].PSObject.Properties.Name) | Should -Not -Contain 'requestMessage'
        @($result.privateLinkConnections[0].PSObject.Properties.Name) | Should -Not -Contain 'description'
        @($result.relationships | Where-Object { $_.sourceId -eq $peId -and $_.relationship -eq 'AttachedToSubnet' -and $_.targetId -eq $subnetId }).Count | Should -Be 1
        @($result.relationships | Where-Object { $_.sourceId -eq $connectionId -and $_.relationship -eq 'ConnectsToResource' -and $_.targetId -eq $targetId }).Count | Should -Be 1
    }

    It 'normalizes a private DNS zone and VNet link with stable parent relationship' {
        $zoneId = '/subscriptions/sub/resourceGroups/RG-DNS/providers/Microsoft.Network/privateDnsZones/privatelink.example.test'
        $linkId = "$zoneId/virtualNetworkLinks/vnet01-link"
        $vnetId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/virtualNetworks/vnet01'

        $rows = @(
            [pscustomobject]@{
                id = $zoneId; name = 'privatelink.example.test'; type = 'microsoft.network/privatednszones'
                subscriptionId = 'sub'; resourceGroup = 'RG-DNS'; location = 'global'; tags = $null; zones = @()
            },
            [pscustomobject]@{
                id = $linkId; name = 'privatelink.example.test/vnet01-link'; type = 'microsoft.network/privatednszones/virtualnetworklinks'
                subscriptionId = 'sub'; resourceGroup = 'RG-DNS'; location = 'global'; tags = $null; zones = @()
                privateDnsLinkVirtualNetworkId = $vnetId
                privateDnsLinkRegistrationEnabled = $false
                privateDnsLinkResolutionPolicy = 'Default'
            }
        )

        $result = ConvertTo-CollectorNetworkInventory -Rows $rows

        $result.summary.privateDnsZones | Should -Be 1
        $result.summary.privateDnsVirtualNetworkLinks | Should -Be 1
        $result.privateDnsVirtualNetworkLinks[0].privateDnsZoneId | Should -Be $zoneId
        $result.privateDnsVirtualNetworkLinks[0].virtualNetworkId | Should -Be $vnetId
        $result.privateDnsVirtualNetworkLinks[0].name | Should -BeExactly 'vnet01-link'
        @($result.relationships | Where-Object { $_.sourceId -eq $zoneId -and $_.relationship -eq 'ContainsVirtualNetworkLink' -and $_.targetId -eq $linkId }).Count | Should -Be 1
        @($result.relationships | Where-Object { $_.sourceId -eq $linkId -and $_.relationship -eq 'LinkedToVNet' -and $_.targetId -eq $vnetId }).Count | Should -Be 1
    }
}

Describe 'P3b NAT and Load Balancer normalization' {
    It 'normalizes NAT Gateway public IP references' {
        $natId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/natGateways/nat01'
        $pipId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/publicIPAddresses/pip01'
        $prefixId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/publicIPPrefixes/prefix01'
        $row = [pscustomobject]@{
            id = $natId; name = 'nat01'; type = 'microsoft.network/natgateways'
            subscriptionId = 'sub'; resourceGroup = 'RG-Network'; location = 'westeurope'; tags = $null
            zones = @('1'); skuName = 'Standard'; skuTier = ''
            natGatewayIdleTimeoutMinutes = 10
            natGatewayPublicIpAddresses = @([pscustomobject]@{ id = $pipId })
            natGatewayPublicIpPrefixes = @([pscustomobject]@{ id = $prefixId })
        }

        $result = ConvertTo-CollectorNetworkInventory -Rows @($row)

        $result.summary.natGateways | Should -Be 1
        $result.natGateways[0].publicIpAddressIds | Should -Contain $pipId
        $result.natGateways[0].publicIpPrefixIds | Should -Contain $prefixId
        @($result.relationships | Where-Object { $_.sourceId -eq $natId -and $_.relationship -eq 'UsesPublicIp' -and $_.targetId -eq $pipId }).Count | Should -Be 1
    }

    It 'normalizes Load Balancer frontend, backend pool, rule and probe relationships' {
        $lbId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/loadBalancers/lb01'
        $frontendId = "$lbId/frontendIPConfigurations/frontend01"
        $poolId = "$lbId/backendAddressPools/pool01"
        $probeId = "$lbId/probes/probe01"
        $ruleId = "$lbId/loadBalancingRules/rule01"
        $subnetId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/virtualNetworks/vnet01/subnets/snet01'
        $pipId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/publicIPAddresses/pip01'

        $row = [pscustomobject]@{
            id = $lbId; name = 'lb01'; type = 'microsoft.network/loadbalancers'
            subscriptionId = 'sub'; resourceGroup = 'RG-Network'; location = 'westeurope'; tags = $null; zones = @()
            skuName = 'Standard'; skuTier = 'Regional'; loadBalancerScope = 'Public'
            loadBalancerFrontendIpConfigurations = @(
                [pscustomobject]@{ id = $frontendId; name = 'frontend01'; properties = [pscustomobject]@{
                    privateIPAddress = ''; privateIPAllocationMethod = 'Dynamic'; privateIPAddressVersion = 'IPv4'
                    subnet = [pscustomobject]@{ id = $subnetId }; publicIPAddress = [pscustomobject]@{ id = $pipId }; publicIPPrefix = $null
                }}
            )
            loadBalancerBackendAddressPools = @(
                [pscustomobject]@{ id = $poolId; name = 'pool01'; properties = [pscustomobject]@{
                    virtualNetwork = $null; syncMode = 'Automatic'; loadBalancerBackendAddresses = @()
                }}
            )
            loadBalancerProbes = @(
                [pscustomobject]@{ id = $probeId; name = 'probe01'; properties = [pscustomobject]@{
                    protocol = 'Tcp'; port = 443; intervalInSeconds = 5; numberOfProbes = 2; probeThreshold = 2; requestPath = ''; noHealthyBackendsBehavior = 'AllProbedDown'
                }}
            )
            loadBalancerRules = @(
                [pscustomobject]@{ id = $ruleId; name = 'rule01'; properties = [pscustomobject]@{
                    protocol = 'Tcp'; frontendPort = 443; backendPort = 443
                    frontendIPConfiguration = [pscustomobject]@{ id = $frontendId }
                    backendAddressPool = [pscustomobject]@{ id = $poolId }
                    backendAddressPools = @(); probe = [pscustomobject]@{ id = $probeId }
                    loadDistribution = 'Default'; idleTimeoutInMinutes = 4; disableOutboundSnat = $false; enableFloatingIP = $false; enableTcpReset = $true
                }}
            )
            loadBalancerOutboundRules = @()
        }

        $result = ConvertTo-CollectorNetworkInventory -Rows @($row)

        $result.summary.loadBalancers | Should -Be 1
        $result.summary.loadBalancerFrontends | Should -Be 1
        $result.summary.loadBalancerBackendPools | Should -Be 1
        $result.summary.loadBalancerRules | Should -Be 1
        $result.summary.loadBalancerProbes | Should -Be 1
        $result.loadBalancerRules[0].backendAddressPoolIds | Should -Contain $poolId
        @($result.relationships | Where-Object { $_.sourceId -eq $ruleId -and $_.relationship -eq 'UsesLoadBalancerProbe' -and $_.targetId -eq $probeId }).Count | Should -Be 1
    }
}

Describe 'P3b Application Gateway and Azure Firewall normalization' {
    It 'normalizes Application Gateway routing without certificate material' {
        $appGwId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/applicationGateways/agw01'
        $subnetId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/virtualNetworks/vnet01/subnets/ApplicationGatewaySubnet'
        $pipId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/publicIPAddresses/agw-pip'
        $ipConfigId = "$appGwId/gatewayIPConfigurations/gwip"
        $frontendId = "$appGwId/frontendIPConfigurations/frontend"
        $portId = "$appGwId/frontendPorts/https"
        $poolId = "$appGwId/backendAddressPools/backend"
        $settingsId = "$appGwId/backendHttpSettingsCollection/https-settings"
        $listenerId = "$appGwId/httpListeners/https-listener"
        $ruleId = "$appGwId/requestRoutingRules/basic-rule"

        $row = [pscustomobject]@{
            id = $appGwId; name = 'agw01'; type = 'microsoft.network/applicationgateways'
            subscriptionId = 'sub'; resourceGroup = 'RG-Network'; location = 'westeurope'; tags = $null; zones = @('1','2')
            applicationGatewaySkuName = 'WAF_v2'; applicationGatewaySkuTier = 'WAF_v2'; applicationGatewaySkuCapacity = 2
            applicationGatewayEnableHttp2 = $true; applicationGatewayAutoscaleMinCapacity = $null; applicationGatewayAutoscaleMaxCapacity = $null
            applicationGatewayFirewallPolicyId = ''
            applicationGatewayIpConfigurations = @([pscustomobject]@{ id = $ipConfigId; name = 'gwip'; properties = [pscustomobject]@{ subnet = [pscustomobject]@{ id = $subnetId } } })
            applicationGatewayFrontendIpConfigurations = @([pscustomobject]@{ id = $frontendId; name = 'frontend'; properties = [pscustomobject]@{ privateIPAddress = ''; privateIPAllocationMethod = 'Dynamic'; subnet = $null; publicIPAddress = [pscustomobject]@{ id = $pipId } } })
            applicationGatewayFrontendPorts = @([pscustomobject]@{ id = $portId; name = 'https'; properties = [pscustomobject]@{ port = 443 } })
            applicationGatewayBackendAddressPools = @([pscustomobject]@{ id = $poolId; name = 'backend'; properties = [pscustomobject]@{ backendAddresses = @([pscustomobject]@{ fqdn = 'app.internal.example.test'; ipAddress = '' }) } })
            applicationGatewayBackendHttpSettings = @([pscustomobject]@{ id = $settingsId; name = 'https-settings'; properties = [pscustomobject]@{ port = 443; protocol = 'Https'; cookieBasedAffinity = 'Disabled'; requestTimeout = 20; pickHostNameFromBackendAddress = $true; probe = $null } })
            applicationGatewayHttpListeners = @([pscustomobject]@{ id = $listenerId; name = 'https-listener'; properties = [pscustomobject]@{ frontendIPConfiguration = [pscustomobject]@{ id = $frontendId }; frontendPort = [pscustomobject]@{ id = $portId }; protocol = 'Https'; hostName = 'app.example.test'; requireServerNameIndication = $true; firewallPolicy = $null; sslCertificate = [pscustomobject]@{ id = "$appGwId/sslCertificates/secret-cert" } } })
            applicationGatewayRequestRoutingRules = @([pscustomobject]@{ id = $ruleId; name = 'basic-rule'; properties = [pscustomobject]@{ ruleType = 'Basic'; priority = 100; httpListener = [pscustomobject]@{ id = $listenerId }; backendAddressPool = [pscustomobject]@{ id = $poolId }; backendHttpSettings = [pscustomobject]@{ id = $settingsId }; urlPathMap = $null; redirectConfiguration = $null } })
            applicationGatewayProbes = @(); applicationGatewayUrlPathMaps = @()
        }

        $result = ConvertTo-CollectorNetworkInventory -Rows @($row)

        $result.summary.applicationGateways | Should -Be 1
        $result.summary.applicationGatewayBackendPools | Should -Be 1
        $result.summary.applicationGatewayRoutingRules | Should -Be 1
        $result.applicationGatewayBackendAddresses[0].fqdn | Should -BeExactly 'app.internal.example.test'
        @($result.applicationGatewayHttpListeners[0].PSObject.Properties.Name) | Should -Not -Contain 'sslCertificate'
        @($result.relationships | Where-Object { $_.sourceId -eq $ruleId -and $_.relationship -eq 'UsesApplicationGatewayBackendPool' -and $_.targetId -eq $poolId }).Count | Should -Be 1
    }

    It 'normalizes Azure Firewall topology and Firewall Policy references without rule collections' {
        $firewallId = '/subscriptions/sub/resourceGroups/RG-Hub/providers/Microsoft.Network/azureFirewalls/azfw01'
        $policyId = '/subscriptions/sub/resourceGroups/RG-Hub/providers/Microsoft.Network/firewallPolicies/policy01'
        $subnetId = '/subscriptions/sub/resourceGroups/RG-Hub/providers/Microsoft.Network/virtualNetworks/hub/subnets/AzureFirewallSubnet'
        $pipId = '/subscriptions/sub/resourceGroups/RG-Hub/providers/Microsoft.Network/publicIPAddresses/azfw-pip'
        $ipConfigId = "$firewallId/ipConfigurations/configuration"

        $rows = @(
            [pscustomobject]@{
                id = $firewallId; name = 'azfw01'; type = 'microsoft.network/azurefirewalls'
                subscriptionId = 'sub'; resourceGroup = 'RG-Hub'; location = 'westeurope'; tags = $null; zones = @('1','2','3')
                azureFirewallSkuName = 'AZFW_VNet'; azureFirewallSkuTier = 'Premium'; azureFirewallThreatIntelMode = 'Alert'
                azureFirewallPolicyId = $policyId; azureFirewallVirtualHubId = ''
                azureFirewallIpConfigurations = @([pscustomobject]@{ id = $ipConfigId; name = 'configuration'; properties = [pscustomobject]@{ privateIPAddress = '10.0.1.4'; subnet = [pscustomobject]@{ id = $subnetId }; publicIPAddress = [pscustomobject]@{ id = $pipId } } })
                azureFirewallManagementIpConfiguration = $null
            },
            [pscustomobject]@{
                id = $policyId; name = 'policy01'; type = 'microsoft.network/firewallpolicies'
                subscriptionId = 'sub'; resourceGroup = 'RG-Hub'; location = 'westeurope'; tags = $null; zones = @()
                firewallPolicySkuTier = 'Premium'; firewallPolicyThreatIntelMode = 'Alert'; firewallPolicyBasePolicyId = ''
            }
        )

        $result = ConvertTo-CollectorNetworkInventory -Rows $rows

        $result.summary.azureFirewalls | Should -Be 1
        $result.summary.azureFirewallIpConfigurations | Should -Be 1
        $result.summary.firewallPolicies | Should -Be 1
        $result.azureFirewalls[0].firewallPolicyId | Should -Be $policyId
        @($result.azureFirewalls[0].PSObject.Properties.Name) | Should -Not -Contain 'applicationRuleCollections'
        @($result.azureFirewalls[0].PSObject.Properties.Name) | Should -Not -Contain 'networkRuleCollections'
        @($result.relationships | Where-Object { $_.sourceId -eq $firewallId -and $_.relationship -eq 'UsesFirewallPolicy' -and $_.targetId -eq $policyId }).Count | Should -Be 1
        @($result.relationships | Where-Object { $_.sourceId -eq $ipConfigId -and $_.relationship -eq 'AttachedToSubnet' -and $_.targetId -eq $subnetId }).Count | Should -Be 1
    }
}

Describe 'P3b empty-collection stability' {
    It 'returns empty arrays for every new P3b collection' {
        $result = ConvertTo-CollectorNetworkInventory -Rows @()

        foreach ($propertyName in @(
            'privateEndpoints', 'privateLinkConnections', 'privateDnsZones', 'privateDnsVirtualNetworkLinks', 'natGateways',
            'loadBalancers', 'loadBalancerFrontendIpConfigurations', 'loadBalancerBackendPools', 'loadBalancerBackendAddresses', 'loadBalancerRules', 'loadBalancerProbes', 'loadBalancerOutboundRules',
            'applicationGateways', 'applicationGatewayIpConfigurations', 'applicationGatewayFrontendIpConfigurations', 'applicationGatewayFrontendPorts', 'applicationGatewayBackendPools', 'applicationGatewayBackendAddresses', 'applicationGatewayBackendHttpSettings', 'applicationGatewayHttpListeners', 'applicationGatewayRequestRoutingRules', 'applicationGatewayProbes', 'applicationGatewayUrlPathMaps', 'applicationGatewayPathRules',
            'azureFirewalls', 'azureFirewallIpConfigurations', 'firewallPolicies'
        )) {
            ($result.$propertyName -is [System.Array]) | Should -BeTrue
            @($result.$propertyName).Count | Should -Be 0
        }
    }
}
