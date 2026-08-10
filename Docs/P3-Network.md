# P3 – Network

Status: **P3a validated; P3b implemented and awaiting Pre-Azure/real-export validation**  
Project: `AzureInfrastructureCollector`  
Safety boundary: **Read-only / fail closed**

## Goal

P3 extends the already validated Core inventory with an explicit, normalized Azure network topology. The output must be suitable for deterministic technical documentation and later relationship/diagram generation without requiring an AI model to infer relationships from resource names.

## P3a – Network topology foundation

P3a collects only explicitly selected, documentation-relevant fields for:

- Virtual Networks
- Subnets
- Virtual Network Peerings
- Network Interfaces
- NIC IP Configurations
- Network Security Groups
- custom NSG Security Rules
- Public IP Addresses
- Route Tables
- Routes
- Virtual Network Gateways
- Local Network Gateways, including separate IP-address and FQDN endpoint fields
- VPN/ER/VNet Connections
- Network Watchers

### Explicit relationships

P3a emits stable Resource-ID-based relationships, including:

```text
VNet -> ContainsSubnet -> Subnet
VNet -> PeeredWith -> VNet
Subnet -> SecuredBy -> NSG
Subnet -> UsesRouteTable -> RouteTable
Subnet -> UsesNatGateway -> NAT Gateway
NIC -> SecuredBy -> NSG
NIC -> AttachedToVm -> VM
NIC -> HasIpConfiguration -> IP Configuration
IP Configuration -> AttachedToSubnet -> Subnet
IP Configuration -> UsesPublicIp -> Public IP
NSG -> ContainsSecurityRule -> Security Rule
RouteTable -> ContainsRoute -> Route
VirtualNetworkGateway -> AttachedToSubnet -> Subnet
VirtualNetworkGateway -> UsesPublicIp -> Public IP
Connection -> UsesVirtualNetworkGateway -> Virtual Network Gateway
Connection -> UsesLocalNetworkGateway -> Local Network Gateway
```

Relationship keys are Azure Resource IDs, not display names.

## P3a validation real-run – 2026-08-10 14:41

The follow-up real export after the export-shape and FQDN fixes completed successfully and confirmed the intended P3a data model:

- collector status `Success`
- `READ-ONLY VERIFIED`
- 12 Resource Groups
- 134 Core resources
- 22 top-level Network resources
- 5 VNets
- 5 Subnets
- 12 directed Peerings
- 4 NICs and 4 IP configurations
- 4 NSGs and 4 custom Security Rules
- 3 Public IPs
- 1 Route Table with 2 Routes
- 1 Virtual Network Gateway
- 1 Local Network Gateway
- 1 Connection
- 2 Network Watchers
- 44 unique Relationships
- 0 collector errors

Validation results:

- all 22 Network top-level IDs match the 22 `Microsoft.Network/*` IDs in the Core inventory,
- all 44 Relationships are unique,
- every relationship source/target resolves to a collected top-level resource, normalized child object, or matching Core resource; orphan count = 0,
- Network summary counts exactly match the actual array lengths,
- no ETS/array-metadata leakage (`Length`, `Count`, `SyncRoot`, `Rank`, `IsFixedSize`, etc.) remains in `network.json` or `readOnlyVerification.json`,
- address prefixes, DNS servers, service endpoints and NSG source/destination/port fields are real string arrays,
- `approvedAzureCommandsFound` is an array of readable command-name strings,
- the Local Network Gateway is correctly represented with `gatewayIpAddress: ""` and `fqdn: "vpn.cannon-deutschland.de"`,
- no `sharedKey`, SAS signature, account key, private key, JWT-shaped token or embedded credential assignment was found in the export.

The export ZIP does not currently persist the detailed Pre-Azure/Pester result or exact passed-test count. The real export therefore proves the collector/read-only/export behavior, while the exact Pester count remains console evidence until validation metadata is embedded into the manifest in a future Core improvement.

## P3b – Extended network services

P3b extends the same `Inventory/network.json`; no parallel export/security path is introduced.

### P3b resource scope

P3b adds normalized collections for:

- Private Endpoints
- Private Link connections
- Private DNS Zones
- Private DNS VNet Links
- NAT Gateways
- Load Balancers
- Load Balancer frontend IP configurations
- Load Balancer backend pools and explicit backend addresses
- Load Balancer rules, probes and outbound rules
- Application Gateways
- Application Gateway IP configurations and frontend IP configurations
- Application Gateway frontend ports
- Application Gateway backend pools and backend addresses
- Application Gateway backend HTTP settings
- Application Gateway HTTP listeners
- Application Gateway request-routing rules
- Application Gateway probes
- Application Gateway URL path maps and path rules
- Azure Firewalls
- Azure Firewall IP/management IP configurations
- Firewall Policies at topology/SKU/inheritance level

### P3b data-minimization boundary

P3b deliberately does **not normalize or export**:

- VPN connection `sharedKey`,
- Private Endpoint `requestMessage`,
- Private Link connection-state descriptions,
- Application Gateway SSL certificate payloads,
- Application Gateway authentication certificate payloads,
- Azure Firewall application/network/NAT rule collections,
- Firewall Policy transport-security certificate/secret configuration,
- complete raw Azure `properties` blocks.

Some parent resources are returned by Azure Resource Graph with nested child structures needed for deterministic topology extraction. Only the explicitly normalized fields listed in this document are allowed to reach `network.json`; transient source properties that are not part of the normalized model are discarded before export.

Application Gateway certificate **material** is outside the P3 scope. The collector documents routing/topology, not certificate contents.

Azure Firewall rule content is reserved for a later explicit Security/Governance decision; P3b captures only network placement, SKU, threat-intelligence mode, policy association and IP configuration references.

### P3b explicit relationships

P3b adds Resource-ID-based relationships such as:

```text
PrivateEndpoint -> AttachedToSubnet -> Subnet
PrivateEndpoint -> ContainsPrivateLinkConnection -> PrivateLinkConnection
PrivateLinkConnection -> ConnectsToResource -> TargetResource
PrivateEndpoint -> ConnectsToResource -> TargetResource

PrivateDnsZone -> ContainsVirtualNetworkLink -> PrivateDnsVirtualNetworkLink
PrivateDnsVirtualNetworkLink -> LinkedToVNet -> VNet
PrivateDnsZone -> LinkedToVNet -> VNet

NatGateway -> UsesPublicIp -> PublicIp
NatGateway -> UsesPublicIpPrefix -> PublicIpPrefix
Subnet -> UsesNatGateway -> NatGateway  # already supplied by P3a subnet normalization

LoadBalancer -> ContainsLoadBalancerFrontend -> Frontend
LoadBalancer -> ContainsLoadBalancerBackendPool -> BackendPool
LoadBalancer -> ContainsLoadBalancerRule -> Rule
LoadBalancer -> ContainsLoadBalancerProbe -> Probe
LoadBalancer -> ContainsLoadBalancerOutboundRule -> OutboundRule
LoadBalancerFrontend -> AttachedToSubnet / UsesPublicIp / UsesPublicIpPrefix
LoadBalancerRule -> UsesLoadBalancerFrontend / UsesLoadBalancerBackendPool / UsesLoadBalancerProbe

ApplicationGateway -> ContainsApplicationGatewayIpConfiguration -> IpConfiguration
ApplicationGatewayIpConfiguration -> AttachedToSubnet -> Subnet
ApplicationGateway -> ContainsApplicationGatewayFrontend -> Frontend
ApplicationGatewayFrontend -> AttachedToSubnet / UsesPublicIp
ApplicationGateway -> ContainsApplicationGatewayBackendPool -> BackendPool
ApplicationGateway -> ContainsApplicationGatewayHttpListener -> Listener
ApplicationGateway -> ContainsApplicationGatewayRoutingRule -> RoutingRule
RoutingRule -> UsesApplicationGatewayHttpListener / BackendPool / BackendHttpSettings / UrlPathMap
ApplicationGateway -> UsesFirewallPolicy -> FirewallPolicy

AzureFirewall -> UsesFirewallPolicy -> FirewallPolicy
AzureFirewall -> AttachedToVirtualHub -> VirtualHub
AzureFirewall -> ContainsAzureFirewallIpConfiguration -> IpConfiguration
AzureFirewallIpConfiguration -> AttachedToSubnet / UsesPublicIp
FirewallPolicy -> InheritsFromFirewallPolicy -> BasePolicy
```

Synthetic IDs are only used for Azure child entries that do not expose their own Resource ID in the selected parent-resource representation. Synthetic IDs are deterministic descendants of the Azure parent ID and stable child name/index; Azure Resource IDs remain the preferred key whenever available.

## Network output

The normal collector writes:

```text
Inventory/network.json
```

P3a/P3b collections include:

- `virtualNetworks`
- `subnets`
- `peerings`
- `networkInterfaces`
- `ipConfigurations`
- `networkSecurityGroups`
- `securityRules`
- `publicIpAddresses`
- `routeTables`
- `routes`
- `virtualNetworkGateways`
- `localNetworkGateways`
- `connections`
- `networkWatchers`
- `privateEndpoints`
- `privateLinkConnections`
- `privateDnsZones`
- `privateDnsVirtualNetworkLinks`
- `natGateways`
- `loadBalancers`
- `loadBalancerFrontendIpConfigurations`
- `loadBalancerBackendPools`
- `loadBalancerBackendAddresses`
- `loadBalancerRules`
- `loadBalancerProbes`
- `loadBalancerOutboundRules`
- `applicationGateways`
- `applicationGatewayIpConfigurations`
- `applicationGatewayFrontendIpConfigurations`
- `applicationGatewayFrontendPorts`
- `applicationGatewayBackendPools`
- `applicationGatewayBackendAddresses`
- `applicationGatewayBackendHttpSettings`
- `applicationGatewayHttpListeners`
- `applicationGatewayRequestRoutingRules`
- `applicationGatewayProbes`
- `applicationGatewayUrlPathMaps`
- `applicationGatewayPathRules`
- `azureFirewalls`
- `azureFirewallIpConfigurations`
- `firewallPolicies`
- `relationships`

`summary.json` receives the complete Network summary as a nested `network` object.

For `localNetworkGateways`, `gatewayIpAddress` and `fqdn` remain distinct fields. The collector preserves whichever Azure configuration is present and does not synthesize one endpoint type from the other.

## Safety and data-minimization rules

P3 continues to use only the existing, allowlisted `Search-AzGraph` path through `Invoke-CollectorResourceGraph`.

P3b introduces no additional Azure PowerShell cmdlet, direct REST request, Azure CLI call, SDK write path or data-plane operation.

Only explicitly selected Azure Resource Graph properties are projected. Full resource `properties` blocks are not exported.

The final `network.json` object passes through `Collector.ExportSecurity.psm1` before writing. Existing property-name and value-based secret filtering therefore applies equally to P3a and P3b.

The export hardening must preserve scalar and collection shape. String values must remain strings, arrays must remain arrays, and PowerShell ETS adapter metadata such as `Length`, `Count`, `SyncRoot` or array type metadata must never replace the underlying values in JSON.

## P3b tests

P3b adds dedicated Unit tests for:

1. the P3b query resource scope and explicit exclusion of sensitive configuration bodies,
2. Private Endpoint / Private Link normalization and target/subnet relationships,
3. Private DNS Zone / VNet-Link normalization,
4. NAT Gateway public-IP/public-prefix references,
5. Load Balancer frontend/backend/rule/probe relationships,
6. Application Gateway routing normalization without certificate material,
7. Azure Firewall / Firewall Policy topology without rule collections,
8. empty-array stability for every new P3b collection.

## Definition of Done P3b

P3b is complete only when:

1. the current executable repository passes automatic Pre-Azure validation,
2. both read-only gates return `READ-ONLY VERIFIED`,
3. Pester reports zero failed tests,
4. a real Azure run completes without new Azure write operations,
5. `network.json` remains structurally stable and P3a fields/counts remain intact,
6. all P3b summary counts match their arrays,
7. P3b relationships are unique and plausible; orphan relationships are either zero or explicitly explainable by references to valid Core resources outside the Network module,
8. no secret-like values or certificate material are exported,
9. VPN `sharedKey`, Private Link request messages and Azure Firewall rule bodies remain absent,
10. Private Endpoints, Private DNS links, NAT, Load Balancer, Application Gateway and Azure Firewall/Policy are represented correctly where present,
11. the Core inventory remains unchanged except for actual Azure-state changes unrelated to the collector.

Until these checks pass on a real export, **P3b is implemented but not validated/closed**.
