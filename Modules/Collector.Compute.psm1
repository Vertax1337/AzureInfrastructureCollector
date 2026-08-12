Set-StrictMode -Version Latest

function Get-CollectorComputeProperty {
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

function ConvertTo-CollectorComputeStringArray {
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

function ConvertTo-CollectorComputeIdArray {
    [CmdletBinding()]
    param($Value)

    @(
        foreach ($item in @($Value)) {
            if ($null -eq $item) {
                continue
            }

            if ($item -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace($item)) {
                    [string]$item
                }

                continue
            }

            $id = [string](Get-CollectorComputeProperty -InputObject $item -Name 'id')
            if (-not [string]::IsNullOrWhiteSpace($id)) {
                $id
            }
        }
    ) | Sort-Object -Unique
}

function New-CollectorComputeRelationship {
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

function ConvertTo-CollectorComputeInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $virtualMachines = [System.Collections.Generic.List[object]]::new()
    $managedDisks = [System.Collections.Generic.List[object]]::new()
    $availabilitySets = [System.Collections.Generic.List[object]]::new()
    $relationships = [System.Collections.Generic.List[object]]::new()

    $networkInterfaceReferenceCount = 0
    $osDiskReferenceCount = 0
    $dataDiskReferenceCount = 0
    $powerStateSnapshotCount = 0

    foreach ($row in @($Rows)) {
        if ($null -eq $row) {
            continue
        }

        $id = [string](Get-CollectorComputeProperty -InputObject $row -Name 'id')
        $name = [string](Get-CollectorComputeProperty -InputObject $row -Name 'name')
        $type = ([string](Get-CollectorComputeProperty -InputObject $row -Name 'type')).ToLowerInvariant()
        $subscriptionId = [string](Get-CollectorComputeProperty -InputObject $row -Name 'subscriptionId')
        $resourceGroup = [string](Get-CollectorComputeProperty -InputObject $row -Name 'resourceGroup')
        $location = [string](Get-CollectorComputeProperty -InputObject $row -Name 'location')
        $tags = Get-CollectorComputeProperty -InputObject $row -Name 'tags'
        $zones = @(ConvertTo-CollectorComputeStringArray (Get-CollectorComputeProperty -InputObject $row -Name 'zones'))

        switch ($type) {
            'microsoft.compute/virtualmachines' {
                $availabilitySetId = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmAvailabilitySetId')
                $powerState = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmPowerState')
                if (-not [string]::IsNullOrWhiteSpace($powerState)) {
                    $powerStateSnapshotCount++
                }

                $networkInterfaces = [System.Collections.Generic.List[object]]::new()
                foreach ($nicReference in @(Get-CollectorComputeProperty -InputObject $row -Name 'vmNetworkInterfaces')) {
                    if ($null -eq $nicReference) {
                        continue
                    }

                    $nicId = [string](Get-CollectorComputeProperty -InputObject $nicReference -Name 'id')
                    if ([string]::IsNullOrWhiteSpace($nicId)) {
                        continue
                    }

                    $nicProperties = Get-CollectorComputeProperty -InputObject $nicReference -Name 'properties'
                    $networkInterfaces.Add([pscustomobject][ordered]@{
                        id           = $nicId
                        primary      = Get-CollectorComputeProperty -InputObject $nicProperties -Name 'primary'
                        deleteOption = [string](Get-CollectorComputeProperty -InputObject $nicProperties -Name 'deleteOption')
                    })
                    $networkInterfaceReferenceCount++

                    $relationship = New-CollectorComputeRelationship -SourceId $id -Relationship 'UsesNetworkInterface' -TargetId $nicId
                    if ($relationship) {
                        $relationships.Add($relationship)
                    }
                }

                $osDiskManagedDiskId = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmOsDiskManagedDiskId')
                $osDisk = [pscustomobject][ordered]@{
                    name               = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmOsDiskName')
                    osType             = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmOsDiskOsType')
                    caching            = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmOsDiskCaching')
                    createOption       = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmOsDiskCreateOption')
                    managedDiskId      = $osDiskManagedDiskId
                    storageAccountType = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmOsDiskStorageAccountType')
                    diskSizeGB         = Get-CollectorComputeProperty -InputObject $row -Name 'vmOsDiskSizeGB'
                }

                if (-not [string]::IsNullOrWhiteSpace($osDiskManagedDiskId)) {
                    $osDiskReferenceCount++
                    $relationship = New-CollectorComputeRelationship -SourceId $id -Relationship 'UsesOsDisk' -TargetId $osDiskManagedDiskId
                    if ($relationship) {
                        $relationships.Add($relationship)
                    }
                }

                $dataDisks = [System.Collections.Generic.List[object]]::new()
                foreach ($dataDisk in @(Get-CollectorComputeProperty -InputObject $row -Name 'vmDataDisks')) {
                    if ($null -eq $dataDisk) {
                        continue
                    }

                    $managedDisk = Get-CollectorComputeProperty -InputObject $dataDisk -Name 'managedDisk'
                    $managedDiskId = [string](Get-CollectorComputeProperty -InputObject $managedDisk -Name 'id')

                    $dataDisks.Add([pscustomobject][ordered]@{
                        name                    = [string](Get-CollectorComputeProperty -InputObject $dataDisk -Name 'name')
                        lun                     = Get-CollectorComputeProperty -InputObject $dataDisk -Name 'lun'
                        caching                 = [string](Get-CollectorComputeProperty -InputObject $dataDisk -Name 'caching')
                        createOption            = [string](Get-CollectorComputeProperty -InputObject $dataDisk -Name 'createOption')
                        deleteOption            = [string](Get-CollectorComputeProperty -InputObject $dataDisk -Name 'deleteOption')
                        diskSizeGB              = Get-CollectorComputeProperty -InputObject $dataDisk -Name 'diskSizeGB'
                        managedDiskId           = $managedDiskId
                        storageAccountType      = [string](Get-CollectorComputeProperty -InputObject $managedDisk -Name 'storageAccountType')
                        writeAcceleratorEnabled = Get-CollectorComputeProperty -InputObject $dataDisk -Name 'writeAcceleratorEnabled'
                    })

                    if (-not [string]::IsNullOrWhiteSpace($managedDiskId)) {
                        $dataDiskReferenceCount++
                        $relationship = New-CollectorComputeRelationship -SourceId $id -Relationship 'UsesDataDisk' -TargetId $managedDiskId
                        if ($relationship) {
                            $relationships.Add($relationship)
                        }
                    }
                }

                if (-not [string]::IsNullOrWhiteSpace($availabilitySetId)) {
                    $relationship = New-CollectorComputeRelationship -SourceId $id -Relationship 'UsesAvailabilitySet' -TargetId $availabilitySetId
                    if ($relationship) {
                        $relationships.Add($relationship)
                    }
                }

                $virtualMachines.Add([pscustomobject][ordered]@{
                    id                = $id
                    name              = $name
                    subscriptionId    = $subscriptionId
                    resourceGroup     = $resourceGroup
                    location          = $location
                    zones             = $zones
                    vmSize            = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmSize')
                    powerState        = $powerState
                    provisioningState = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmProvisioningState')
                    availabilitySetId = $availabilitySetId
                    imageReference    = [pscustomobject][ordered]@{
                        id                      = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmImageReferenceId')
                        sharedGalleryImageId    = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmImageSharedGalleryImageId')
                        communityGalleryImageId = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmImageCommunityGalleryImageId')
                        publisher               = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmImagePublisher')
                        offer                   = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmImageOffer')
                        sku                     = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmImageSku')
                        version                 = [string](Get-CollectorComputeProperty -InputObject $row -Name 'vmImageVersion')
                    }
                    osDisk            = $osDisk
                    networkInterfaces = @($networkInterfaces | Sort-Object id)
                    dataDisks         = @($dataDisks | Sort-Object lun, name, managedDiskId)
                    tags              = $tags
                })
            }

            'microsoft.compute/disks' {
                $managedByResourceId = [string](Get-CollectorComputeProperty -InputObject $row -Name 'diskManagedBy')

                $managedDisks.Add([pscustomobject][ordered]@{
                    id                  = $id
                    name                = $name
                    subscriptionId      = $subscriptionId
                    resourceGroup       = $resourceGroup
                    location            = $location
                    zones               = $zones
                    skuName             = [string](Get-CollectorComputeProperty -InputObject $row -Name 'skuName')
                    skuTier             = [string](Get-CollectorComputeProperty -InputObject $row -Name 'skuTier')
                    performanceTier     = [string](Get-CollectorComputeProperty -InputObject $row -Name 'diskTier')
                    diskSizeGB          = Get-CollectorComputeProperty -InputObject $row -Name 'diskSizeGB'
                    osType              = [string](Get-CollectorComputeProperty -InputObject $row -Name 'diskOsType')
                    diskState           = [string](Get-CollectorComputeProperty -InputObject $row -Name 'diskState')
                    createOption        = [string](Get-CollectorComputeProperty -InputObject $row -Name 'diskCreateOption')
                    managedByResourceId = $managedByResourceId
                    tags                = $tags
                })

                if (-not [string]::IsNullOrWhiteSpace($managedByResourceId)) {
                    $relationship = New-CollectorComputeRelationship -SourceId $id -Relationship 'ManagedByResource' -TargetId $managedByResourceId
                    if ($relationship) {
                        $relationships.Add($relationship)
                    }
                }
            }

            'microsoft.compute/availabilitysets' {
                $virtualMachineIds = @(ConvertTo-CollectorComputeIdArray (Get-CollectorComputeProperty -InputObject $row -Name 'availabilitySetVirtualMachines'))
                $proximityPlacementGroupId = [string](Get-CollectorComputeProperty -InputObject $row -Name 'availabilitySetProximityPlacementGroupId')

                $availabilitySets.Add([pscustomobject][ordered]@{
                    id                        = $id
                    name                      = $name
                    subscriptionId            = $subscriptionId
                    resourceGroup             = $resourceGroup
                    location                  = $location
                    skuName                   = [string](Get-CollectorComputeProperty -InputObject $row -Name 'skuName')
                    platformFaultDomainCount  = Get-CollectorComputeProperty -InputObject $row -Name 'availabilitySetFaultDomainCount'
                    platformUpdateDomainCount = Get-CollectorComputeProperty -InputObject $row -Name 'availabilitySetUpdateDomainCount'
                    proximityPlacementGroupId = $proximityPlacementGroupId
                    virtualMachineIds         = $virtualMachineIds
                    tags                      = $tags
                })

                foreach ($virtualMachineId in $virtualMachineIds) {
                    $relationship = New-CollectorComputeRelationship -SourceId $id -Relationship 'ContainsVm' -TargetId ([string]$virtualMachineId)
                    if ($relationship) {
                        $relationships.Add($relationship)
                    }
                }

                if (-not [string]::IsNullOrWhiteSpace($proximityPlacementGroupId)) {
                    $relationship = New-CollectorComputeRelationship -SourceId $id -Relationship 'UsesProximityPlacementGroup' -TargetId $proximityPlacementGroupId
                    if ($relationship) {
                        $relationships.Add($relationship)
                    }
                }
            }
        }
    }

    $sortedRelationships = @($relationships | Sort-Object sourceId, relationship, targetId -Unique)

    [pscustomobject][ordered]@{
        schemaVersion = '1.0'
        summary       = [pscustomobject][ordered]@{
            virtualMachines            = $virtualMachines.Count
            managedDisks               = $managedDisks.Count
            availabilitySets           = $availabilitySets.Count
            networkInterfaceReferences = $networkInterfaceReferenceCount
            osDiskReferences           = $osDiskReferenceCount
            dataDiskReferences         = $dataDiskReferenceCount
            powerStateSnapshots        = $powerStateSnapshotCount
            relationships              = $sortedRelationships.Count
        }
        virtualMachines = @($virtualMachines | Sort-Object subscriptionId, resourceGroup, name, id)
        managedDisks    = @($managedDisks | Sort-Object subscriptionId, resourceGroup, name, id)
        availabilitySets = @($availabilitySets | Sort-Object subscriptionId, resourceGroup, name, id)
        relationships   = $sortedRelationships
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-CollectorComputeInventory'
)
