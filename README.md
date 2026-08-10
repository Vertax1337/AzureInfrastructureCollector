# AzureInfrastructureCollector

Read-only PowerShell collector for repeatable, customer-neutral Azure infrastructure inventories.

> Current milestone: **Core MVP 0.1.0**

> **Supreme safety rule:** No collector build is approved for a real Azure run unless the final verification result is `READ-ONLY VERIFIED` and the mandatory pre-Azure validation completes with `READY FOR AZURE TEST`.

The authoritative project scope, architecture and safety rules are defined in [`Umsetzungsplan.md`](./Umsetzungsplan.md).

## Before the first real Azure test

Use the dedicated Azure-free validation workflow from **PowerShell 7 (`pwsh.exe`)**:

```powershell
./Tools/Invoke-PreAzureValidation.ps1
```

Or explicitly from Command Prompt / Windows PowerShell:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Invoke-PreAzureValidation.ps1
```

The workflow performs, in this order:

1. PowerShell 7.2+ runtime check,
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
...
Azure access performed: NO
Administrator elevation: NOT USED
```

The pre-Azure validation itself does **not** authenticate to Azure and does **not** run the collector.

## Recommended collector entry point

After a successful pre-Azure validation, use:

```powershell
./Start-AzureInfrastructureCollector.ps1
```

If starting from Command Prompt or Windows PowerShell, invoke PowerShell 7 explicitly:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-AzureInfrastructureCollector.ps1
```

The bootstrap performs only local prerequisite handling before starting the collector:

1. verifies PowerShell 7.2 or newer,
2. runs the mandatory local read-only source-code gate,
3. checks `Az.Accounts` and `Az.ResourceGraph`,
4. installs a missing required module from `PSGallery` with `-Scope CurrentUser`,
5. verifies that every required module can be imported,
6. starts `Collect-AzureDocumentation.ps1`,
7. the collector runs the read-only gate again before Azure access.

## Administrator rights and elevation

**Local Windows administrator rights are not required for the normal collector or pre-Azure validation workflow.**

Missing runtime Az modules and the optional validation dependency Pester are installed only in the current user's PowerShell module path:

```powershell
Install-Module <Module> -Repository PSGallery -Scope CurrentUser
```

The project deliberately does **not**:

- install modules with `-Scope AllUsers`,
- call `Start-Process -Verb RunAs`,
- restart itself elevated,
- request a UAC administrator token,
- automatically install or upgrade PowerShell 7,
- automatically register or modify `PSGallery`.

If PowerShell 7.2+ is missing, the script stops with an explanatory error. PowerShell installation remains a separate, deliberate workstation/admin task.

If `PSGallery` is not registered, dependency handling also stops instead of changing repository configuration automatically.

Azure RBAC permissions are separate from local Windows administrator rights. The Azure identity still needs sufficient read permissions for the selected tenant/subscriptions.

## Standalone read-only verification

For a source-code-only safety check without running Pester:

```powershell
./Tools/Test-ReadOnlyCompliance.ps1
```

Or explicitly:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Test-ReadOnlyCompliance.ps1
```

Do **not** use `powershell.exe`; Windows PowerShell 5.1 is outside the supported runtime.

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
- suspicious direct Azure HTTP/SDK usage blocks approval.

Currently approved Azure commands:

- `Connect-AzAccount`
- `Get-AzContext`
- `Get-AzTenant`
- `Get-AzSubscription`
- `Set-AzContext -Scope Process`
- `Search-AzGraph`

Local dependency installation in `CurrentUser` scope does not modify Azure and is part of the approved local bootstrap/validation boundary.

## Requirements

Runtime:

- PowerShell 7.2 or newer
- network access to PowerShell Gallery when a required module is missing
- `Az.Accounts`
- `Az.ResourceGraph`
- Azure identity with read access to the target scope

Pre-Azure validation additionally requires Pester 5.5.0 or newer. `Invoke-PreAzureValidation.ps1` installs it automatically for `CurrentUser` when it is missing.

## Usage

### Interactive

```powershell
./Start-AzureInfrastructureCollector.ps1
```

If no usable Azure context exists, the collector starts interactive `Connect-AzAccount`. You then select tenant, subscriptions and optionally Resource Groups.

### Explicit tenant and subscriptions

```powershell
./Start-AzureInfrastructureCollector.ps1 `
    -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
    -SubscriptionId 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy'
```

Multiple subscriptions:

```powershell
./Start-AzureInfrastructureCollector.ps1 `
    -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
    -SubscriptionId @(
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222'
    )
```

### Resource-group filter

```powershell
./Start-AzureInfrastructureCollector.ps1 `
    -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
    -SubscriptionId 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy' `
    -ResourceGroup 'RG-PROD','RG-NETWORK'
```

### Non-interactive collector run

Authentication must already exist and scope parameters must be supplied:

```powershell
./Start-AzureInfrastructureCollector.ps1 `
    -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
    -SubscriptionId 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy' `
    -OutputPath 'C:\AzureDocs' `
    -NonInteractive
```

### Direct collector call

On an already prepared workstation you can still call:

```powershell
./Collect-AzureDocumentation.ps1
```

This path does not auto-install dependencies; `Az.Accounts` and `Az.ResourceGraph` must already be available. The read-only gate still runs before Azure access.

## Output

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

`Output/` is ignored by Git because exports can contain customer infrastructure information.

## Secret handling

The Core MVP exports only explicitly selected inventory fields. Full resource `properties` blocks are not exported. Sensitive-looking tag/property names such as secrets, passwords, tokens, credentials, access keys and client secrets are additionally redacted.

## Tests

For the mandatory pre-Azure test, use the combined workflow:

```powershell
./Tools/Invoke-PreAzureValidation.ps1
```

For development, Pester can still be invoked directly:

```powershell
Invoke-Pester ./Tests
```

The suite covers:

- normalization and secret redaction,
- PowerShell runtime validation,
- dependency reuse and `CurrentUser` installation behavior,
- fail-closed read-only checks,
- self-elevation blocking,
- Azure command allowlisting.

## Current scope of 0.1.0

Implemented:

- dedicated Azure-free `Invoke-PreAzureValidation.ps1`
- automatic `CurrentUser` installation of Pester for mandatory validation
- double read-only verification around the Pester suite
- explicit `READY FOR AZURE TEST` gate status
- preferred non-elevating bootstrap entry point
- automatic `CurrentUser` installation of missing `Az.Accounts` / `Az.ResourceGraph`
- no automatic PowerShell installation
- no self-elevation
- mandatory fail-closed read-only verification gate
- standalone and automatic read-only verification
- existing-context reuse / interactive Azure login
- tenant discovery and selection
- multi-subscription selection
- optional Resource Group filtering
- paginated Azure Resource Graph collection
- generic resource/resource-group inventory
- normalized JSON export
- verification report, manifest, summary and logging
- defense-in-depth secret redaction

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
