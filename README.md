# AzureInfrastructureCollector

Read-only PowerShell collector for repeatable, customer-neutral Azure infrastructure inventories.

> Current milestone: **Core MVP 0.1.0**

> **Supreme safety rule:** No collector build is approved for a real Azure run unless the final verification result is `READ-ONLY VERIFIED` and the mandatory pre-Azure validation completes with `READY FOR AZURE TEST`.

The authoritative project scope, architecture and safety rules are defined in [`Umsetzungsplan.md`](./Umsetzungsplan.md).

## Runtime requirement

The supported runtime baseline is **PowerShell 7.6 LTS or newer** (`pwsh.exe`, minimum `7.6.0`).

Do not use:

- Windows PowerShell 5.1 (`powershell.exe`)
- PowerShell Core 6.x
- PowerShell 7.0–7.5 for an approved collector run

PowerShell itself is deliberately **not installed or upgraded automatically** by this project. Installing or upgrading the runtime remains a separate workstation/admin action.

## Before the first real Azure test

Use the dedicated Azure-free validation workflow:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Invoke-PreAzureValidation.ps1
```

The workflow performs, in this order:

1. PowerShell 7.6 LTS runtime check,
2. initial fail-closed read-only source-code verification,
3. Pester 5.5.0+ detection,
4. automatic Pester installation from `PSGallery` with `-Scope CurrentUser` if missing,
5. complete Pester test suite under `./Tests`,
6. final fail-closed read-only source-code verification,
7. explicit final status.

A real Azure test is permitted only when the command ends with:

```text
PRE-AZURE VALIDATION RESULT
Status: READY FOR AZURE TEST
Initial read-only gate: READ-ONLY VERIFIED
Pester: <version>; Failed: 0
Final read-only gate: READ-ONLY VERIFIED
Azure access performed: NO
Administrator elevation: NOT USED
```

The pre-Azure validation itself does **not** authenticate to Azure and does **not** run the collector.

## Recommended collector entry point

After successful pre-Azure validation:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-AzureInfrastructureCollector.ps1
```

The bootstrap:

1. verifies PowerShell 7.6 LTS or newer,
2. runs the mandatory local read-only source-code gate,
3. checks `Az.Accounts` and `Az.ResourceGraph`,
4. installs a missing required module from `PSGallery` with `-Scope CurrentUser`,
5. verifies that every required module can be imported,
6. starts `Collect-AzureDocumentation.ps1`,
7. the collector runs the read-only gate again before Azure access.

## Administrator rights and elevation

**Local Windows administrator rights are not required for the normal collector or pre-Azure validation workflow.**

Missing runtime Az modules and Pester are installed only in the current user's PowerShell module path:

```powershell
Install-Module <Module> -Repository PSGallery -Scope CurrentUser
```

The project deliberately does **not**:

- install modules with `-Scope AllUsers`,
- call `Start-Process -Verb RunAs`,
- restart itself elevated,
- request a UAC administrator token,
- automatically install or upgrade PowerShell,
- automatically register or modify `PSGallery`.

Azure RBAC permissions are separate from local Windows administrator rights. The Azure identity still needs sufficient read permissions for the selected tenant/subscriptions.

## Standalone read-only verification

For a source-code-only safety check without running Pester:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Test-ReadOnlyCompliance.ps1
```

The only successful read-only state is:

```text
READ-ONLY VERIFICATION
Status: READ-ONLY VERIFIED
Azure resource mutations: NONE DETECTED
Azure data mutations: NONE DETECTED
Control-plane write operations: NONE DETECTED
Data-plane write operations: NONE DETECTED
```

The gate is fail-closed:

- Azure PowerShell uses an explicit allowlist.
- Any new `*-Az*` command is blocked until reviewed and allowlisted.
- `Set-AzContext` is allowed only with explicit `-Scope Process`.
- direct REST/web calls are blocked in the MVP until explicitly reviewed.
- Azure CLI execution is blocked.
- dynamic command execution is blocked.
- `Start-Process` is blocked, preventing self-elevation paths.
- `Install-Module` is allowed only with literal `-Scope CurrentUser`.
- PowerShell repository mutation and alternative package mutation paths are blocked.
- PowerShell parse errors block approval.

Currently approved Azure commands:

- `Connect-AzAccount`
- `Get-AzContext`
- `Get-AzTenant`
- `Get-AzSubscription`
- `Set-AzContext -Scope Process`
- `Search-AzGraph`

## Requirements

Runtime:

- PowerShell 7.6 LTS or newer
- network access to PowerShell Gallery when a required module is missing
- `Az.Accounts`
- `Az.ResourceGraph`
- Azure identity with read access to the target scope

Pre-Azure validation additionally requires Pester 5.5.0 or newer. `Invoke-PreAzureValidation.ps1` installs it automatically for `CurrentUser` when missing.

## Usage

Interactive:

```powershell
./Start-AzureInfrastructureCollector.ps1
```

Explicit tenant/subscription:

```powershell
./Start-AzureInfrastructureCollector.ps1 `
    -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
    -SubscriptionId 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy'
```

Multiple subscriptions are supported via a string array. Resource-group filtering is available with `-ResourceGroup`.

Non-interactive mode requires an existing Azure authentication context and explicit scope parameters:

```powershell
./Start-AzureInfrastructureCollector.ps1 `
    -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
    -SubscriptionId 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy' `
    -OutputPath 'C:\AzureDocs' `
    -NonInteractive
```

## Output

```text
Output/
└── TenantName_<timestamp>/
    ├── readOnlyVerification.json
    ├── manifest.json
    ├── summary.json
    ├── Inventory/
    │   ├── resourceGroups.json
    │   └── resources.json
    └── Logs/
        └── collector.log
```

`Output/` is ignored by Git because exports can contain customer infrastructure information.

## Secret handling

The Core MVP exports only explicitly selected inventory fields. Full resource `properties` blocks are not exported. Sensitive-looking tag/property names such as secrets, passwords, tokens, credentials, access keys and client secrets are additionally redacted.

## Current scope of 0.1.0

Implemented:

- PowerShell 7.6 LTS runtime baseline
- dedicated Azure-free pre-Azure validation
- automatic `CurrentUser` installation of Pester for mandatory validation
- double read-only verification around the Pester suite
- explicit `READY FOR AZURE TEST` gate status
- preferred non-elevating bootstrap entry point
- automatic `CurrentUser` installation of missing `Az.Accounts` / `Az.ResourceGraph`
- no automatic PowerShell installation
- no self-elevation
- mandatory fail-closed read-only verification gate
- existing-context reuse / interactive Azure login
- tenant discovery and selection
- multi-subscription selection
- optional Resource Group filtering
- paginated Azure Resource Graph collection
- generic resource/resource-group inventory
- normalized JSON export
- verification report, manifest, summary and logging
- defense-in-depth secret redaction

Planned next:

- Network detail module
- Compute detail module
- Azure Virtual Desktop module
- Storage/Backup/Key Vault
- Security/RBAC/Governance
- Monitoring/Automation
- relationship engine
- snapshot diff
- AI documentation generation
