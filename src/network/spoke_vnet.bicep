targetScope = 'resourceGroup'

param location string = resourceGroup().location
param name string
param addressPrefix string
param tags object = {}
param subnets object[] = []
param nextHopType string = nextHopDefaultRouteIP != '' ? 'VirtualAppliance' : 'Internet'
param nextHopDefaultRouteIP string = ''
param customRoutes object[] = []
param connectToHubNetwork bool

var nsgName = 'default-nsg-${name}'
var routeTableName = 'default-rt-${name}'
var publicIpNatGatewayName = 'pip-natgw-${name}'
var natGatewayName = 'natgw-${name}'

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: nsgName
  location: location
  properties: {}
}

resource routeTable 'Microsoft.Network/routeTables@2024-07-01' = {
  name: routeTableName
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
  }
}

resource publicIpNatGateway 'Microsoft.Network/publicIPAddresses@2024-07-01' = if (!connectToHubNetwork) {
  name: publicIpNatGatewayName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    dnsSettings: {
      domainNameLabel: toLower(replace('pip-natgw-${name}', '_', '-'))
    }
  }
}

resource natGateway 'Microsoft.Network/natGateways@2024-07-01' = if (!connectToHubNetwork) {
  name: natGatewayName
  location: location
  sku: {
      name: 'Standard'
    }
  properties: {
    publicIpAddresses: [
      {
        id: publicIpNatGateway.id
      }
    ]
  }
}

resource routeTableRoute 'Microsoft.Network/routeTables/routes@2024-07-01' = {
  parent: routeTable
  name: 'default-route'
  properties: nextHopDefaultRouteIP != '' ? {
    addressPrefix: '0.0.0.0/0'
    nextHopType: nextHopType
    nextHopIpAddress: nextHopDefaultRouteIP
  } : {
    addressPrefix: '0.0.0.0/0'
    nextHopType: 'Internet'
  }
}

resource routeTableCustomRoute 'Microsoft.Network/routeTables/routes@2024-07-01' = [for customRoute in customRoutes: {
  parent: routeTable
  name: customRoute.name
  properties: (customRoute.nextHopIpAddress != '') ? {
    addressPrefix: customRoute.addressPrefix
    nextHopType: customRoute.nextHopType
    nextHopIpAddress: customRoute.nextHopIpAddress
  } : {
    addressPrefix: customRoute.addressPrefix
    nextHopType: customRoute.nextHopType
  }
}]

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [for subnet in subnets: {
      name: subnet.name
      properties: {
        addressPrefix: subnet.addressPrefix
        routeTable: {
          id: routeTable.id
        }
        networkSecurityGroup: {
          id: networkSecurityGroup.id
        }
        natGateway: !connectToHubNetwork ? {
          id: natGateway.id
        } : null
      }
    }]
  }
}

output id string = virtualNetwork.id
output name string = virtualNetwork.name
output addressPrefixes array = virtualNetwork.properties.addressSpace.addressPrefixes
output location string = virtualNetwork.location
output resourceGroupName string = resourceGroup().name
output subscriptionId string = subscription().id
output tags object = virtualNetwork.tags
output subnets array = virtualNetwork.properties.subnets
output routeTable object = {
  id: routeTable.id
  name: routeTable.name
  location: routeTable.location
  tags: routeTable.tags
}
