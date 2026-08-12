BeforeAll {
    $topLevelQueryPath = Join-Path $PSScriptRoot '../../Queries/AVD.kql'
    $sessionHostsQueryPath = Join-Path $PSScriptRoot '../../Queries/AVD.SessionHosts.kql'
    $collectorPath = Join-Path $PSScriptRoot '../../Collect-AzureDocumentation.ps1'
}

Describe 'P5 AVD Resource Graph query split regression' {
    It 'keeps Resources and DesktopVirtualizationResources in separate queries without cross-table union' {
        $topLevelQuery = Get-Content $topLevelQueryPath -Raw
        $sessionHostsQuery = Get-Content $sessionHostsQueryPath -Raw

        $topLevelExecutableLines = @($topLevelQuery -split "`r?`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
        $sessionHostExecutableLines = @($sessionHostsQuery -split "`r?`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"

        $topLevelExecutableLines | Should -Match '(?im)^\s*Resources\s*$'
        $topLevelExecutableLines | Should -Not -Match '(?im)^\s*DesktopVirtualizationResources\s*$'
        $topLevelExecutableLines | Should -Not -Match '(?i)\|\s*union\b'

        $sessionHostExecutableLines | Should -Match '(?im)^\s*DesktopVirtualizationResources\s*$'
        $sessionHostExecutableLines | Should -Not -Match '(?im)^\s*Resources\s*$'
        $sessionHostExecutableLines | Should -Not -Match '(?i)\|\s*union\b'
    }

    It 'invokes both AVD query files through the existing Resource Graph wrapper only' {
        $collector = Get-Content $collectorPath -Raw

        $collector | Should -Match [regex]::Escape("Queries/AVD.kql")
        $collector | Should -Match [regex]::Escape("Queries/AVD.SessionHosts.kql")
        @([regex]::Matches($collector, 'Invoke-CollectorResourceGraph')).Count | Should -BeGreaterOrEqual 6
        $collector | Should -Not -Match '(?i)\bGet-AzWvd(SessionHost|HostPool|Workspace|ApplicationGroup|ScalingPlan)\b'
        $collector | Should -Not -Match '(?i)\bInvoke-RestMethod\b|\bInvoke-WebRequest\b'
        $collector | Should -Not -Match '(?im)^\s*az\s+'
    }
}
