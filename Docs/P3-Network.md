# P3 – Network

Status: **P3a validation in progress**  
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

For `localNetworkGateways`, `gatewayIpAddress` and `fqdn` are distinct fields. The collector preserves whichever Azure configuration is present and does not synthesize one endpoint type from the other.

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

The export hardening must preserve scalar and collection shape. String values must remain strings, arrays must remain arrays, and PowerShell ETS adapter metadata such as `Length`, `Count`, `SyncRoot` or array type metadata must never replace the underlying values in JSON.

## First P3a real-run findings – 2026-08-10

The first confirmed P3a real export completed with:

- 12 Resource Groups
- 134 Core resources
- 22 top-level `Microsoft.Network` source resources
- 5 VNets
- 5 Subnets
- 12 directed VNet Peerings
- 4 NICs
- 4 NSGs
- 3 Public IPs
- 1 Route Table with 2 routes
- 1 Virtual Network Gateway
- 1 Local Network Gateway
- 1 Connection
- 2 Network Watchers
- 44 unique Resource-ID relationships
- 0 collector errors
- `READ-ONLY VERIFIED`

All 22 top-level Network objects matched the corresponding 22 Core `Microsoft.Network/*` resource IDs. All 44 relationship source/target IDs resolved to either a collected top-level resource or a normalized child object; no orphan relationship was found.

The real export also exposed an export-shape regression: string arrays were partially serialized through PowerShell ETS adapter properties, producing objects such as `{ "Length": 12 }` instead of the original string. Accidental nested array wrappers could similarly surface array metadata. `Collector.ExportSecurity.psm1` was corrected to process scalar values and enumerables before PSCustomObject property inspection and to flatten accidental nested enumerable wrappers. Dedicated regression tests were added.

The same regression affected the presentation of `approvedAzureCommandsFound` in `readOnlyVerification.json`; the safety result itself remained `READ-ONLY VERIFIED`, but the exported command-name strings were not represented correctly. The scalar-preservation fix covers this field as well.

The Local Network Gateway in the first real export had an empty `gatewayIpAddress`. P3a now explicitly projects `properties.fqdn` as `localGatewayFqdn` and normalizes it into a separate `fqdn` field. This allows an FQDN-configured on-premises gateway to be documented without overloading or fabricating `gatewayIpAddress`.

Because executable export-hardening and Network-normalization code changed after this real run, this run does **not** close P3a. The next normal collector start must first pass the complete automatic Pre-Azure validation again and then produce a new real export with stable scalar/array values and correct Local Network Gateway endpoint information.

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
6. string arrays and empty arrays retain their intended JSON types and values,
7. network counts and relationships are plausible against the Azure environment,
8. no secret-like values are exported,
9. VPN connection `sharedKey` is absent from query and export,
10. Local Network Gateway endpoint information covers both IP- and FQDN-based configuration where present,
11. the Core inventory remains unchanged except for the intended P3 additions.
