Set-StrictMode -Version Latest

function Test-CollectorSensitiveScalarValue {
    [CmdletBinding()]
    param(
        $Value,

        [string[]]$SensitiveValuePatterns = @()
    )

    if ($Value -isnot [string] -or [string]::IsNullOrEmpty([string]$Value)) {
        return $false
    }

    foreach ($pattern in @($SensitiveValuePatterns)) {
        if (-not [string]::IsNullOrWhiteSpace($pattern) -and [string]$Value -match $pattern) {
            return $true
        }
    }

    return $false
}

function Protect-CollectorExportValue {
    [CmdletBinding()]
    param(
        $Value,

        [Parameter(Mandatory)]
        [string]$SensitivePropertyPattern,

        [string[]]$SensitiveValuePatterns = @()
    )

    if ($null -eq $Value) {
        return $null
    }

    # Scalars must be handled before PSCustomObject/ETS property inspection. Without
    # this ordering PowerShell can expose scalar adapter properties (for example the
    # Length property of a string) and the exported value loses its actual content.
    if ($Value -is [string]) {
        if (Test-CollectorSensitiveScalarValue -Value $Value -SensitiveValuePatterns $SensitiveValuePatterns) {
            return '[REDACTED]'
        }

        return [string]$Value
    }

    $baseObject = $Value.PSObject.BaseObject
    if ($null -ne $baseObject -and $baseObject.GetType().IsValueType) {
        return $baseObject
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $sanitized = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object)) {
            if ([string]$key -match $SensitivePropertyPattern) {
                $sanitized[[string]$key] = '[REDACTED]'
            }
            else {
                $sanitized[[string]$key] = Protect-CollectorExportValue `
                    -Value $Value[$key] `
                    -SensitivePropertyPattern $SensitivePropertyPattern `
                    -SensitiveValuePatterns $SensitiveValuePatterns
            }
        }
        return $sanitized
    }

    # Enumerables must be handled before PSCustomObject inspection as arrays/lists can
    # otherwise be serialized through their adapter metadata (Count/Length/SyncRoot).
    # Accidental nested enumerable wrappers are flattened because the collector JSON
    # schema uses arrays of scalar values or objects, not arrays-of-arrays.
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $sanitizedItems = [System.Collections.Generic.List[object]]::new()

        foreach ($item in $Value) {
            $sanitizedItem = Protect-CollectorExportValue `
                -Value $item `
                -SensitivePropertyPattern $SensitivePropertyPattern `
                -SensitiveValuePatterns $SensitiveValuePatterns

            $itemIsNestedEnumerable = (
                $null -ne $item -and
                $item -is [System.Collections.IEnumerable] -and
                $item -isnot [string] -and
                $item -isnot [System.Collections.IDictionary]
            )

            if ($itemIsNestedEnumerable) {
                foreach ($nestedItem in @($sanitizedItem)) {
                    $sanitizedItems.Add($nestedItem)
                }
            }
            else {
                $sanitizedItems.Add($sanitizedItem)
            }
        }

        # Return the array as one pipeline object so empty arrays remain [] instead of
        # disappearing and becoming $null in a parent property assignment.
        return ,@($sanitizedItems)
    }

    if ($Value -is [pscustomobject]) {
        $sanitized = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
            if ($property.Name -match $SensitivePropertyPattern) {
                $sanitized[$property.Name] = '[REDACTED]'
            }
            else {
                $sanitized[$property.Name] = Protect-CollectorExportValue `
                    -Value $property.Value `
                    -SensitivePropertyPattern $SensitivePropertyPattern `
                    -SensitiveValuePatterns $SensitiveValuePatterns
            }
        }
        return [pscustomobject]$sanitized
    }

    if (Test-CollectorSensitiveScalarValue -Value $Value -SensitiveValuePatterns $SensitiveValuePatterns) {
        return '[REDACTED]'
    }

    return $Value
}

function Resolve-CollectorResourceGroupReferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Resources,

        [Parameter(Mandatory)]
        [object[]]$ResourceGroups
    )

    $canonicalNames = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($resourceGroup in @($ResourceGroups)) {
        $subscriptionId = [string]$resourceGroup.subscriptionId
        $name = [string]$resourceGroup.name
        if ([string]::IsNullOrWhiteSpace($subscriptionId) -or [string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $key = '{0}|{1}' -f $subscriptionId, $name
        $canonicalNames[$key] = $name
    }

    return @(
        foreach ($resource in @($Resources)) {
            $copy = [ordered]@{}
            foreach ($property in @($resource.PSObject.Properties)) {
                $copy[$property.Name] = $property.Value
            }

            if ($copy.Contains('resourceGroup')) {
                $subscriptionId = [string]$copy['subscriptionId']
                $resourceGroupName = [string]$copy['resourceGroup']
                if (-not [string]::IsNullOrWhiteSpace($subscriptionId) -and -not [string]::IsNullOrWhiteSpace($resourceGroupName)) {
                    $key = '{0}|{1}' -f $subscriptionId, $resourceGroupName
                    if ($canonicalNames.ContainsKey($key)) {
                        $copy['resourceGroup'] = $canonicalNames[$key]
                    }
                }
            }

            [pscustomobject]$copy
        }
    )
}

function New-CollectorPublicReadOnlyVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Verification
    )

    [pscustomobject][ordered]@{
        status                     = [string]$Verification.status
        verified                   = [bool]$Verification.verified
        verifiedAt                 = [string]$Verification.verifiedAt
        filesScanned               = [int]$Verification.filesScanned
        approvedAzureCommandsFound = @($Verification.approvedAzureCommandsFound)
        azureResourceMutations     = [string]$Verification.azureResourceMutations
        azureDataMutations         = [string]$Verification.azureDataMutations
        controlPlaneWrites         = [string]$Verification.controlPlaneWrites
        dataPlaneWrites            = [string]$Verification.dataPlaneWrites
        localWrites                = [string]$Verification.localWrites
        violations                 = @($Verification.violations)
    }
}

function New-CollectorPublicManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Manifest
    )

    $publicManifest = [ordered]@{}
    foreach ($property in @($Manifest.PSObject.Properties)) {
        if ($property.Name -ne 'execution') {
            $publicManifest[$property.Name] = $property.Value
            continue
        }

        $execution = [ordered]@{}
        foreach ($executionProperty in @($property.Value.PSObject.Properties)) {
            if ($executionProperty.Name -ne 'account') {
                $execution[$executionProperty.Name] = $executionProperty.Value
            }
        }
        $publicManifest['execution'] = [pscustomobject]$execution
    }

    return [pscustomobject]$publicManifest
}

Export-ModuleMember -Function @(
    'Test-CollectorSensitiveScalarValue',
    'Protect-CollectorExportValue',
    'Resolve-CollectorResourceGroupReferences',
    'New-CollectorPublicReadOnlyVerification',
    'New-CollectorPublicManifest'
)
