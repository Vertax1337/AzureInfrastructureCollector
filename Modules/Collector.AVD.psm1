Set-StrictMode -Version Latest

function Get-CollectorAvdProperty {
    [CmdletBinding()]
    param(
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }

        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $null
}

function ConvertTo-CollectorAvdStringArray {
    [CmdletBinding()]
    param($Value)

    @(
        foreach ($item in @($Value)) {
            if ($null -eq $item) {
                continue
            }

            $text = [string]$item
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $text
            }
        }
    ) | Sort-Object -Unique
}

function ConvertTo-CollectorAvdIso8601Utc {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) {
        return ''
    }

    $utcDateTime = $null

    if ($Value -is [datetimeoffset]) {
        $utcDateTime = ([datetimeoffset]$Value).UtcDateTime
    }
    elseif ($Value -is [datetime]) {
        $dateTimeValue = [datetime]$Value
        if ($dateTimeValue.Kind -eq [System.DateTimeKind]::Unspecified) {
            $utcDateTime = [datetime]::SpecifyKind($dateTimeValue, [System.DateTimeKind]::Utc)
        }
        else {
            $utcDateTime = $dateTimeValue.ToUniversalTime()
        }
    }
    else {
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) {
            return ''
        }

        $parsed = [datetimeoffset]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
        if (-not [datetimeoffset]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
            return ''
        }

        $utcDateTime = $parsed.UtcDateTime
    }

    return $utcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-CollectorAvdParentResourceId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceId,

        [Parameter(Mandatory)]
        [string]$ChildSegment
    )

    if ([string]::IsNullOrWhiteSpace($ResourceId)) {
        return ''
    }

    $marker = "/$ChildSegment/"
    $index = $ResourceId.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
    if ($index -le 0) {
        return ''
    }

    return $ResourceId.Substring(0, $index)
}

function Get-CollectorAvdLeafName {
    [CmdletBinding()]
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ''
    }

    $segments = @($Name -split '/' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($segments.Count -eq 0) {
        return ''
    }

    return [string]$segments[-1]
}

function New-CollectorAvdRelationship {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [string]$Relationship,

        [Parameter(Mandatory)]
        [string]$TargetId
    )

    if ([string]::IsNullOrWhiteSpace($SourceId) -or [string]::IsNullOrWhiteSpace($TargetId)) {
        return $null
    }

    [pscustomobject][ordered]@{
        sourceId     = $SourceId
        relationship = $Relationship
        targetId     = $TargetId
    }
}

function ConvertTo-CollectorAvdTime {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    [pscustomobject][ordered]@{
        hour   = Get-CollectorAvdProperty -InputObject $Value -Name 'hour'
        minute = Get-CollectorAvdProperty -InputObject $Value -Name 'minute'
    }
}

function ConvertTo-CollectorAvdAgentUpdate {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    $maintenanceWindows = [System.Collections.Generic.List[object]]::new()
    foreach ($window in @(Get-CollectorAvdProperty -InputObject $Value -Name 'maintenanceWindows')) {
        if ($null -eq $window) {
            continue
        }

        $maintenanceWindows.Add([pscustomobject][ordered]@{
            dayOfWeek = [string](Get-CollectorAvdProperty -InputObject $window -Name 'dayOfWeek')
            hour      = Get-CollectorAvdProperty -InputObject $window -Name 'hour'
        })
    }

    [pscustomobject][ordered]@{
        type                      = [string](Get-CollectorAvdProperty -InputObject $Value -Name 'type')
        maintenanceWindowTimeZone = [string](Get-CollectorAvdProperty -InputObject $Value -Name 'maintenanceWindowTimeZone')
        useSessionHostLocalTime   = Get-CollectorAvdProperty -InputObject $Value -Name 'useSessionHostLocalTime'
        maintenanceWindows        = @($maintenanceWindows | Sort-Object dayOfWeek, hour)
    }
}

function ConvertTo-CollectorAvdScalingSchedule {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    $createDeleteValue = Get-CollectorAvdProperty -InputObject $Value -Name 'createDelete'
    $createDelete = $null
    if ($null -ne $createDeleteValue) {
        $createDelete = [pscustomobject][ordered]@{
            rampUpMinimumHostPoolSize   = Get-CollectorAvdProperty -InputObject $createDeleteValue -Name 'rampUpMinimumHostPoolSize'
            rampUpMaximumHostPoolSize   = Get-CollectorAvdProperty -InputObject $createDeleteValue -Name 'rampUpMaximumHostPoolSize'
            rampDownMinimumHostPoolSize = Get-CollectorAvdProperty -InputObject $createDeleteValue -Name 'rampDownMinimumHostPoolSize'
            rampDownMaximumHostPoolSize = Get-CollectorAvdProperty -InputObject $createDeleteValue -Name 'rampDownMaximumHostPoolSize'
        }
    }

    [pscustomobject][ordered]@{
        name                           = [string](Get-CollectorAvdProperty -InputObject $Value -Name 'name')
        daysOfWeek                     = @(ConvertTo-CollectorAvdStringArray (Get-CollectorAvdProperty -InputObject $Value -Name 'daysOfWeek'))
        scalingMethod                  = [string](Get-CollectorAvdProperty -InputObject $Value -Name 'scalingMethod')
        rampUpStartTime                = ConvertTo-CollectorAvdTime (Get-CollectorAvdProperty -InputObject $Value -Name 'rampUpStartTime')
        rampUpLoadBalancingAlgorithm   = [string](Get-CollectorAvdProperty -InputObject $Value -Name 'rampUpLoadBalancingAlgorithm')
        rampUpMinimumHostsPct          = Get-CollectorAvdProperty -InputObject $Value -Name 'rampUpMinimumHostsPct'
        rampUpCapacityThresholdPct     = Get-CollectorAvdProperty -InputObject $Value -Name 'rampUpCapacityThresholdPct'
        peakStartTime                  = ConvertTo-CollectorAvdTime (Get-CollectorAvdProperty -InputObject $Value -Name 'peakStartTime')
        peakLoadBalancingAlgorithm     = [string](Get-CollectorAvdProperty -InputObject $Value -Name 'peakLoadBalancingAlgorithm')
        rampDownStartTime              = ConvertTo-CollectorAvdTime (Get-CollectorAvdProperty -InputObject $Value -Name 'rampDownStartTime')
        rampDownLoadBalancingAlgorithm = [string](Get-CollectorAvdProperty -InputObject $Value -Name 'rampDownLoadBalancingAlgorithm')
        rampDownMinimumHostsPct        = Get-CollectorAvdProperty -InputObject $Value -Name 'rampDownMinimumHostsPct'
        rampDownCapacityThresholdPct   = Get-CollectorAvdProperty -InputObject $Value -Name 'rampDownCapacityThresholdPct'
        rampDownForceLogoffUsers       = Get-CollectorAvdProperty -InputObject $Value -Name 'rampDownForceLogoffUsers'
        rampDownWaitTimeMinutes        = Get-CollectorAvdProperty -InputObject $Value -Name 'rampDownWaitTimeMinutes'
        rampDownStopHostsWhen          = [string](Get-CollectorAvdProperty -InputObject $Value -Name 'rampDownStopHostsWhen')
        offPeakStartTime               = ConvertTo-CollectorAvdTime (Get-CollectorAvdProperty -InputObject $Value -Name 'offPeakStartTime')
        offPeakLoadBalancingAlgorithm  = [string](Get-CollectorAvdProperty -InputObject $Value -Name 'offPeakLoadBalancingAlgorithm')
        createDelete                   = $createDelete
    }
}

function ConvertTo-CollectorAvdInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $workspaces = [System.Collections.Generic.List[object]]::new()
    $hostPools = [System.Collections.Generic.List[object]]::new()
    $applicationGroups = [System.Collections.Generic.List[object]]::new()
    $sessionHosts = [System.Collections.Generic.List[object]]::new()
    $scalingPlans = [System.Collections.Generic.List[object]]::new()
    $relationships = [System.Collections.Generic.List[object]]::new()

    $workspaceApplicationGroupReferenceCount = 0
    $applicationGroupHostPoolReferenceCount = 0
    $sessionHostVmReferenceCount = 0
    $scalingPlanHostPoolReferenceCount = 0
    $scalingScheduleCount = 0

    foreach ($row in @($Rows)) {
        if ($null -eq $row) {
            continue
        }

        $id = [string](Get-CollectorAvdProperty -InputObject $row -Name 'id')
        $name = [string](Get-CollectorAvdProperty -InputObject $row -Name 'name')
        $type = ([string](Get-CollectorAvdProperty -InputObject $row -Name 'type')).ToLowerInvariant()
        $subscriptionId = [string](Get-CollectorAvdProperty -InputObject $row -Name 'subscriptionId')
        $resourceGroup = [string](Get-CollectorAvdProperty -InputObject $row -Name 'resourceGroup')
        $location = [string](Get-CollectorAvdProperty -InputObject $row -Name 'location')
        $tags = Get-CollectorAvdProperty -InputObject $row -Name 'tags'

        switch ($type) {
            'microsoft.desktopvirtualization/workspaces' {
                $applicationGroupIds = @(ConvertTo-CollectorAvdStringArray (Get-CollectorAvdProperty -InputObject $row -Name 'workspaceApplicationGroupReferences'))

                foreach ($applicationGroupId in $applicationGroupIds) {
                    $workspaceApplicationGroupReferenceCount++
                    $relationship = New-CollectorAvdRelationship -SourceId $id -Relationship 'ReferencesApplicationGroup' -TargetId ([string]$applicationGroupId)
                    if ($relationship) {
                        $relationships.Add($relationship)
                    }
                }

                $workspaces.Add([pscustomobject][ordered]@{
                    id                        = $id
                    name                      = $name
                    subscriptionId            = $subscriptionId
                    resourceGroup             = $resourceGroup
                    location                  = $location
                    friendlyName              = [string](Get-CollectorAvdProperty -InputObject $row -Name 'workspaceFriendlyName')
                    publicNetworkAccess       = [string](Get-CollectorAvdProperty -InputObject $row -Name 'workspacePublicNetworkAccess')
                    applicationGroupReferences = $applicationGroupIds
                    tags                      = $tags
                })
            }

            'microsoft.desktopvirtualization/hostpools' {
                $hostPools.Add([pscustomobject][ordered]@{
                    id                            = $id
                    name                          = $name
                    subscriptionId                = $subscriptionId
                    resourceGroup                 = $resourceGroup
                    location                      = $location
                    friendlyName                  = [string](Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolFriendlyName')
                    hostPoolType                  = [string](Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolType')
                    loadBalancerType              = [string](Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolLoadBalancerType')
                    maxSessionLimit               = Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolMaxSessionLimit'
                    personalDesktopAssignmentType = [string](Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolPersonalDesktopAssignmentType')
                    preferredAppGroupType         = [string](Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolPreferredAppGroupType')
                    publicNetworkAccess           = [string](Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolPublicNetworkAccess')
                    startVmOnConnect              = Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolStartVmOnConnect'
                    validationEnvironment         = Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolValidationEnvironment'
                    managementType                = [string](Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolManagementType')
                    directUdp                     = [string](Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolDirectUdp')
                    managedPrivateUdp             = [string](Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolManagedPrivateUdp')
                    publicUdp                     = [string](Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolPublicUdp')
                    relayUdp                      = [string](Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolRelayUdp')
                    agentUpdate                   = ConvertTo-CollectorAvdAgentUpdate (Get-CollectorAvdProperty -InputObject $row -Name 'hostPoolAgentUpdate')
                    tags                          = $tags
                })
            }

            'microsoft.desktopvirtualization/applicationgroups' {
                $hostPoolId = [string](Get-CollectorAvdProperty -InputObject $row -Name 'applicationGroupHostPoolArmPath')
                if (-not [string]::IsNullOrWhiteSpace($hostPoolId)) {
                    $applicationGroupHostPoolReferenceCount++
                    $relationship = New-CollectorAvdRelationship -SourceId $id -Relationship 'UsesHostPool' -TargetId $hostPoolId
                    if ($relationship) {
                        $relationships.Add($relationship)
                    }
                }

                $applicationGroups.Add([pscustomobject][ordered]@{
                    id                   = $id
                    name                 = $name
                    subscriptionId       = $subscriptionId
                    resourceGroup        = $resourceGroup
                    location             = $location
                    friendlyName         = [string](Get-CollectorAvdProperty -InputObject $row -Name 'applicationGroupFriendlyName')
                    applicationGroupType = [string](Get-CollectorAvdProperty -InputObject $row -Name 'applicationGroupType')
                    hostPoolId           = $hostPoolId
                    showInFeed           = Get-CollectorAvdProperty -InputObject $row -Name 'applicationGroupShowInFeed'
                    tags                 = $tags
                })
            }

            'microsoft.desktopvirtualization/hostpools/sessionhosts' {
                $hostPoolId = Get-CollectorAvdParentResourceId -ResourceId $id -ChildSegment 'sessionhosts'
                $virtualMachineResourceId = [string](Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostVirtualMachineResourceId')

                if (-not [string]::IsNullOrWhiteSpace($hostPoolId)) {
                    $relationship = New-CollectorAvdRelationship -SourceId $hostPoolId -Relationship 'ContainsSessionHost' -TargetId $id
                    if ($relationship) {
                        $relationships.Add($relationship)
                    }
                }

                if (-not [string]::IsNullOrWhiteSpace($virtualMachineResourceId)) {
                    $sessionHostVmReferenceCount++
                    $relationship = New-CollectorAvdRelationship -SourceId $id -Relationship 'BackedByVm' -TargetId $virtualMachineResourceId
                    if ($relationship) {
                        $relationships.Add($relationship)
                    }
                }

                $sessionHosts.Add([pscustomobject][ordered]@{
                    id                       = $id
                    name                     = Get-CollectorAvdLeafName -Name $name
                    subscriptionId           = $subscriptionId
                    resourceGroup            = $resourceGroup
                    location                 = $location
                    hostPoolId               = $hostPoolId
                    friendlyName             = [string](Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostFriendlyName')
                    status                   = [string](Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostStatus')
                    statusTimestamp          = ConvertTo-CollectorAvdIso8601Utc (Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostStatusTimestamp')
                    allowNewSession          = Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostAllowNewSession'
                    sessions                 = Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostSessions'
                    activeSessions           = Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostActiveSessions'
                    disconnectedSessions     = Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostDisconnectedSessions'
                    pendingSessions          = Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostPendingSessions'
                    agentVersion             = [string](Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostAgentVersion')
                    osVersion                = [string](Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostOsVersion')
                    sxsStackVersion          = [string](Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostSxsStackVersion')
                    updateState              = [string](Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostUpdateState')
                    lastHeartBeat            = ConvertTo-CollectorAvdIso8601Utc (Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostLastHeartBeat')
                    lastUpdateTime           = ConvertTo-CollectorAvdIso8601Utc (Get-CollectorAvdProperty -InputObject $row -Name 'sessionHostLastUpdateTime')
                    virtualMachineResourceId = $virtualMachineResourceId
                    tags                     = $tags
                })
            }

            'microsoft.desktopvirtualization/scalingplans' {
                $hostPoolReferences = [System.Collections.Generic.List[object]]::new()
                foreach ($reference in @(Get-CollectorAvdProperty -InputObject $row -Name 'scalingPlanHostPoolReferences')) {
                    if ($null -eq $reference) {
                        continue
                    }

                    $hostPoolId = [string](Get-CollectorAvdProperty -InputObject $reference -Name 'hostPoolArmPath')
                    if ([string]::IsNullOrWhiteSpace($hostPoolId)) {
                        continue
                    }

                    $hostPoolReferences.Add([pscustomobject][ordered]@{
                        hostPoolId        = $hostPoolId
                        scalingPlanEnabled = Get-CollectorAvdProperty -InputObject $reference -Name 'scalingPlanEnabled'
                    })
                    $scalingPlanHostPoolReferenceCount++

                    $relationship = New-CollectorAvdRelationship -SourceId $id -Relationship 'TargetsHostPool' -TargetId $hostPoolId
                    if ($relationship) {
                        $relationships.Add($relationship)
                    }
                }

                $schedules = [System.Collections.Generic.List[object]]::new()
                foreach ($schedule in @(Get-CollectorAvdProperty -InputObject $row -Name 'scalingPlanSchedules')) {
                    if ($null -eq $schedule) {
                        continue
                    }

                    $normalizedSchedule = ConvertTo-CollectorAvdScalingSchedule -Value $schedule
                    if ($normalizedSchedule) {
                        $schedules.Add($normalizedSchedule)
                        $scalingScheduleCount++
                    }
                }

                $scalingPlans.Add([pscustomobject][ordered]@{
                    id                 = $id
                    name               = $name
                    subscriptionId     = $subscriptionId
                    resourceGroup      = $resourceGroup
                    location           = $location
                    friendlyName       = [string](Get-CollectorAvdProperty -InputObject $row -Name 'scalingPlanFriendlyName')
                    exclusionTag       = [string](Get-CollectorAvdProperty -InputObject $row -Name 'scalingPlanExclusionTag')
                    hostPoolType       = [string](Get-CollectorAvdProperty -InputObject $row -Name 'scalingPlanHostPoolType')
                    timeZone           = [string](Get-CollectorAvdProperty -InputObject $row -Name 'scalingPlanTimeZone')
                    hostPoolReferences = @($hostPoolReferences | Sort-Object hostPoolId)
                    schedules          = @($schedules | Sort-Object name)
                    tags               = $tags
                })
            }
        }
    }

    $sortedRelationships = @($relationships | Sort-Object sourceId, relationship, targetId -Unique)

    [pscustomobject][ordered]@{
        schemaVersion = '1.0'
        summary       = [pscustomobject][ordered]@{
            workspaces                         = $workspaces.Count
            hostPools                          = $hostPools.Count
            applicationGroups                  = $applicationGroups.Count
            sessionHosts                       = $sessionHosts.Count
            scalingPlans                       = $scalingPlans.Count
            workspaceApplicationGroupReferences = $workspaceApplicationGroupReferenceCount
            applicationGroupHostPoolReferences = $applicationGroupHostPoolReferenceCount
            sessionHostVmReferences            = $sessionHostVmReferenceCount
            scalingPlanHostPoolReferences      = $scalingPlanHostPoolReferenceCount
            scalingSchedules                   = $scalingScheduleCount
            startVmOnConnectEnabledHostPools   = @($hostPools | Where-Object { $_.startVmOnConnect -eq $true }).Count
            sessionHostsAllowingNewSession     = @($sessionHosts | Where-Object { $_.allowNewSession -eq $true }).Count
            relationships                      = $sortedRelationships.Count
        }
        workspaces        = @($workspaces | Sort-Object subscriptionId, resourceGroup, name, id)
        hostPools         = @($hostPools | Sort-Object subscriptionId, resourceGroup, name, id)
        applicationGroups = @($applicationGroups | Sort-Object subscriptionId, resourceGroup, name, id)
        sessionHosts      = @($sessionHosts | Sort-Object subscriptionId, resourceGroup, hostPoolId, name, id)
        scalingPlans      = @($scalingPlans | Sort-Object subscriptionId, resourceGroup, name, id)
        relationships     = $sortedRelationships
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-CollectorAvdInventory'
)
