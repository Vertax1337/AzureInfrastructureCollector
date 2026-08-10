# Read-Only Verification – Core MVP 0.1.0

> Verification date: 2026-08-10  
> Baseline: `main` after commit `ec07ce4aeb91ffaacdc4e9da73e2b9f95a154b7b`  
> Manual verification result: **READ-ONLY VERIFIED**

This document records the initial read-only review performed before the first Azure test of the collector.

## Result

```text
READ-ONLY VERIFICATION
Status: READ-ONLY VERIFIED
Azure resource mutations: NONE DETECTED
Azure data mutations: NONE DETECTED
Control-plane write operations: NONE DETECTED
Data-plane write operations: NONE DETECTED
Local writes: Collector export, logs and local processing only
```

## Reviewed Azure command surface

The Core MVP currently uses only the following Azure PowerShell commands:

| Command | Project use | Verification |
|---|---|---|
| `Connect-AzAccount` | Authenticate the user for Az PowerShell | Approved; authentication/context operation, no Azure resource mutation |
| `Get-AzContext` | Read current authentication/context metadata | Approved read operation |
| `Get-AzTenant` | Enumerate tenants authorized for the current identity | Approved read operation |
| `Get-AzSubscription` | Enumerate accessible subscriptions | Approved read operation |
| `Set-AzContext -Scope Process` | Select tenant/subscription context for the current PowerShell process | Approved local/session context operation; explicit `Process` scope required by the gate |
| `Search-AzGraph` | Query Azure Resource Graph | Approved read-only inventory query |

Reference semantics were checked against the Microsoft Learn documentation for the respective Az PowerShell cmdlets before approval.

## Resource Graph queries reviewed

`Queries/Resources.kql` reads from `Resources` and projects only:

- resource ID,
- name,
- type,
- resource group,
- subscription ID,
- location,
- tags.

`Queries/ResourceGroups.kql` reads from `ResourceContainers`, filters resource groups and projects only inventory metadata.

Neither query performs or requests a resource mutation.

## Local-only writes

The collector performs local filesystem writes for:

- export directories,
- JSON output,
- manifest,
- summary,
- read-only verification report,
- collector log.

These writes do not modify Azure resources or Azure-hosted customer data.

## Automatic fail-closed gate

`Modules/Collector.ReadOnlyGuard.psm1` implements the mandatory gate.

The initial policy:

- explicitly allowlists the currently reviewed Azure commands,
- blocks any unknown `*-Az*` command,
- requires `Set-AzContext` to use `-Scope Process`,
- blocks Azure CLI execution,
- blocks direct REST/web execution in the MVP,
- blocks dynamic command execution,
- blocks selected direct HTTP/SDK patterns,
- treats PowerShell parse errors as verification failures,
- returns `BLOCKED` for any violation.

`Collect-AzureDocumentation.ps1` invokes this gate before Core initialization and before any Azure authentication or Azure Resource Graph request. A failed verification throws and blocks collector execution.

## Tests

`Tests/ReadOnly/ReadOnlyGuard.Tests.ps1` contains positive and negative tests for:

- current repository approval,
- unknown Azure command blocking,
- dynamic command blocking,
- direct REST blocking,
- `Set-AzContext` scope enforcement,
- approved command allowlist behavior.

`.github/workflows/read-only-gate.yml` runs the mandatory verification and Pester tests on pushes to `main` and on pull requests with GitHub repository permissions restricted to `contents: read`.

## Pre-Azure-test requirement

Before the first real Azure test, the local checkout must run:

```powershell
./Tools/Test-ReadOnlyCompliance.ps1
```

The Azure collector must not be started unless this local execution reports exactly:

```text
Status: READ-ONLY VERIFIED
```

This local gate execution itself performs no Azure authentication and no Azure request; it only parses and reviews local repository PowerShell source files.

## Verification rule for future changes

This approval applies only to the reviewed executable scope. Any new or changed Azure command, API path, module or executable code invalidates the previous approval until the mandatory read-only verification has been repeated.
