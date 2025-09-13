targetScope = 'resourceGroup'

param location string = resourceGroup().location
param name string
param addressPrefix string
param tags object = {}
param subnets object[] = []
param nextHopType string = 'VirtualAppliance'
param nextHopDefaultRouteIP string
param customRoutes object[] = []
param hubVnetId string = ''
param hubHasVpnGateway bool
param dnsServers array = []

var hubResourceGroup = length(split(hubVnetId, '/')) >= 5 ? split(hubVnetId, '/')[4] : ''
var hubSubscriptionId = length(split(hubVnetId, '/')) >= 3 ? split(hubVnetId, '/')[2] : ''
var nsgName = 'default-nsg-${name}'
var routeTableName = 'default-rt-${name}'
var publicIpNatGatewayName = 'pip-natgw-${name}'
var natGatewayName = 'natgw-${name}'
var createRouteTable = (nextHopDefaultRouteIP != '') ? true : false

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: nsgName
  location: location
  properties: {}
}

resource routeTable 'Microsoft.Network/routeTables@2024-07-01' = if (createRouteTable) {
  name: routeTableName
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
  }
}

resource publicIpNatGateway 'Microsoft.Network/publicIPAddresses@2024-07-01' = if (!createRouteTable){
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

resource natGateway 'Microsoft.Network/natGateways@2024-07-01' = if (!createRouteTable) {
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

resource routeTableRoute 'Microsoft.Network/routeTables/routes@2024-07-01' = if (createRouteTable) {
  parent: routeTable
  name: 'default-route'
  properties: {
    addressPrefix: '0.0.0.0/0'
    nextHopType: nextHopType
    nextHopIpAddress: nextHopDefaultRouteIP
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
    dhcpOptions: {
      dnsServers: dnsServers
    }
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [for subnet in subnets: {
      name: subnet.name
      properties: {
        addressPrefix: subnet.addressPrefix
        routeTable: (createRouteTable) ? {
          id: routeTable.id
        } : null
        networkSecurityGroup: {
          id: networkSecurityGroup.id
        }
        natGateway: (!createRouteTable) ? {
          id: natGateway.id
        } : null
      }
    }]
  }
}

module vnetPeeringToHub 'peering.bicep' = {
  name: 'Deploy-Peering-1'
  params: {
    peeringName: 'peering-to-hub-${location}'
    sourceVirtualNetworkName: name
    remoteVirtualNetworkId: hubVnetId
    allowGatewayTransit: false
    useRemoteGateways: hubHasVpnGateway
  }
  dependsOn: [
    virtualNetwork
  ]
}

module vnetPeeringFromHub 'peering.bicep' =  {
  name: 'Deploy-Peering-2'
  scope: resourceGroup(hubSubscriptionId, hubResourceGroup)
  params: {
    peeringName: 'peering-to-${name}'
    sourceVirtualNetworkName: last(split(hubVnetId, '/'))
    remoteVirtualNetworkId: virtualNetwork.id
    allowGatewayTransit: hubHasVpnGateway
    useRemoteGateways: false
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
output routeTableId string = createRouteTable ? routeTable.id : ''
output routeTableName string = createRouteTable ? routeTable.name : ''
output networkSecurityGroupId string = networkSecurityGroup.id
output networkSecurityGroupName string = networkSecurityGroup.name
output natGatewayId string = !createRouteTable ? natGateway.id : ''
output natGatewayName string = !createRouteTable ? natGateway.name : ''
output publicIpNatGatewayId string = !createRouteTable ? publicIpNatGateway.id : ''
output publicIpNatGatewayName string = !createRouteTable ? publicIpNatGateway.name : ''

