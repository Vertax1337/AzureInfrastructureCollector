# Read-Only Verification – Core MVP 0.1.0

> Verification date: 2026-08-10  
> Scope: current `main`, including bootstrap/dependency and pre-Azure validation handling  
> Manual/static verification result: **READ-ONLY VERIFIED**

This document records the read-only review required before the first real Azure test.

## Result

```text
READ-ONLY VERIFICATION
Status: READ-ONLY VERIFIED
Azure resource mutations: NONE DETECTED
Azure data mutations: NONE DETECTED
Control-plane write operations: NONE DETECTED
Data-plane write operations: NONE DETECTED
Local writes: approved CurrentUser dependency installation plus collector export/logs only
Self-elevation: NONE
```

## Reviewed Azure command surface

The executable collector scope uses only:

| Command | Project use | Verification |
|---|---|---|
| `Connect-AzAccount` | Authenticate for Az PowerShell | Approved authentication/context operation; no Azure resource mutation |
| `Get-AzContext` | Read current Az context | Approved read operation |
| `Get-AzTenant` | Enumerate authorized tenants | Approved read operation |
| `Get-AzSubscription` | Enumerate accessible subscriptions | Approved read operation |
| `Set-AzContext -Scope Process` | Select tenant/subscription for the current PowerShell process | Approved local/session context operation; `Process` scope is enforced by the gate |
| `Search-AzGraph` | Query Azure Resource Graph | Approved read-only inventory query |

Neither bootstrap nor pre-Azure validation adds an Azure command.

## Resource Graph queries reviewed

`Queries/Resources.kql` reads from `Resources` and projects only inventory metadata.

`Queries/ResourceGroups.kql` reads from `ResourceContainers`, filters Resource Groups and projects only inventory metadata.

Neither query mutates Azure state.

## Bootstrap boundary

`Start-AzureInfrastructureCollector.ps1` and `Modules/Collector.Bootstrap.psm1` form a separate local prerequisite layer.

Approved local behavior:

- verify PowerShell 7.2+,
- verify the repository read-only state,
- inspect installed PowerShell modules,
- query the already registered `PSGallery`,
- install a missing required module only with `Install-Module -Scope CurrentUser`,
- import required modules,
- start the collector.

Explicitly not implemented:

- `Start-Process -Verb RunAs`,
- any other self-elevation path,
- `Install-Module -Scope AllUsers`,
- automatic PowerShell 7 installation/update,
- automatic PowerShell repository registration/change,
- Azure CLI execution,
- direct REST/web Azure calls.

If PowerShell 7.2+ or PSGallery is unavailable, bootstrap fails instead of elevating or changing workstation-wide configuration.

## Mandatory pre-Azure validation

`Tools/Invoke-PreAzureValidation.ps1` is the canonical Azure-free validation workflow before the first real Azure test and after later executable-code changes.

It performs:

1. PowerShell 7.2+ runtime validation,
2. initial `READ-ONLY VERIFIED` source-code gate,
3. Pester 5.5.0+ discovery,
4. if necessary, Pester installation from the already registered `PSGallery` with literal `-Scope CurrentUser`,
5. complete Pester execution for `./Tests` with `-PassThru`,
6. failure if any Pester test fails or no result can be proven,
7. final read-only source-code gate,
8. final `READY FOR AZURE TEST` status only if every mandatory check succeeded.

The validation workflow does not call `Connect-AzAccount`, `Search-AzGraph`, or any other Azure operation. It performs no Azure authentication and no Azure request.

Pester remains a validation/development dependency and is not required for a normal collector run after validation. Its minimum version is defined in `Config/collector.config.json` as `validation.minimumPesterVersion`.

## Automatic fail-closed gate

`Modules/Collector.ReadOnlyGuard.psm1` enforces both Azure and local bootstrap/validation boundaries.

It:

- allowlists the reviewed Azure cmdlets,
- blocks unknown `*-Az*` commands,
- requires `Set-AzContext -Scope Process`,
- blocks direct REST/web execution,
- blocks Azure CLI,
- blocks dynamic command execution,
- blocks `Start-Process`,
- allows `Install-Module` only with literal `-Scope CurrentUser`,
- blocks module update/uninstall/save operations in executable project code,
- blocks PowerShell repository mutation,
- blocks package/PSResource mutation mechanisms outside the approved bootstrap path,
- treats parse errors as verification failures.

`Invoke-PreAzureValidation.ps1` runs the gate before and after Pester. `Start-AzureInfrastructureCollector.ps1` runs the gate before runtime dependency installation. `Collect-AzureDocumentation.ps1` runs it again before Azure authentication/inventory collection.

## Windows PowerShell 5.1 handling

The project runtime is PowerShell 7.2+ (`pwsh.exe`). Legacy Windows PowerShell 5.1 (`powershell.exe`) is not supported for the collector or validation tools.

Both validation entry points contain a PowerShell-5.1-compatible runtime preflight before importing the guard. If started via `powershell.exe`, they exit without making any Azure request and instruct the operator to rerun using `pwsh.exe`.

## Tests

The Pester suite includes:

- current repository approval,
- unknown Azure command blocking,
- dynamic execution blocking,
- direct REST blocking,
- self-elevation blocking,
- `Install-Module -Scope CurrentUser` approval,
- `Install-Module -Scope AllUsers` blocking,
- PowerShell repository mutation blocking,
- `Set-AzContext -Scope Process` enforcement,
- bootstrap runtime validation,
- dependency reuse,
- missing dependency installation in `CurrentUser` scope.

`.github/workflows/read-only-gate.yml` invokes the same canonical `Tools/Invoke-PreAzureValidation.ps1` used locally. The workflow repository permission remains restricted to `contents: read`.

## Mandatory command before the first real Azure test

From PowerShell 7:

```powershell
./Tools/Invoke-PreAzureValidation.ps1
```

Or explicitly from another shell:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Invoke-PreAzureValidation.ps1
```

The Azure test is permitted only if the workflow completes with:

```text
PRE-AZURE VALIDATION RESULT
Status: READY FOR AZURE TEST
Initial read-only gate: READ-ONLY VERIFIED
Pester: <version>; Passed: <n>; Failed: 0; Skipped: <n>
Final read-only gate: READ-ONLY VERIFIED
Azure access performed: NO
Administrator elevation: NOT USED
```

## Future changes

Any new or changed Azure command, API path, dependency mechanism, module mutation path or executable code invalidates the previous approval until the mandatory pre-Azure validation has been repeated successfully.
