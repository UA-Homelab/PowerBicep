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
    -DeployEntraPrivateAccess `
    -Force

Set-AzContext -Subscription $spokeVnet1SubscriptionId

$spokeVnet = New-PBSpokeVirtualNetwork `
    -Environment $environment `
    -Location $location `
    -AddressPrefix $spokeVnet1AddressPrefix `
    -ApplicationNameShort $spokeVnet1ApplicationNameShort `
    -Subnets $spokeVnet1Subnets `
    -Force