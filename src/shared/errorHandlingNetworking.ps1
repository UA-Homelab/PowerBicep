function Test-IpAddress {
    param (
        [string]$IpAddress
    )

    if ($IpAddress -notmatch '^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$') {
        throw "IP Address '$IpAddress' is invalid. Please provide a valid IP address."
    }

    return $true
}

function Test-SubnetMask {
    param (
        [string]$SubnetMask
    )

    if ($subnetMask -notmatch '^(?:[2-9]|1[0-9]|2[0-9])$') {
        throw "Subnet mask '$subnetMask' is invalid. Must be an integer between 2 and 29."
    }

    return $true
}

function Test-OverlappingIpAddressPrefixes {
    param (
        [string]$AddressPrefix,
        [string]$VirtualNetworkName
    )

    Write-Verbose "Checking for overlapping VNets with Address Prefix '$AddressPrefix'"
    $overlappingVirtualNetworks = Search-AzGraph -Query "resources
        | where type == 'microsoft.network/virtualnetworks'
        | where name != '$VirtualNetworkName'
        | where properties.addressSpace.addressPrefixes contains '$AddressPrefix'"

    if ($null -ne $overlappingVirtualNetworks.name) {
        throw "The Address Space of '$($overlappingVirtualNetworks.name)' overlaps with '$AddressPrefix'. Please choose a different address prefix. Or use the -AcceptOverlappingIpAddresses switch to allow overlapping IP addresses. This will cause errors, if you try to connect more than one overlapping network to the hub!"
    }

    return $true
}

function Test-SubnetConfiguration {
    param (
        [hashtable]$Subnets
    )

    foreach ($subnet in $Subnets.GetEnumerator()) {
        $subnetName = $subnet.Key
        $subnetMask = $subnet.Value

        if ($subnetName -notmatch '^[a-zA-Z0-9\-_]+$') {
            throw "Subnet name '$subnetName' is invalid. Only letters, numbers, '-' and '_' are allowed."
        }
        try {
            $testSubnetMask =  Test-SubnetMask -SubnetMask $subnetMask
        } catch {
            throw "Subnet mask '$subnetMask' for subnet '$subnetName' is invalid. Must be an integer between 2 and 29."
        }
    }

    return $true
}

function Test-VirtualNetworkAddressPrefix {
    param (
        [string]$AddressPrefix
    )

    $ip = $AddressPrefix.Split('/')[0]
    $subnetMask = $AddressPrefix.Split('/')[1]

    try {
        $testIpAddress = Test-IpAddress -IpAddress $ip
        $testSubnetMask =  Test-SubnetMask -SubnetMask $subnetMask
    } catch {
        throw "Virtual Network Address Prefix '$AddressPrefix' is invalid. Please provide a valid IP range in CIDR format."
    }

    return $true
}

