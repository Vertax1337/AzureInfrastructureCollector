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
    $relationships = [System.Collections.Generic.List[object]]::new()

    foreach ($row in @($Rows)) {
        $id = [string](Get-CollectorNetworkProperty -InputObject $row -Name 'id')
        $name = [string](Get-CollectorNetworkProperty -InputObject $row -Name 'name')
        $type = ([string](Get-CollectorNetworkProperty -InputObject $row -Name 'type')).ToLowerInvariant()
        $subscriptionId = [string](Get-CollectorNetworkProperty -InputObject $row -Name 'subscriptionId')
        $resourceGroup = [string](Get-CollectorNetworkProperty -InputObject $row -Name 'resourceGroup')
        $location = [string](Get-CollectorNetworkProperty -InputObject $row -Name 'location')
        $tags = Get-CollectorNetworkProperty -InputObject $row -Name 'tags'

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
        relationships          = $sortedRelationships
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-CollectorNetworkInventory'
)
