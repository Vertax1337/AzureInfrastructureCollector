BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.AVD.psm1') -Force
}

Describe 'P5 AVD session host datetime normalization' {
    It 'normalizes Resource Graph datetime values to invariant UTC ISO 8601 strings' {
        $hostPoolId = '/subscriptions/sub/resourceGroups/RG-AVD/providers/Microsoft.DesktopVirtualization/hostPools/hp01'
        $sessionHostId = "$hostPoolId/sessionHosts/sh01.contoso.local"
        $vmId = '/subscriptions/sub/resourceGroups/RG-AVD/providers/Microsoft.Compute/virtualMachines/sh01'

        $row = [pscustomobject]@{
            id = $sessionHostId
            name = 'hp01/sh01.contoso.local'
            type = 'microsoft.desktopvirtualization/hostpools/sessionhosts'
            subscriptionId = 'sub'
            resourceGroup = 'RG-AVD'
            location = 'westeurope'
            tags = $null
            sessionHostStatus = 'Available'
            sessionHostStatusTimestamp = [datetime]::SpecifyKind([datetime]'2026-08-12T06:02:03', [System.DateTimeKind]::Utc)
            sessionHostLastHeartBeat = [datetime]::SpecifyKind([datetime]'2026-08-12T06:01:03', [System.DateTimeKind]::Utc)
            sessionHostLastUpdateTime = [datetime]::SpecifyKind([datetime]'2026-07-12T02:32:00', [System.DateTimeKind]::Utc)
            sessionHostVirtualMachineResourceId = $vmId
        }

        $result = ConvertTo-CollectorAvdInventory -Rows @($row)
        $sessionHost = $result.sessionHosts[0]

        $sessionHost.statusTimestamp | Should -BeExactly '2026-08-12T06:02:03.0000000Z'
        $sessionHost.lastHeartBeat | Should -BeExactly '2026-08-12T06:01:03.0000000Z'
        $sessionHost.lastUpdateTime | Should -BeExactly '2026-07-12T02:32:00.0000000Z'
    }
}
