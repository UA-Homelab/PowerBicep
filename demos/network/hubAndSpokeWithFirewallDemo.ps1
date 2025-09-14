# This script demonstrates how to deploy a hub-and-spoke network topology using PowerBicep.
# It creates a hub network with Azure Firewall and Azure Bastion
# and spoke networks across multiple subscriptions with connection to the hub and routing over the firewall.

$location = "westeurope"
$environment = "dev"

$hubSubscriptionId = "025c998e-1f39-4344-89a5-4340c65b11bb"
$hubVnetAddressPrefix = "192.168.0.0/24"

$hubVnet2SubscriptionId = "025c998e-1f39-4344-89a5-4340c65b11bb"
$hubVnet2AddressPrefix = "192.168.1.0/24"
$hubVnet2Location = "northeurope"

$spokeVnet1SubscriptionId = "643c55c2-e49d-4895-bf82-54276b60839e"
$spokeVnet1AddressPrefix = "192.168.10.0/24"
$spokeVnet1ApplicationNameShort = "AppOne"
$spokeVnet1Subnets = @{
    snet1 = 26
    snet2 = 27
}

$spokeVnet2SubscriptionId = "025c998e-1f39-4344-89a5-4340c65b11bb"
$spokeVnet2AddressPrefix = "192.168.20.0/24"
$spokeVnet2ApplicationNameShort = "AppTwo"
$spokeVnet2Subnets = @{
    snet1 = 28
    snet2 = 27
    snet3 = 26
    snet4 = 28
}

Connect-AzAccount

Set-AzContext -Subscription $hubSubscriptionId

$hubVnet = New-PBHubVirtualNetwork `
    -Environment $environment `
    -Location $location `
    -AddressPrefix $hubVnetAddressPrefix `
    -DeployAzureFirewall `
    -AzureFirewallSku 'Standard' `
    -DeployAzureBastion `
    -AzureBastionSku 'Standard' `
    -AzureFirewallAllowOutboundInternetAccess `
    -Force

Set-AzContext -Subscription $hubVnet2SubscriptionId

$hubVnet2 = New-PBHubVirtualNetwork `
    -Environment $environment `
    -Location $hubVnet2Location `
    -AddressPrefix $hubVnet2AddressPrefix `
    -AzureFirewallAllowOutboundInternetAccess `
    -Force

Set-AzContext -Subscription $spokeVnet1SubscriptionId

$spokeVnet1 = New-PBSpokeVirtualNetwork `
    -Environment $environment `
    -Location $location `
    -AddressPrefix $spokeVnet1AddressPrefix `
    -ApplicationNameShort $spokeVnet1ApplicationNameShort `
    -Subnets $spokeVnet1Subnets `
    -Force

Set-AzContext -Subscription $spokeVnet2SubscriptionId

$spokeVnet2 = New-PBSpokeVirtualNetwork `
    -Environment $environment `
    -Location $location `
    -AddressPrefix $spokeVnet2AddressPrefix `
    -ApplicationNameShort $spokeVnet2ApplicationNameShort `
    -Subnets $spokeVnet2Subnets `
    -Force -Verbose