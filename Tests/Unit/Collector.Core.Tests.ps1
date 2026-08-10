BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.Core.psm1') -Force
}

Describe 'ConvertTo-CollectorSafeName' {
    It 'replaces whitespace and invalid filename characters' {
        $result = ConvertTo-CollectorSafeName -Value 'Kunde A/B'
        $result | Should -Not -Match '\s'
        $result | Should -Not -Match '/'
    }
}

Describe 'Protect-CollectorValue' {
    It 'redacts sensitive dictionary keys recursively' {
        $inputValue = [ordered]@{
            Environment = 'Production'
            ClientSecret = 'do-not-export'
            Nested = [ordered]@{
                ApiToken = 'also-secret'
                Owner = 'Operations'
            }
        }

        $result = Protect-CollectorValue -Value $inputValue

        $result.Environment | Should -Be 'Production'
        $result.ClientSecret | Should -Be '[REDACTED]'
        $result.Nested.ApiToken | Should -Be '[REDACTED]'
        $result.Nested.Owner | Should -Be 'Operations'
    }
}

Describe 'ConvertTo-CollectorResource' {
    It 'creates the stable core resource shape' {
        $inputValue = [pscustomobject]@{
            id = '/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm01'
            name = 'vm01'
            type = 'microsoft.compute/virtualmachines'
            subscriptionId = 'sub'
            resourceGroup = 'rg'
            location = 'germanywestcentral'
            tags = [ordered]@{ Environment = 'Production' }
        }

        $result = ConvertTo-CollectorResource -InputObject $inputValue

        $result.name | Should -Be 'vm01'
        $result.subscriptionId | Should -Be 'sub'
        $result.resourceGroup | Should -Be 'rg'
        $result.tags.Environment | Should -Be 'Production'
        @($result.PSObject.Properties.Name) | Should -Be @('id', 'name', 'type', 'subscriptionId', 'resourceGroup', 'location', 'tags')
    }
}
