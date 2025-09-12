Import-Module "$PSScriptRoot/../PowerBicep.psm1" -Force

Describe 'New-PBSpokeVirtualNetwork' {

    It 'Throws on various invalid AddressPrefix formats and ranges' {
        $invalidPrefixes = @(
            '256.0.0.0/24',
            '172.256.0.0/24',
            '172.16.256.0/24',
            '172.16.0.256/24',
            '172.16.0.0/0',
            '172.16.0.0/1',
            '172.16.0.0/30',
            '172.16.0.0/31',
            '172.16.0.0/32'
        )
        foreach ($prefix in $invalidPrefixes) {
            { New-PBSpokeVirtualNetwork -ApplicationNameShort 'test' -Environment 'dev' -Location 'westeurope' -AddressPrefix $prefix -Subnets @{snet1=25; snet2=26; snet3=26} } | Should -Throw
        }
    }

    It 'Throws on invalid Azure region' {
        $invalidRegions = @(
            'westeu',
            'west europe',
            ' ',
            ' westeurope',
            'westeurope '
        )
        foreach ($region in $invalidRegions) {
            { New-PBHubVirtualNetwork -Environment 'dev' -Location $region -AddressPrefix '10.0.0.0/24' -AcceptOverlappingIpAddresses } | Should -Throw
        }
    }

    it 'Throws on missing mandatory parameter' {
        $mandatoryParams = @('ApplicationNameShort', 'Environment', 'Location', 'AddressPrefix', 'Subnets')

        $params = @{
                ApplicationNameShort = 'test'
                Environment = 'dev'
                Location = 'westeurope'
                AddressPrefix = '10.0.0.0/24'
                Subnets = @{snet1=25}
                AcceptOverlappingIpAddresses = $true
        }

        foreach ($param in $mandatoryParams.GetEnumerator()) {
            $params.Remove($param)
            { New-PBSpokeVirtualNetwork @params } | Should -Throw
        }
    }

        it 'Throws on missing overlapping IP Ranges' {
        $invalidPrefixes = @(
            '192.168.1.0/24' # Has to be adjusted based on actual overlapping ranges in the target environment
        )
        foreach ($prefix in $invalidPrefixes) {
            { New-PBSpokeVirtualNetwork -ApplicationNameShort 'test' -Environment 'dev' -Location 'westeurope' -AddressPrefix $prefix -Subnets @{snet1=25; snet2=26; snet3=26} } | Should -Throw
        }
    }
}

Describe 'New-PBHubVirtualNetwork' {

    It 'Throws on various invalid AddressPrefix formats and ranges' {
        $invalidPrefixes = @(
            '256.0.0.0/24',
            '172.256.0.0/24',
            '172.16.256.0/24',
            '172.16.0.256/24',
            '172.16.0.0/0',
            '172.16.0.0/1',
            '172.16.0.0/30',
            '172.16.0.0/31',
            '172.16.0.0/32'
        )
        foreach ($prefix in $invalidPrefixes) {
            { New-PBHubVirtualNetwork -Environment 'dev' -Location 'westeurope' -AddressPrefix $prefix } | Should -Throw
        }
    }

    It 'Throws on invalid Environment' {
        $invalidEnvironments = @(
            'testing',
            'production',
            'development',
            ' test',
            'dev ',
            ' prod '
        )
        foreach ($env in $invalidEnvironments) {
            { New-PBHubVirtualNetwork -Environment $env -Location 'westeurope' -AddressPrefix '10.0.0.0/24' -AcceptOverlappingIpAddresses } | Should -Throw
        }
    }

    It 'Throws on invalid Azure region' {
        $invalidRegions = @(
            'westeu',
            'west europe',
            ' ',
            ' westeurope',
            'westeurope '
        )
        foreach ($region in $invalidRegions) {
            { New-PBHubVirtualNetwork -Environment 'dev' -Location $region -AddressPrefix '10.0.0.0/24' -AcceptOverlappingIpAddresses } | Should -Throw
        }
    }

    it 'Throws on missing mandatory parameter' {
        $mandatoryParams = @('Environment', 'Location', 'AddressPrefix')

        $params = @{
            Environment = 'dev'
            Location = 'westeurope'
            AddressPrefix = '10.0.0.0/24'
            AcceptOverlappingIpAddresses = $true
        }

        foreach ($param in $mandatoryParams.GetEnumerator()) {
            $params.Remove($param)
            { New-PBHubVirtualNetwork @params } | Should -Throw
        }
    }

    it 'Throws on missing overlapping IP Ranges' {
        $invalidPrefixes = @(
            '192.168.0.0/24' # Has to be adjusted based on actual overlapping ranges in the target environment
        )
        foreach ($prefix in $invalidPrefixes) {
            { New-PBHubVirtualNetwork -Environment 'dev' -Location 'westeurope' -AddressPrefix $prefix } | Should -Throw
        }
    }

}

# Describe Get-NextCIDRBlock {
#     It 'Returns the next CIDR block correctly' {
#         $global:availableCIDRs = [System.Collections.ArrayList]@()
#         $global:availableCIDRs.Add("192.168.0.0/24")

#         $testValues = @(
#             {
#                 vnetName = 'vnet-test-dev-euw-001'
#                 snetName = 'snet2'
#                 minimumSubnetMask = 25
#                 existingSubnetRange = '192.168.0.0/25'
#             }
#         )

#         foreach ($test in $testValues) {

#             $virtualNetworkName = $test.vnetName
#             $subnetName = $test.snetName
#             $minimumSubnetMask = $test.minimumSubnetMask
#             $existingSubnetRange = $test.existingSubnetRange

#         $nextBlock = Get-NextCIDRBlock -virtualNetworkName $virtualNetworkName -subnetName $subnetName -minimumSubnetMask $minimumSubnetMask

#             $nextBlock | Should -Be $existingSubnetRange
#         }
#     }
# }
