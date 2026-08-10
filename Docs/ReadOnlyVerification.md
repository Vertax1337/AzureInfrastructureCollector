# Read-Only Verification – Core MVP 0.1.0

> Verification date: 2026-08-10  
> Scope: current `main`, including bootstrap/dependency handling  
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

No Azure write cmdlet was added by the bootstrap implementation.

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

## Automatic fail-closed gate

`Modules/Collector.ReadOnlyGuard.psm1` enforces both Azure and bootstrap boundaries.

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

`Start-AzureInfrastructureCollector.ps1` runs the gate before dependency installation. `Collect-AzureDocumentation.ps1` runs it again before Azure authentication/inventory collection.

## Windows PowerShell 5.1 handling

The project runtime is PowerShell 7.2+ (`pwsh.exe`). Legacy Windows PowerShell 5.1 (`powershell.exe`) is not supported for the collector or the standalone verification.

`Tools/Test-ReadOnlyCompliance.ps1` contains a PowerShell-5.1-compatible runtime preflight before importing the guard. If the checker is started via `powershell.exe`, it exits with code `7`, makes no Azure request and instructs the operator to rerun it using `pwsh.exe`.

This prevents low-level compatibility failures such as missing .NET methods from being mistaken for a read-only verification failure.

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

`.github/workflows/read-only-gate.yml` runs the source-code gate and Pester tests on pushes to `main` and pull requests with repository permission restricted to `contents: read`.

## Mandatory local check before the first Azure test

The manual/static review above verifies the code design and Azure command surface. Before the first real Azure connection, the local checkout must execute the actual PowerShell parser/gate and test suite under **PowerShell 7**.

From PowerShell 7:

```powershell
./Tools/Test-ReadOnlyCompliance.ps1
Invoke-Pester ./Tests
```

Or explicitly from another shell:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Test-ReadOnlyCompliance.ps1
pwsh.exe -NoProfile -Command "Invoke-Pester .\Tests"
```

The Azure test is permitted only if the first command reports exactly:

```text
Status: READ-ONLY VERIFIED
```

and the Pester suite has no failures.

The standalone read-only gate itself performs no Azure authentication and no Azure request.

## Future changes

Any new or changed Azure command, API path, dependency mechanism, module mutation path or executable code invalidates the previous approval until the mandatory read-only verification is repeated.
