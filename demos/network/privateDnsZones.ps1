$location = "westeurope"
$environment = "dev"

New-PBPrivateDnsZone `
    -All `
    -LinkToHub `
    -Environment $environment `
    -Location $location `
    -DenyManualChanges `
    -Force