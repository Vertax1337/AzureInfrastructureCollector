BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.Compute.psm1') -Force
}

Describe 'P4 Compute query safety boundary' {
    It 'collects only planned compute resource types and excludes sensitive VM configuration paths' {
        $query = Get-Content (Join-Path $PSScriptRoot '../../Queries/Compute.kql') -Raw

        foreach ($resourceType in @(
            'microsoft.compute/virtualmachines',
            'microsoft.compute/disks',
            'microsoft.compute/availabilitysets'
        )) {
            $query | Should -Match ([regex]::Escape($resourceType))
        }

        $query | Should -Not -Match '(?i)virtualmachines/extensions'
        $query | Should -Not -Match '(?i)restorepointcollections'
        $query | Should -Not -Match '(?i)osProfile'
        $query | Should -Not -Match '(?i)adminUsername'
        $query | Should -Not -Match '(?i)adminPassword'
        $query | Should -Not -Match '(?i)userData'
        $query | Should -Not -Match '(?i)diagnosticsProfile'
        $query | Should -Not -Match '(?i)protectedSettings'
        $query | Should -Not -Match '(?i)secretUrl'
        $query | Should -Not -Match '(?i)keyUrl'
        $query | Should -Not -Match '(?i)encryptionSettingsCollection'
    }
}

Describe 'P4 Virtual Machine normalization' {
    It 'normalizes VM size, image, power state, availability, NICs and managed disk relationships' {
        $vmId = '/subscriptions/sub/resourceGroups/RG-Compute/providers/Microsoft.Compute/virtualMachines/vm01'
        $nicId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/networkInterfaces/nic01'
        $osDiskId = '/subscriptions/sub/resourceGroups/RG-Compute/providers/Microsoft.Compute/disks/vm01-os'
        $dataDiskId = '/subscriptions/sub/resourceGroups/RG-Compute/providers/Microsoft.Compute/disks/vm01-data01'
        $availabilitySetId = '/subscriptions/sub/resourceGroups/RG-Compute/providers/Microsoft.Compute/availabilitySets/as01'

        $row = [pscustomobject]@{
            id = $vmId
            name = 'vm01'
            type = 'microsoft.compute/virtualmachines'
            subscriptionId = 'sub'
            resourceGroup = 'RG-Compute'
            location = 'westeurope'
            tags = $null
            zones = @('1')
            vmSize = 'Standard_D4s_v5'
            vmPowerState = 'PowerState/running'
            vmProvisioningState = 'Succeeded'
            vmAvailabilitySetId = $availabilitySetId
            vmImageReferenceId = ''
            vmImageSharedGalleryImageId = ''
            vmImageCommunityGalleryImageId = ''
            vmImagePublisher = 'MicrosoftWindowsServer'
            vmImageOffer = 'WindowsServer'
            vmImageSku = '2025-datacenter-azure-edition'
            vmImageVersion = 'latest'
            vmOsDiskName = 'vm01-os'
            vmOsDiskOsType = 'Windows'
            vmOsDiskCaching = 'ReadWrite'
            vmOsDiskCreateOption = 'FromImage'
            vmOsDiskManagedDiskId = $osDiskId
            vmOsDiskStorageAccountType = 'Premium_LRS'
            vmOsDiskSizeGB = 128
            vmNetworkInterfaces = @(
                [pscustomobject]@{
                    id = $nicId
                    properties = [pscustomobject]@{
                        primary = $true
                        deleteOption = 'Detach'
                    }
                }
            )
            vmDataDisks = @(
                [pscustomobject]@{
                    name = 'vm01-data01'
                    lun = 0
                    caching = 'None'
                    createOption = 'Attach'
                    deleteOption = 'Detach'
                    diskSizeGB = 256
                    writeAcceleratorEnabled = $false
                    managedDisk = [pscustomobject]@{
                        id = $dataDiskId
                        storageAccountType = 'Premium_LRS'
                    }
                }
            )
        }

        $result = ConvertTo-CollectorComputeInventory -Rows @($row)

        $result.summary.virtualMachines | Should -Be 1
        $result.summary.networkInterfaceReferences | Should -Be 1
        $result.summary.osDiskReferences | Should -Be 1
        $result.summary.dataDiskReferences | Should -Be 1
        $result.summary.powerStateSnapshots | Should -Be 1
        $result.virtualMachines[0].vmSize | Should -BeExactly 'Standard_D4s_v5'
        $result.virtualMachines[0].powerState | Should -BeExactly 'PowerState/running'
        $result.virtualMachines[0].imageReference.publisher | Should -BeExactly 'MicrosoftWindowsServer'
        $result.virtualMachines[0].networkInterfaces[0].id | Should -Be $nicId
        $result.virtualMachines[0].osDisk.managedDiskId | Should -Be $osDiskId
        $result.virtualMachines[0].dataDisks[0].managedDiskId | Should -Be $dataDiskId
        @($result.relationships | Where-Object { $_.sourceId -eq $vmId -and $_.relationship -eq 'UsesNetworkInterface' -and $_.targetId -eq $nicId }).Count | Should -Be 1
        @($result.relationships | Where-Object { $_.sourceId -eq $vmId -and $_.relationship -eq 'UsesOsDisk' -and $_.targetId -eq $osDiskId }).Count | Should -Be 1
        @($result.relationships | Where-Object { $_.sourceId -eq $vmId -and $_.relationship -eq 'UsesDataDisk' -and $_.targetId -eq $dataDiskId }).Count | Should -Be 1
        @($result.relationships | Where-Object { $_.sourceId -eq $vmId -and $_.relationship -eq 'UsesAvailabilitySet' -and $_.targetId -eq $availabilitySetId }).Count | Should -Be 1
    }

    It 'does not normalize unmanaged VHD/image URIs or disk encryption references from nested data-disk objects' {
        $vmId = '/subscriptions/sub/resourceGroups/RG-Compute/providers/Microsoft.Compute/virtualMachines/vm02'
        $row = [pscustomobject]@{
            id = $vmId
            name = 'vm02'
            type = 'microsoft.compute/virtualmachines'
            subscriptionId = 'sub'
            resourceGroup = 'RG-Compute'
            location = 'westeurope'
            tags = $null
            zones = @()
            vmSize = 'Standard_D2s_v5'
            vmPowerState = ''
            vmProvisioningState = 'Succeeded'
            vmAvailabilitySetId = ''
            vmImageReferenceId = ''
            vmImageSharedGalleryImageId = ''
            vmImageCommunityGalleryImageId = ''
            vmImagePublisher = ''
            vmImageOffer = ''
            vmImageSku = ''
            vmImageVersion = ''
            vmOsDiskName = ''
            vmOsDiskOsType = 'Linux'
            vmOsDiskCaching = ''
            vmOsDiskCreateOption = ''
            vmOsDiskManagedDiskId = ''
            vmOsDiskStorageAccountType = ''
            vmOsDiskSizeGB = $null
            vmNetworkInterfaces = @()
            vmDataDisks = @(
                [pscustomobject]@{
                    name = 'unsafe-source'
                    lun = 2
                    caching = 'None'
                    createOption = 'Attach'
                    diskSizeGB = 32
                    vhd = [pscustomobject]@{ uri = 'https://storage.example.test/private.vhd' }
                    image = [pscustomobject]@{ uri = 'https://storage.example.test/image.vhd' }
                    managedDisk = [pscustomobject]@{
                        id = '/subscriptions/sub/resourceGroups/RG-Compute/providers/Microsoft.Compute/disks/safe-id'
                        storageAccountType = 'StandardSSD_LRS'
                        diskEncryptionSet = [pscustomobject]@{ id = '/subscriptions/sub/resourceGroups/RG-Security/providers/Microsoft.Compute/diskEncryptionSets/des01' }
                    }
                }
            )
        }

        $result = ConvertTo-CollectorComputeInventory -Rows @($row)
        $dataDisk = $result.virtualMachines[0].dataDisks[0]

        @($dataDisk.PSObject.Properties.Name) | Should -Not -Contain 'vhd'
        @($dataDisk.PSObject.Properties.Name) | Should -Not -Contain 'image'
        @($dataDisk.PSObject.Properties.Name) | Should -Not -Contain 'diskEncryptionSet'
        ($result | ConvertTo-Json -Depth 20) | Should -Not -Match 'private\.vhd|image\.vhd|diskEncryptionSets/des01'
    }
}

Describe 'P4 Managed Disk normalization' {
    It 'normalizes disk SKU, tier, size, state and managed-by relationship' {
        $diskId = '/subscriptions/sub/resourceGroups/RG-Compute/providers/Microsoft.Compute/disks/data01'
        $vmId = '/subscriptions/sub/resourceGroups/RG-Compute/providers/Microsoft.Compute/virtualMachines/vm01'

        $row = [pscustomobject]@{
            id = $diskId
            name = 'data01'
            type = 'microsoft.compute/disks'
            subscriptionId = 'sub'
            resourceGroup = 'RG-Compute'
            location = 'westeurope'
            tags = $null
            zones = @('1')
            skuName = 'Premium_LRS'
            skuTier = 'Premium'
            diskTier = 'P20'
            diskManagedBy = $vmId
            diskSizeGB = 512
            diskOsType = ''
            diskState = 'Attached'
            diskCreateOption = 'Empty'
        }

        $result = ConvertTo-CollectorComputeInventory -Rows @($row)

        $result.summary.managedDisks | Should -Be 1
        $result.managedDisks[0].skuName | Should -BeExactly 'Premium_LRS'
        $result.managedDisks[0].performanceTier | Should -BeExactly 'P20'
        $result.managedDisks[0].diskSizeGB | Should -Be 512
        $result.managedDisks[0].diskState | Should -BeExactly 'Attached'
        $result.managedDisks[0].managedByResourceId | Should -Be $vmId
        @($result.relationships | Where-Object { $_.sourceId -eq $diskId -and $_.relationship -eq 'ManagedByResource' -and $_.targetId -eq $vmId }).Count | Should -Be 1
    }
}

Describe 'P4 Availability Set normalization' {
    It 'normalizes fault/update domains and VM membership' {
        $availabilitySetId = '/subscriptions/sub/resourceGroups/RG-Compute/providers/Microsoft.Compute/availabilitySets/as01'
        $vmId = '/subscriptions/sub/resourceGroups/RG-Compute/providers/Microsoft.Compute/virtualMachines/vm01'
        $ppgId = '/subscriptions/sub/resourceGroups/RG-Compute/providers/Microsoft.Compute/proximityPlacementGroups/ppg01'

        $row = [pscustomobject]@{
            id = $availabilitySetId
            name = 'as01'
            type = 'microsoft.compute/availabilitysets'
            subscriptionId = 'sub'
            resourceGroup = 'RG-Compute'
            location = 'westeurope'
            tags = $null
            zones = @()
            skuName = 'Aligned'
            skuTier = ''
            availabilitySetFaultDomainCount = 3
            availabilitySetUpdateDomainCount = 5
            availabilitySetVirtualMachines = @([pscustomobject]@{ id = $vmId })
            availabilitySetProximityPlacementGroupId = $ppgId
        }

        $result = ConvertTo-CollectorComputeInventory -Rows @($row)

        $result.summary.availabilitySets | Should -Be 1
        $result.availabilitySets[0].platformFaultDomainCount | Should -Be 3
        $result.availabilitySets[0].platformUpdateDomainCount | Should -Be 5
        $result.availabilitySets[0].virtualMachineIds | Should -Contain $vmId
        @($result.relationships | Where-Object { $_.sourceId -eq $availabilitySetId -and $_.relationship -eq 'ContainsVm' -and $_.targetId -eq $vmId }).Count | Should -Be 1
        @($result.relationships | Where-Object { $_.sourceId -eq $availabilitySetId -and $_.relationship -eq 'UsesProximityPlacementGroup' -and $_.targetId -eq $ppgId }).Count | Should -Be 1
    }
}

Describe 'P4 Compute empty collection stability' {
    It 'keeps all top-level compute collections as arrays when no resources exist' {
        $result = ConvertTo-CollectorComputeInventory -Rows @()

        $result.summary.virtualMachines | Should -Be 0
        $result.summary.managedDisks | Should -Be 0
        $result.summary.availabilitySets | Should -Be 0
        $result.summary.relationships | Should -Be 0
        $result.virtualMachines.GetType().IsArray | Should -BeTrue
        $result.managedDisks.GetType().IsArray | Should -BeTrue
        $result.availabilitySets.GetType().IsArray | Should -BeTrue
        $result.relationships.GetType().IsArray | Should -BeTrue
    }
}
