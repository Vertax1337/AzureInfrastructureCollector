# Changelog

All notable changes to AzureInfrastructureCollector are documented in this file.

## [0.1.0] - 2026-08-10

### Added

- mandatory fail-closed read-only verification gate
- standalone `Tools/Test-ReadOnlyCompliance.ps1` verification command
- automatic verification before any collector Azure authentication or Resource Graph collection
- explicit allowlist for verified Azure PowerShell commands
- blocking of unknown Azure cmdlets, dynamic command execution, Azure CLI and direct REST/web execution in the MVP
- process-scope enforcement for `Set-AzContext`
- Pester tests for positive and negative read-only-gate scenarios
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
