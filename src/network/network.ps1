. $PSScriptRoot/../basics/basics.ps1

$global:vnetAddressPrefix = ""
$global:availableCIDRs = [System.Collections.ArrayList]@()
$global:usedRanges = [System.Collections.ArrayList]@()
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
        [int]$minimumSubnetMask
    )

    for ($i = 0; $i -lt $global:availableCIDRs.Count; $i++) {

        $cidrParts = $global:availableCIDRs[$i] -split "/"
        $cidrNetworkAddress = $cidrParts[0]
        Write-Verbose "CIDR Network Address: $cidrNetworkAddress"
        $cidrMask = [int]$cidrParts[1]

        $availableCIDRStartIp = [uint32](IpStringToInt($cidrNetworkAddress))
        $availableCIDREndIp = [uint32]($availableCIDRStartIp + [math]::Pow(2, 32 - $cidrMask) - 1)
        if ($cidrMask -le $minimumSubnetMask) {
            # Always construct CIDR block as a string
            $cidrBlock = "$cidrNetworkAddress/$minimumSubnetMask"
            $allocatedStart = [uint32]$availableCIDRStartIp
            $allocatedEnd = [uint32]($allocatedStart + [math]::Pow(2, 32 - $minimumSubnetMask) - 1)

            $global:availableCIDRs.RemoveAt($i)
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

            Write-Verbose "Check CIDR Block before Return: $cidrBlock"
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

        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$Environment,

        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$Location,

        # [ValidatePattern('^([0-9]{1,3}\.){3}[0-9]{1,3}/[2-25]{1,2}$')]
        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$AddressPrefix,

        # [Parameter(ParameterSetName = "Default")]
        # [hashtable]$Subnets = @{},

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
        [string]$AzureBastionSku = "Basic",

        [Parameter(ParameterSetName = "Default")]
        [switch]$DeployEntraPrivateAccess,

        [Parameter(ParameterSetName = "Default")]
        [switch]$DeployAzureVpnGateway

    )

    # Reset globals for each new VNet deployment
    $global:vnetAddressPrefix = $AddressPrefix
    $global:availableCIDRs = [System.Collections.ArrayList]@()
    $global:usedRanges = [System.Collections.ArrayList]@()

    Write-Verbose "VNet Address Prefix: $global:vnetAddressPrefix"
    $global:availableCIDRs.Add($global:vnetAddressPrefix)

    $locationShortcutList = Get-Content -Path "../lib/locationsShortcuts.json" | ConvertFrom-Json -AsHashtable
    
    $locationShort = $locationShortcutList.$Location

    $virtualNetworkName = New-PBResourceName -ResourceType "Microsoft.Network/virtualNetworks" -NamingConventionOption $NamingConventionOption -ApplicationNameShort $ApplicationNameShort -Environment $Environment -Location $Location -Index $Index

    $resourceGroupName = New-PBResourceName -ResourceType "Microsoft.Resources/resourceGroups" -NamingConventionOption $NamingConventionOption -ApplicationNameShort $ApplicationNameShort -Environment $Environment -Location $Location -Index $Index

    $Tags.add("HubVNET", "True")

    [hashtable]$subnets = @{}
    if ($true) {
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
    
    $resourceGroup = New-AzSubscriptionDeployment `
        -Name "Deploy-$ApplicationNameShort-Network-RG-$locationShort" `
        -Location $Location `
        -TemplateFile "./resourceContainer/resource_group.bicep" `
        -TemplateParameterObject @{
            name = $resourceGroupName
            location = $Location
            tags = $Tags
        }
    
    if ($Force) {
    $virtualNetwork = New-AzResourceGroupDeploymentStack `
        -ResourceGroupName $resourceGroup.Outputs.name.value `
        -Name "Deploy-$ApplicationNameShort-VNET-$locationShort" `
        -TemplateFile "./network/hub_vnet.bicep" `
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
        -TemplateFile "./network/hub_vnet.bicep" `
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
        [Parameter(ParameterSetName = "HubConnection", Mandatory = $true)]
        [string]$ApplicationNameShort,

        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [Parameter(ParameterSetName = "HubConnection", Mandatory = $true)]
        [string]$Environment,

        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [Parameter(ParameterSetName = "HubConnection", Mandatory = $true)]
        [string]$Location,

        [Parameter(ParameterSetName = "Default", Mandatory = $true)]
        [Parameter(ParameterSetName = "HubConnection", Mandatory = $true)]
        [ValidatePattern('^([0-9]{1,3}\.){3}[0-9]{1,3}/25$')]
        [ValidateScript({
            $parts = $_ -split '/'
            if ($parts.Count -ne 2 -or $parts[1] -ge '30' -or $parts[1] -lt '2') { return $false }
            $ip = $parts[0] -split '\.'
            if ($ip[0] -eq '10') { return $true }
            if ($ip[0] -eq '192' -and $ip[1] -eq '168') { return $true }
            if ($ip[0] -eq '172' -and [int]$ip[1] -ge 16 -and [int]$ip[1] -le 31) { return $true }
            return $false
        })]
        [string]$AddressPrefix,

        [Parameter(ParameterSetName = "Default")]
        [Parameter(ParameterSetName = "HubConnection")]
        [string]$Index = "001",

        [Parameter(ParameterSetName = "Default")]
        [Parameter(ParameterSetName = "HubConnection")]
        [object]$Tags = @{},

        [Parameter(ParameterSetName = "Default")]
        [Parameter(ParameterSetName = "HubConnection")]
        [hashtable]$Subnets = @{},

        [Parameter(ParameterSetName = "Default")]
        [Parameter(ParameterSetName = "HubConnection")]
        [int]$NamingConventionOption = 1,

        [Parameter(ParameterSetName="HubConnection", Mandatory=$true)]
        [string]$NextHopDefaultRouteIP,

        [Parameter(ParameterSetName="HubConnection")]
        [switch]$ConnectToHubNetwork,

        [Parameter(ParameterSetName = "Default")]
        [Parameter(ParameterSetName="HubConnection")]
        [string]$NextHopType = "VirtualAppliance",

        [Parameter(ParameterSetName = "Default")]
        [Parameter(ParameterSetName="HubConnection")]
        [switch]$DenyManualChanges,

        [Parameter(ParameterSetName = "Default")]
        [Parameter(ParameterSetName="HubConnection")]
        [switch]$Force
    )

    # Reset globals for each new VNet deployment
    $global:vnetAddressPrefix = $AddressPrefix
    $global:availableCIDRs = [System.Collections.ArrayList]@()
    $global:usedRanges = [System.Collections.ArrayList]@()

    Write-Verbose "VNet Address Prefix: $global:vnetAddressPrefix"
    $global:availableCIDRs.Add($global:vnetAddressPrefix)

    $locationShortcutList = Get-Content -Path "../lib/locationsShortcuts.json" | ConvertFrom-Json -AsHashtable
    
    $locationShort = $locationShortcutList.$Location

    $virtualNetworkName = New-PBResourceName -ResourceType "Microsoft.Network/virtualNetworks" -NamingConventionOption $NamingConventionOption -ApplicationNameShort $ApplicationNameShort -Environment $Environment -Location $Location -Index $Index

    $resourceGroupName = New-PBResourceName -ResourceType "Microsoft.Resources/resourceGroups" -NamingConventionOption $NamingConventionOption -ApplicationNameShort $ApplicationNameShort -Environment $Environment -Location $Location -Index $Index

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

        $cidrBlock = [string](Get-NextCIDRBlock -minimumSubnetMask $subnetMask)
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
        -TemplateFile "./network/spoke_vnet.bicep" `
        -TemplateParameterObject @{
            location = $Location
            name = $virtualNetworkName
            addressPrefix = $AddressPrefix
            tags = $Tags
            subnets = $subnetsObjectArray
            connectToHubNetwork = ($ConnectToHubNetwork ? $true : $false)
            nextHopDefaultRouteIP = $NextHopDefaultRouteIP
        } `
        -ActionOnUnmanage "DeleteAll" `
        -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None") `
        -Force
    } else {
        $virtualNetwork = New-AzResourceGroupDeploymentStack `
            -ResourceGroupName $resourceGroup.Outputs.name.value `
            -Name "Deploy-$ApplicationNameShort-VNET-$locationShort" `
            -TemplateFile "./network/spoke_vnet.bicep" `
            -TemplateParameterObject @{
                location = $Location
                name = $virtualNetworkName
                addressPrefix = $AddressPrefix
                tags = $Tags
                subnets = $subnetsObjectArray
                connectToHubNetwork = ($ConnectToHubNetwork ? $true : $false)
            } `
            -ActionOnUnmanage "DeleteAll" `
            -DenySettingsMode ($DenyManualChanges ? "DenyWriteAndDelete" : "None")
    }
    return $virtualNetwork

}
