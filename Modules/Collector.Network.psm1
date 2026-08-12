Set-StrictMode -Version Latest

function Get-CollectorNetworkProperty {
    [CmdletBinding()]
    param(
        $InputObject,
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $null
}

function ConvertTo-CollectorNetworkStringArray {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) {
        return ,@()
    }

    $items = @(
        foreach ($item in @($Value)) {
            if ($null -eq $item) {
                continue
            }
            $text = [string]$item
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $text
            }
        }
    )

    return ,@($items | Sort-Object -Unique)
}

function ConvertTo-CollectorNetworkIdArray {
    [CmdletBinding()]
    param($Value)

    $ids = @(
        foreach ($item in @($Value)) {
            if ($null -eq $item) {
                continue
            }

            if ($item -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace($item)) {
                    $item
                }
                continue
            }

            $id = Get-CollectorNetworkProperty -InputObject $item -Name 'id'
            if (-not [string]::IsNullOrWhiteSpace([string]$id)) {
                [string]$id
            }
        }
    )

    return ,@($ids | Sort-Object -Unique)
}

function Get-CollectorNetworkChildId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ParentId,

        [Parameter(Mandatory)]
        [string]$CollectionName,

        $Child,

        [int]$Index = 0
    )

    $id = [string](Get-CollectorNetworkProperty -InputObject $Child -Name 'id')
    if (-not [string]::IsNullOrWhiteSpace($id)) {
        return $id
    }

    $name = [string](Get-CollectorNetworkProperty -InputObject $Child -Name 'name')
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = 'item-{0}' -f $Index
    }

    return '{0}/{1}/{2}' -f $ParentId, $CollectionName, $name
}

function New-CollectorNetworkRelationship {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [string]$Relationship,

        [Parameter(Mandatory)]
        [string]$TargetId
    )

    if ([string]::IsNullOrWhiteSpace($SourceId) -or [string]::IsNullOrWhiteSpace($TargetId)) {
        return $null
    }

    [pscustomobject][ordered]@{
        sourceId     = $SourceId
        relationship = $Relationship
        targetId     = $TargetId
    }
}

function ConvertTo-CollectorNetworkInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $virtualNetworks = [System.Collections.Generic.List[object]]::new()
    $subnets = [System.Collections.Generic.List[object]]::new()
    $peerings = [System.Collections.Generic.List[object]]::new()
    $networkInterfaces = [System.Collections.Generic.List[object]]::new()
    $ipConfigurations = [System.Collections.Generic.List[object]]::new()
    $networkSecurityGroups = [System.Collections.Generic.List[object]]::new()
    $securityRules = [System.Collections.Generic.List[object]]::new()
    $publicIpAddresses = [System.Collections.Generic.List[object]]::new()
    $routeTables = [System.Collections.Generic.List[object]]::new()
    $routes = [System.Collections.Generic.List[object]]::new()
    $virtualNetworkGateways = [System.Collections.Generic.List[object]]::new()
    $localNetworkGateways = [System.Collections.Generic.List[object]]::new()
    $connections = [System.Collections.Generic.List[object]]::new()
    $networkWatchers = [System.Collections.Generic.List[object]]::new()

    $privateEndpoints = [System.Collections.Generic.List[object]]::new()
    $privateLinkConnections = [System.Collections.Generic.List[object]]::new()
    $privateDnsZones = [System.Collections.Generic.List[object]]::new()
    $privateDnsVirtualNetworkLinks = [System.Collections.Generic.List[object]]::new()
    $natGateways = [System.Collections.Generic.List[object]]::new()

    $loadBalancers = [System.Collections.Generic.List[object]]::new()
    $loadBalancerFrontendIpConfigurations = [System.Collections.Generic.List[object]]::new()
    $loadBalancerBackendPools = [System.Collections.Generic.List[object]]::new()
    $loadBalancerBackendAddresses = [System.Collections.Generic.List[object]]::new()
    $loadBalancerRules = [System.Collections.Generic.List[object]]::new()
    $loadBalancerProbes = [System.Collections.Generic.List[object]]::new()
    $loadBalancerOutboundRules = [System.Collections.Generic.List[object]]::new()

    $applicationGateways = [System.Collections.Generic.List[object]]::new()
    $applicationGatewayIpConfigurations = [System.Collections.Generic.List[object]]::new()
    $applicationGatewayFrontendIpConfigurations = [System.Collections.Generic.List[object]]::new()
    $applicationGatewayFrontendPorts = [System.Collections.Generic.List[object]]::new()
    $applicationGatewayBackendPools = [System.Collections.Generic.List[object]]::new()
    $applicationGatewayBackendAddresses = [System.Collections.Generic.List[object]]::new()
    $applicationGatewayBackendHttpSettings = [System.Collections.Generic.List[object]]::new()
    $applicationGatewayHttpListeners = [System.Collections.Generic.List[object]]::new()
    $applicationGatewayRequestRoutingRules = [System.Collections.Generic.List[object]]::new()
    $applicationGatewayProbes = [System.Collections.Generic.List[object]]::new()
    $applicationGatewayUrlPathMaps = [System.Collections.Generic.List[object]]::new()
    $applicationGatewayPathRules = [System.Collections.Generic.List[object]]::new()

    $azureFirewalls = [System.Collections.Generic.List[object]]::new()
    $azureFirewallIpConfigurations = [System.Collections.Generic.List[object]]::new()
    $firewallPolicies = [System.Collections.Generic.List[object]]::new()

    $relationships = [System.Collections.Generic.List[object]]::new()

    foreach ($row in @($Rows)) {
        $id = [string](Get-CollectorNetworkProperty -InputObject $row -Name 'id')
        $name = [string](Get-CollectorNetworkProperty -InputObject $row -Name 'name')
        $type = ([string](Get-CollectorNetworkProperty -InputObject $row -Name 'type')).ToLowerInvariant()
        $subscriptionId = [string](Get-CollectorNetworkProperty -InputObject $row -Name 'subscriptionId')
        $resourceGroup = [string](Get-CollectorNetworkProperty -InputObject $row -Name 'resourceGroup')
        $location = [string](Get-CollectorNetworkProperty -InputObject $row -Name 'location')
        $tags = Get-CollectorNetworkProperty -InputObject $row -Name 'tags'
        $zones = ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty -InputObject $row -Name 'zones')

        switch ($type) {
            'microsoft.network/virtualnetworks' {
                $virtualNetworks.Add([pscustomobject][ordered]@{
                    id                     = $id
                    name                   = $name
                    subscriptionId         = $subscriptionId
                    resourceGroup          = $resourceGroup
                    location               = $location
                    addressPrefixes        = ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty $row 'vnetAddressPrefixes')
                    dnsServers             = ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty $row 'vnetDnsServers')
                    enableDdosProtection   = Get-CollectorNetworkProperty $row 'vnetEnableDdosProtection'
                    ddosProtectionPlanId   = [string](Get-CollectorNetworkProperty $row 'vnetDdosProtectionPlanId')
                    tags                   = $tags
                })

                foreach ($subnet in @(Get-CollectorNetworkProperty $row 'vnetSubnets')) {
                    $subnetProperties = Get-CollectorNetworkProperty $subnet 'properties'
                    $subnetId = [string](Get-CollectorNetworkProperty $subnet 'id')
                    $subnetName = [string](Get-CollectorNetworkProperty $subnet 'name')
                    if ([string]::IsNullOrWhiteSpace($subnetId) -and -not [string]::IsNullOrWhiteSpace($subnetName)) {
                        $subnetId = '{0}/subnets/{1}' -f $id, $subnetName
                    }

                    $addressPrefixes = @()
                    $singlePrefix = [string](Get-CollectorNetworkProperty $subnetProperties 'addressPrefix')
                    if (-not [string]::IsNullOrWhiteSpace($singlePrefix)) {
                        $addressPrefixes += $singlePrefix
                    }
                    $addressPrefixes += @(ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty $subnetProperties 'addressPrefixes'))
                    $addressPrefixes = @($addressPrefixes | Sort-Object -Unique)

                    $networkSecurityGroup = Get-CollectorNetworkProperty $subnetProperties 'networkSecurityGroup'
                    $routeTable = Get-CollectorNetworkProperty $subnetProperties 'routeTable'
                    $natGateway = Get-CollectorNetworkProperty $subnetProperties 'natGateway'
                    $nsgId = [string](Get-CollectorNetworkProperty $networkSecurityGroup 'id')
                    $routeTableId = [string](Get-CollectorNetworkProperty $routeTable 'id')
                    $natGatewayId = [string](Get-CollectorNetworkProperty $natGateway 'id')

                    $serviceEndpointTypes = @(
                        foreach ($endpoint in @(Get-CollectorNetworkProperty $subnetProperties 'serviceEndpoints')) {
                            $service = [string](Get-CollectorNetworkProperty $endpoint 'service')
                            if (-not [string]::IsNullOrWhiteSpace($service)) { $service }
                        }
                    ) | Sort-Object -Unique

                    $delegationServices = @(
                        foreach ($delegation in @(Get-CollectorNetworkProperty $subnetProperties 'delegations')) {
                            $delegationProperties = Get-CollectorNetworkProperty $delegation 'properties'
                            $serviceName = [string](Get-CollectorNetworkProperty $delegationProperties 'serviceName')
                            if (-not [string]::IsNullOrWhiteSpace($serviceName)) { $serviceName }
                        }
                    ) | Sort-Object -Unique

                    $subnets.Add([pscustomobject][ordered]@{
                        id                            = $subnetId
                        name                          = $subnetName
                        virtualNetworkId              = $id
                        subscriptionId                = $subscriptionId
                        resourceGroup                 = $resourceGroup
                        addressPrefixes               = @($addressPrefixes)
                        networkSecurityGroupId        = $nsgId
                        routeTableId                  = $routeTableId
                        natGatewayId                  = $natGatewayId
                        privateEndpointNetworkPolicies = [string](Get-CollectorNetworkProperty $subnetProperties 'privateEndpointNetworkPolicies')
                        privateLinkServiceNetworkPolicies = [string](Get-CollectorNetworkProperty $subnetProperties 'privateLinkServiceNetworkPolicies')
                        serviceEndpoints              = @($serviceEndpointTypes)
                        delegations                   = @($delegationServices)
                    })

                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsSubnet' -TargetId $subnetId
                    if ($relationship) { $relationships.Add($relationship) }
                    foreach ($target in @(
                        [pscustomobject]@{ Id = $nsgId; Relation = 'SecuredBy' },
                        [pscustomobject]@{ Id = $routeTableId; Relation = 'UsesRouteTable' },
                        [pscustomobject]@{ Id = $natGatewayId; Relation = 'UsesNatGateway' }
                    )) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                            $relationship = New-CollectorNetworkRelationship -SourceId $subnetId -Relationship $target.Relation -TargetId ([string]$target.Id)
                            if ($relationship) { $relationships.Add($relationship) }
                        }
                    }
                }

                foreach ($peering in @(Get-CollectorNetworkProperty $row 'vnetPeerings')) {
                    $peeringProperties = Get-CollectorNetworkProperty $peering 'properties'
                    $peeringName = [string](Get-CollectorNetworkProperty $peering 'name')
                    $peeringId = [string](Get-CollectorNetworkProperty $peering 'id')
                    if ([string]::IsNullOrWhiteSpace($peeringId) -and -not [string]::IsNullOrWhiteSpace($peeringName)) {
                        $peeringId = '{0}/virtualNetworkPeerings/{1}' -f $id, $peeringName
                    }
                    $remoteVirtualNetwork = Get-CollectorNetworkProperty $peeringProperties 'remoteVirtualNetwork'
                    $remoteVirtualNetworkId = [string](Get-CollectorNetworkProperty $remoteVirtualNetwork 'id')

                    $peerings.Add([pscustomobject][ordered]@{
                        id                        = $peeringId
                        name                      = $peeringName
                        virtualNetworkId          = $id
                        remoteVirtualNetworkId    = $remoteVirtualNetworkId
                        peeringState              = [string](Get-CollectorNetworkProperty $peeringProperties 'peeringState')
                        peeringSyncLevel          = [string](Get-CollectorNetworkProperty $peeringProperties 'peeringSyncLevel')
                        allowVirtualNetworkAccess = Get-CollectorNetworkProperty $peeringProperties 'allowVirtualNetworkAccess'
                        allowForwardedTraffic     = Get-CollectorNetworkProperty $peeringProperties 'allowForwardedTraffic'
                        allowGatewayTransit       = Get-CollectorNetworkProperty $peeringProperties 'allowGatewayTransit'
                        useRemoteGateways         = Get-CollectorNetworkProperty $peeringProperties 'useRemoteGateways'
                    })

                    if (-not [string]::IsNullOrWhiteSpace($remoteVirtualNetworkId)) {
                        $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'PeeredWith' -TargetId $remoteVirtualNetworkId
                        if ($relationship) { $relationships.Add($relationship) }
                    }
                }
            }

            'microsoft.network/networkinterfaces' {
                $nsgId = [string](Get-CollectorNetworkProperty $row 'nicNetworkSecurityGroupId')
                $virtualMachineId = [string](Get-CollectorNetworkProperty $row 'nicVirtualMachineId')
                $networkInterfaces.Add([pscustomobject][ordered]@{
                    id                          = $id
                    name                        = $name
                    subscriptionId              = $subscriptionId
                    resourceGroup               = $resourceGroup
                    location                    = $location
                    networkSecurityGroupId      = $nsgId
                    virtualMachineId            = $virtualMachineId
                    enableAcceleratedNetworking = Get-CollectorNetworkProperty $row 'nicEnableAcceleratedNetworking'
                    enableIpForwarding          = Get-CollectorNetworkProperty $row 'nicEnableIpForwarding'
                    macAddress                  = [string](Get-CollectorNetworkProperty $row 'nicMacAddress')
                    dnsServers                  = ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty $row 'nicDnsServers')
                    tags                        = $tags
                })

                foreach ($target in @(
                    [pscustomobject]@{ Id = $nsgId; Relation = 'SecuredBy' },
                    [pscustomobject]@{ Id = $virtualMachineId; Relation = 'AttachedToVm' }
                )) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                        $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship $target.Relation -TargetId ([string]$target.Id)
                        if ($relationship) { $relationships.Add($relationship) }
                    }
                }

                foreach ($ipConfig in @(Get-CollectorNetworkProperty $row 'nicIpConfigurations')) {
                    $ipProperties = Get-CollectorNetworkProperty $ipConfig 'properties'
                    $ipConfigName = [string](Get-CollectorNetworkProperty $ipConfig 'name')
                    $ipConfigId = [string](Get-CollectorNetworkProperty $ipConfig 'id')
                    if ([string]::IsNullOrWhiteSpace($ipConfigId) -and -not [string]::IsNullOrWhiteSpace($ipConfigName)) {
                        $ipConfigId = '{0}/ipConfigurations/{1}' -f $id, $ipConfigName
                    }
                    $subnetId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $ipProperties 'subnet') 'id')
                    $publicIpId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $ipProperties 'publicIPAddress') 'id')

                    $ipConfigurations.Add([pscustomobject][ordered]@{
                        id                        = $ipConfigId
                        name                      = $ipConfigName
                        networkInterfaceId        = $id
                        privateIpAddress          = [string](Get-CollectorNetworkProperty $ipProperties 'privateIPAddress')
                        privateIpAllocationMethod = [string](Get-CollectorNetworkProperty $ipProperties 'privateIPAllocationMethod')
                        privateIpAddressVersion   = [string](Get-CollectorNetworkProperty $ipProperties 'privateIPAddressVersion')
                        primary                   = Get-CollectorNetworkProperty $ipProperties 'primary'
                        subnetId                  = $subnetId
                        publicIpAddressId         = $publicIpId
                    })

                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'HasIpConfiguration' -TargetId $ipConfigId
                    if ($relationship) { $relationships.Add($relationship) }
                    foreach ($target in @(
                        [pscustomobject]@{ Id = $subnetId; Relation = 'AttachedToSubnet' },
                        [pscustomobject]@{ Id = $publicIpId; Relation = 'UsesPublicIp' }
                    )) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                            $relationship = New-CollectorNetworkRelationship -SourceId $ipConfigId -Relationship $target.Relation -TargetId ([string]$target.Id)
                            if ($relationship) { $relationships.Add($relationship) }
                        }
                    }
                }
            }

            'microsoft.network/networksecuritygroups' {
                $networkSecurityGroups.Add([pscustomobject][ordered]@{
                    id              = $id
                    name            = $name
                    subscriptionId  = $subscriptionId
                    resourceGroup   = $resourceGroup
                    location        = $location
                    flushConnection = Get-CollectorNetworkProperty $row 'nsgFlushConnection'
                    tags            = $tags
                })

                foreach ($rule in @(Get-CollectorNetworkProperty $row 'nsgSecurityRules')) {
                    $ruleProperties = Get-CollectorNetworkProperty $rule 'properties'
                    $ruleName = [string](Get-CollectorNetworkProperty $rule 'name')
                    $ruleId = [string](Get-CollectorNetworkProperty $rule 'id')
                    if ([string]::IsNullOrWhiteSpace($ruleId) -and -not [string]::IsNullOrWhiteSpace($ruleName)) {
                        $ruleId = '{0}/securityRules/{1}' -f $id, $ruleName
                    }

                    $sourceAddressPrefixes = @()
                    $singleSource = [string](Get-CollectorNetworkProperty $ruleProperties 'sourceAddressPrefix')
                    if (-not [string]::IsNullOrWhiteSpace($singleSource)) { $sourceAddressPrefixes += $singleSource }
                    $sourceAddressPrefixes += @(ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty $ruleProperties 'sourceAddressPrefixes'))

                    $destinationAddressPrefixes = @()
                    $singleDestination = [string](Get-CollectorNetworkProperty $ruleProperties 'destinationAddressPrefix')
                    if (-not [string]::IsNullOrWhiteSpace($singleDestination)) { $destinationAddressPrefixes += $singleDestination }
                    $destinationAddressPrefixes += @(ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty $ruleProperties 'destinationAddressPrefixes'))

                    $sourcePortRanges = @()
                    $singleSourcePort = [string](Get-CollectorNetworkProperty $ruleProperties 'sourcePortRange')
                    if (-not [string]::IsNullOrWhiteSpace($singleSourcePort)) { $sourcePortRanges += $singleSourcePort }
                    $sourcePortRanges += @(ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty $ruleProperties 'sourcePortRanges'))

                    $destinationPortRanges = @()
                    $singleDestinationPort = [string](Get-CollectorNetworkProperty $ruleProperties 'destinationPortRange')
                    if (-not [string]::IsNullOrWhiteSpace($singleDestinationPort)) { $destinationPortRanges += $singleDestinationPort }
                    $destinationPortRanges += @(ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty $ruleProperties 'destinationPortRanges'))

                    $securityRules.Add([pscustomobject][ordered]@{
                        id                           = $ruleId
                        name                         = $ruleName
                        networkSecurityGroupId       = $id
                        priority                     = Get-CollectorNetworkProperty $ruleProperties 'priority'
                        direction                    = [string](Get-CollectorNetworkProperty $ruleProperties 'direction')
                        access                       = [string](Get-CollectorNetworkProperty $ruleProperties 'access')
                        protocol                     = [string](Get-CollectorNetworkProperty $ruleProperties 'protocol')
                        sourceAddressPrefixes        = @($sourceAddressPrefixes | Sort-Object -Unique)
                        sourcePortRanges             = @($sourcePortRanges | Sort-Object -Unique)
                        destinationAddressPrefixes   = @($destinationAddressPrefixes | Sort-Object -Unique)
                        destinationPortRanges        = @($destinationPortRanges | Sort-Object -Unique)
                        sourceApplicationSecurityGroupIds = ConvertTo-CollectorNetworkIdArray (Get-CollectorNetworkProperty $ruleProperties 'sourceApplicationSecurityGroups')
                        destinationApplicationSecurityGroupIds = ConvertTo-CollectorNetworkIdArray (Get-CollectorNetworkProperty $ruleProperties 'destinationApplicationSecurityGroups')
                    })

                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsSecurityRule' -TargetId $ruleId
                    if ($relationship) { $relationships.Add($relationship) }
                }
            }

            'microsoft.network/publicipaddresses' {
                $publicIpAddresses.Add([pscustomobject][ordered]@{
                    id                    = $id
                    name                  = $name
                    subscriptionId        = $subscriptionId
                    resourceGroup         = $resourceGroup
                    location              = $location
                    skuName               = [string](Get-CollectorNetworkProperty $row 'skuName')
                    skuTier               = [string](Get-CollectorNetworkProperty $row 'skuTier')
                    ipAddress             = [string](Get-CollectorNetworkProperty $row 'publicIpAddress')
                    allocationMethod      = [string](Get-CollectorNetworkProperty $row 'publicIpAllocationMethod')
                    ipAddressVersion      = [string](Get-CollectorNetworkProperty $row 'publicIpAddressVersion')
                    idleTimeoutInMinutes  = Get-CollectorNetworkProperty $row 'publicIpIdleTimeoutMinutes'
                    fqdn                  = [string](Get-CollectorNetworkProperty $row 'publicIpDnsFqdn')
                    tags                  = $tags
                })
            }

            'microsoft.network/routetables' {
                $routeTables.Add([pscustomobject][ordered]@{
                    id                         = $id
                    name                       = $name
                    subscriptionId             = $subscriptionId
                    resourceGroup              = $resourceGroup
                    location                   = $location
                    disableBgpRoutePropagation = Get-CollectorNetworkProperty $row 'routeTableDisableBgpRoutePropagation'
                    tags                       = $tags
                })

                foreach ($route in @(Get-CollectorNetworkProperty $row 'routeTableRoutes')) {
                    $routeProperties = Get-CollectorNetworkProperty $route 'properties'
                    $routeName = [string](Get-CollectorNetworkProperty $route 'name')
                    $routeId = [string](Get-CollectorNetworkProperty $route 'id')
                    if ([string]::IsNullOrWhiteSpace($routeId) -and -not [string]::IsNullOrWhiteSpace($routeName)) {
                        $routeId = '{0}/routes/{1}' -f $id, $routeName
                    }
                    $routes.Add([pscustomobject][ordered]@{
                        id               = $routeId
                        name             = $routeName
                        routeTableId     = $id
                        addressPrefix    = [string](Get-CollectorNetworkProperty $routeProperties 'addressPrefix')
                        nextHopType      = [string](Get-CollectorNetworkProperty $routeProperties 'nextHopType')
                        nextHopIpAddress = [string](Get-CollectorNetworkProperty $routeProperties 'nextHopIpAddress')
                    })
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsRoute' -TargetId $routeId
                    if ($relationship) { $relationships.Add($relationship) }
                }
            }

            'microsoft.network/virtualnetworkgateways' {
                $gatewayIpConfigurations = @()
                foreach ($ipConfig in @(Get-CollectorNetworkProperty $row 'gatewayIpConfigurations')) {
                    $ipProperties = Get-CollectorNetworkProperty $ipConfig 'properties'
                    $subnetId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $ipProperties 'subnet') 'id')
                    $publicIpId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $ipProperties 'publicIPAddress') 'id')
                    $gatewayIpConfigurations += [pscustomobject][ordered]@{
                        name                      = [string](Get-CollectorNetworkProperty $ipConfig 'name')
                        privateIpAllocationMethod = [string](Get-CollectorNetworkProperty $ipProperties 'privateIPAllocationMethod')
                        subnetId                  = $subnetId
                        publicIpAddressId         = $publicIpId
                    }
                    foreach ($target in @(
                        [pscustomobject]@{ Id = $subnetId; Relation = 'AttachedToSubnet' },
                        [pscustomobject]@{ Id = $publicIpId; Relation = 'UsesPublicIp' }
                    )) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                            $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship $target.Relation -TargetId ([string]$target.Id)
                            if ($relationship) { $relationships.Add($relationship) }
                        }
                    }
                }

                $virtualNetworkGateways.Add([pscustomobject][ordered]@{
                    id                = $id
                    name              = $name
                    subscriptionId    = $subscriptionId
                    resourceGroup     = $resourceGroup
                    location          = $location
                    gatewayType       = [string](Get-CollectorNetworkProperty $row 'gatewayType')
                    vpnType           = [string](Get-CollectorNetworkProperty $row 'gatewayVpnType')
                    skuName           = [string](Get-CollectorNetworkProperty $row 'skuName')
                    skuTier           = [string](Get-CollectorNetworkProperty $row 'skuTier')
                    enableBgp         = Get-CollectorNetworkProperty $row 'gatewayEnableBgp'
                    activeActive      = Get-CollectorNetworkProperty $row 'gatewayActiveActive'
                    bgpAsn            = Get-CollectorNetworkProperty $row 'gatewayBgpAsn'
                    bgpPeeringAddress = [string](Get-CollectorNetworkProperty $row 'gatewayBgpPeeringAddress')
                    ipConfigurations  = @($gatewayIpConfigurations)
                    tags              = $tags
                })
            }

            'microsoft.network/localnetworkgateways' {
                $localNetworkGateways.Add([pscustomobject][ordered]@{
                    id                = $id
                    name              = $name
                    subscriptionId    = $subscriptionId
                    resourceGroup     = $resourceGroup
                    location          = $location
                    gatewayIpAddress  = [string](Get-CollectorNetworkProperty $row 'localGatewayIpAddress')
                    fqdn              = [string](Get-CollectorNetworkProperty $row 'localGatewayFqdn')
                    addressPrefixes   = ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty $row 'localGatewayAddressPrefixes')
                    bgpAsn            = Get-CollectorNetworkProperty $row 'localGatewayBgpAsn'
                    bgpPeerWeight     = Get-CollectorNetworkProperty $row 'localGatewayBgpPeerWeight'
                    bgpPeeringAddress = [string](Get-CollectorNetworkProperty $row 'localGatewayBgpPeeringAddress')
                    tags              = $tags
                })
            }

            'microsoft.network/connections' {
                $virtualGateway1Id = [string](Get-CollectorNetworkProperty $row 'connectionVirtualNetworkGateway1Id')
                $virtualGateway2Id = [string](Get-CollectorNetworkProperty $row 'connectionVirtualNetworkGateway2Id')
                $localGateway2Id = [string](Get-CollectorNetworkProperty $row 'connectionLocalNetworkGateway2Id')

                $connections.Add([pscustomobject][ordered]@{
                    id                             = $id
                    name                           = $name
                    subscriptionId                 = $subscriptionId
                    resourceGroup                  = $resourceGroup
                    location                       = $location
                    connectionType                 = [string](Get-CollectorNetworkProperty $row 'connectionType')
                    connectionProtocol             = [string](Get-CollectorNetworkProperty $row 'connectionProtocol')
                    enableBgp                      = Get-CollectorNetworkProperty $row 'connectionEnableBgp'
                    routingWeight                  = Get-CollectorNetworkProperty $row 'connectionRoutingWeight'
                    usePolicyBasedTrafficSelectors = Get-CollectorNetworkProperty $row 'connectionUsePolicyBasedTrafficSelectors'
                    dpdTimeoutSeconds              = Get-CollectorNetworkProperty $row 'connectionDpdTimeoutSeconds'
                    virtualNetworkGateway1Id       = $virtualGateway1Id
                    virtualNetworkGateway2Id       = $virtualGateway2Id
                    localNetworkGateway2Id         = $localGateway2Id
                    tags                           = $tags
                })

                foreach ($target in @(
                    [pscustomobject]@{ Id = $virtualGateway1Id; Relation = 'UsesVirtualNetworkGateway' },
                    [pscustomobject]@{ Id = $virtualGateway2Id; Relation = 'UsesVirtualNetworkGateway' },
                    [pscustomobject]@{ Id = $localGateway2Id; Relation = 'UsesLocalNetworkGateway' }
                )) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                        $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship $target.Relation -TargetId ([string]$target.Id)
                        if ($relationship) { $relationships.Add($relationship) }
                    }
                }
            }

            'microsoft.network/networkwatchers' {
                $networkWatchers.Add([pscustomobject][ordered]@{
                    id             = $id
                    name           = $name
                    subscriptionId = $subscriptionId
                    resourceGroup  = $resourceGroup
                    location       = $location
                    tags           = $tags
                })
            }

            'microsoft.network/privateendpoints' {
                $subnetId = [string](Get-CollectorNetworkProperty $row 'privateEndpointSubnetId')
                $privateEndpoints.Add([pscustomobject][ordered]@{
                    id             = $id
                    name           = $name
                    subscriptionId = $subscriptionId
                    resourceGroup  = $resourceGroup
                    location       = $location
                    subnetId       = $subnetId
                    tags           = $tags
                })

                if (-not [string]::IsNullOrWhiteSpace($subnetId)) {
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'AttachedToSubnet' -TargetId $subnetId
                    if ($relationship) { $relationships.Add($relationship) }
                }

                foreach ($connectionSet in @(
                    [pscustomobject]@{ Mode = 'Automatic'; Items = @(Get-CollectorNetworkProperty $row 'privateEndpointConnections') },
                    [pscustomobject]@{ Mode = 'Manual'; Items = @(Get-CollectorNetworkProperty $row 'privateEndpointManualConnections') }
                )) {
                    $index = 0
                    foreach ($connection in @($connectionSet.Items)) {
                        $index++
                        if ($null -eq $connection) { continue }
                        $connectionProperties = Get-CollectorNetworkProperty $connection 'properties'
                        $connectionState = Get-CollectorNetworkProperty $connectionProperties 'privateLinkServiceConnectionState'
                        $connectionId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'privateLinkServiceConnections' -Child $connection -Index $index
                        $connectionName = [string](Get-CollectorNetworkProperty $connection 'name')
                        $targetResourceId = [string](Get-CollectorNetworkProperty $connectionProperties 'privateLinkServiceId')

                        $privateLinkConnections.Add([pscustomobject][ordered]@{
                            id                    = $connectionId
                            name                  = $connectionName
                            privateEndpointId     = $id
                            connectionMode        = [string]$connectionSet.Mode
                            privateLinkServiceId  = $targetResourceId
                            groupIds              = ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty $connectionProperties 'groupIds')
                            status                = [string](Get-CollectorNetworkProperty $connectionState 'status')
                            actionsRequired       = [string](Get-CollectorNetworkProperty $connectionState 'actionsRequired')
                        })

                        $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsPrivateLinkConnection' -TargetId $connectionId
                        if ($relationship) { $relationships.Add($relationship) }
                        if (-not [string]::IsNullOrWhiteSpace($targetResourceId)) {
                            $relationship = New-CollectorNetworkRelationship -SourceId $connectionId -Relationship 'ConnectsToResource' -TargetId $targetResourceId
                            if ($relationship) { $relationships.Add($relationship) }
                            $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ConnectsToResource' -TargetId $targetResourceId
                            if ($relationship) { $relationships.Add($relationship) }
                        }
                    }
                }
            }

            'microsoft.network/privatednszones' {
                $privateDnsZones.Add([pscustomobject][ordered]@{
                    id             = $id
                    name           = $name
                    subscriptionId = $subscriptionId
                    resourceGroup  = $resourceGroup
                    location       = $location
                    tags           = $tags
                })
            }

            'microsoft.network/privatednszones/virtualnetworklinks' {
                $zoneId = $id -replace '(?i)/virtualNetworkLinks/[^/]+$',''
                $linkName = $name
                if ($linkName -match '/') {
                    $linkName = ($linkName -split '/')[-1]
                }
                $virtualNetworkId = [string](Get-CollectorNetworkProperty $row 'privateDnsLinkVirtualNetworkId')

                $privateDnsVirtualNetworkLinks.Add([pscustomobject][ordered]@{
                    id                  = $id
                    name                = $linkName
                    privateDnsZoneId    = $zoneId
                    subscriptionId      = $subscriptionId
                    resourceGroup       = $resourceGroup
                    location            = $location
                    virtualNetworkId    = $virtualNetworkId
                    registrationEnabled = Get-CollectorNetworkProperty $row 'privateDnsLinkRegistrationEnabled'
                    resolutionPolicy    = [string](Get-CollectorNetworkProperty $row 'privateDnsLinkResolutionPolicy')
                    tags                = $tags
                })

                if (-not [string]::IsNullOrWhiteSpace($zoneId)) {
                    $relationship = New-CollectorNetworkRelationship -SourceId $zoneId -Relationship 'ContainsVirtualNetworkLink' -TargetId $id
                    if ($relationship) { $relationships.Add($relationship) }
                }
                if (-not [string]::IsNullOrWhiteSpace($virtualNetworkId)) {
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'LinkedToVNet' -TargetId $virtualNetworkId
                    if ($relationship) { $relationships.Add($relationship) }
                    if (-not [string]::IsNullOrWhiteSpace($zoneId)) {
                        $relationship = New-CollectorNetworkRelationship -SourceId $zoneId -Relationship 'LinkedToVNet' -TargetId $virtualNetworkId
                        if ($relationship) { $relationships.Add($relationship) }
                    }
                }
            }

            'microsoft.network/natgateways' {
                $publicIpIds = ConvertTo-CollectorNetworkIdArray (Get-CollectorNetworkProperty $row 'natGatewayPublicIpAddresses')
                $publicIpPrefixIds = ConvertTo-CollectorNetworkIdArray (Get-CollectorNetworkProperty $row 'natGatewayPublicIpPrefixes')
                $natGateways.Add([pscustomobject][ordered]@{
                    id                   = $id
                    name                 = $name
                    subscriptionId       = $subscriptionId
                    resourceGroup        = $resourceGroup
                    location             = $location
                    skuName              = [string](Get-CollectorNetworkProperty $row 'skuName')
                    zones                = $zones
                    idleTimeoutInMinutes = Get-CollectorNetworkProperty $row 'natGatewayIdleTimeoutMinutes'
                    publicIpAddressIds   = $publicIpIds
                    publicIpPrefixIds    = $publicIpPrefixIds
                    tags                 = $tags
                })

                foreach ($publicIpId in @($publicIpIds)) {
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'UsesPublicIp' -TargetId $publicIpId
                    if ($relationship) { $relationships.Add($relationship) }
                }
                foreach ($publicIpPrefixId in @($publicIpPrefixIds)) {
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'UsesPublicIpPrefix' -TargetId $publicIpPrefixId
                    if ($relationship) { $relationships.Add($relationship) }
                }
            }

            'microsoft.network/loadbalancers' {
                $loadBalancers.Add([pscustomobject][ordered]@{
                    id             = $id
                    name           = $name
                    subscriptionId = $subscriptionId
                    resourceGroup  = $resourceGroup
                    location       = $location
                    skuName        = [string](Get-CollectorNetworkProperty $row 'skuName')
                    skuTier        = [string](Get-CollectorNetworkProperty $row 'skuTier')
                    scope          = [string](Get-CollectorNetworkProperty $row 'loadBalancerScope')
                    tags           = $tags
                })

                $index = 0
                foreach ($frontend in @(Get-CollectorNetworkProperty $row 'loadBalancerFrontendIpConfigurations')) {
                    $index++
                    $frontendProperties = Get-CollectorNetworkProperty $frontend 'properties'
                    $frontendId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'frontendIPConfigurations' -Child $frontend -Index $index
                    $frontendName = [string](Get-CollectorNetworkProperty $frontend 'name')
                    $subnetId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $frontendProperties 'subnet') 'id')
                    $publicIpId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $frontendProperties 'publicIPAddress') 'id')
                    $publicIpPrefixId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $frontendProperties 'publicIPPrefix') 'id')

                    $loadBalancerFrontendIpConfigurations.Add([pscustomobject][ordered]@{
                        id                        = $frontendId
                        name                      = $frontendName
                        loadBalancerId            = $id
                        privateIpAddress          = [string](Get-CollectorNetworkProperty $frontendProperties 'privateIPAddress')
                        privateIpAllocationMethod = [string](Get-CollectorNetworkProperty $frontendProperties 'privateIPAllocationMethod')
                        privateIpAddressVersion   = [string](Get-CollectorNetworkProperty $frontendProperties 'privateIPAddressVersion')
                        subnetId                  = $subnetId
                        publicIpAddressId         = $publicIpId
                        publicIpPrefixId          = $publicIpPrefixId
                        zones                     = ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty $frontend 'zones')
                    })

                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsLoadBalancerFrontend' -TargetId $frontendId
                    if ($relationship) { $relationships.Add($relationship) }
                    foreach ($target in @(
                        [pscustomobject]@{ Id = $subnetId; Relation = 'AttachedToSubnet' },
                        [pscustomobject]@{ Id = $publicIpId; Relation = 'UsesPublicIp' },
                        [pscustomobject]@{ Id = $publicIpPrefixId; Relation = 'UsesPublicIpPrefix' }
                    )) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                            $relationship = New-CollectorNetworkRelationship -SourceId $frontendId -Relationship $target.Relation -TargetId ([string]$target.Id)
                            if ($relationship) { $relationships.Add($relationship) }
                        }
                    }
                }

                $poolIndex = 0
                foreach ($pool in @(Get-CollectorNetworkProperty $row 'loadBalancerBackendAddressPools')) {
                    $poolIndex++
                    $poolProperties = Get-CollectorNetworkProperty $pool 'properties'
                    $poolId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'backendAddressPools' -Child $pool -Index $poolIndex
                    $poolName = [string](Get-CollectorNetworkProperty $pool 'name')
                    $virtualNetworkId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $poolProperties 'virtualNetwork') 'id')
                    $backendAddresses = @(Get-CollectorNetworkProperty $poolProperties 'loadBalancerBackendAddresses')

                    $loadBalancerBackendPools.Add([pscustomobject][ordered]@{
                        id                     = $poolId
                        name                   = $poolName
                        loadBalancerId         = $id
                        virtualNetworkId       = $virtualNetworkId
                        syncMode               = [string](Get-CollectorNetworkProperty $poolProperties 'syncMode')
                        backendAddressCount    = $backendAddresses.Count
                    })

                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsLoadBalancerBackendPool' -TargetId $poolId
                    if ($relationship) { $relationships.Add($relationship) }
                    if (-not [string]::IsNullOrWhiteSpace($virtualNetworkId)) {
                        $relationship = New-CollectorNetworkRelationship -SourceId $poolId -Relationship 'AttachedToVNet' -TargetId $virtualNetworkId
                        if ($relationship) { $relationships.Add($relationship) }
                    }

                    $backendIndex = 0
                    foreach ($backend in $backendAddresses) {
                        $backendIndex++
                        $backendProperties = Get-CollectorNetworkProperty $backend 'properties'
                        $backendId = Get-CollectorNetworkChildId -ParentId $poolId -CollectionName 'backendAddresses' -Child $backend -Index $backendIndex
                        $backendName = [string](Get-CollectorNetworkProperty $backend 'name')
                        $backendSubnetId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $backendProperties 'subnet') 'id')
                        $backendVnetId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $backendProperties 'virtualNetwork') 'id')
                        $backendFrontendId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $backendProperties 'loadBalancerFrontendIPConfiguration') 'id')

                        $loadBalancerBackendAddresses.Add([pscustomobject][ordered]@{
                            id                            = $backendId
                            name                          = $backendName
                            backendPoolId                 = $poolId
                            ipAddress                     = [string](Get-CollectorNetworkProperty $backendProperties 'ipAddress')
                            adminState                    = [string](Get-CollectorNetworkProperty $backendProperties 'adminState')
                            subnetId                      = $backendSubnetId
                            virtualNetworkId              = $backendVnetId
                            frontendIpConfigurationId     = $backendFrontendId
                        })

                        $relationship = New-CollectorNetworkRelationship -SourceId $poolId -Relationship 'ContainsBackendAddress' -TargetId $backendId
                        if ($relationship) { $relationships.Add($relationship) }
                        foreach ($target in @(
                            [pscustomobject]@{ Id = $backendSubnetId; Relation = 'AttachedToSubnet' },
                            [pscustomobject]@{ Id = $backendVnetId; Relation = 'AttachedToVNet' },
                            [pscustomobject]@{ Id = $backendFrontendId; Relation = 'UsesLoadBalancerFrontend' }
                        )) {
                            if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                                $relationship = New-CollectorNetworkRelationship -SourceId $backendId -Relationship $target.Relation -TargetId ([string]$target.Id)
                                if ($relationship) { $relationships.Add($relationship) }
                            }
                        }
                    }
                }

                $probeIndex = 0
                foreach ($probe in @(Get-CollectorNetworkProperty $row 'loadBalancerProbes')) {
                    $probeIndex++
                    $probeProperties = Get-CollectorNetworkProperty $probe 'properties'
                    $probeId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'probes' -Child $probe -Index $probeIndex
                    $loadBalancerProbes.Add([pscustomobject][ordered]@{
                        id                        = $probeId
                        name                      = [string](Get-CollectorNetworkProperty $probe 'name')
                        loadBalancerId            = $id
                        protocol                  = [string](Get-CollectorNetworkProperty $probeProperties 'protocol')
                        port                      = Get-CollectorNetworkProperty $probeProperties 'port'
                        intervalInSeconds         = Get-CollectorNetworkProperty $probeProperties 'intervalInSeconds'
                        numberOfProbes            = Get-CollectorNetworkProperty $probeProperties 'numberOfProbes'
                        probeThreshold            = Get-CollectorNetworkProperty $probeProperties 'probeThreshold'
                        requestPath               = [string](Get-CollectorNetworkProperty $probeProperties 'requestPath')
                        noHealthyBackendsBehavior = [string](Get-CollectorNetworkProperty $probeProperties 'noHealthyBackendsBehavior')
                    })
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsLoadBalancerProbe' -TargetId $probeId
                    if ($relationship) { $relationships.Add($relationship) }
                }

                $ruleIndex = 0
                foreach ($rule in @(Get-CollectorNetworkProperty $row 'loadBalancerRules')) {
                    $ruleIndex++
                    $ruleProperties = Get-CollectorNetworkProperty $rule 'properties'
                    $ruleId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'loadBalancingRules' -Child $rule -Index $ruleIndex
                    $frontendId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $ruleProperties 'frontendIPConfiguration') 'id')
                    $probeId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $ruleProperties 'probe') 'id')
                    $backendPoolIds = @()
                    $singleBackendPoolId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $ruleProperties 'backendAddressPool') 'id')
                    if (-not [string]::IsNullOrWhiteSpace($singleBackendPoolId)) {
                        $backendPoolIds += $singleBackendPoolId
                    }
                    $additionalBackendPoolIds = ConvertTo-CollectorNetworkIdArray (Get-CollectorNetworkProperty $ruleProperties 'backendAddressPools')
                    foreach ($additionalBackendPoolId in @($additionalBackendPoolIds)) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$additionalBackendPoolId)) {
                            $backendPoolIds += [string]$additionalBackendPoolId
                        }
                    }
                    $backendPoolIds = @($backendPoolIds | Sort-Object -Unique)

                    $loadBalancerRules.Add([pscustomobject][ordered]@{
                        id                       = $ruleId
                        name                     = [string](Get-CollectorNetworkProperty $rule 'name')
                        loadBalancerId           = $id
                        protocol                 = [string](Get-CollectorNetworkProperty $ruleProperties 'protocol')
                        frontendPort             = Get-CollectorNetworkProperty $ruleProperties 'frontendPort'
                        backendPort              = Get-CollectorNetworkProperty $ruleProperties 'backendPort'
                        frontendIpConfigurationId = $frontendId
                        backendAddressPoolIds    = $backendPoolIds
                        probeId                  = $probeId
                        loadDistribution         = [string](Get-CollectorNetworkProperty $ruleProperties 'loadDistribution')
                        idleTimeoutInMinutes     = Get-CollectorNetworkProperty $ruleProperties 'idleTimeoutInMinutes'
                        disableOutboundSnat      = Get-CollectorNetworkProperty $ruleProperties 'disableOutboundSnat'
                        enableFloatingIp         = Get-CollectorNetworkProperty $ruleProperties 'enableFloatingIP'
                        enableTcpReset           = Get-CollectorNetworkProperty $ruleProperties 'enableTcpReset'
                    })

                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsLoadBalancerRule' -TargetId $ruleId
                    if ($relationship) { $relationships.Add($relationship) }
                    if (-not [string]::IsNullOrWhiteSpace($frontendId)) {
                        $relationship = New-CollectorNetworkRelationship -SourceId $ruleId -Relationship 'UsesLoadBalancerFrontend' -TargetId $frontendId
                        if ($relationship) { $relationships.Add($relationship) }
                    }
                    foreach ($backendPoolId in $backendPoolIds) {
                        $relationship = New-CollectorNetworkRelationship -SourceId $ruleId -Relationship 'UsesLoadBalancerBackendPool' -TargetId $backendPoolId
                        if ($relationship) { $relationships.Add($relationship) }
                    }
                    if (-not [string]::IsNullOrWhiteSpace($probeId)) {
                        $relationship = New-CollectorNetworkRelationship -SourceId $ruleId -Relationship 'UsesLoadBalancerProbe' -TargetId $probeId
                        if ($relationship) { $relationships.Add($relationship) }
                    }
                }

                $outboundIndex = 0
                foreach ($outboundRule in @(Get-CollectorNetworkProperty $row 'loadBalancerOutboundRules')) {
                    $outboundIndex++
                    $outboundProperties = Get-CollectorNetworkProperty $outboundRule 'properties'
                    $outboundId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'outboundRules' -Child $outboundRule -Index $outboundIndex
                    $backendPoolId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $outboundProperties 'backendAddressPool') 'id')
                    $frontendIds = ConvertTo-CollectorNetworkIdArray (Get-CollectorNetworkProperty $outboundProperties 'frontendIPConfigurations')

                    $loadBalancerOutboundRules.Add([pscustomobject][ordered]@{
                        id                       = $outboundId
                        name                     = [string](Get-CollectorNetworkProperty $outboundRule 'name')
                        loadBalancerId           = $id
                        protocol                 = [string](Get-CollectorNetworkProperty $outboundProperties 'protocol')
                        backendAddressPoolId     = $backendPoolId
                        frontendIpConfigurationIds = $frontendIds
                        allocatedOutboundPorts   = Get-CollectorNetworkProperty $outboundProperties 'allocatedOutboundPorts'
                        idleTimeoutInMinutes     = Get-CollectorNetworkProperty $outboundProperties 'idleTimeoutInMinutes'
                        enableTcpReset           = Get-CollectorNetworkProperty $outboundProperties 'enableTcpReset'
                    })

                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsLoadBalancerOutboundRule' -TargetId $outboundId
                    if ($relationship) { $relationships.Add($relationship) }
                    if (-not [string]::IsNullOrWhiteSpace($backendPoolId)) {
                        $relationship = New-CollectorNetworkRelationship -SourceId $outboundId -Relationship 'UsesLoadBalancerBackendPool' -TargetId $backendPoolId
                        if ($relationship) { $relationships.Add($relationship) }
                    }
                    foreach ($frontendId in @($frontendIds)) {
                        $relationship = New-CollectorNetworkRelationship -SourceId $outboundId -Relationship 'UsesLoadBalancerFrontend' -TargetId $frontendId
                        if ($relationship) { $relationships.Add($relationship) }
                    }
                }
            }

            'microsoft.network/applicationgateways' {
                $firewallPolicyId = [string](Get-CollectorNetworkProperty $row 'applicationGatewayFirewallPolicyId')
                $applicationGateways.Add([pscustomobject][ordered]@{
                    id               = $id
                    name             = $name
                    subscriptionId   = $subscriptionId
                    resourceGroup    = $resourceGroup
                    location         = $location
                    skuName          = [string](Get-CollectorNetworkProperty $row 'applicationGatewaySkuName')
                    skuTier          = [string](Get-CollectorNetworkProperty $row 'applicationGatewaySkuTier')
                    skuCapacity      = Get-CollectorNetworkProperty $row 'applicationGatewaySkuCapacity'
                    autoscaleMinCapacity = Get-CollectorNetworkProperty $row 'applicationGatewayAutoscaleMinCapacity'
                    autoscaleMaxCapacity = Get-CollectorNetworkProperty $row 'applicationGatewayAutoscaleMaxCapacity'
                    enableHttp2      = Get-CollectorNetworkProperty $row 'applicationGatewayEnableHttp2'
                    firewallPolicyId = $firewallPolicyId
                    zones            = $zones
                    tags             = $tags
                })

                if (-not [string]::IsNullOrWhiteSpace($firewallPolicyId)) {
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'UsesFirewallPolicy' -TargetId $firewallPolicyId
                    if ($relationship) { $relationships.Add($relationship) }
                }

                $index = 0
                foreach ($ipConfig in @(Get-CollectorNetworkProperty $row 'applicationGatewayIpConfigurations')) {
                    $index++
                    $properties = Get-CollectorNetworkProperty $ipConfig 'properties'
                    $childId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'gatewayIPConfigurations' -Child $ipConfig -Index $index
                    $subnetId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'subnet') 'id')
                    $applicationGatewayIpConfigurations.Add([pscustomobject][ordered]@{
                        id                   = $childId
                        name                 = [string](Get-CollectorNetworkProperty $ipConfig 'name')
                        applicationGatewayId = $id
                        subnetId             = $subnetId
                    })
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsApplicationGatewayIpConfiguration' -TargetId $childId
                    if ($relationship) { $relationships.Add($relationship) }
                    if (-not [string]::IsNullOrWhiteSpace($subnetId)) {
                        $relationship = New-CollectorNetworkRelationship -SourceId $childId -Relationship 'AttachedToSubnet' -TargetId $subnetId
                        if ($relationship) { $relationships.Add($relationship) }
                    }
                }

                $index = 0
                foreach ($frontend in @(Get-CollectorNetworkProperty $row 'applicationGatewayFrontendIpConfigurations')) {
                    $index++
                    $properties = Get-CollectorNetworkProperty $frontend 'properties'
                    $childId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'frontendIPConfigurations' -Child $frontend -Index $index
                    $subnetId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'subnet') 'id')
                    $publicIpId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'publicIPAddress') 'id')
                    $applicationGatewayFrontendIpConfigurations.Add([pscustomobject][ordered]@{
                        id                        = $childId
                        name                      = [string](Get-CollectorNetworkProperty $frontend 'name')
                        applicationGatewayId      = $id
                        privateIpAddress          = [string](Get-CollectorNetworkProperty $properties 'privateIPAddress')
                        privateIpAllocationMethod = [string](Get-CollectorNetworkProperty $properties 'privateIPAllocationMethod')
                        subnetId                  = $subnetId
                        publicIpAddressId         = $publicIpId
                    })
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsApplicationGatewayFrontend' -TargetId $childId
                    if ($relationship) { $relationships.Add($relationship) }
                    foreach ($target in @(
                        [pscustomobject]@{ Id = $subnetId; Relation = 'AttachedToSubnet' },
                        [pscustomobject]@{ Id = $publicIpId; Relation = 'UsesPublicIp' }
                    )) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                            $relationship = New-CollectorNetworkRelationship -SourceId $childId -Relationship $target.Relation -TargetId ([string]$target.Id)
                            if ($relationship) { $relationships.Add($relationship) }
                        }
                    }
                }

                $index = 0
                foreach ($port in @(Get-CollectorNetworkProperty $row 'applicationGatewayFrontendPorts')) {
                    $index++
                    $properties = Get-CollectorNetworkProperty $port 'properties'
                    $childId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'frontendPorts' -Child $port -Index $index
                    $applicationGatewayFrontendPorts.Add([pscustomobject][ordered]@{
                        id                   = $childId
                        name                 = [string](Get-CollectorNetworkProperty $port 'name')
                        applicationGatewayId = $id
                        port                 = Get-CollectorNetworkProperty $properties 'port'
                    })
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsApplicationGatewayFrontendPort' -TargetId $childId
                    if ($relationship) { $relationships.Add($relationship) }
                }

                $poolIndex = 0
                foreach ($pool in @(Get-CollectorNetworkProperty $row 'applicationGatewayBackendAddressPools')) {
                    $poolIndex++
                    $properties = Get-CollectorNetworkProperty $pool 'properties'
                    $poolId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'backendAddressPools' -Child $pool -Index $poolIndex
                    $backendAddresses = @(Get-CollectorNetworkProperty $properties 'backendAddresses')
                    $applicationGatewayBackendPools.Add([pscustomobject][ordered]@{
                        id                   = $poolId
                        name                 = [string](Get-CollectorNetworkProperty $pool 'name')
                        applicationGatewayId = $id
                        backendAddressCount  = $backendAddresses.Count
                    })
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsApplicationGatewayBackendPool' -TargetId $poolId
                    if ($relationship) { $relationships.Add($relationship) }

                    $backendIndex = 0
                    foreach ($backendAddress in $backendAddresses) {
                        $backendIndex++
                        $backendId = '{0}/backendAddresses/item-{1}' -f $poolId, $backendIndex
                        $applicationGatewayBackendAddresses.Add([pscustomobject][ordered]@{
                            id            = $backendId
                            backendPoolId = $poolId
                            ipAddress     = [string](Get-CollectorNetworkProperty $backendAddress 'ipAddress')
                            fqdn          = [string](Get-CollectorNetworkProperty $backendAddress 'fqdn')
                        })
                        $relationship = New-CollectorNetworkRelationship -SourceId $poolId -Relationship 'ContainsBackendAddress' -TargetId $backendId
                        if ($relationship) { $relationships.Add($relationship) }
                    }
                }

                $index = 0
                foreach ($settings in @(Get-CollectorNetworkProperty $row 'applicationGatewayBackendHttpSettings')) {
                    $index++
                    $properties = Get-CollectorNetworkProperty $settings 'properties'
                    $childId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'backendHttpSettingsCollection' -Child $settings -Index $index
                    $probeId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'probe') 'id')
                    $applicationGatewayBackendHttpSettings.Add([pscustomobject][ordered]@{
                        id                            = $childId
                        name                          = [string](Get-CollectorNetworkProperty $settings 'name')
                        applicationGatewayId          = $id
                        port                          = Get-CollectorNetworkProperty $properties 'port'
                        protocol                      = [string](Get-CollectorNetworkProperty $properties 'protocol')
                        cookieBasedAffinity           = [string](Get-CollectorNetworkProperty $properties 'cookieBasedAffinity')
                        requestTimeout                = Get-CollectorNetworkProperty $properties 'requestTimeout'
                        pickHostNameFromBackendAddress = Get-CollectorNetworkProperty $properties 'pickHostNameFromBackendAddress'
                        probeId                       = $probeId
                    })
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsApplicationGatewayBackendHttpSettings' -TargetId $childId
                    if ($relationship) { $relationships.Add($relationship) }
                    if (-not [string]::IsNullOrWhiteSpace($probeId)) {
                        $relationship = New-CollectorNetworkRelationship -SourceId $childId -Relationship 'UsesApplicationGatewayProbe' -TargetId $probeId
                        if ($relationship) { $relationships.Add($relationship) }
                    }
                }

                $index = 0
                foreach ($probe in @(Get-CollectorNetworkProperty $row 'applicationGatewayProbes')) {
                    $index++
                    $properties = Get-CollectorNetworkProperty $probe 'properties'
                    $childId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'probes' -Child $probe -Index $index
                    $match = Get-CollectorNetworkProperty $properties 'match'
                    $applicationGatewayProbes.Add([pscustomobject][ordered]@{
                        id                            = $childId
                        name                          = [string](Get-CollectorNetworkProperty $probe 'name')
                        applicationGatewayId          = $id
                        protocol                      = [string](Get-CollectorNetworkProperty $properties 'protocol')
                        host                          = [string](Get-CollectorNetworkProperty $properties 'host')
                        path                          = [string](Get-CollectorNetworkProperty $properties 'path')
                        port                          = Get-CollectorNetworkProperty $properties 'port'
                        interval                      = Get-CollectorNetworkProperty $properties 'interval'
                        timeout                       = Get-CollectorNetworkProperty $properties 'timeout'
                        unhealthyThreshold            = Get-CollectorNetworkProperty $properties 'unhealthyThreshold'
                        pickHostNameFromBackendHttpSettings = Get-CollectorNetworkProperty $properties 'pickHostNameFromBackendHttpSettings'
                        statusCodes                   = ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty $match 'statusCodes')
                    })
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsApplicationGatewayProbe' -TargetId $childId
                    if ($relationship) { $relationships.Add($relationship) }
                }

                $index = 0
                foreach ($listener in @(Get-CollectorNetworkProperty $row 'applicationGatewayHttpListeners')) {
                    $index++
                    $properties = Get-CollectorNetworkProperty $listener 'properties'
                    $childId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'httpListeners' -Child $listener -Index $index
                    $frontendId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'frontendIPConfiguration') 'id')
                    $frontendPortId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'frontendPort') 'id')
                    $listenerFirewallPolicyId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'firewallPolicy') 'id')
                    $applicationGatewayHttpListeners.Add([pscustomobject][ordered]@{
                        id                      = $childId
                        name                    = [string](Get-CollectorNetworkProperty $listener 'name')
                        applicationGatewayId    = $id
                        frontendIpConfigurationId = $frontendId
                        frontendPortId          = $frontendPortId
                        protocol                = [string](Get-CollectorNetworkProperty $properties 'protocol')
                        hostName                = [string](Get-CollectorNetworkProperty $properties 'hostName')
                        requireServerNameIndication = Get-CollectorNetworkProperty $properties 'requireServerNameIndication'
                        firewallPolicyId        = $listenerFirewallPolicyId
                    })
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsApplicationGatewayHttpListener' -TargetId $childId
                    if ($relationship) { $relationships.Add($relationship) }
                    foreach ($target in @(
                        [pscustomobject]@{ Id = $frontendId; Relation = 'UsesApplicationGatewayFrontend' },
                        [pscustomobject]@{ Id = $frontendPortId; Relation = 'UsesApplicationGatewayFrontendPort' },
                        [pscustomobject]@{ Id = $listenerFirewallPolicyId; Relation = 'UsesFirewallPolicy' }
                    )) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                            $relationship = New-CollectorNetworkRelationship -SourceId $childId -Relationship $target.Relation -TargetId ([string]$target.Id)
                            if ($relationship) { $relationships.Add($relationship) }
                        }
                    }
                }

                $index = 0
                foreach ($rule in @(Get-CollectorNetworkProperty $row 'applicationGatewayRequestRoutingRules')) {
                    $index++
                    $properties = Get-CollectorNetworkProperty $rule 'properties'
                    $childId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'requestRoutingRules' -Child $rule -Index $index
                    $listenerId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'httpListener') 'id')
                    $backendPoolId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'backendAddressPool') 'id')
                    $backendHttpSettingsId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'backendHttpSettings') 'id')
                    $urlPathMapId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'urlPathMap') 'id')
                    $redirectConfigurationId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'redirectConfiguration') 'id')
                    $applicationGatewayRequestRoutingRules.Add([pscustomobject][ordered]@{
                        id                    = $childId
                        name                  = [string](Get-CollectorNetworkProperty $rule 'name')
                        applicationGatewayId  = $id
                        ruleType              = [string](Get-CollectorNetworkProperty $properties 'ruleType')
                        priority              = Get-CollectorNetworkProperty $properties 'priority'
                        httpListenerId        = $listenerId
                        backendAddressPoolId  = $backendPoolId
                        backendHttpSettingsId = $backendHttpSettingsId
                        urlPathMapId          = $urlPathMapId
                        redirectConfigurationId = $redirectConfigurationId
                    })
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsApplicationGatewayRoutingRule' -TargetId $childId
                    if ($relationship) { $relationships.Add($relationship) }
                    foreach ($target in @(
                        [pscustomobject]@{ Id = $listenerId; Relation = 'UsesApplicationGatewayHttpListener' },
                        [pscustomobject]@{ Id = $backendPoolId; Relation = 'UsesApplicationGatewayBackendPool' },
                        [pscustomobject]@{ Id = $backendHttpSettingsId; Relation = 'UsesApplicationGatewayBackendHttpSettings' },
                        [pscustomobject]@{ Id = $urlPathMapId; Relation = 'UsesApplicationGatewayUrlPathMap' }
                    )) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                            $relationship = New-CollectorNetworkRelationship -SourceId $childId -Relationship $target.Relation -TargetId ([string]$target.Id)
                            if ($relationship) { $relationships.Add($relationship) }
                        }
                    }
                }

                $mapIndex = 0
                foreach ($urlPathMap in @(Get-CollectorNetworkProperty $row 'applicationGatewayUrlPathMaps')) {
                    $mapIndex++
                    $properties = Get-CollectorNetworkProperty $urlPathMap 'properties'
                    $mapId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'urlPathMaps' -Child $urlPathMap -Index $mapIndex
                    $defaultBackendPoolId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'defaultBackendAddressPool') 'id')
                    $defaultBackendHttpSettingsId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'defaultBackendHttpSettings') 'id')
                    $defaultRedirectConfigurationId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'defaultRedirectConfiguration') 'id')
                    $pathRules = @(Get-CollectorNetworkProperty $properties 'pathRules')
                    $applicationGatewayUrlPathMaps.Add([pscustomobject][ordered]@{
                        id                           = $mapId
                        name                         = [string](Get-CollectorNetworkProperty $urlPathMap 'name')
                        applicationGatewayId         = $id
                        defaultBackendAddressPoolId  = $defaultBackendPoolId
                        defaultBackendHttpSettingsId = $defaultBackendHttpSettingsId
                        defaultRedirectConfigurationId = $defaultRedirectConfigurationId
                        pathRuleCount                = $pathRules.Count
                    })
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsApplicationGatewayUrlPathMap' -TargetId $mapId
                    if ($relationship) { $relationships.Add($relationship) }
                    foreach ($target in @(
                        [pscustomobject]@{ Id = $defaultBackendPoolId; Relation = 'UsesApplicationGatewayBackendPool' },
                        [pscustomobject]@{ Id = $defaultBackendHttpSettingsId; Relation = 'UsesApplicationGatewayBackendHttpSettings' }
                    )) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                            $relationship = New-CollectorNetworkRelationship -SourceId $mapId -Relationship $target.Relation -TargetId ([string]$target.Id)
                            if ($relationship) { $relationships.Add($relationship) }
                        }
                    }

                    $pathIndex = 0
                    foreach ($pathRule in $pathRules) {
                        $pathIndex++
                        $pathProperties = Get-CollectorNetworkProperty $pathRule 'properties'
                        $pathRuleId = Get-CollectorNetworkChildId -ParentId $mapId -CollectionName 'pathRules' -Child $pathRule -Index $pathIndex
                        $backendPoolId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $pathProperties 'backendAddressPool') 'id')
                        $backendHttpSettingsId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $pathProperties 'backendHttpSettings') 'id')
                        $redirectConfigurationId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $pathProperties 'redirectConfiguration') 'id')
                        $applicationGatewayPathRules.Add([pscustomobject][ordered]@{
                            id                    = $pathRuleId
                            name                  = [string](Get-CollectorNetworkProperty $pathRule 'name')
                            urlPathMapId          = $mapId
                            paths                 = ConvertTo-CollectorNetworkStringArray (Get-CollectorNetworkProperty $pathProperties 'paths')
                            backendAddressPoolId  = $backendPoolId
                            backendHttpSettingsId = $backendHttpSettingsId
                            redirectConfigurationId = $redirectConfigurationId
                        })
                        $relationship = New-CollectorNetworkRelationship -SourceId $mapId -Relationship 'ContainsApplicationGatewayPathRule' -TargetId $pathRuleId
                        if ($relationship) { $relationships.Add($relationship) }
                        foreach ($target in @(
                            [pscustomobject]@{ Id = $backendPoolId; Relation = 'UsesApplicationGatewayBackendPool' },
                            [pscustomobject]@{ Id = $backendHttpSettingsId; Relation = 'UsesApplicationGatewayBackendHttpSettings' }
                        )) {
                            if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                                $relationship = New-CollectorNetworkRelationship -SourceId $pathRuleId -Relationship $target.Relation -TargetId ([string]$target.Id)
                                if ($relationship) { $relationships.Add($relationship) }
                            }
                        }
                    }
                }
            }

            'microsoft.network/azurefirewalls' {
                $firewallPolicyId = [string](Get-CollectorNetworkProperty $row 'azureFirewallPolicyId')
                $virtualHubId = [string](Get-CollectorNetworkProperty $row 'azureFirewallVirtualHubId')
                $azureFirewalls.Add([pscustomobject][ordered]@{
                    id              = $id
                    name            = $name
                    subscriptionId  = $subscriptionId
                    resourceGroup   = $resourceGroup
                    location        = $location
                    skuName         = [string](Get-CollectorNetworkProperty $row 'azureFirewallSkuName')
                    skuTier         = [string](Get-CollectorNetworkProperty $row 'azureFirewallSkuTier')
                    threatIntelMode = [string](Get-CollectorNetworkProperty $row 'azureFirewallThreatIntelMode')
                    firewallPolicyId = $firewallPolicyId
                    virtualHubId    = $virtualHubId
                    zones           = $zones
                    tags            = $tags
                })

                foreach ($target in @(
                    [pscustomobject]@{ Id = $firewallPolicyId; Relation = 'UsesFirewallPolicy' },
                    [pscustomobject]@{ Id = $virtualHubId; Relation = 'AttachedToVirtualHub' }
                )) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                        $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship $target.Relation -TargetId ([string]$target.Id)
                        if ($relationship) { $relationships.Add($relationship) }
                    }
                }

                $index = 0
                foreach ($ipConfig in @(Get-CollectorNetworkProperty $row 'azureFirewallIpConfigurations')) {
                    $index++
                    $properties = Get-CollectorNetworkProperty $ipConfig 'properties'
                    $childId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'ipConfigurations' -Child $ipConfig -Index $index
                    $subnetId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'subnet') 'id')
                    $publicIpId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'publicIPAddress') 'id')
                    $azureFirewallIpConfigurations.Add([pscustomobject][ordered]@{
                        id              = $childId
                        name            = [string](Get-CollectorNetworkProperty $ipConfig 'name')
                        azureFirewallId = $id
                        role            = 'Data'
                        privateIpAddress = [string](Get-CollectorNetworkProperty $properties 'privateIPAddress')
                        subnetId        = $subnetId
                        publicIpAddressId = $publicIpId
                    })
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsAzureFirewallIpConfiguration' -TargetId $childId
                    if ($relationship) { $relationships.Add($relationship) }
                    foreach ($target in @(
                        [pscustomobject]@{ Id = $subnetId; Relation = 'AttachedToSubnet' },
                        [pscustomobject]@{ Id = $publicIpId; Relation = 'UsesPublicIp' }
                    )) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                            $relationship = New-CollectorNetworkRelationship -SourceId $childId -Relationship $target.Relation -TargetId ([string]$target.Id)
                            if ($relationship) { $relationships.Add($relationship) }
                        }
                    }
                }

                $managementIpConfig = Get-CollectorNetworkProperty $row 'azureFirewallManagementIpConfiguration'
                if ($null -ne $managementIpConfig) {
                    $properties = Get-CollectorNetworkProperty $managementIpConfig 'properties'
                    $childId = Get-CollectorNetworkChildId -ParentId $id -CollectionName 'managementIpConfiguration' -Child $managementIpConfig -Index 1
                    $subnetId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'subnet') 'id')
                    $publicIpId = [string](Get-CollectorNetworkProperty (Get-CollectorNetworkProperty $properties 'publicIPAddress') 'id')
                    $azureFirewallIpConfigurations.Add([pscustomobject][ordered]@{
                        id               = $childId
                        name             = [string](Get-CollectorNetworkProperty $managementIpConfig 'name')
                        azureFirewallId  = $id
                        role             = 'Management'
                        privateIpAddress = [string](Get-CollectorNetworkProperty $properties 'privateIPAddress')
                        subnetId         = $subnetId
                        publicIpAddressId = $publicIpId
                    })
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'ContainsAzureFirewallManagementIpConfiguration' -TargetId $childId
                    if ($relationship) { $relationships.Add($relationship) }
                    foreach ($target in @(
                        [pscustomobject]@{ Id = $subnetId; Relation = 'AttachedToSubnet' },
                        [pscustomobject]@{ Id = $publicIpId; Relation = 'UsesPublicIp' }
                    )) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$target.Id)) {
                            $relationship = New-CollectorNetworkRelationship -SourceId $childId -Relationship $target.Relation -TargetId ([string]$target.Id)
                            if ($relationship) { $relationships.Add($relationship) }
                        }
                    }
                }
            }

            'microsoft.network/firewallpolicies' {
                $basePolicyId = [string](Get-CollectorNetworkProperty $row 'firewallPolicyBasePolicyId')
                $firewallPolicies.Add([pscustomobject][ordered]@{
                    id              = $id
                    name            = $name
                    subscriptionId  = $subscriptionId
                    resourceGroup   = $resourceGroup
                    location        = $location
                    skuTier         = [string](Get-CollectorNetworkProperty $row 'firewallPolicySkuTier')
                    threatIntelMode = [string](Get-CollectorNetworkProperty $row 'firewallPolicyThreatIntelMode')
                    basePolicyId    = $basePolicyId
                    tags            = $tags
                })
                if (-not [string]::IsNullOrWhiteSpace($basePolicyId)) {
                    $relationship = New-CollectorNetworkRelationship -SourceId $id -Relationship 'InheritsFromFirewallPolicy' -TargetId $basePolicyId
                    if ($relationship) { $relationships.Add($relationship) }
                }
            }
        }
    }

    $sortedRelationships = @($relationships | Sort-Object sourceId, relationship, targetId -Unique)

    [pscustomobject][ordered]@{
        schemaVersion          = '1.0'
        summary                = [pscustomobject][ordered]@{
            virtualNetworks        = $virtualNetworks.Count
            subnets                = $subnets.Count
            peerings               = $peerings.Count
            networkInterfaces      = $networkInterfaces.Count
            ipConfigurations       = $ipConfigurations.Count
            networkSecurityGroups  = $networkSecurityGroups.Count
            securityRules          = $securityRules.Count
            publicIpAddresses      = $publicIpAddresses.Count
            routeTables            = $routeTables.Count
            routes                 = $routes.Count
            virtualNetworkGateways = $virtualNetworkGateways.Count
            localNetworkGateways   = $localNetworkGateways.Count
            connections            = $connections.Count
            networkWatchers        = $networkWatchers.Count
            privateEndpoints       = $privateEndpoints.Count
            privateLinkConnections = $privateLinkConnections.Count
            privateDnsZones        = $privateDnsZones.Count
            privateDnsVirtualNetworkLinks = $privateDnsVirtualNetworkLinks.Count
            natGateways            = $natGateways.Count
            loadBalancers          = $loadBalancers.Count
            loadBalancerFrontends  = $loadBalancerFrontendIpConfigurations.Count
            loadBalancerBackendPools = $loadBalancerBackendPools.Count
            loadBalancerBackendAddresses = $loadBalancerBackendAddresses.Count
            loadBalancerRules      = $loadBalancerRules.Count
            loadBalancerProbes     = $loadBalancerProbes.Count
            loadBalancerOutboundRules = $loadBalancerOutboundRules.Count
            applicationGateways    = $applicationGateways.Count
            applicationGatewayIpConfigurations = $applicationGatewayIpConfigurations.Count
            applicationGatewayFrontends = $applicationGatewayFrontendIpConfigurations.Count
            applicationGatewayFrontendPorts = $applicationGatewayFrontendPorts.Count
            applicationGatewayBackendPools = $applicationGatewayBackendPools.Count
            applicationGatewayBackendAddresses = $applicationGatewayBackendAddresses.Count
            applicationGatewayBackendHttpSettings = $applicationGatewayBackendHttpSettings.Count
            applicationGatewayHttpListeners = $applicationGatewayHttpListeners.Count
            applicationGatewayRoutingRules = $applicationGatewayRequestRoutingRules.Count
            applicationGatewayProbes = $applicationGatewayProbes.Count
            applicationGatewayUrlPathMaps = $applicationGatewayUrlPathMaps.Count
            applicationGatewayPathRules = $applicationGatewayPathRules.Count
            azureFirewalls          = $azureFirewalls.Count
            azureFirewallIpConfigurations = $azureFirewallIpConfigurations.Count
            firewallPolicies        = $firewallPolicies.Count
            relationships          = $sortedRelationships.Count
        }
        virtualNetworks        = @($virtualNetworks | Sort-Object subscriptionId, resourceGroup, name, id)
        subnets                = @($subnets | Sort-Object subscriptionId, resourceGroup, virtualNetworkId, name, id)
        peerings               = @($peerings | Sort-Object virtualNetworkId, name, id)
        networkInterfaces      = @($networkInterfaces | Sort-Object subscriptionId, resourceGroup, name, id)
        ipConfigurations       = @($ipConfigurations | Sort-Object networkInterfaceId, name, id)
        networkSecurityGroups  = @($networkSecurityGroups | Sort-Object subscriptionId, resourceGroup, name, id)
        securityRules          = @($securityRules | Sort-Object networkSecurityGroupId, priority, name, id)
        publicIpAddresses      = @($publicIpAddresses | Sort-Object subscriptionId, resourceGroup, name, id)
        routeTables            = @($routeTables | Sort-Object subscriptionId, resourceGroup, name, id)
        routes                 = @($routes | Sort-Object routeTableId, name, id)
        virtualNetworkGateways = @($virtualNetworkGateways | Sort-Object subscriptionId, resourceGroup, name, id)
        localNetworkGateways   = @($localNetworkGateways | Sort-Object subscriptionId, resourceGroup, name, id)
        connections            = @($connections | Sort-Object subscriptionId, resourceGroup, name, id)
        networkWatchers        = @($networkWatchers | Sort-Object subscriptionId, resourceGroup, name, id)
        privateEndpoints       = @($privateEndpoints | Sort-Object subscriptionId, resourceGroup, name, id)
        privateLinkConnections = @($privateLinkConnections | Sort-Object privateEndpointId, name, id)
        privateDnsZones        = @($privateDnsZones | Sort-Object subscriptionId, resourceGroup, name, id)
        privateDnsVirtualNetworkLinks = @($privateDnsVirtualNetworkLinks | Sort-Object privateDnsZoneId, name, id)
        natGateways            = @($natGateways | Sort-Object subscriptionId, resourceGroup, name, id)
        loadBalancers          = @($loadBalancers | Sort-Object subscriptionId, resourceGroup, name, id)
        loadBalancerFrontendIpConfigurations = @($loadBalancerFrontendIpConfigurations | Sort-Object loadBalancerId, name, id)
        loadBalancerBackendPools = @($loadBalancerBackendPools | Sort-Object loadBalancerId, name, id)
        loadBalancerBackendAddresses = @($loadBalancerBackendAddresses | Sort-Object backendPoolId, name, id)
        loadBalancerRules      = @($loadBalancerRules | Sort-Object loadBalancerId, name, id)
        loadBalancerProbes     = @($loadBalancerProbes | Sort-Object loadBalancerId, name, id)
        loadBalancerOutboundRules = @($loadBalancerOutboundRules | Sort-Object loadBalancerId, name, id)
        applicationGateways    = @($applicationGateways | Sort-Object subscriptionId, resourceGroup, name, id)
        applicationGatewayIpConfigurations = @($applicationGatewayIpConfigurations | Sort-Object applicationGatewayId, name, id)
        applicationGatewayFrontendIpConfigurations = @($applicationGatewayFrontendIpConfigurations | Sort-Object applicationGatewayId, name, id)
        applicationGatewayFrontendPorts = @($applicationGatewayFrontendPorts | Sort-Object applicationGatewayId, port, name, id)
        applicationGatewayBackendPools = @($applicationGatewayBackendPools | Sort-Object applicationGatewayId, name, id)
        applicationGatewayBackendAddresses = @($applicationGatewayBackendAddresses | Sort-Object backendPoolId, fqdn, ipAddress, id)
        applicationGatewayBackendHttpSettings = @($applicationGatewayBackendHttpSettings | Sort-Object applicationGatewayId, name, id)
        applicationGatewayHttpListeners = @($applicationGatewayHttpListeners | Sort-Object applicationGatewayId, name, id)
        applicationGatewayRequestRoutingRules = @($applicationGatewayRequestRoutingRules | Sort-Object applicationGatewayId, priority, name, id)
        applicationGatewayProbes = @($applicationGatewayProbes | Sort-Object applicationGatewayId, name, id)
        applicationGatewayUrlPathMaps = @($applicationGatewayUrlPathMaps | Sort-Object applicationGatewayId, name, id)
        applicationGatewayPathRules = @($applicationGatewayPathRules | Sort-Object urlPathMapId, name, id)
        azureFirewalls         = @($azureFirewalls | Sort-Object subscriptionId, resourceGroup, name, id)
        azureFirewallIpConfigurations = @($azureFirewallIpConfigurations | Sort-Object azureFirewallId, role, name, id)
        firewallPolicies       = @($firewallPolicies | Sort-Object subscriptionId, resourceGroup, name, id)
        relationships          = $sortedRelationships
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-CollectorNetworkInventory'
)
