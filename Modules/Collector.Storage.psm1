Set-StrictMode -Version Latest

function Get-CollectorStorageProperty {
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

function ConvertTo-CollectorStorageVirtualNetworkRules {
    [CmdletBinding()]
    param($Value)

    @(
        foreach ($rule in @($Value)) {
            if ($null -eq $rule) { continue }
            $id = [string](Get-CollectorStorageProperty -InputObject $rule -Name 'id')
            if (-not [string]::IsNullOrWhiteSpace($id)) { $id }
        }
    ) | Sort-Object -Unique
}

function ConvertTo-CollectorStorageIpRules {
    [CmdletBinding()]
    param($Value)

    @(
        foreach ($rule in @($Value)) {
            if ($null -eq $rule) { continue }
            $ip = [string](Get-CollectorStorageProperty -InputObject $rule -Name 'value')
            if (-not [string]::IsNullOrWhiteSpace($ip)) { $ip }
        }
    ) | Sort-Object -Unique
}

function ConvertTo-CollectorStorageInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $accounts = [System.Collections.Generic.List[object]]::new()
    $relationships = [System.Collections.Generic.List[object]]::new()
    $subnetReferences = 0

    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        if (([string](Get-CollectorStorageProperty -InputObject $row -Name 'type')).ToLowerInvariant() -ne 'microsoft.storage/storageaccounts') { continue }

        $id = [string](Get-CollectorStorageProperty -InputObject $row -Name 'id')
        $virtualNetworkRules = @(ConvertTo-CollectorStorageVirtualNetworkRules (Get-CollectorStorageProperty -InputObject $row -Name 'networkVirtualNetworkRules'))
        $ipRules = @(ConvertTo-CollectorStorageIpRules (Get-CollectorStorageProperty -InputObject $row -Name 'networkIpRules'))

        foreach ($subnetId in $virtualNetworkRules) {
            $subnetReferences++
            $relationships.Add([pscustomobject][ordered]@{
                sourceId = $id
                relationship = 'AllowsSubnet'
                targetId = [string]$subnetId
            })
        }

        $accounts.Add([pscustomobject][ordered]@{
            id                           = $id
            name                         = [string](Get-CollectorStorageProperty -InputObject $row -Name 'name')
            subscriptionId               = [string](Get-CollectorStorageProperty -InputObject $row -Name 'subscriptionId')
            resourceGroup                = [string](Get-CollectorStorageProperty -InputObject $row -Name 'resourceGroup')
            location                     = [string](Get-CollectorStorageProperty -InputObject $row -Name 'location')
            kind                         = [string](Get-CollectorStorageProperty -InputObject $row -Name 'kind')
            skuName                      = [string](Get-CollectorStorageProperty -InputObject $row -Name 'skuName')
            skuTier                      = [string](Get-CollectorStorageProperty -InputObject $row -Name 'skuTier')
            accessTier                   = [string](Get-CollectorStorageProperty -InputObject $row -Name 'accessTier')
            allowBlobPublicAccess        = Get-CollectorStorageProperty -InputObject $row -Name 'allowBlobPublicAccess'
            allowSharedKeyAccess         = Get-CollectorStorageProperty -InputObject $row -Name 'allowSharedKeyAccess'
            defaultToOAuthAuthentication = Get-CollectorStorageProperty -InputObject $row -Name 'defaultToOAuthAuthentication'
            isHnsEnabled                 = Get-CollectorStorageProperty -InputObject $row -Name 'isHnsEnabled'
            isNfsV3Enabled               = Get-CollectorStorageProperty -InputObject $row -Name 'isNfsV3Enabled'
            isSftpEnabled                = Get-CollectorStorageProperty -InputObject $row -Name 'isSftpEnabled'
            isLocalUserEnabled           = Get-CollectorStorageProperty -InputObject $row -Name 'isLocalUserEnabled'
            minimumTlsVersion            = [string](Get-CollectorStorageProperty -InputObject $row -Name 'minimumTlsVersion')
            publicNetworkAccess          = [string](Get-CollectorStorageProperty -InputObject $row -Name 'publicNetworkAccess')
            supportsHttpsTrafficOnly     = Get-CollectorStorageProperty -InputObject $row -Name 'supportsHttpsTrafficOnly'
            largeFileSharesState         = [string](Get-CollectorStorageProperty -InputObject $row -Name 'largeFileSharesState')
            networkAcls                  = [pscustomobject][ordered]@{
                defaultAction       = [string](Get-CollectorStorageProperty -InputObject $row -Name 'networkDefaultAction')
                bypass              = [string](Get-CollectorStorageProperty -InputObject $row -Name 'networkBypass')
                virtualNetworkRules = $virtualNetworkRules
                ipRules             = $ipRules
            }
            tags                         = Get-CollectorStorageProperty -InputObject $row -Name 'tags'
        })
    }

    $sortedRelationships = @($relationships | Sort-Object sourceId, relationship, targetId -Unique)

    [pscustomobject][ordered]@{
        schemaVersion = '1.0'
        summary = [pscustomobject][ordered]@{
            storageAccounts                 = $accounts.Count
            sharedKeyDisabledAccounts       = @($accounts | Where-Object { $_.allowSharedKeyAccess -eq $false }).Count
            blobPublicAccessDisabledAccounts = @($accounts | Where-Object { $_.allowBlobPublicAccess -eq $false }).Count
            httpsOnlyAccounts               = @($accounts | Where-Object { $_.supportsHttpsTrafficOnly -eq $true }).Count
            publicNetworkDisabledAccounts   = @($accounts | Where-Object { $_.publicNetworkAccess -eq 'Disabled' }).Count
            subnetReferences                = $subnetReferences
            relationships                   = $sortedRelationships.Count
        }
        storageAccounts = @($accounts | Sort-Object subscriptionId, resourceGroup, name, id)
        relationships   = $sortedRelationships
    }
}

Export-ModuleMember -Function 'ConvertTo-CollectorStorageInventory'
