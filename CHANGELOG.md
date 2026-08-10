# Changelog

All notable changes to AzureInfrastructureCollector are documented in this file.

## [0.1.0] - 2026-08-10

### Added

- PowerShell 7.6 LTS (`7.6.0+`) as the supported runtime baseline
- canonical Azure-free `Tools/Invoke-PreAzureValidation.ps1` workflow
- automatic invocation of the complete pre-Azure validation from `Start-AzureInfrastructureCollector.ps1`; operators no longer need a separate validation command before a normal collector run
- pre-Azure validation sequence: read-only gate -> Pester prerequisite -> Pester suite -> final read-only gate
- exact Pester `6.0.1` validation pin via `validation.requiredPesterVersion`
- automatic installation of exactly Pester 6.0.1 with `Install-Module -RequiredVersion 6.0.1 -Scope CurrentUser`
- explicit isolation/import of the selected Pester module path before validation
- explicit final `READY FOR AZURE TEST` status only after all mandatory local checks pass
- GitHub Actions uses the same canonical pre-Azure validation workflow as local validation
- preferred bootstrap entry point `Start-AzureInfrastructureCollector.ps1`
- reusable `Collector.Bootstrap.psm1`
- automatic detection of required Az modules before collector execution
- automatic installation of missing `Az.Accounts` and `Az.ResourceGraph` with `Install-Module -Scope CurrentUser`
- explicit prohibition of self-elevation and `AllUsers` dependency installation
- controlled abort when the supported PowerShell runtime is unavailable instead of automatic PowerShell installation
- controlled abort when `PSGallery` is unavailable instead of modifying repository configuration
- bootstrap Pester tests for runtime and dependency behavior
- read-only tests that explicitly allow `CurrentUser` module installation and block `Start-Process -Verb RunAs`
- mandatory fail-closed read-only verification gate
- standalone `Tools/Test-ReadOnlyCompliance.ps1` verification command
- automatic verification before any collector Azure authentication or Resource Graph collection
- explicit allowlist for verified Azure PowerShell commands
- blocking of unknown Azure cmdlets, dynamic command execution, Azure CLI and direct REST/web execution in the MVP
- process-scope enforcement for `Set-AzContext`
- `readOnlyVerification.json` in successful collector exports
- initial Core MVP entry point `Collect-AzureDocumentation.ps1`
- reusable `Collector.Core.psm1`
- reusable `Collector.ExportSecurity.psm1` as a centralized final export-hardening layer for current and future collector modules
- PowerShell and required Az module validation
- interactive Azure authentication fallback and existing-context reuse
- tenant discovery and tenant selection
- subscription discovery and multi-subscription selection
- non-interactive tenant/subscription scope support
- optional resource-group filtering
- process-scoped Azure context switching
- paginated Azure Resource Graph query helper
- generic resource and resource-group KQL queries
- normalized resource and resource-group JSON models
- visible collector progress with timestamps, `Write-Progress` status during Azure Resource Graph waits, collected-object counts, JSON-write status and total run duration
- defense-in-depth redaction of sensitive-looking keys
- value-based export redaction for signed URL/SAS signatures, account keys/shared-access-signature connection strings, private-key blocks, JWT-shaped tokens and embedded credential assignments
- subscription-aware canonicalization of Resource Group references in resource inventory
- public export projection for read-only verification and manifest metadata minimization
- eight dedicated Pester tests covering export hardening, canonical Resource Group names, metadata minimization and JSON array type stability
- tenant-specific timestamped export structure
- `manifest.json`, `summary.json` and collector log
- initial Pester unit tests
- P3a `Queries/Network.kql` with an explicit safe projection for VNets, NICs, NSGs, Public IPs, Route Tables, Virtual Network Gateways, Local Network Gateways, Connections and Network Watchers
- P3a `Collector.Network.psm1` normalization for VNets/Subnets/Peerings, NIC/IP configurations, NSGs/custom rules, Public IPs, Route Tables/Routes and gateway/connection topology
- explicit Resource-ID-based P3 network relationships for subnet containment, peerings, NSG/route/NAT associations, NIC/VM/subnet/Public-IP associations and gateway connections
- `Inventory/network.json` plus nested `summary.network` output
- six P3 network Pester tests covering query safety, topology normalization, NSG rule minimization, VPN connection secret exclusion and empty-collection stability
- three additional export-shape regression tests covering string-array preservation, nested enumerable flattening and hardened network address fields
- `Docs/P3-Network.md` defining the P3a/P3b architecture and safety boundary

### Fixed

- export hardening now preserves empty arrays as `[]` instead of collapsing them to `null`; this keeps fields such as `errors`, `violations` and `resourceGroupFilter` schema-stable
- export hardening now handles strings/value types and enumerables before PSCustomObject/ETS property inspection so string arrays remain actual values instead of objects such as `{ "Length": 12 }`
- accidental nested enumerable wrappers are flattened during final export hardening so collection fields remain stable one-dimensional arrays instead of leaking PowerShell array metadata such as `Count`, `Length`, `SyncRoot` or `Rank`
- the scalar/array export-shape fix also restores readable command-name strings in `readOnlyVerification.json.approvedAzureCommandsFound`
- `resources.json` now uses the canonical Resource Group spelling from `resourceGroups.json` for the same subscription instead of preserving inconsistent Resource Graph casing
- `readOnlyVerification.json` no longer exposes the local collector repository path (`repositoryRoot`)
- `manifest.json` no longer exports the executing Azure account/UPN
- normal collector runs no longer pause after Resource Group discovery for an optional `Read-Host` filter prompt; without `-ResourceGroup`, all discovered Resource Groups are collected automatically, while explicit `-ResourceGroup` filtering remains available
- Azure authentication temporarily forces plain-text rendering (`$PSStyle.OutputRendering = PlainText` plus `NO_COLOR`) so device-code/login text is copyable without raw ANSI escape sequences; previous rendering settings are restored afterwards
- normal bootstrap import suppresses PowerShell's unapproved-verb discoverability warning without changing module behavior
- preferred bootstrap login falls back from failed WAM/browser authentication to `Connect-AzAccount -UseDeviceAuthentication`, while keeping the Az context process-scoped and preserving the non-interactive no-prompt behavior
- Pester validation no longer accepts an arbitrary newer major version; the validation runtime is deterministic at Pester 6.0.1
- bootstrap tests migrated from removed `Assert-MockCalled` assertions to Pester 6 `Should -Invoke`, preventing legacy Pester 3.4.0 from being auto-loaded to satisfy deprecated commands
- validation removes already-loaded Pester modules and imports the exact configured module path before running tests, preventing mixed Pester-generation command resolution
- standalone read-only verification detects Windows PowerShell 5.1 before loading PowerShell-7-only guard code and exits with a clear `pwsh.exe` retry command instead of failing on unavailable .NET APIs such as `System.IO.Path.GetRelativePath`
- runtime documentation and tests consistently require the supported PowerShell 7.6 LTS baseline
- README examples explicitly distinguish `pwsh.exe` from legacy `powershell.exe`
