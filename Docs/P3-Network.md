# P3 – Network

Status: **Started**  
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
- Local Network Gateways
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

## P3a output

The normal collector writes:

```text
Inventory/network.json
```

The document contains:

- `schemaVersion`
- `summary`
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
- `relationships`

`summary.json` receives the P3 network summary as a nested `network` object.

## Safety and data-minimization rules

P3 continues to use only the existing, already allowlisted `Search-AzGraph` path through `Invoke-CollectorResourceGraph`.

No additional Azure PowerShell cmdlet, REST request, Azure CLI call, SDK write path or data-plane operation is introduced by P3a.

Only explicitly selected Azure Resource Graph properties are projected. Full resource `properties` blocks are not exported.

### VPN connection shared key

`Microsoft.Network/connections.properties.sharedKey` is deliberately excluded from `Queries/Network.kql` and from the normalized model. It must never be added to an export query or schema.

### NSG descriptions

Free-form NSG rule descriptions are deliberately not part of the initial normalized schema. P3a focuses on deterministic rule semantics: priority, direction, access, protocol, source/destination prefixes and ports, and ASG references.

### Export hardening

The final `network.json` object passes through `Collector.ExportSecurity.psm1` before writing. Existing property-name and value-based secret filtering therefore applies to P3 and to future network extensions.

## P3b – Extended network services

P3b is planned after P3a has passed local Pre-Azure validation and a real export review. Planned scope:

- Private Endpoints
- Private DNS Zones and VNet links
- NAT Gateways
- Load Balancers
- Application Gateways
- Azure Firewall / Firewall Policy references
- additional network relationship coverage where Resource Graph exposes sufficient safe metadata

P3b must not broaden the export to complete raw `properties` blocks merely for convenience.

## Definition of Done P3a

P3a is complete only when:

1. the current executable repository passes automatic Pre-Azure validation,
2. both read-only gates return `READ-ONLY VERIFIED`,
3. Pester reports zero failed tests,
4. a real Azure run completes without new Azure write operations,
5. `network.json` is structurally stable,
6. network counts and relationships are plausible against the Azure environment,
7. no secret-like values are exported,
8. VPN connection `sharedKey` is absent from query and export,
9. the Core inventory remains unchanged except for the intended P3 additions.
