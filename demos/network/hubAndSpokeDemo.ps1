# This script demonstrates how to deploy a hub-and-spoke network topology using PowerBicep.
# It creates a hub network with Azure Firewall and Azure Bastion
# and spoke networks across multiple subscriptions with connection to the hub and routing over the firewall.

$location = "westeurope"
$environment = "dev"

$hubSubscriptionId = "025c998e-1f39-4344-89a5-4340c65b11bb"
$hubVnetAddressPrefix = "192.168.0.0/24"

$spokeVnet1SubscriptionId = "643c55c2-e49d-4895-bf82-54276b60839e"
$spokeVnet1AddressPrefix = "192.168.1.0/24"
$spokeVnet1ApplicationNameShort = "AppOne"
$spokeVnet1Subnets = @{
    snet1 = 26
    snet2 = 27
}

$spokeVnet2SubscriptionId = "643c55c2-e49d-4895-bf82-54276b60839e"
$spokeVnet2AddressPrefix = "192.168.2.0/24"
$spokeVnet2ApplicationNameShort = "AppTwo"
$spokeVnet2Subnets = @{
    snet1 = 26
    snet2 = 27
}

Connect-AzAccount

Set-AzContext -Subscription $hubSubscriptionId

$hubVnet = New-PBHubVirtualNetwork `
    -Environment $environment `
    -Location $location `
    -AddressPrefix $hubVnetAddressPrefix `
    -DeployAzureFirewall `
    -AzureFirewallSku 'Basic' `
    -DeployAzureBastion `
    -AzureBastionSku 'Basic' `
    -AzureFirewallAllowOutboundInternetAccess `
    -Force #-Verbose

Set-AzContext -Subscription $spokeVnet1SubscriptionId

$spokeVnet1 = New-PBSpokeVirtualNetwork `
    -Environment $environment `
    -Location $location `
    -AddressPrefix $spokeVnet1AddressPrefix `
    -ApplicationNameShort $spokeVnet1ApplicationNameShort `
    -Subnets $spokeVnet1Subnets `
    -Force #-Verbose

Set-AzContext -Subscription $spokeVnet2SubscriptionId

$spokeVnet2 = New-PBSpokeVirtualNetwork `
    -Environment $environment `
    -Location $location `
    -AddressPrefix $spokeVnet2AddressPrefix `
    -ApplicationNameShort $spokeVnet2ApplicationNameShort `
    -Subnets $spokeVnet2Subnets `
    -Force #-Verbose