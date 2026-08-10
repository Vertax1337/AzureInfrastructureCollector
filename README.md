# AzureInfrastructureCollector

Read-only PowerShell collector for repeatable, customer-neutral Azure infrastructure inventories.

> Current milestone: **Core MVP 0.1.0**

> **Supreme safety rule:** No collector build is approved for a real Azure run unless the final verification result is `READ-ONLY VERIFIED` and the mandatory pre-Azure validation completes with `READY FOR AZURE TEST`.

The authoritative project scope, architecture and safety rules are defined in [`Umsetzungsplan.md`](./Umsetzungsplan.md).

## Normal operator workflow: one command

Use PowerShell 7.6 LTS and start only the bootstrap entry point:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -ExecutionPolicy Bypass -File .\Start-AzureInfrastructureCollector.ps1
```

`Start-AzureInfrastructureCollector.ps1` performs the complete safety and prerequisite workflow automatically. A separate manual pre-validation command is **not required** for the normal collector workflow.

The startup sequence is:

1. verify PowerShell 7.6 LTS or newer,
2. automatically run the Azure-free pre-Azure validation,
3. run the initial fail-closed read-only source-code gate,
4. verify/install exactly Pester 6.0.1 for `CurrentUser` when needed,
5. run the complete Pester suite,
6. run the final read-only source-code gate,
7. require `READY FOR AZURE TEST`,
8. verify/install `Az.Accounts` and `Az.ResourceGraph` for `CurrentUser` when needed,
9. verify the Azure authentication context,
10. attempt normal interactive Azure login when required,
11. automatically fall back to device-code authentication if WAM/browser authentication fails,
12. start `Collect-AzureDocumentation.ps1`, which runs the read-only gate again before Azure inventory collection.

Any mandatory validation failure stops execution **before Azure authentication or Azure collection**.

## Runtime requirement

The supported runtime baseline is **PowerShell 7.6 LTS or newer** (`pwsh.exe`, minimum `7.6.0`).

Do not use:

- Windows PowerShell 5.1 (`powershell.exe`)
- PowerShell Core 6.x
- PowerShell 7.0–7.5 for an approved collector run

PowerShell itself is deliberately **not installed or upgraded automatically** by this project. Installing or upgrading the runtime remains a separate workstation/admin action.

## Automatic pre-Azure validation

The normal bootstrap executes `Tools/Invoke-PreAzureValidation.ps1` automatically in embedded/fail-closed mode.

A successful validation contains:

```text
PRE-AZURE VALIDATION RESULT
Status: READY FOR AZURE TEST
Initial read-only gate: READ-ONLY VERIFIED
Pester: 6.0.1; Failed: 0
Final read-only gate: READ-ONLY VERIFIED
Azure access performed: NO
Administrator elevation: NOT USED
```

The standalone validator remains available for diagnostics and CI:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Invoke-PreAzureValidation.ps1
```

It is not a prerequisite command the operator has to remember before every normal run.

### Pester isolation

The validator requires exactly **Pester 6.0.1**.

Windows can contain an old inbox/system Pester version such as 3.4.0. It does not have to be removed. The validator removes already-loaded Pester modules from its current validation session, imports the exact configured Pester 6.0.1 module path and verifies the required Pester commands before executing the suite.

## Azure authentication

If an active Az context already exists, it is reused.

Otherwise the interactive workflow first attempts:

```powershell
Connect-AzAccount -Scope Process
```

If WAM/browser authentication fails, the bootstrap automatically retries with device-code authentication:

```powershell
Connect-AzAccount -UseDeviceAuthentication -Scope Process
```

When `-TenantId` is supplied to the bootstrap, the tenant is also supplied during authentication.

The Azure login output is temporarily forced to plain-text rendering so copied device-code/login messages do not contain raw ANSI escape sequences. The previous PowerShell rendering settings are restored immediately after authentication.

`-NonInteractive` never initiates an interactive sign-in; an existing Azure authentication context is required.

## Administrator rights and elevation

**Local Windows administrator rights are not required for the normal collector workflow.**

Missing PowerShell modules are installed only in the current user's module path:

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

Azure RBAC permissions are separate from local Windows administrator rights. The Azure identity needs sufficient read permissions for the selected tenant/subscriptions.

## Standalone read-only verification

For a source-code-only safety check without running the complete validation workflow:

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

Validation:

- exact Pester 6.0.1, automatically installed for `CurrentUser` when missing

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

- one-command normal operator workflow
- automatic embedded pre-Azure validation before every normal collector run
- PowerShell 7.6 LTS runtime baseline
- deterministic Pester 6.0.1 validation runtime
- Pester 6-compatible test assertions
- automatic `CurrentUser` installation of the pinned Pester validation version
- double read-only verification around the Pester suite
- explicit `READY FOR AZURE TEST` gate status
- preferred non-elevating bootstrap entry point
- automatic `CurrentUser` installation of missing `Az.Accounts` / `Az.ResourceGraph`
- no automatic PowerShell installation
- no self-elevation
- mandatory fail-closed read-only verification gate
- existing-context reuse / interactive Azure login
- automatic device-code fallback
- plain-text Azure login rendering
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
