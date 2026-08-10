# AzureInfrastructureCollector

Read-only PowerShell collector for repeatable, customer-neutral Azure infrastructure inventories.

> Current milestone: **Core MVP 0.1.0**

> **Supreme safety rule:** No collector build is approved for execution unless the final verification result is `READ-ONLY VERIFIED`.

The collector converts the actual Azure state into a normalized JSON export. Documentation generation, AI analysis, diagrams, DOCX/PDF output and specialized service modules are intentionally separate follow-up stages.

## Core principles

- customer- and tenant-neutral
- one tenant per collector run
- one or multiple subscriptions per run
- Azure Resource Graph first
- read-only by design
- fail-closed read-only verification before Azure access
- no intentional export of secrets or credentials
- deterministic, normalized JSON output
- best-effort collection with errors recorded in the manifest and log

The authoritative project scope, architecture and supreme read-only rule are defined in [`Umsetzungsplan.md`](./Umsetzungsplan.md).

## Mandatory read-only verification

Before the first Azure test and before every later execution approval, run:

```powershell
./Tools/Test-ReadOnlyCompliance.ps1
```

The only successful approval state is:

```text
READ-ONLY VERIFICATION
Status: READ-ONLY VERIFIED
Azure resource mutations: NONE DETECTED
Azure data mutations: NONE DETECTED
Control-plane write operations: NONE DETECTED
Data-plane write operations: NONE DETECTED
```

The collector also executes the same gate automatically at the very beginning of `Collect-AzureDocumentation.ps1`, before authentication or Resource Graph collection. A failed or ambiguous verification blocks execution.

The MVP gate is deliberately strict:

- Azure PowerShell uses an explicit allowlist.
- Any new `*-Az*` command is blocked until separately reviewed and allowlisted.
- `Set-AzContext` is allowed only with explicit `-Scope Process`.
- direct REST/web calls are blocked in the MVP until explicitly reviewed.
- Azure CLI execution is blocked.
- dynamic command execution is blocked.
- PowerShell parse errors block approval.
- suspicious direct Azure HTTP/SDK usage blocks approval.

The currently approved Azure commands are limited to:

- `Connect-AzAccount`
- `Get-AzContext`
- `Get-AzTenant`
- `Get-AzSubscription`
- `Set-AzContext -Scope Process`
- `Search-AzGraph`

These operations are used only for authentication/local context selection and read-only inventory queries. Local writes are limited to collector output, logs and local processing.

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

For tests:

```powershell
Install-Module Pester -Scope CurrentUser
```

## Usage

### Safety check first

```powershell
./Tools/Test-ReadOnlyCompliance.ps1
```

Do not continue unless the result is `READ-ONLY VERIFIED`.

### Interactive

```powershell
./Collect-AzureDocumentation.ps1
```

The collector reruns the mandatory read-only gate automatically. It then reuses an existing Azure context where possible. If no context exists, an interactive `Connect-AzAccount` login is started. You can then select the tenant and one or more subscriptions.

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
    ├── readOnlyVerification.json
    ├── manifest.json
    ├── summary.json
    ├── Inventory/
    │   ├── resourceGroups.json
    │   └── resources.json
    └── Logs/
        └── collector.log
```

### `readOnlyVerification.json`

Records the mandatory verification result that allowed the collector run to proceed, including the scanned-file count, approved Azure commands observed and detected mutation status.

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

Run all Pester tests:

```powershell
Invoke-Pester ./Tests
```

The test suite covers core normalization/security behavior plus the read-only guard. Guard tests explicitly verify that unapproved Azure commands, dynamic execution, direct REST execution and unsafe `Set-AzContext` usage are blocked.

## Current scope of 0.1.0

Implemented:

- mandatory fail-closed read-only verification gate
- standalone read-only verification command
- automatic read-only verification before collector Azure access
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
- `readOnlyVerification.json`
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
