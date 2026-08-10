# AzureInfrastructureCollector

Read-only PowerShell collector for repeatable, customer-neutral Azure infrastructure inventories.

> Current milestone: **Core MVP 0.1.0**

The collector converts the actual Azure state into a normalized JSON export. Documentation generation, AI analysis, diagrams, DOCX/PDF output and specialized service modules are intentionally separate follow-up stages.

## Core principles

- customer- and tenant-neutral
- one tenant per collector run
- one or multiple subscriptions per run
- Azure Resource Graph first
- read-only by design
- no intentional export of secrets or credentials
- deterministic, normalized JSON output
- best-effort collection with errors recorded in the manifest and log

The authoritative project scope and architecture are defined in [`Umsetzungsplan.md`](./Umsetzungsplan.md).

## Requirements

- PowerShell 7.2 or newer
- `Az.Accounts`
- `Az.ResourceGraph`
- Azure account with read access to the target subscriptions

Install the required modules if necessary:

```powershell
Install-Module Az.Accounts -Scope CurrentUser
Install-Module Az.ResourceGraph -Scope CurrentUser
```

## Usage

### Interactive

```powershell
./Collect-AzureDocumentation.ps1
```

The collector reuses an existing Azure context where possible. If no context exists, an interactive `Connect-AzAccount` login is started. You can then select the tenant and one or more subscriptions.

An optional resource-group filter can be entered after resource groups have been discovered.

### Explicit tenant and subscriptions

```powershell
./Collect-AzureDocumentation.ps1 `
    -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
    -SubscriptionId 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy'
```

Multiple subscriptions are supported:

```powershell
./Collect-AzureDocumentation.ps1 `
    -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
    -SubscriptionId @(
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222'
    )
```

### Resource-group filter

```powershell
./Collect-AzureDocumentation.ps1 `
    -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
    -SubscriptionId 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy' `
    -ResourceGroup 'RG-PROD','RG-NETWORK'
```

### Non-interactive collector run

Version 0.1.0 supports deterministic non-interactive scope selection. Authentication must already exist before the script is started.

```powershell
./Collect-AzureDocumentation.ps1 `
    -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
    -SubscriptionId 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy' `
    -OutputPath 'C:\AzureDocs' `
    -NonInteractive
```

`-TenantId` and `-SubscriptionId` are required in `-NonInteractive` mode.

## Output

A run creates its own tenant-specific timestamped directory:

```text
Output/
└── TenantName_2026-08-10_084800/
    ├── manifest.json
    ├── summary.json
    ├── Inventory/
    │   ├── resourceGroups.json
    │   └── resources.json
    └── Logs/
        └── collector.log
```

### `manifest.json`

Contains collector/schema version, execution timestamps, account, tenant, selected subscriptions, scope, status, result counts and collected errors.

### `summary.json`

Contains resource/subscription counts plus grouped resource types and Azure locations.

### `Inventory/resources.json`

Normalized generic Azure resource inventory with these stable MVP fields:

- `id`
- `name`
- `type`
- `subscriptionId`
- `resourceGroup`
- `location`
- `tags`

### Secret handling

The Core MVP queries only the inventory fields required above; resource `properties` are deliberately not exported. Additionally, sensitive-looking tag/property names such as secrets, passwords, tokens, credentials, access keys and client secrets are redacted by the normalization layer.

This is a defense-in-depth measure and does not replace correct Azure RBAC and data-classification practices.

## Tests

Unit tests use Pester:

```powershell
Invoke-Pester ./Tests/Unit
```

The first tests cover safe export names, recursive sensitive-value redaction and the stable normalized core resource shape.

## Current scope of 0.1.0

Implemented:

- prerequisite validation
- existing-context reuse / interactive Azure login
- tenant discovery and selection
- subscription discovery and multi-selection
- process-scoped Azure context selection
- optional resource-group filtering
- paginated Azure Resource Graph collection
- generic resource inventory
- resource-group inventory
- normalized JSON export
- `manifest.json`
- `summary.json`
- logging
- best-effort handling of inventory query failures
- basic secret redaction

Not yet implemented:

- Compute detail module
- Network detail module
- Storage detail module
- Azure Virtual Desktop module
- Security/RBAC/Governance module
- Backup module
- Monitoring module
- Automation module
- relationship engine
- snapshot diff
- AI documentation generation
- diagrams, DOCX and PDF generation
- Managed Identity / Service Principal authentication

These follow the phased roadmap in `Umsetzungsplan.md`.
