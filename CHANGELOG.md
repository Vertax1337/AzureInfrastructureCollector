# Changelog

All notable changes to AzureInfrastructureCollector are documented in this file.

## [0.1.0] - 2026-08-10

### Added

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
