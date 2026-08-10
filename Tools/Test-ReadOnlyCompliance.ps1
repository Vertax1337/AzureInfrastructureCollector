[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$minimumPowerShellVersion = [version]'7.6.0'

# This standalone safety check uses the same supported runtime as the collector.
# Keep this preflight compatible with Windows PowerShell 5.1 so an accidental
# powershell.exe invocation fails cleanly before the PowerShell-7 guard is loaded.
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt $minimumPowerShellVersion) {
    Write-Error (
        "PowerShell {0} or newer (PowerShell 7.6 LTS / pwsh.exe / PSEdition Core) is required for the read-only verification. Current runtime: {1} {2}. No Azure request was made. Re-run after installing/upgrading PowerShell 7.6 LTS with: pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Test-ReadOnlyCompliance.ps1" -f `
            $minimumPowerShellVersion,
            $PSVersionTable.PSEdition,
            $PSVersionTable.PSVersion
    )
    exit 7
}

$guardModulePath = Join-Path $RepositoryRoot 'Modules/Collector.ReadOnlyGuard.psm1'
Import-Module $guardModulePath -Force -ErrorAction Stop

$result = Test-CollectorReadOnlyCompliance -RepositoryRoot $RepositoryRoot

if ($AsJson) {
    $result | ConvertTo-Json -Depth 10
}
else {
    Write-Host ''
    Write-Host 'READ-ONLY VERIFICATION'
    Write-Host ("Status: {0}" -f $result.status)
    Write-Host ("Files scanned: {0}" -f $result.filesScanned)
    Write-Host ("Approved Azure commands found: {0}" -f (($result.approvedAzureCommandsFound) -join ', '))
    Write-Host ("Azure resource mutations: {0}" -f $result.azureResourceMutations)
    Write-Host ("Azure data mutations: {0}" -f $result.azureDataMutations)
    Write-Host ("Control-plane write operations: {0}" -f $result.controlPlaneWrites)
    Write-Host ("Data-plane write operations: {0}" -f $result.dataPlaneWrites)

    if (-not $result.verified) {
        Write-Host ''
        Write-Host 'Violations:'
        foreach ($violation in $result.violations) {
            Write-Host ("- {0}:{1}:{2} [{3}] {4}" -f $violation.file, $violation.line, $violation.column, $violation.code, $violation.message)
        }
    }
}

if (-not $result.verified) {
    exit 10
}

exit 0
