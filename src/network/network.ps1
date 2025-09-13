. $PSScriptRoot/../basics/basics.ps1
. $PSScriptRoot/../shared/errorHandlingNetworking.ps1
. $PSScriptRoot/../shared/errorHandlingBasics.ps1

$global:vnetAddressPrefix = ""
$global:availableCIDRs = [System.Collections.ArrayList]@()
$global:usedRanges = [System.Collections.ArrayList]@()
$global:removedExistingSubnets = $false
function IpIntToString($ipInt) {
    $bytes = [BitConverter]::GetBytes([uint32]$ipInt)
    [Array]::Reverse($bytes)
    return [System.Net.IPAddress]::new($bytes).ToString()
}
function IpStringToInt($ipString) {
    $ipBytes = [System.Net.IPAddress]::Parse($ipString).GetAddressBytes()
    if ([BitConverter]::IsLittleEndian) {
        [Array]::Reverse($ipBytes)
    }
    return [BitConverter]::ToUInt32($ipBytes, 0)
}
function Split-IpRangeToCIDRs {
    param (
        [uint32]$startIp,
        [uint32]$endIp
    )
    $cidrs = @()
    while ($startIp -le $endIp) {
        $maxSize = 32 - [math]::Floor([math]::Log([uint32]($startIp -bxor $endIp), 2))
        $maxMask = 32 - [math]::Floor([math]::Log([uint32]($startIp -band -$startIp), 2))
        $mask = [Math]::Min($maxSize, $maxMask)
        $blockSize = [math]::Pow(2, 32 - $mask)
        if ($startIp + $blockSize - 1 -gt $endIp) {
            $mask = 32 - [math]::Floor([math]::Log([uint32]($endIp - $startIp + 1), 2))
            $blockSize = [math]::Pow(2, 32 - $mask)
        }
        $cidrs += "$(IpIntToString($startIp))/$mask"
        $startIp = [uint32]($startIp + $blockSize)
    }
    Write-Verbose "CIDRS: $cidrs"

    return $cidrs
}
function Get-NextCIDRBlock {
    param (
        [string]$resourceGroupName,
        [string]$virtualNetworkName,
        [string]$subnetName,
        [int]$minimumSubnetMask
    )

    $checkIfVnetExists = Search-AzGraph -Query "resources
        | where type == 'microsoft.network/virtualnetworks'
        | where subscriptionId == '$((Get-AzContext).Subscription.Id)'
        | where resourceGroup  == '$resourceGroupName'
        | where name == '$virtualNetworkName'"

    if ($checkIfVnetExists) {
        Write-Verbose "Subnet '$subnetName' already exists in virtual network '$virtualNetworkName'."

        $allExistingSubnets = $checkIfVnetExists.properties.subnets

        if ($allExistingSubnets) {
            Write-Verbose "Found existing subnets in virtual network '$virtualNetworkName'"

            foreach ($subnet in $allExistingSubnets) {
                if (-not $global:removedExistingSubnets){
                    Write-Verbose "Remove existing Subnet $($subnet.name) with CIDR $($subnet.properties.addressPrefix) from available ranges."
                    $cidr = $subnet.properties.addressPrefix
                    $global:usedRanges.Add($cidr)

                    $cidrParts = $cidr -split "/"
                    $networkAddress = $cidrParts[0]
                    $mask = [int]$cidrParts[1]
                    $startIp = IpStringToInt($networkAddress)
                    $endIp = $startIp + [math]::Pow(2, 32 - $mask) - 1

                    for ($j = 0; $j -lt $global:availableCIDRs.Count; $j++) {
                        $availableCidrParts = $global:availableCIDRs[$j] -split "/"
                        $availableNetworkAddress = $availableCidrParts[0]
                        $availableMask = [int]$availableCidrParts[1]
                        $availableStartIp = IpStringToInt($availableNetworkAddress)
                        $availableEndIp = $availableStartIp + [math]::Pow(2, 32 - $availableMask) - 1

                        if ($startIp -ge $availableStartIp -and $endIp -le $availableEndIp) {
                            $global:availableCIDRs.RemoveAt($j)
                            if ($startIp -gt $availableStartIp) {
                                $beforeCIDRs = Split-IpRangeToCIDRs -startIp $availableStartIp -endIp ($startIp - 1)
                                foreach ($beforeCidr in $beforeCIDRs) { $global:availableCIDRs.Add([string]$beforeCidr) }
                            }
                            if ($endIp -lt $availableEndIp) {
                                $afterCIDRs = Split-IpRangeToCIDRs -startIp ($endIp + 1) -endIp $availableEndIp
                                foreach ($afterCidr in $afterCIDRs) { $global:availableCIDRs.Add([string]$afterCidr) }
                            }
                            break
                        }
                    }
                } 
                
                if ($subnetName -eq $subnet.name) {
                    return $subnet.properties.addressPrefix
                }
            }
            Write-Verbose "Available CIDRs after removing existing subnets: $global:availableCIDRs"
            $global:removedExistingSubnets = $true 
        }  
    }

    for ($i = 0; $i -lt $global:availableCIDRs.Count; $i++) {

        $cidrParts = $global:availableCIDRs[$i] -split "/"
        $cidrNetworkAddress = $cidrParts[0]
        $cidrMask = [int]$cidrParts[1]

        $availableCIDRStartIp = [uint32](IpStringToInt($cidrNetworkAddress))
        $availableCIDREndIp = [uint32]($availableCIDRStartIp + [math]::Pow(2, 32 - $cidrMask) - 1)

        if ($cidrMask -le $minimumSubnetMask) {
            $global:availableCIDRs.RemoveAt($i)
            $cidrBlock = "$cidrNetworkAddress/$minimumSubnetMask"
            $allocatedStart = [uint32]$availableCIDRStartIp
            $allocatedEnd = [uint32]($allocatedStart + [math]::Pow(2, 32 - $minimumSubnetMask) - 1)

            #$global:availableCIDRs.RemoveAt($i)
            Write-Verbose "Removed $cidrNetworkAddress/$cidrMask from Available CIDRs"

            $global:usedRanges.Add($cidrBlock)

            if ($allocatedStart -gt $availableCIDRStartIp) {
                $beforeCIDRs = Split-IpRangeToCIDRs -startIp $availableCIDRStartIp -endIp ($allocatedStart - 1)
                foreach ($cidr in $beforeCIDRs) { $global:availableCIDRs.Add([string]$cidr) }
            }
            if ($allocatedEnd -lt $availableCIDREndIp) {
                $afterCIDRs = Split-IpRangeToCIDRs -startIp ($allocatedEnd + 1) -endIp $availableCIDREndIp
                foreach ($cidr in $afterCIDRs) { $global:availableCIDRs.Add([string]$cidr) }
            }

            Write-Verbose "Available CIDRs after allocation: $($global:availableCIDRs -join ', ')"

            return $cidrBlock

        } elseif ($i -eq ($global:availableCIDRs.Count - 1)) {
            throw "No available CIDR block found that fits the required subnet mask /$minimumSubnetMask"
        }
    }
}
function New-PBHubVirtualNetwork {
    param (
        [Parameter(ParameterSetName = "Default")]
        [string]$ApplicationNameShort = "hub",

        [ValidateSet("Prod", "Dev", "Test", "Staging", "QA", "Sandbox")]
        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$Environment,

        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$Location,

        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$AddressPrefix,

        [ValidatePattern('^(0[0-9]{2}|[1-9][0-9]{2})$')]
        [Parameter(ParameterSetName = "Default")]
        [string]$Index = "001",

        [Parameter(ParameterSetName = "Default")]
        [object]$Tags = @{},

        [Parameter(ParameterSetName = "Default")]
        [int]$NamingConventionOption = 1,

        [Parameter(ParameterSetName = "Default")]
        [switch]$DenyManualChanges,

        [Parameter(ParameterSetName = "Default")]
        [switch]$Force,

        [Parameter(ParameterSetName = "Default")]
        [switch]$DeployAzureFirewall,

        [ValidateSet("Basic", "Standard", "Premium")]
        [Parameter(ParameterSetName = "Default")]
        [string]$AzureFirewallSku,

        [Parameter(ParameterSetName = "Default")]
        [switch]$DeployAzureBastion,

        [ValidateSet("Basic", "Standard", "Premium")]
        [Parameter(ParameterSetName = "Default")]
        [string]$AzureBastionSku,

        [Parameter(ParameterSetName = "Default")]
        [switch]$DeployEntraPrivateAccess,

        [Parameter(ParameterSetName = "Default")]
        [switch]$DeployAzureVpnGateway
    )

    #Input validation
    try {
        Test-LocationName -Location $Location | Out-Null
        Test-VirtualNetworkAddressPrefix -AddressPrefix $AddressPrefix | Out-Null
    } catch {
        throw "Error: $_"
    }

    $global:vnetAddressPrefix = $AddressPrefix
    $global:availableCIDRs = [System.Collections.ArrayList]@()
    $global:usedRanges = [System.Collections.ArrayList]@()
    $global:availableCIDRs.Add($global:vnetAddressPrefix) | Out-Null

    $locationShortcutList = Get-Content -Path "./lib/locationsShortcuts.json" | ConvertFrom-Json -AsHashtable

    $locationShort = $locationShortcutList.$Location

    $virtualNetworkName = New-PBResourceName -ResourceType "Microsoft.Network/virtualNetworks" -NamingConventionOption $NamingConventionOption -ApplicationNameShort $ApplicationNameShort -Environment $Environment -Location $Location -Index $Index

    $resourceGroupName = New-PBResourceName -ResourceType "Microsoft.Resources/resourceGroups" -NamingConventionOption $NamingConventionOption -ApplicationNameShort $ApplicationNameShort -Environment $Environment -Location $Location -Index $Index

    Write-Verbose "Checking for overlapping VNets with Address Prefix '$AddressPrefix'"
    $overlappingVirtualNetworks = Search-AzGraph -Query "resources
        | where type == 'microsoft.network/virtualnetworks'
        | where name != '$virtualNetworkName'
        | where properties.addressSpace.addressPrefixes contains '$AddressPrefix'"

    if (-not $AcceptOverlappingIpAddresses) {
        try {
            Test-OverlappingIpAddressPrefixes -VirtualNetworkName $virtualNetworkName -AddressPrefix $AddressPrefix | Out-Null
        } catch {
            throw "Error: $_"
        }
    }

    $Tags.add("HubVNET", "True")

    [hashtable]$subnets = @{}
    if ($DeployAzureFirewall) {
        $subnets.Add("AzureFirewallSubnet", 26)
        $subnets.Add("AzureFirewallManagementSubnet", 26)
    }

    if ($DeployAzureBastion) {
        $subnets.Add("AzureBastionSubnet", 26)
    }

    if ($DeployEntraPrivateAccess) {
        $subnets.Add("EntraPrivateAccessSubnet", 27)
    }

    if ($DeployAzureVpnGateway) {
        $subnets.Add("GatewaySubnet", 27)
    }

    [array]$subnetsObjectArray = @()

    [array]$subnetsObjectArray = @()

    $sortedSubnets = $Subnets.GetEnumerator() | Sort-Object -Property Value

    foreach ($subnet in $sortedSubnets) {
        $subnetName = $subnet.Key
        $subnetMask = $subnet.Value

        $cidrBlock = [string](Get-NextCIDRBlock -minimumSubnetMask $subnetMask)
        $cidrBlockSplit = $cidrBlock -split ' '
        $cidrBlock = $cidrBlockSplit[$cidrBlockSplit.Length - 1]


        $subnetObject = @{
            name = $subnetName
            addressPrefix = $cidrBlock
        }

        $subnetsObjectArray += $subnetObject
    }

    if ($DeployAzureVpnGateway) {
        $Tags.add("VpnGateway", "True")
    }

    if ($DeployAzureFirewall) {
        $azureFirewallSubnetObject = $subnetsObjectArray | Where-Object { $_.name -eq "AzureFirewallSubnet" }
        Write-Verbose "AzureFirewallSubnet found with address prefix: $($azureFirewallSubnetObject.addressPrefix)"
        $azureFirewallSubnetNetworkAddress = $azureFirewallSubnetObject.addressPrefix.Split("/")[0]
        Write-Verbose "AzureFirewallSubnet network address: $azureFirewallSubnetNetworkAddress"

        $azureFirewallPrivateIpInt = (IpStringToInt($azureFirewallSubnetNetworkAddress)) + 4
        $azureFirewallPrivateIp = IpIntToString($azureFirewallPrivateIpInt)

        $Tags.add("AzFirewall", "True")
        $Tags.add("AzFirewallPrivateIp", $azureFirewallPrivateIp)
    }

    if ($DeployAzureBastion) {
        $Tags.add("Bastion", "True")
    }

    if ($DeployEntraPrivateAccess) {
        $Tags.add("EntraPrivateAccess", "True")
    }
    
    $resourceGroup = New-AzSubscriptionDeployment `
        -Name "Deploy-$ApplicationNameShort-Network-RG-$locationShort" `
        -Location $Location `
        -TemplateFile "./src/resourceContainer/resource_group.bicep" `
        -TemplateParameterObject @{
            name = $resourceGroupName
            location = $Location
            tags = $Tags
        }
    
    if ($Force) {
    $virtualNetwork = New-AzResourceGroupDeploymentStack `
        -ResourceGroupName $resourceGroup.Outputs.name.value `
        -Name "Deploy-$ApplicationNameShort-VNET-$locationShort" `
        -TemplateFile "./src/network/bicep/hub_vnet.bicep" `
        -TemplateParameterObject @{
            location = $Location
            name = $virtualNetworkName
            addressPrefix = $AddressPrefix
            tags = $Tags
            subnets = $subnetsObjectArray
            deployAzureFirewall = ($DeployAzureFirewall ? $true : $false)
            deployAzureBastion = ($DeployAzureBastion ? $true : $false)
            deployEntraPrivateAccess = ($DeployEntraPrivateAccess ? $true : $false)
            deployAzureVpnGateway = ($DeployAzureVpnGateway ? $true : $false)
            azureFirewallSku = $AzureFirewallSku
            bastionSku = $AzureBastionSku
        } `
        -ActionOnUnmanage "DeleteAll" `
        -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None") `
        -Force
    } else {
        $virtualNetwork = New-AzResourceGroupDeploymentStack `
        -ResourceGroupName $resourceGroup.Outputs.name.value `
        -Name "Deploy-$ApplicationNameShort-VNET-$locationShort" `
        -TemplateFile "./src/network/hub_vnet.bicep" `
        -TemplateParameterObject @{
            location = $Location
            name = $virtualNetworkName
            addressPrefix = $AddressPrefix
            tags = $Tags
            subnets = $subnetsObjectArray
            deployAzureFirewall = ($DeployAzureFirewall ? $true : $false)
            deployAzureBastion = ($DeployAzureBastion ? $true : $false)
            deployEntraPrivateAccess = ($DeployEntraPrivateAccess ? $true : $false)
            deployAzureVpnGateway = ($DeployAzureVpnGateway ? $true : $false)
            azureFirewallSku = $AzureFirewallSku
            bastionSku = $AzureBastionSku
        } `
        -ActionOnUnmanage "DeleteAll" `
        -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None")
    }
    return $virtualNetwork

}
function New-PBSpokeVirtualNetwork {
    param (
        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$ApplicationNameShort,

        [ValidateSet("Prod", "Dev", "Test", "Staging", "QA", "Sandbox")]
        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$Environment,

        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$Location,

        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$AddressPrefix,

        [ValidatePattern('^(0[0-9]{2}|[1-9][0-9]{2})$')]
        [Parameter(ParameterSetName = "Default")]
        [string]$Index = "001",

        [Parameter(ParameterSetName = "Default")]
        [object]$Tags = @{},

        [Parameter(ParameterSetName = "Default")]
        
        [hashtable]$Subnets = @{},

        [Parameter(ParameterSetName = "Default")]
        [int]$NamingConventionOption = 1,

        [Parameter(ParameterSetName = "Default")]
        [switch]$DenyManualChanges,

        [Parameter(ParameterSetName = "Default")]
        [switch]$Force,

        [Parameter(ParameterSetName = "Default")]
        [switch]$AcceptOverlappingIpAddresses
    )

    #Input validation
    try {
        Test-ApplicationNameShort -ApplicationNameShort $ApplicationNameShort | Out-Null
        Test-SubnetConfiguration -Subnets $Subnets | Out-Null
        Test-LocationName -Location $Location | Out-Null
        Test-VirtualNetworkAddressPrefix -AddressPrefix $AddressPrefix | Out-Null

    } catch {
        throw "Error: $_"
    }

    $global:vnetAddressPrefix = $AddressPrefix
    $global:availableCIDRs = [System.Collections.ArrayList]@()
    $global:usedRanges = [System.Collections.ArrayList]@()
    $global:availableCIDRs.Add($global:vnetAddressPrefix) | Out-Null

    $locationShortcutList = Get-Content -Path "lib/locationsShortcuts.json" | ConvertFrom-Json -AsHashtable
    
    $locationShort = $locationShortcutList.$Location

    $virtualNetworkName = New-PBResourceName -ResourceType "Microsoft.Network/virtualNetworks" -NamingConventionOption $NamingConventionOption -ApplicationNameShort $ApplicationNameShort -Environment $Environment -Location $Location -Index $Index

    $resourceGroupName = New-PBResourceGroupName -NamingConventionOption $NamingConventionOption -ApplicationNameShort $ApplicationNameShort -Environment $Environment -Location $Location -Index $Index -NetworkResourceGroup

    if (-not $AcceptOverlappingIpAddresses) {
        try {
            Test-OverlappingIpAddressPrefixes -VirtualNetworkName $virtualNetworkName -AddressPrefix $AddressPrefix | Out-Null
        } catch {
            throw "Error: $_"
        }
    }

    Write-Verbose "Checking for Hub VNet in location '$Location'"

    $hubVnet = Search-AzGraph -Query "resources
        | where tags.HubVNET == 'True'
        | where location == '$Location'"

    if ($hubVnet.location -eq $null) {
        throw "No Hub network found in location '$Location'. Please deploy a Hub network first using 'New-PBHubNetwork' and retry the deployment."
    }

    Write-Verbose "Creating Resource Group '$resourceGroupName'"
    $resourceGroup = New-AzSubscriptionDeployment `
        -Name "Deploy-$ApplicationNameShort-Network-RG-$locationShort" `
        -Location $Location `
        -TemplateFile "./src/resourceContainer/resource_group.bicep" `
        -TemplateParameterObject @{
            name = $resourceGroupName
            location = $Location
            tags = $Tags
        }
    
    [array]$subnetsObjectArray = @()
    
    $sortedSubnets = $Subnets.GetEnumerator() | Sort-Object -Property Value
    foreach ($subnet in $sortedSubnets) {
        $subnetName = $subnet.Key
        $subnetMask = $subnet.Value

        $cidrBlock = [string](Get-NextCIDRBlock -resourceGroupName $resourceGroupName -virtualNetworkName $virtualNetworkName -subnetName $subnetName -minimumSubnetMask $subnetMask)
        $cidrBlockSplit = $cidrBlock -split ' '
        $cidrBlock = $cidrBlockSplit[$cidrBlockSplit.Length - 1]


        $subnetObject = @{
            name = $subnetName
            addressPrefix = $cidrBlock
        }

        $subnetsObjectArray += $subnetObject
    }
    
    if ($Force) {
        $virtualNetwork = New-AzResourceGroupDeploymentStack `
            -ResourceGroupName $resourceGroup.Outputs.name.value `
            -Name "Deploy-$ApplicationNameShort-VNET-$locationShort" `
            -TemplateFile "./src/network/bicep/spoke_vnet.bicep" `
            -TemplateParameterObject @{
                location = $Location
                name = $virtualNetworkName
                addressPrefix = $AddressPrefix
                tags = $Tags
                subnets = $subnetsObjectArray
                nextHopDefaultRouteIP = $hubVnet.tags.AzFirewall -eq "True" ? $hubVnet.tags.AzFirewallPrivateIp : $nextHopDefaultRouteIP
                hubVnetId = $hubVnet.id
                hubHasVpnGateway = ($hubVnet.tags.VpnGateway -eq "True" ? $true : $false)
            } `
            -ActionOnUnmanage "DeleteAll" `
            -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None") `
            -Force
    } else {
        $virtualNetwork = New-AzResourceGroupDeploymentStack `
            -ResourceGroupName $resourceGroup.Outputs.name.value `
            -Name "Deploy-$ApplicationNameShort-VNET-$locationShort" `
            -TemplateFile "./src/network/bicep/spoke_vnet.bicep" `
            -TemplateParameterObject @{
                location = $Location
                name = $virtualNetworkName
                addressPrefix = $AddressPrefix
                tags = $Tags
                subnets = $subnetsObjectArray
                nextHopDefaultRouteIP = $hubVnet.tags.AzFirewall -eq "True" ? $hubVnet.tags.AzFirewallPrivateIp : $nextHopDefaultRouteIP
                hubVnetId = $hubVnet.id
                hubHasVpnGateway = ($hubVnet.tags.VpnGateway -eq "True" ? $true : $false)
            } `
            -ActionOnUnmanage "DeleteAll" `
            -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None")
    }

    $virtualNetworkPSObject = Get-AzVirtualNetwork -Name $virtualNetwork.Outputs.name.value -ResourceGroupName $resourceGroup.Outputs.name.value

    return $virtualNetworkPSObject

}

function New-PBIsolatedVirtualNetwork {
    param (
        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$ApplicationNameShort,

        [ValidateSet("Prod", "Dev", "Test", "Staging", "QA", "Sandbox")]
        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$Environment,

        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$Location,

        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$AddressPrefix,

        [ValidatePattern('^(0[0-9]{2}|[1-9][0-9]{2})$')]
        [Parameter(ParameterSetName = "Default")]
        [string]$Index = "001",

        [Parameter(ParameterSetName = "Default")]
        [object]$Tags = @{},

        [Parameter(ParameterSetName = "Default")]
        
        [hashtable]$Subnets = @{},

        [Parameter(ParameterSetName = "Default")]
        [int]$NamingConventionOption = 1,

        [Parameter(ParameterSetName = "Default")]
        [switch]$DenyManualChanges,

        [Parameter(ParameterSetName = "Default")]
        [switch]$Force,

        [Parameter(ParameterSetName = "Default")]
        [switch]$AcceptOverlappingIpAddresses
    )

    #Input validation
    try {
        Test-ApplicationNameShort -ApplicationNameShort $ApplicationNameShort | Out-Null
        Test-SubnetConfiguration -Subnets $Subnets | Out-Null
        Test-LocationName -Location $Location | Out-Null
        Test-VirtualNetworkAddressPrefix -AddressPrefix $AddressPrefix | Out-Null

    } catch {
        throw "Error: $_"
    }

    $global:vnetAddressPrefix = $AddressPrefix
    $global:availableCIDRs = [System.Collections.ArrayList]@()
    $global:usedRanges = [System.Collections.ArrayList]@()
    $global:availableCIDRs.Add($global:vnetAddressPrefix) | Out-Null

    $locationShortcutList = Get-Content -Path "lib/locationsShortcuts.json" | ConvertFrom-Json -AsHashtable
    
    $locationShort = $locationShortcutList.$Location

    $virtualNetworkName = New-PBResourceName -ResourceType "Microsoft.Network/virtualNetworks" -NamingConventionOption $NamingConventionOption -ApplicationNameShort $ApplicationNameShort -Environment $Environment -Location $Location -Index $Index

    $resourceGroupName = New-PBResourceGroupName -NamingConventionOption $NamingConventionOption -ApplicationNameShort $ApplicationNameShort -Environment $Environment -Location $Location -Index $Index -NetworkResourceGroup

    if (-not $AcceptOverlappingIpAddresses) {
        try {
            Test-OverlappingIpAddressPrefixes -VirtualNetworkName $virtualNetworkName -AddressPrefix $AddressPrefix | Out-Null
        } catch {
            throw "Error: $_"
        }
    }
    
    Write-Verbose "Creating Resource Group '$resourceGroupName'"
    $resourceGroup = New-AzSubscriptionDeployment `
        -Name "Deploy-$ApplicationNameShort-Network-RG-$locationShort" `
        -Location $Location `
        -TemplateFile "./resourceContainer/resource_group.bicep" `
        -TemplateParameterObject @{
            name = $resourceGroupName
            location = $Location
            tags = $Tags
        }
    
    [array]$subnetsObjectArray = @()
    
    $sortedSubnets = $Subnets.GetEnumerator() | Sort-Object -Property Value
    foreach ($subnet in $sortedSubnets) {
        $subnetName = $subnet.Key
        $subnetMask = $subnet.Value

        $cidrBlock = [string](Get-NextCIDRBlock -resourceGroupName $resourceGroupName -virtualNetworkName $virtualNetworkName -subnetName $subnetName -minimumSubnetMask $subnetMask)
        $cidrBlockSplit = $cidrBlock -split ' '
        $cidrBlock = $cidrBlockSplit[$cidrBlockSplit.Length - 1]


        $subnetObject = @{
            name = $subnetName
            addressPrefix = $cidrBlock
        }

        $subnetsObjectArray += $subnetObject
    }
    
    if ($Force) {
        $virtualNetwork = New-AzResourceGroupDeploymentStack `
            -ResourceGroupName $resourceGroup.Outputs.name.value `
            -Name "deploy-$ApplicationNameShort-vnet-$locationShort" `
            -TemplateFile "./network/bicep/isolated_vnet.bicep" `
            -TemplateParameterObject @{
                location = $Location
                name = $virtualNetworkName
                addressPrefix = $AddressPrefix
                tags = $Tags
                subnets = $subnetsObjectArray
            } `
            -ActionOnUnmanage "DeleteAll" `
            -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None") `
            -Force
    } else {
        $virtualNetwork = New-AzResourceGroupDeploymentStack `
            -ResourceGroupName $resourceGroup.Outputs.name.value `
            -Name "Deploy-$ApplicationNameShort-VNET-$locationShort" `
            -TemplateFile "./network/bicep/isolated_vnet.bicep" `
            -TemplateParameterObject @{
                location = $Location
                name = $virtualNetworkName
                addressPrefix = $AddressPrefix
                tags = $Tags
                subnets = $subnetsObjectArray
            } `
            -ActionOnUnmanage "DeleteAll" `
            -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None")
    }

    $virtualNetworkPSObject = Get-AzVirtualNetwork -Name $virtualNetwork.Outputs.name.value -ResourceGroupName $resourceGroup.Outputs.name.value

    return $virtualNetworkPSObject

}
