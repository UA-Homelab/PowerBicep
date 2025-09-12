# This script deploys an isolated vnet without hub connectivity.

$subscriptionId = "025c998e-1f39-4344-89a5-4340c65b11bb"
$location = "westeurope"
$environment = "dev"
$isolatedVnetAddressPrefix = "192.168.10.0/24"
$isolatedVnetApplicationNameShort = "isolated"
$isolatedVnetSubnets = @{
    snet1 = 28
    snet2 = 27
    snet3 = 29
    snet4 = 29
}

Connect-AzAccount

Set-AzContext -Subscription $subscriptionId

New-PBIsolatedVirtualNetwork `
    -ApplicationNameShort $isolatedVnetApplicationNameShort `
    -Environment $environment `
    -Location $location `
    -AddressPrefix $isolatedVnetAddressPrefix `
    -Subnets $isolatedVnetSubnets `
    -Force