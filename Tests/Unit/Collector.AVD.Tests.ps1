BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.AVD.psm1') -Force
}

Describe 'P5 AVD query safety boundary' {
    It 'uses Resource Graph including DesktopVirtualizationResources and excludes sensitive AVD paths' {
        $query = Get-Content (Join-Path $PSScriptRoot '../../Queries/AVD.kql') -Raw

        foreach ($resourceType in @(
            'microsoft.desktopvirtualization/workspaces',
            'microsoft.desktopvirtualization/hostpools',
            'microsoft.desktopvirtualization/applicationgroups',
            'microsoft.desktopvirtualization/scalingplans',
            'microsoft.desktopvirtualization/hostpools/sessionhosts'
        )) {
            $query | Should -Match ([regex]::Escape($resourceType))
        }

        $query | Should -Match '(?i)DesktopVirtualizationResources'
        $query | Should -Not -Match '(?i)registrationInfo'
        $query | Should -Not -Match '(?i)registrationToken'
        $query | Should -Not -Match '(?i)assignedUser'
        $query | Should -Not -Match '(?i)updateErrorMessage'
        $query | Should -Not -Match '(?i)sessionHostHealthCheckResults'
        $query | Should -Not -Match '(?i)customRdpProperty'
        $query | Should -Not -Match '(?i)vmTemplate'
        $query | Should -Not -Match '(?i)ssoClientSecretKeyVaultPath'
        $query | Should -Not -Match '(?i)oboTenantId'
        $query | Should -Not -Match '(?i)rampDownNotificationMessage'
    }
}

Describe 'P5 Workspace normalization' {
    It 'normalizes workspace application group references and relationships' {
        $workspaceId = '/subscriptions/sub/resourceGroups/RG-AVD/providers/Microsoft.DesktopVirtualization/workspaces/ws01'
        $desktopGroupId = '/subscriptions/sub/resourceGroups/RG-AVD/providers/Microsoft.DesktopVirtualization/applicationGroups/dag01'
        $remoteAppGroupId = '/subscriptions/sub/resourceGroups/RG-AVD/providers/Microsoft.DesktopVirtualization/applicationGroups/rag01'

        $row = [pscustomobject]@{
            id = $workspaceId; name = 'ws01'; type = 'microsoft.desktopvirtualization/workspaces'
            subscriptionId = 'sub'; resourceGroup = 'RG-AVD'; location = 'westeurope'; tags = $null
            workspaceFriendlyName = 'Workspace 01'; workspacePublicNetworkAccess = 'Enabled'
            workspaceApplicationGroupReferences = @($desktopGroupId, $remoteAppGroupId)
        }

        $result = ConvertTo-CollectorAvdInventory -Rows @($row)

        $result.summary.workspaces | Should -Be 1
        $result.summary.workspaceApplicationGroupReferences | Should -Be 2
        $result.workspaces[0].applicationGroupReferences | Should -Contain $desktopGroupId
        $result.workspaces[0].applicationGroupReferences | Should -Contain $remoteAppGroupId
        @($result.relationships | Where-Object { $_.sourceId -eq $workspaceId -and $_.relationship -eq 'ReferencesApplicationGroup' }).Count | Should -Be 2
    }
}

Describe 'P5 Host Pool normalization' {
    It 'normalizes operational host pool settings without registration, SSO-secret or free-form RDP data' {
        $hostPoolId = '/subscriptions/sub/resourceGroups/RG-AVD/providers/Microsoft.DesktopVirtualization/hostPools/hp01'
        $row = [pscustomobject]@{
            id = $hostPoolId; name = 'hp01'; type = 'microsoft.desktopvirtualization/hostpools'
            subscriptionId = 'sub'; resourceGroup = 'RG-AVD'; location = 'westeurope'; tags = $null
            hostPoolFriendlyName = 'HP 01'; hostPoolType = 'Pooled'; hostPoolLoadBalancerType = 'BreadthFirst'
            hostPoolMaxSessionLimit = 16; hostPoolPersonalDesktopAssignmentType = ''; hostPoolPreferredAppGroupType = 'Desktop'
            hostPoolPublicNetworkAccess = 'Enabled'; hostPoolStartVmOnConnect = $true; hostPoolValidationEnvironment = $false
            hostPoolManagementType = 'Standard'; hostPoolDirectUdp = 'Default'; hostPoolManagedPrivateUdp = 'Default'
            hostPoolPublicUdp = 'Default'; hostPoolRelayUdp = 'Default'
            hostPoolAgentUpdate = [pscustomobject]@{
                type = 'ScheduledForSessionHosts'; maintenanceWindowTimeZone = 'W. Europe Standard Time'; useSessionHostLocalTime = $false
                maintenanceWindows = @([pscustomobject]@{ dayOfWeek = 'Saturday'; hour = 3 })
            }
            registrationInfo = [pscustomobject]@{ token = 'must-not-export' }
            customRdpProperty = 'must-not-export'
            vmTemplate = 'must-not-export'
            ssoClientSecretKeyVaultPath = 'must-not-export'
        }

        $result = ConvertTo-CollectorAvdInventory -Rows @($row)
        $hostPool = $result.hostPools[0]

        $result.summary.hostPools | Should -Be 1
        $result.summary.startVmOnConnectEnabledHostPools | Should -Be 1
        $hostPool.hostPoolType | Should -BeExactly 'Pooled'
        $hostPool.loadBalancerType | Should -BeExactly 'BreadthFirst'
        $hostPool.maxSessionLimit | Should -Be 16
        $hostPool.startVmOnConnect | Should -BeTrue
        $hostPool.agentUpdate.maintenanceWindows[0].dayOfWeek | Should -BeExactly 'Saturday'
        @($hostPool.PSObject.Properties.Name) | Should -Not -Contain 'registrationInfo'
        @($hostPool.PSObject.Properties.Name) | Should -Not -Contain 'customRdpProperty'
        @($hostPool.PSObject.Properties.Name) | Should -Not -Contain 'vmTemplate'
        @($hostPool.PSObject.Properties.Name) | Should -Not -Contain 'ssoClientSecretKeyVaultPath'
    }
}

Describe 'P5 Application Group normalization' {
    It 'links application groups to their host pool by ARM resource ID' {
        $hostPoolId = '/subscriptions/sub/resourceGroups/RG-AVD/providers/Microsoft.DesktopVirtualization/hostPools/hp01'
        $applicationGroupId = '/subscriptions/sub/resourceGroups/RG-AVD/providers/Microsoft.DesktopVirtualization/applicationGroups/dag01'
        $row = [pscustomobject]@{
            id = $applicationGroupId; name = 'dag01'; type = 'microsoft.desktopvirtualization/applicationgroups'
            subscriptionId = 'sub'; resourceGroup = 'RG-AVD'; location = 'westeurope'; tags = $null
            applicationGroupFriendlyName = 'Desktop'; applicationGroupType = 'Desktop'
            applicationGroupHostPoolArmPath = $hostPoolId; applicationGroupShowInFeed = $true
        }

        $result = ConvertTo-CollectorAvdInventory -Rows @($row)

        $result.summary.applicationGroups | Should -Be 1
        $result.summary.applicationGroupHostPoolReferences | Should -Be 1
        $result.applicationGroups[0].hostPoolId | Should -BeExactly $hostPoolId
        @($result.relationships | Where-Object { $_.sourceId -eq $applicationGroupId -and $_.relationship -eq 'UsesHostPool' -and $_.targetId -eq $hostPoolId }).Count | Should -Be 1
    }
}

Describe 'P5 Session Host normalization' {
    It 'normalizes technical session host state and links the session host to host pool and VM without user or free-text error data' {
        $hostPoolId = '/subscriptions/sub/resourceGroups/RG-AVD/providers/Microsoft.DesktopVirtualization/hostPools/hp01'
        $sessionHostId = "$hostPoolId/sessionHosts/sh01.contoso.local"
        $vmId = '/subscriptions/sub/resourceGroups/RG-AVD/providers/Microsoft.Compute/virtualMachines/sh01'

        $row = [pscustomobject]@{
            id = $sessionHostId; name = 'hp01/sh01.contoso.local'; type = 'microsoft.desktopvirtualization/hostpools/sessionhosts'
            subscriptionId = 'sub'; resourceGroup = 'RG-AVD'; location = 'westeurope'; tags = $null
            sessionHostFriendlyName = 'SH01'; sessionHostLastHeartBeat = '2026-08-12T13:00:00Z'
            sessionHostSessions = 2; sessionHostActiveSessions = 1; sessionHostDisconnectedSessions = 1; sessionHostPendingSessions = 0
            sessionHostAgentVersion = '1.0.0.0'; sessionHostAllowNewSession = $true; sessionHostStatus = 'Available'
            sessionHostStatusTimestamp = '2026-08-12T13:00:00Z'; sessionHostOsVersion = '10.0.26100'
            sessionHostSxsStackVersion = '1.0'; sessionHostUpdateState = 'Succeeded'; sessionHostLastUpdateTime = '2026-08-12T12:00:00Z'
            sessionHostVirtualMachineResourceId = $vmId
            assignedUser = 'must-not-export@example.test'; updateErrorMessage = 'must-not-export'
            sessionHostHealthCheckResults = @([pscustomobject]@{ additionalFailureDetails = 'must-not-export' })
        }

        $result = ConvertTo-CollectorAvdInventory -Rows @($row)
        $sessionHost = $result.sessionHosts[0]

        $result.summary.sessionHosts | Should -Be 1
        $result.summary.sessionHostVmReferences | Should -Be 1
        $sessionHost.name | Should -BeExactly 'sh01.contoso.local'
        $sessionHost.hostPoolId | Should -BeExactly $hostPoolId
        $sessionHost.virtualMachineResourceId | Should -BeExactly $vmId
        $sessionHost.status | Should -BeExactly 'Available'
        $sessionHost.sessions | Should -Be 2
        @($sessionHost.PSObject.Properties.Name) | Should -Not -Contain 'assignedUser'
        @($sessionHost.PSObject.Properties.Name) | Should -Not -Contain 'updateErrorMessage'
        @($sessionHost.PSObject.Properties.Name) | Should -Not -Contain 'sessionHostHealthCheckResults'
        @($result.relationships | Where-Object { $_.sourceId -eq $hostPoolId -and $_.relationship -eq 'ContainsSessionHost' -and $_.targetId -eq $sessionHostId }).Count | Should -Be 1
        @($result.relationships | Where-Object { $_.sourceId -eq $sessionHostId -and $_.relationship -eq 'BackedByVm' -and $_.targetId -eq $vmId }).Count | Should -Be 1
    }
}

Describe 'P5 Scaling Plan normalization' {
    It 'normalizes scaling host pool references and safe schedule controls without user notification free text' {
        $scalingPlanId = '/subscriptions/sub/resourceGroups/RG-AVD/providers/Microsoft.DesktopVirtualization/scalingPlans/sp01'
        $hostPoolId = '/subscriptions/sub/resourceGroups/RG-AVD/providers/Microsoft.DesktopVirtualization/hostPools/hp01'
        $row = [pscustomobject]@{
            id = $scalingPlanId; name = 'sp01'; type = 'microsoft.desktopvirtualization/scalingplans'
            subscriptionId = 'sub'; resourceGroup = 'RG-AVD'; location = 'westeurope'; tags = $null
            scalingPlanFriendlyName = 'Business Hours'; scalingPlanExclusionTag = 'NoScale'; scalingPlanHostPoolType = 'Pooled'
            scalingPlanTimeZone = 'W. Europe Standard Time'
            scalingPlanHostPoolReferences = @([pscustomobject]@{ hostPoolArmPath = $hostPoolId; scalingPlanEnabled = $true })
            scalingPlanSchedules = @([pscustomobject]@{
                name = 'Weekdays'; daysOfWeek = @('Monday','Tuesday','Wednesday','Thursday','Friday')
                scalingMethod = 'PowerManage'
                rampUpStartTime = [pscustomobject]@{ hour = 7; minute = 0 }
                rampUpLoadBalancingAlgorithm = 'BreadthFirst'; rampUpMinimumHostsPct = 20; rampUpCapacityThresholdPct = 80
                peakStartTime = [pscustomobject]@{ hour = 9; minute = 0 }; peakLoadBalancingAlgorithm = 'BreadthFirst'
                rampDownStartTime = [pscustomobject]@{ hour = 17; minute = 0 }
                rampDownLoadBalancingAlgorithm = 'DepthFirst'; rampDownMinimumHostsPct = 10; rampDownCapacityThresholdPct = 50
                rampDownForceLogoffUsers = $false; rampDownWaitTimeMinutes = 30; rampDownStopHostsWhen = 'ZeroSessions'
                rampDownNotificationMessage = 'must-not-export'
                offPeakStartTime = [pscustomobject]@{ hour = 22; minute = 0 }; offPeakLoadBalancingAlgorithm = 'DepthFirst'
                createDelete = [pscustomobject]@{
                    rampUpMinimumHostPoolSize = 1; rampUpMaximumHostPoolSize = 4
                    rampDownMinimumHostPoolSize = 1; rampDownMaximumHostPoolSize = 2
                }
            })
        }

        $result = ConvertTo-CollectorAvdInventory -Rows @($row)
        $plan = $result.scalingPlans[0]
        $schedule = $plan.schedules[0]

        $result.summary.scalingPlans | Should -Be 1
        $result.summary.scalingPlanHostPoolReferences | Should -Be 1
        $result.summary.scalingSchedules | Should -Be 1
        $plan.hostPoolReferences[0].hostPoolId | Should -BeExactly $hostPoolId
        $schedule.daysOfWeek | Should -Contain 'Monday'
        $schedule.rampUpStartTime.hour | Should -Be 7
        $schedule.createDelete.rampUpMaximumHostPoolSize | Should -Be 4
        @($schedule.PSObject.Properties.Name) | Should -Not -Contain 'rampDownNotificationMessage'
        @($result.relationships | Where-Object { $_.sourceId -eq $scalingPlanId -and $_.relationship -eq 'TargetsHostPool' -and $_.targetId -eq $hostPoolId }).Count | Should -Be 1
    }
}

Describe 'P5 empty collection stability' {
    It 'returns stable empty arrays for all AVD collections' {
        $result = ConvertTo-CollectorAvdInventory -Rows @()

        $result.summary.workspaces | Should -Be 0
        $result.summary.hostPools | Should -Be 0
        $result.summary.applicationGroups | Should -Be 0
        $result.summary.sessionHosts | Should -Be 0
        $result.summary.scalingPlans | Should -Be 0
        @($result.workspaces).Count | Should -Be 0
        @($result.hostPools).Count | Should -Be 0
        @($result.applicationGroups).Count | Should -Be 0
        @($result.sessionHosts).Count | Should -Be 0
        @($result.scalingPlans).Count | Should -Be 0
        @($result.relationships).Count | Should -Be 0
    }
}
