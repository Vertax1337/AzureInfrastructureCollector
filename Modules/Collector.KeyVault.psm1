Set-StrictMode -Version Latest

function Get-CollectorKeyVaultProperty {
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

function ConvertTo-CollectorKeyVaultVirtualNetworkRules {
    [CmdletBinding()]
    param($Value)

    @(
        foreach ($rule in @($Value)) {
            if ($null -eq $rule) { continue }
            $id = [string](Get-CollectorKeyVaultProperty -InputObject $rule -Name 'id')
            if (-not [string]::IsNullOrWhiteSpace($id)) { $id }
        }
    ) | Sort-Object -Unique
}

function ConvertTo-CollectorKeyVaultIpRules {
    [CmdletBinding()]
    param($Value)

    @(
        foreach ($rule in @($Value)) {
            if ($null -eq $rule) { continue }
            $ip = [string](Get-CollectorKeyVaultProperty -InputObject $rule -Name 'value')
            if (-not [string]::IsNullOrWhiteSpace($ip)) { $ip }
        }
    ) | Sort-Object -Unique
}

function ConvertTo-CollectorKeyVaultInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $vaults = [System.Collections.Generic.List[object]]::new()
    $relationships = [System.Collections.Generic.List[object]]::new()
    $subnetReferences = 0

    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        if (([string](Get-CollectorKeyVaultProperty -InputObject $row -Name 'type')).ToLowerInvariant() -ne 'microsoft.keyvault/vaults') { continue }

        $id = [string](Get-CollectorKeyVaultProperty -InputObject $row -Name 'id')
        $virtualNetworkRules = @(ConvertTo-CollectorKeyVaultVirtualNetworkRules (Get-CollectorKeyVaultProperty -InputObject $row -Name 'networkVirtualNetworkRules'))
        $ipRules = @(ConvertTo-CollectorKeyVaultIpRules (Get-CollectorKeyVaultProperty -InputObject $row -Name 'networkIpRules'))
        $enableRbacAuthorization = Get-CollectorKeyVaultProperty -InputObject $row -Name 'enableRbacAuthorization'

        foreach ($subnetId in $virtualNetworkRules) {
            $subnetReferences++
            $relationships.Add([pscustomobject][ordered]@{
                sourceId = $id
                relationship = 'AllowsSubnet'
                targetId = [string]$subnetId
            })
        }

        $vaults.Add([pscustomobject][ordered]@{
            id                           = $id
            name                         = [string](Get-CollectorKeyVaultProperty -InputObject $row -Name 'name')
            subscriptionId               = [string](Get-CollectorKeyVaultProperty -InputObject $row -Name 'subscriptionId')
            resourceGroup                = [string](Get-CollectorKeyVaultProperty -InputObject $row -Name 'resourceGroup')
            location                     = [string](Get-CollectorKeyVaultProperty -InputObject $row -Name 'location')
            skuName                      = [string](Get-CollectorKeyVaultProperty -InputObject $row -Name 'skuName')
            skuFamily                    = [string](Get-CollectorKeyVaultProperty -InputObject $row -Name 'skuFamily')
            authorizationModel           = if ($enableRbacAuthorization -eq $true) { 'RBAC' } elseif ($enableRbacAuthorization -eq $false) { 'AccessPolicy' } else { '' }
            enableRbacAuthorization      = $enableRbacAuthorization
            enableSoftDelete             = Get-CollectorKeyVaultProperty -InputObject $row -Name 'enableSoftDelete'
            enablePurgeProtection        = Get-CollectorKeyVaultProperty -InputObject $row -Name 'enablePurgeProtection'
            softDeleteRetentionInDays    = Get-CollectorKeyVaultProperty -InputObject $row -Name 'softDeleteRetentionInDays'
            publicNetworkAccess          = [string](Get-CollectorKeyVaultProperty -InputObject $row -Name 'publicNetworkAccess')
            enabledForDeployment         = Get-CollectorKeyVaultProperty -InputObject $row -Name 'enabledForDeployment'
            enabledForDiskEncryption     = Get-CollectorKeyVaultProperty -InputObject $row -Name 'enabledForDiskEncryption'
            enabledForTemplateDeployment = Get-CollectorKeyVaultProperty -InputObject $row -Name 'enabledForTemplateDeployment'
            networkAcls                  = [pscustomobject][ordered]@{
                defaultAction       = [string](Get-CollectorKeyVaultProperty -InputObject $row -Name 'networkDefaultAction')
                bypass              = [string](Get-CollectorKeyVaultProperty -InputObject $row -Name 'networkBypass')
                virtualNetworkRules = $virtualNetworkRules
                ipRules             = $ipRules
            }
            tags                         = Get-CollectorKeyVaultProperty -InputObject $row -Name 'tags'
        })
    }

    $sortedRelationships = @($relationships | Sort-Object sourceId, relationship, targetId -Unique)

    [pscustomobject][ordered]@{
        schemaVersion = '1.0'
        summary = [pscustomobject][ordered]@{
            keyVaults                         = $vaults.Count
            rbacAuthorizedVaults              = @($vaults | Where-Object { $_.enableRbacAuthorization -eq $true }).Count
            purgeProtectionEnabledVaults      = @($vaults | Where-Object { $_.enablePurgeProtection -eq $true }).Count
            publicNetworkDisabledVaults       = @($vaults | Where-Object { $_.publicNetworkAccess -eq 'Disabled' }).Count
            subnetReferences                  = $subnetReferences
            relationships                     = $sortedRelationships.Count
        }
        keyVaults     = @($vaults | Sort-Object subscriptionId, resourceGroup, name, id)
        relationships = $sortedRelationships
    }
}

Export-ModuleMember -Function 'ConvertTo-CollectorKeyVaultInventory'
