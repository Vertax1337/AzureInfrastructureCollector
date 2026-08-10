BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.ExportSecurity.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.Network.psm1') -Force

    $script:PropertyPattern = '(?i)(secret|password|passwd|token|credential|connectionstring|connection_string|sastoken|accesskey|accountkey|privatekey|clientsecret|apikey)'
    $script:ValuePatterns = @(
        '(?i)(?:^|[?&])sig=[^&\s]+(?:&|$)',
        '(?i)(?:AccountKey|SharedAccessSignature)\s*=\s*[^;\s]+',
        '(?i)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        '(?i)\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b',
        '(?i)\b(?:password|passwd|clientsecret|api[_-]?key|access[_-]?key|sas[_-]?token)\s*[:=]\s*[^\s;,]+'
    )
}

Describe 'Export shape regression protection' {
    It 'preserves string arrays as strings instead of ETS Length objects' {
        $inputObject = [ordered]@{
            addressPrefixes = @('10.0.0.0/16', '10.1.0.0/16')
            dnsServers = @('10.0.0.4', '10.0.0.5')
        }

        $result = Protect-CollectorExportValue `
            -Value $inputObject `
            -SensitivePropertyPattern $script:PropertyPattern `
            -SensitiveValuePatterns $script:ValuePatterns

        ($result.addressPrefixes -is [System.Array]) | Should -BeTrue
        @($result.addressPrefixes).Count | Should -Be 2
        $result.addressPrefixes[0] | Should -BeExactly '10.0.0.0/16'
        $result.addressPrefixes[1] | Should -BeExactly '10.1.0.0/16'
        $result.dnsServers[0] | Should -BeExactly '10.0.0.4'
        ($result.addressPrefixes[0] -is [string]) | Should -BeTrue
    }

    It 'flattens accidental nested enumerable wrappers without array metadata leakage' {
        $nestedValues = [System.Collections.Generic.List[object]]::new()
        $nestedValues.Add([object[]]@())
        $nestedValues.Add([object[]]@('10.0.0.0/16'))
        $nestedValues.Add('10.1.0.0/16')

        $result = Protect-CollectorExportValue `
            -Value ([ordered]@{ prefixes = $nestedValues }) `
            -SensitivePropertyPattern $script:PropertyPattern `
            -SensitiveValuePatterns $script:ValuePatterns

        ($result.prefixes -is [System.Array]) | Should -BeTrue
        @($result.prefixes).Count | Should -Be 2
        $result.prefixes[0] | Should -BeExactly '10.0.0.0/16'
        $result.prefixes[1] | Should -BeExactly '10.1.0.0/16'
        @($result.prefixes | Where-Object { $_ -isnot [string] }).Count | Should -Be 0
    }

    It 'keeps hardened network address fields as stable one-dimensional string arrays' {
        $vnetId = '/subscriptions/sub/resourceGroups/RG-Network/providers/Microsoft.Network/virtualNetworks/vnet01'
        $subnetId = "$vnetId/subnets/default"
        $row = [pscustomobject]@{
            id = $vnetId
            name = 'vnet01'
            type = 'microsoft.network/virtualnetworks'
            subscriptionId = 'sub'
            resourceGroup = 'RG-Network'
            location = 'westeurope'
            tags = $null
            vnetAddressPrefixes = @('10.0.0.0/16')
            vnetDnsServers = @('10.0.0.4')
            vnetEnableDdosProtection = $false
            vnetDdosProtectionPlanId = ''
            vnetPeerings = @()
            vnetSubnets = @(
                [pscustomobject]@{
                    id = $subnetId
                    name = 'default'
                    properties = [pscustomobject]@{
                        addressPrefix = '10.0.1.0/24'
                        addressPrefixes = @()
                        networkSecurityGroup = $null
                        routeTable = $null
                        natGateway = $null
                        privateEndpointNetworkPolicies = 'Disabled'
                        privateLinkServiceNetworkPolicies = 'Enabled'
                        serviceEndpoints = @([pscustomobject]@{ service = 'Microsoft.Storage' })
                        delegations = @()
                    }
                }
            )
        }

        $inventory = ConvertTo-CollectorNetworkInventory -Rows @($row)
        $result = Protect-CollectorExportValue `
            -Value $inventory `
            -SensitivePropertyPattern $script:PropertyPattern `
            -SensitiveValuePatterns $script:ValuePatterns

        @($result.virtualNetworks[0].addressPrefixes).Count | Should -Be 1
        $result.virtualNetworks[0].addressPrefixes[0] | Should -BeExactly '10.0.0.0/16'
        $result.virtualNetworks[0].dnsServers[0] | Should -BeExactly '10.0.0.4'
        @($result.subnets[0].addressPrefixes).Count | Should -Be 1
        $result.subnets[0].addressPrefixes[0] | Should -BeExactly '10.0.1.0/24'
        @($result.subnets[0].serviceEndpoints).Count | Should -Be 1
        $result.subnets[0].serviceEndpoints[0] | Should -BeExactly 'Microsoft.Storage'
    }
}
