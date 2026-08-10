BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.ExportSecurity.psm1') -Force
}

Describe 'Protect-CollectorExportValue' {
    BeforeEach {
        $propertyPattern = '(?i)(secret|password|passwd|token|credential|connectionstring|connection_string|sastoken|accesskey|accountkey|privatekey|clientsecret|apikey)'
        $valuePatterns = @(
            '(?i)(?:^|[?&])sig=[^&\s]+(?:&|$)',
            '(?i)(?:AccountKey|SharedAccessSignature)\s*=\s*[^;\s]+',
            '(?i)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
            '(?i)\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b',
            '(?i)\b(?:password|passwd|clientsecret|api[_-]?key|access[_-]?key|sas[_-]?token)\s*[:=]\s*[^\s;,]+'
        )
    }

    It 'redacts a sensitive property name' {
        $result = Protect-CollectorExportValue `
            -Value ([ordered]@{ ClientSecret = 'do-not-export'; Environment = 'Production' }) `
            -SensitivePropertyPattern $propertyPattern `
            -SensitiveValuePatterns $valuePatterns

        $result.ClientSecret | Should -Be '[REDACTED]'
        $result.Environment | Should -Be 'Production'
    }

    It 'redacts a SAS signature even under an innocent property name' {
        $result = Protect-CollectorExportValue `
            -Value ([ordered]@{ Comment = 'https://example.blob.core.windows.net/container/file?sv=2026-01-01&sig=TopSecretSignature&se=2026-12-31' }) `
            -SensitivePropertyPattern $propertyPattern `
            -SensitiveValuePatterns $valuePatterns

        $result.Comment | Should -Be '[REDACTED]'
    }

    It 'redacts a storage account key in a connection string value' {
        $result = Protect-CollectorExportValue `
            -Value ([ordered]@{ Note = 'DefaultEndpointsProtocol=https;AccountName=demo;AccountKey=abc123;EndpointSuffix=core.windows.net' }) `
            -SensitivePropertyPattern $propertyPattern `
            -SensitiveValuePatterns $valuePatterns

        $result.Note | Should -Be '[REDACTED]'
    }

    It 'does not redact an ordinary HTTPS URL' {
        $url = 'https://management.azure.com/subscriptions/example/resourceGroups/rg'
        $result = Protect-CollectorExportValue `
            -Value ([ordered]@{ Documentation = $url }) `
            -SensitivePropertyPattern $propertyPattern `
            -SensitiveValuePatterns $valuePatterns

        $result.Documentation | Should -Be $url
    }
}

Describe 'Resolve-CollectorResourceGroupReferences' {
    It 'uses canonical Resource Group casing from the matching subscription' {
        $resourceGroups = @(
            [pscustomobject]@{ subscriptionId = 'sub-a'; name = 'NetworkWatcherRG' },
            [pscustomobject]@{ subscriptionId = 'sub-b'; name = 'networkwatcherrg' }
        )
        $resources = @(
            [pscustomobject][ordered]@{
                id = '/subscriptions/sub-a/resourceGroups/networkwatcherrg/providers/Microsoft.Network/networkWatchers/watcher'
                name = 'watcher'
                type = 'microsoft.network/networkwatchers'
                subscriptionId = 'sub-a'
                resourceGroup = 'networkwatcherrg'
                location = 'westeurope'
                tags = [ordered]@{}
            }
        )

        $result = @(Resolve-CollectorResourceGroupReferences -Resources $resources -ResourceGroups $resourceGroups)

        $result.Count | Should -Be 1
        $result[0].resourceGroup | Should -BeExactly 'NetworkWatcherRG'
    }
}

Describe 'New-CollectorPublicReadOnlyVerification' {
    It 'removes the local repository path from the exported verification object' {
        $verification = [pscustomobject][ordered]@{
            status = 'READ-ONLY VERIFIED'
            verified = $true
            verifiedAt = '2026-08-10T10:00:00+02:00'
            repositoryRoot = 'C:\Users\Operator\Private\Repository'
            filesScanned = 10
            approvedAzureCommandsFound = @('Search-AzGraph')
            azureResourceMutations = 'NONE DETECTED'
            azureDataMutations = 'NONE DETECTED'
            controlPlaneWrites = 'NONE DETECTED'
            dataPlaneWrites = 'NONE DETECTED'
            localWrites = 'approved local writes only'
            violations = @()
        }

        $result = New-CollectorPublicReadOnlyVerification -Verification $verification

        @($result.PSObject.Properties.Name) | Should -Not -Contain 'repositoryRoot'
        $result.status | Should -Be 'READ-ONLY VERIFIED'
    }
}

Describe 'New-CollectorPublicManifest' {
    It 'removes the executing account while retaining execution status and timestamps' {
        $manifest = [pscustomobject][ordered]@{
            schemaVersion = '1.0'
            execution = [pscustomobject][ordered]@{
                startedAt = '2026-08-10T10:00:00+02:00'
                completedAt = '2026-08-10T10:00:03+02:00'
                account = 'admin@example.com'
                status = 'Success'
            }
            tenant = [pscustomobject]@{ id = 'tenant'; displayName = 'Tenant' }
        }

        $result = New-CollectorPublicManifest -Manifest $manifest

        @($result.execution.PSObject.Properties.Name) | Should -Not -Contain 'account'
        $result.execution.status | Should -Be 'Success'
        $result.execution.startedAt | Should -Be '2026-08-10T10:00:00+02:00'
    }
}
