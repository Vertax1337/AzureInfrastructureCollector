# Changelog

All notable changes to AzureInfrastructureCollector are documented in this file.

## [0.1.0] - 2026-08-10

### Added

- PowerShell 7.6 LTS (`7.6.0+`) as the supported runtime baseline
- canonical Azure-free `Tools/Invoke-PreAzureValidation.ps1` workflow
- pre-Azure validation sequence: read-only gate -> Pester prerequisite -> Pester suite -> final read-only gate
- automatic installation of missing Pester 5.5.0+ with `Install-Module -Scope CurrentUser`
- explicit final `READY FOR AZURE TEST` status only after all mandatory local checks pass
- central `validation.minimumPesterVersion` configuration
- GitHub Actions now uses the same canonical pre-Azure validation workflow as local validation
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
- defense-in-depth redaction of sensitive-looking keys
- tenant-specific timestamped export structure
- `manifest.json`, `summary.json` and collector log
- initial Pester unit tests

### Fixed

- standalone read-only verification detects Windows PowerShell 5.1 before loading PowerShell-7-only guard code and exits with a clear `pwsh.exe` retry command instead of failing on unavailable .NET APIs such as `System.IO.Path.GetRelativePath`
- runtime documentation and tests now consistently require the supported PowerShell 7.6 LTS baseline
- README examples explicitly distinguish `pwsh.exe` from legacy `powershell.exe`
