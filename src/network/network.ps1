. $PSScriptRoot/../basics/basics.ps1
. $PSScriptRoot/../shared/errorHandlingNetworking.ps1
. $PSScriptRoot/../shared/errorHandlingBasics.ps1

$global:vnetAddressPrefix = ""
$global:availableCIDRs = [System.Collections.ArrayList]@()
$global:usedRanges = [System.Collections.ArrayList]@()
$global:removedExistingSubnets = $false
$global:resourceGroupBicepTemplatePath = "./src/resourceContainer/bicep/resource_group.bicep"
$global:hubVnetBicepTemplatePath = "./src/network/bicep/hub_vnet.bicep"
$global:spokeVnetBicepTemplatePath = "./src/network/bicep/spoke_vnet.bicep"
$global:privateDnsZonesBicepTemplatePath = "./src/network/bicep/private_dns_zones.bicep"
$global:isolatedVnetBicepTemplatePath = "./src/network/bicep/isolated_vnet.bicep"

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
        [string]$AzureFirewallSku = "Basic",

        [Parameter(ParameterSetName = "Default")]
        [switch]$AzureFirewallAllowOutboundInternetAccess,

        [Parameter(ParameterSetName = "Default")]
        [switch]$DeployAzureBastion,

        [ValidateSet("Basic", "Standard", "Premium")]
        [Parameter(ParameterSetName = "Default")]
        [string]$AzureBastionSku = "Basic",

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

    if (-not $AcceptOverlappingIpAddresses) {
        try {
            Test-OverlappingIpAddressPrefixes -VirtualNetworkName $virtualNetworkName -AddressPrefix $AddressPrefix | Out-Null
        } catch {
            throw "Error: $_"
        }
    }

    $Tags.add("HubVNET", "True")
    $Tags.add("Environment", $Environment)
    $Tags.add("CreatedWith", "PowerBicep")

    [hashtable]$subnets = @{}
    
    $subnets.Add("AzureFirewallSubnet", 26)
    $subnets.Add("AzureFirewallManagementSubnet", 26)
    $subnets.Add("AzureBastionSubnet", 26)
    $subnets.Add("GatewaySubnet", 27)


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
    
    $resourceGroupDeploymentName = "Deploy-$ApplicationNameShort-Network-RG-$($locationShort.toUpper())"

    $resourceGroup = New-AzSubscriptionDeployment `
        -Name $resourceGroupDeploymentName `
        -Location $Location `
        -TemplateFile $global:resourceGroupBicepTemplatePath `
        -TemplateParameterObject @{
            name = $resourceGroupName
            location = $Location
            tags = $Tags
        }
    
    $vnetDeploymentName = "Deploy-$ApplicationNameShort-VNET-$($locationShort.toUpper())"
    $vnetDeploymentParameters = @{
        location = $Location
        name = $virtualNetworkName
        addressPrefix = $AddressPrefix
        tags = $Tags
        subnets = $subnetsObjectArray
        deployAzureFirewall = ($DeployAzureFirewall ? $true : $false)
        deployAzureBastion = ($DeployAzureBastion ? $true : $false)
        azureFirewallSku = $AzureFirewallSku
        bastionSku = $AzureBastionSku
        allowOutboundInternetAccess = ($AzureFirewallAllowOutboundInternetAccess ? $true : $false)
    }
    
    if ($Force) {
    $virtualNetwork = New-AzResourceGroupDeploymentStack `
        -ResourceGroupName $resourceGroup.Outputs.name.value `
        -Name $vnetDeploymentName `
        -TemplateFile $global:hubVnetBicepTemplatePath `
        -TemplateParameterObject $vnetDeploymentParameters `
        -ActionOnUnmanage "DeleteAll" `
        -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None") `
        -DenySettingsApplyToChildScopes `
        -Force
    } else {
        $virtualNetwork = New-AzResourceGroupDeploymentStack `
        -ResourceGroupName $resourceGroup.Outputs.name.value `
        -Name $vnetDeploymentName `
        -TemplateFile $global:hubVnetBicepTemplatePath `
        -TemplateParameterObject $vnetDeploymentParameters `
        -ActionOnUnmanage "DeleteAll" `
        -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None") `
        -DenySettingsApplyToChildScopes
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
        [switch]$AcceptOverlappingIpAddresses,

        [Parameter(ParameterSetName = "Default")]
        [array]$CustomDnsServers = @()

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

    $Tags.add("Environment", $Environment)
    $Tags.add("CreatedWith", "PowerBicep")

    Write-Verbose "Checking for Hub VNet in location '$Location'"

    $hubVnet = Search-AzGraph -Query "resources
        | where type == 'microsoft.network/virtualnetworks'
        | where tags.HubVNET == 'True'
        | where location == '$Location'"

    if ($null -eq $hubVnet.location) {
        throw "No Hub network found in location '$Location'. Please deploy a Hub network first using 'New-PBHubNetwork' and retry the deployment."
    }

    if ($hubVnet.tags.AzFirewall -eq "True") {
        $firewall = Search-AzGraph -Query "resources
            | where type == 'microsoft.network/azurefirewalls'
            | where resourceGroup  == '$($hubVnet.resourceGroup)'"
    }

    $resourceGroupDeploymentName = "Deploy-$ApplicationNameShort-Network-RG-$($locationShort.toUpper())"

    Write-Verbose "Creating Resource Group '$resourceGroupName'"
    $resourceGroup = New-AzSubscriptionDeployment `
        -Name $resourceGroupDeploymentName `
        -Location $Location `
        -TemplateFile $global:resourceGroupBicepTemplatePath `
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
    $vnetDeploymentName = "Deploy-$ApplicationNameShort-VNET-$($locationShort.toUpper())"
    $vnetDeploymentParameters = @{
        location = $Location
        name = $virtualNetworkName
        addressPrefix = $AddressPrefix
        tags = $Tags
        subnets = $subnetsObjectArray
        nextHopDefaultRouteIP = $hubVnet.tags.AzFirewall -eq "True" ? $hubVnet.tags.AzFirewallPrivateIp : ''
        azureFirewallPrivateIP = $hubVnet.tags.AzFirewallPrivateIp ? $hubVnet.tags.AzFirewallPrivateIp : ''
        dnsServers = ($CustomDnsServers -ne @()) ? $CustomDnsServers : ($firewall.properties.sku.tier -ne "Basic" -and $hubVnet.tags.AzFirewall -eq "True") ? @($hubVnet.tags.AzFirewallPrivateIp) : @()
        hubVnetId = $hubVnet.id
        hubHasVpnGateway = ($hubVnet.tags.VpnGateway -eq "True" ? $true : $false)
    }

    if ($Force) {
        $virtualNetwork = New-AzResourceGroupDeploymentStack `
            -ResourceGroupName $resourceGroup.Outputs.name.value `
            -Name $vnetDeploymentName `
            -TemplateFile $global:spokeVnetBicepTemplatePath `
            -TemplateParameterObject $vnetDeploymentParameters `
            -ActionOnUnmanage "DeleteAll" `
            -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None") `
            -DenySettingsApplyToChildScopes `
            -Force
    } else {
        $virtualNetwork = New-AzResourceGroupDeploymentStack `
            -ResourceGroupName $resourceGroup.Outputs.name.value `
            -Name $vnetDeploymentName `
            -TemplateFile $global:spokeVnetBicepTemplatePath `
            -TemplateParameterObject $vnetDeploymentParameters `
            -ActionOnUnmanage "DeleteAll" `
            -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None") `
            -DenySettingsApplyToChildScopes
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
    
    $Tags.add("Environment", $Environment)
    $Tags.add("CreatedWith", "PowerBicep")

    $resourceGroupDeploymentName = "Deploy-$ApplicationNameShort-Network-RG-$($locationShort.toUpper())"

    Write-Verbose "Creating Resource Group '$resourceGroupName'"
    $resourceGroup = New-AzSubscriptionDeployment `
        -Name $resourceGroupDeploymentName `
        -Location $Location `
        -TemplateFile $global:resourceGroupBicepTemplatePath `
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

    $vnetDeploymentName = "Deploy-$ApplicationNameShort-VNET-$($locationShort.toUpper())"
    $vnetDeploymentParameters = @{
        location = $Location
        name = $virtualNetworkName
        addressPrefix = $AddressPrefix
        tags = $Tags
        subnets = $subnetsObjectArray
    }

    if ($Force) {
        $virtualNetwork = New-AzResourceGroupDeploymentStack `
            -ResourceGroupName $resourceGroup.Outputs.name.value `
            -Name $vnetDeploymentName `
            -TemplateFile $global:isolatedVnetBicepTemplatePath `
            -TemplateParameterObject $vnetDeploymentParameters `
            -ActionOnUnmanage "DeleteAll" `
            -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None") `
            -DenySettingsApplyToChildScopes `
            -Force
    } else {
        $virtualNetwork = New-AzResourceGroupDeploymentStack `
            -ResourceGroupName $resourceGroup.Outputs.name.value `
            -Name $vnetDeploymentName `
            -TemplateFile $global:isolatedVnetBicepTemplatePath `
            -TemplateParameterObject $vnetDeploymentParameters `
            -ActionOnUnmanage "DeleteAll" `
            -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None") `
            -DenySettingsApplyToChildScopes
    }

    $virtualNetworkPSObject = Get-AzVirtualNetwork -Name $virtualNetwork.Outputs.name.value -ResourceGroupName $resourceGroup.Outputs.name.value

    return $virtualNetworkPSObject

}

function New-PBPrivateDnsZone {
    param (
        [Parameter()]
        [switch]$All,

        [Parameter()]
        [string[]]$CustomPrivateDnsZones,

        [Parameter()]
        [switch]$LinkToHub,

        [Parameter()]
        [string[]]$LinkedVirtualNetworkIds,

        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter()]
        [hashtable]$Tags = @{},

        [Parameter()]
        [string]$Index = "001",

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$DenyManualChanges,

        [Parameter()]
        [int]$NamingConventionOption = 1
    )

    $privateDnsZoneNames = @()
    if ($All) {
        $privateDnsZoneNames = @(
                'privatelink.api.azureml.ms'
                'privatelink.notebooks.azure.net'
                'privatelink.cognitiveservices.azure.com'
                'privatelink.openai.azure.com'
                'privatelink.services.ai.azure.com'
                'privatelink.directline.botframework.com'
                'privatelink.token.botframework.com'
                'privatelink.sql.azuresynapse.net'
                'privatelink.dev.azuresynapse.net'
                'privatelink.azuresynapse.net'
                'privatelink.servicebus.windows.net'
                'privatelink.datafactory.azure.net'
                'privatelink.adf.azure.com'
                'privatelink.azurehdinsight.net'
                'privatelink.blob.core.windows.net'
                'privatelink.queue.core.windows.net'
                'privatelink.table.core.windows.net'
                'privatelink.analysis.windows.net'
                'privatelink.pbidedicated.windows.net'
                'privatelink.tip1.powerquery.microsoft.com'
                'privatelink.azuredatabricks.net'
                'privatelink.batch.azure.com'
                'privatelink-global.wvd.microsoft.com'
                'privatelink.wvd.microsoft.com'
                'privatelink.azurecr.io'
                'privatelink.database.windows.net'
                'privatelink.documents.azure.com'
                'privatelink.mongo.cosmos.azure.com'
                'privatelink.cassandra.cosmos.azure.com'
                'privatelink.gremlin.cosmos.azure.com'
                'privatelink.table.cosmos.azure.com'
                'privatelink.analytics.cosmos.azure.com'
                'privatelink.postgres.cosmos.azure.com'
                'privatelink.postgres.database.azure.com'
                'privatelink.mysql.database.azure.com'
                'privatelink.mariadb.database.azure.com'
                'privatelink.redis.cache.windows.net'
                'privatelink.redisenterprise.cache.azure.net'
                'privatelink.redis.azure.net'
                'privatelink.his.arc.azure.com'
                'privatelink.guestconfiguration.azure.com'
                'privatelink.dp.kubernetesconfiguration.azure.com'
                'privatelink.eventgrid.azure.net'
                'privatelink.ts.eventgrid.azure.net'
                'privatelink.azure-api.net'
                'privatelink.azurehealthcareapis.com'
                'privatelink.dicom.azurehealthcareapis.com'
                'privatelink.azure-devices.net'
                'privatelink.azure-devices-provisioning.net'
                'privatelink.api.adu.microsoft.com'
                'privatelink.azureiotcentral.com'
                'privatelink.digitaltwins.azure.net'
                'privatelink.media.azure.net'
                'privatelink.azure-automation.net'
                'privatelink.monitor.azure.com'
                'privatelink.oms.opinsights.azure.com'
                'privatelink.ods.opinsights.azure.com'
                'privatelink.agentsvc.azure-automation.net'
                'privatelink.purview.azure.com'
                'privatelink.purviewstudio.azure.com'
                'privatelink.purview-service.microsoft.com'
                'privatelink.prod.migration.windowsazure.com'
                'privatelink.azure.com'
                'privatelink.grafana.azure.com'
                'privatelink.vaultcore.azure.net'
                'privatelink.managedhsm.azure.net'
                'privatelink.azconfig.io'
                'privatelink.attest.azure.net'
                'privatelink.file.core.windows.net'
                'privatelink.web.core.windows.net'
                'privatelink.dfs.core.windows.net'
                'privatelink.afs.azure.net'
                'privatelink.blob.storage.azure.net'
                'privatelink.search.windows.net'
                'privatelink.azurewebsites.net'
                'scm.privatelink.azurewebsites.net'
                'privatelink.service.signalr.net'
                'privatelink.azurestaticapps.net'
                'privatelink.webpubsub.azure.com'
        )
    } else {
        $privateDnsZoneNames = $CustomPrivateDnsZones
    }

    if ($LinkToHub) {
        Write-Verbose "Searching for Hub VNet in location '$Location'"

        $hubVnets = Search-AzGraph -Query "resources
            | where type == 'microsoft.network/virtualnetworks'
            | where tags.HubVNET == 'True'"

        $LinkedVirtualNetworkIds += $hubVnets.id
    }

    $Tags.add("Environment", $Environment)
    $Tags.add("CreatedWith", "PowerBicep")

    $resourceGroupName = New-PBResourceGroupName -NamingConventionOption $NamingConventionOption -ApplicationNameShort "dns" -Environment $Environment.toLower() -Location $Location -Index $Index

    $locationShortcutList = Get-Content -Path "./lib/locationsShortcuts.json" | ConvertFrom-Json -AsHashtable
    $locationShort = $locationShortcutList.$Location

    $resourceGroupDeploymentName = "Deploy-PrivateDnsZones-RG-$($locationShort.toUpper())"

    $resourceGroup = New-AzSubscriptionDeployment `
        -Name $resourceGroupDeploymentName `
        -Location $Location `
        -TemplateFile $global:resourceGroupBicepTemplatePath `
        -TemplateParameterObject @{
            name = $resourceGroupName
            location = $Location
            tags = $Tags
        }

    $privateDnsZonesDeploymentName = "Deploy-PrivateDnsZones-$($locationShort.toUpper())"
    $privateDnsZonesParameters = @{
        privateDnsZoneNames = $privateDnsZoneNames
        tags = $Tags
        linkedVirtualNetworkIds = $LinkedVirtualNetworkIds
    }
        
    if ($Force) {
        New-AzResourceGroupDeploymentStack `
            -Name $privateDnsZonesDeploymentName `
            -ResourceGroupName $resourceGroup.Outputs.name.value `
            -TemplateFile $global:privateDnsZonesBicepTemplatePath `
            -TemplateParameterObject $privateDnsZonesParameters `
            -ActionOnUnmanage "DeleteAll" `
            -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None") `
            -DenySettingsApplyToChildScopes `
            -Force
    } else {
        New-AzResourceGroupDeploymentStack `
            -Name $privateDnsZonesDeploymentName `
            -ResourceGroupName $resourceGroup.Outputs.name.value `
            -TemplateFile $global:privateDnsZonesBicepTemplatePath `
            -TemplateParameterObject $privateDnsZonesParameters `
            -ActionOnUnmanage "DeleteAll" `
            -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None") `
            -DenySettingsApplyToChildScopes
    }
}