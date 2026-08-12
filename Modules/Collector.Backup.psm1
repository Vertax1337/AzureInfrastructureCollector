Set-StrictMode -Version Latest

function Get-CollectorBackupProperty {
    [CmdletBinding()]
    param($InputObject, [Parameter(Mandatory)][string]$Name)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function ConvertTo-CollectorBackupIso8601Utc {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) { return '' }

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
        if ([string]::IsNullOrWhiteSpace($text)) { return '' }
        $parsed = [datetimeoffset]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
        if (-not [datetimeoffset]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) { return '' }
        $utcDateTime = $parsed.UtcDateTime
    }

    return $utcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-CollectorBackupParentResourceId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceId,
        [Parameter(Mandatory)][string]$ChildSegment
    )

    if ([string]::IsNullOrWhiteSpace($ResourceId)) { return '' }
    $marker = "/$ChildSegment/"
    $index = $ResourceId.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
    if ($index -le 0) { return '' }
    return $ResourceId.Substring(0, $index)
}

function ConvertTo-CollectorBackupStringArray {
    [CmdletBinding()]
    param($Value)

    @(
        foreach ($item in @($Value)) {
            if ($null -eq $item) { continue }
            $text = [string]$item
            if (-not [string]::IsNullOrWhiteSpace($text)) { $text }
        }
    ) | Sort-Object -Unique
}

function ConvertTo-CollectorBackupStorageSettings {
    [CmdletBinding()]
    param($Value)

    @(
        foreach ($setting in @($Value)) {
            if ($null -eq $setting) { continue }
            [pscustomobject][ordered]@{
                datastoreType = [string](Get-CollectorBackupProperty -InputObject $setting -Name 'datastoreType')
                redundancy    = [string](Get-CollectorBackupProperty -InputObject $setting -Name 'type')
            }
        }
    ) | Sort-Object datastoreType, redundancy
}

function New-CollectorBackupRelationship {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceId,
        [Parameter(Mandatory)][string]$Relationship,
        [Parameter(Mandatory)][string]$TargetId
    )

    if ([string]::IsNullOrWhiteSpace($SourceId) -or [string]::IsNullOrWhiteSpace($TargetId)) { return $null }
    [pscustomobject][ordered]@{
        sourceId = $SourceId
        relationship = $Relationship
        targetId = $TargetId
    }
}

function ConvertTo-CollectorBackupInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$TopLevelRows,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$BackupRows
    )

    $recoveryServicesVaults = [System.Collections.Generic.List[object]]::new()
    $backupVaults = [System.Collections.Generic.List[object]]::new()
    $backupPolicies = [System.Collections.Generic.List[object]]::new()
    $recoveryProtectedItems = [System.Collections.Generic.List[object]]::new()
    $dataProtectionBackupInstances = [System.Collections.Generic.List[object]]::new()
    $relationships = [System.Collections.Generic.List[object]]::new()

    foreach ($row in @($TopLevelRows)) {
        if ($null -eq $row) { continue }
        $type = ([string](Get-CollectorBackupProperty -InputObject $row -Name 'type')).ToLowerInvariant()
        $id = [string](Get-CollectorBackupProperty -InputObject $row -Name 'id')

        switch ($type) {
            'microsoft.recoveryservices/vaults' {
                $recoveryServicesVaults.Add([pscustomobject][ordered]@{
                    id                            = $id
                    name                          = [string](Get-CollectorBackupProperty -InputObject $row -Name 'name')
                    subscriptionId                = [string](Get-CollectorBackupProperty -InputObject $row -Name 'subscriptionId')
                    resourceGroup                 = [string](Get-CollectorBackupProperty -InputObject $row -Name 'resourceGroup')
                    location                      = [string](Get-CollectorBackupProperty -InputObject $row -Name 'location')
                    skuName                       = [string](Get-CollectorBackupProperty -InputObject $row -Name 'skuName')
                    skuTier                       = [string](Get-CollectorBackupProperty -InputObject $row -Name 'skuTier')
                    publicNetworkAccess           = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryPublicNetworkAccess')
                    standardTierStorageRedundancy = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryStandardTierStorageRedundancy')
                    crossRegionRestore            = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryCrossRegionRestore')
                    crossSubscriptionRestoreState = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryCrossSubscriptionRestoreState')
                    softDeleteState               = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoverySoftDeleteState')
                    softDeleteRetentionDays       = Get-CollectorBackupProperty -InputObject $row -Name 'recoverySoftDeleteRetentionDays'
                    enhancedSecurityState         = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryEnhancedSecurityState')
                    immutabilityState             = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryImmutabilityState')
                    tags                          = Get-CollectorBackupProperty -InputObject $row -Name 'tags'
                })
            }
            'microsoft.dataprotection/backupvaults' {
                $backupVaults.Add([pscustomobject][ordered]@{
                    id                            = $id
                    name                          = [string](Get-CollectorBackupProperty -InputObject $row -Name 'name')
                    subscriptionId                = [string](Get-CollectorBackupProperty -InputObject $row -Name 'subscriptionId')
                    resourceGroup                 = [string](Get-CollectorBackupProperty -InputObject $row -Name 'resourceGroup')
                    location                      = [string](Get-CollectorBackupProperty -InputObject $row -Name 'location')
                    storageSettings               = @(ConvertTo-CollectorBackupStorageSettings (Get-CollectorBackupProperty -InputObject $row -Name 'backupVaultStorageSettings'))
                    softDeleteState               = [string](Get-CollectorBackupProperty -InputObject $row -Name 'backupVaultSoftDeleteState')
                    softDeleteRetentionDays       = Get-CollectorBackupProperty -InputObject $row -Name 'backupVaultSoftDeleteRetentionDays'
                    immutabilityState             = [string](Get-CollectorBackupProperty -InputObject $row -Name 'backupVaultImmutabilityState')
                    crossRegionRestoreState       = [string](Get-CollectorBackupProperty -InputObject $row -Name 'backupVaultCrossRegionRestoreState')
                    crossSubscriptionRestoreState = [string](Get-CollectorBackupProperty -InputObject $row -Name 'backupVaultCrossSubscriptionRestoreState')
                    tags                          = Get-CollectorBackupProperty -InputObject $row -Name 'tags'
                })
            }
        }
    }

    foreach ($row in @($BackupRows)) {
        if ($null -eq $row) { continue }
        $type = ([string](Get-CollectorBackupProperty -InputObject $row -Name 'type')).ToLowerInvariant()
        $id = [string](Get-CollectorBackupProperty -InputObject $row -Name 'id')
        $name = [string](Get-CollectorBackupProperty -InputObject $row -Name 'name')
        $subscriptionId = [string](Get-CollectorBackupProperty -InputObject $row -Name 'subscriptionId')
        $resourceGroup = [string](Get-CollectorBackupProperty -InputObject $row -Name 'resourceGroup')

        switch ($type) {
            'microsoft.recoveryservices/vaults/backuppolicies' {
                $vaultId = Get-CollectorBackupParentResourceId -ResourceId $id -ChildSegment 'backupPolicies'
                $policy = [pscustomobject][ordered]@{
                    id                   = $id
                    name                 = $name
                    providerModel        = 'RecoveryServices'
                    subscriptionId       = $subscriptionId
                    resourceGroup        = $resourceGroup
                    vaultId              = $vaultId
                    dataSourceTypes       = @([string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryBackupManagementType')) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                    protectedItemsCount  = Get-CollectorBackupProperty -InputObject $row -Name 'recoveryProtectedItemsCount'
                    scheduleRunFrequency = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryScheduleRunFrequency')
                    retentionPolicyType  = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryRetentionPolicyType')
                }
                $backupPolicies.Add($policy)
                $relationship = New-CollectorBackupRelationship -SourceId $vaultId -Relationship 'ContainsBackupPolicy' -TargetId $id
                if ($relationship) { $relationships.Add($relationship) }
            }
            'microsoft.dataprotection/backupvaults/backuppolicies' {
                $vaultId = Get-CollectorBackupParentResourceId -ResourceId $id -ChildSegment 'backupPolicies'
                $policy = [pscustomobject][ordered]@{
                    id                   = $id
                    name                 = $name
                    providerModel        = 'DataProtection'
                    subscriptionId       = $subscriptionId
                    resourceGroup        = $resourceGroup
                    vaultId              = $vaultId
                    dataSourceTypes       = @(ConvertTo-CollectorBackupStringArray (Get-CollectorBackupProperty -InputObject $row -Name 'dataProtectionDatasourceTypes'))
                    protectedItemsCount  = $null
                    scheduleRunFrequency = ''
                    retentionPolicyType  = [string](Get-CollectorBackupProperty -InputObject $row -Name 'dataProtectionPolicyObjectType')
                }
                $backupPolicies.Add($policy)
                $relationship = New-CollectorBackupRelationship -SourceId $vaultId -Relationship 'ContainsBackupPolicy' -TargetId $id
                if ($relationship) { $relationships.Add($relationship) }
            }
            'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems' {
                $vaultId = Get-CollectorBackupParentResourceId -ResourceId $id -ChildSegment 'backupFabrics'
                $sourceResourceId = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoverySourceResourceId')
                $policyId = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryPolicyId')
                $recoveryProtectedItems.Add([pscustomobject][ordered]@{
                    id                    = $id
                    name                  = $name
                    subscriptionId        = $subscriptionId
                    resourceGroup         = $resourceGroup
                    vaultId               = $vaultId
                    friendlyName          = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryFriendlyName')
                    backupManagementType  = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryBackupManagementType')
                    workloadType          = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryWorkloadType')
                    sourceResourceId      = $sourceResourceId
                    policyId              = $policyId
                    policyName            = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryPolicyName')
                    protectionState       = [string](Get-CollectorBackupProperty -InputObject $row -Name 'recoveryProtectionState')
                    lastRecoveryPoint     = ConvertTo-CollectorBackupIso8601Utc (Get-CollectorBackupProperty -InputObject $row -Name 'recoveryLastRecoveryPoint')
                })
                foreach ($rel in @(
                    (New-CollectorBackupRelationship -SourceId $vaultId -Relationship 'ContainsProtectedItem' -TargetId $id),
                    (New-CollectorBackupRelationship -SourceId $id -Relationship 'UsesBackupPolicy' -TargetId $policyId),
                    (New-CollectorBackupRelationship -SourceId $id -Relationship 'ProtectsResource' -TargetId $sourceResourceId)
                )) { if ($rel) { $relationships.Add($rel) } }
            }
            'microsoft.dataprotection/backupvaults/backupinstances' {
                $vaultId = Get-CollectorBackupParentResourceId -ResourceId $id -ChildSegment 'backupInstances'
                $sourceResourceId = [string](Get-CollectorBackupProperty -InputObject $row -Name 'dataProtectionSourceResourceId')
                $policyId = [string](Get-CollectorBackupProperty -InputObject $row -Name 'dataProtectionPolicyId')
                $dataProtectionBackupInstances.Add([pscustomobject][ordered]@{
                    id                    = $id
                    name                  = $name
                    subscriptionId        = $subscriptionId
                    resourceGroup         = $resourceGroup
                    vaultId               = $vaultId
                    friendlyName          = [string](Get-CollectorBackupProperty -InputObject $row -Name 'dataProtectionFriendlyName')
                    dataSourceType        = [string](Get-CollectorBackupProperty -InputObject $row -Name 'dataProtectionDatasourceType')
                    sourceResourceId      = $sourceResourceId
                    sourceResourceLocation = [string](Get-CollectorBackupProperty -InputObject $row -Name 'dataProtectionSourceResourceLocation')
                    policyId              = $policyId
                    policyName            = [string](Get-CollectorBackupProperty -InputObject $row -Name 'dataProtectionPolicyName')
                    protectionState       = [string](Get-CollectorBackupProperty -InputObject $row -Name 'dataProtectionProtectionState')
                    lastRecoveryPoint     = ConvertTo-CollectorBackupIso8601Utc (Get-CollectorBackupProperty -InputObject $row -Name 'dataProtectionLastRecoveryPoint')
                })
                foreach ($rel in @(
                    (New-CollectorBackupRelationship -SourceId $vaultId -Relationship 'ContainsBackupInstance' -TargetId $id),
                    (New-CollectorBackupRelationship -SourceId $id -Relationship 'UsesBackupPolicy' -TargetId $policyId),
                    (New-CollectorBackupRelationship -SourceId $id -Relationship 'ProtectsResource' -TargetId $sourceResourceId)
                )) { if ($rel) { $relationships.Add($rel) } }
            }
        }
    }

    $sortedRelationships = @($relationships | Sort-Object sourceId, relationship, targetId -Unique)

    [pscustomobject][ordered]@{
        schemaVersion = '1.0'
        summary = [pscustomobject][ordered]@{
            recoveryServicesVaults          = $recoveryServicesVaults.Count
            backupVaults                    = $backupVaults.Count
            backupPolicies                  = $backupPolicies.Count
            recoveryProtectedItems          = $recoveryProtectedItems.Count
            dataProtectionBackupInstances   = $dataProtectionBackupInstances.Count
            protectedResourceReferences     = @($sortedRelationships | Where-Object { $_.relationship -eq 'ProtectsResource' }).Count
            relationships                   = $sortedRelationships.Count
        }
        recoveryServicesVaults        = @($recoveryServicesVaults | Sort-Object subscriptionId, resourceGroup, name, id)
        backupVaults                  = @($backupVaults | Sort-Object subscriptionId, resourceGroup, name, id)
        backupPolicies                = @($backupPolicies | Sort-Object subscriptionId, resourceGroup, providerModel, name, id)
        recoveryProtectedItems        = @($recoveryProtectedItems | Sort-Object subscriptionId, resourceGroup, vaultId, name, id)
        dataProtectionBackupInstances = @($dataProtectionBackupInstances | Sort-Object subscriptionId, resourceGroup, vaultId, name, id)
        relationships                 = $sortedRelationships
    }
}

Export-ModuleMember -Function 'ConvertTo-CollectorBackupInventory'
