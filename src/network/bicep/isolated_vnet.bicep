targetScope = 'resourceGroup'

param location string = resourceGroup().location
param name string
param addressPrefix string
param tags object = {}
param subnets object[] = []

var nsgName = 'default-nsg-${name}'
var publicIpNatGatewayName = 'pip-natgw-${name}'
var natGatewayName = 'natgw-${name}'

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: nsgName
  location: location
  properties: {}
}

resource publicIpNatGateway 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
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

resource natGateway 'Microsoft.Network/natGateways@2024-07-01' = {
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
        networkSecurityGroup: {
          id: networkSecurityGroup.id
        }
        natGateway: {
          id: natGateway.id
        }
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
output networkSecurityGroupId string = networkSecurityGroup.id
output natGatewayId string = natGateway.id
output publicIpNatGatewayId string = publicIpNatGateway.id
output publicIpNatGatewayName string = publicIpNatGateway.name
output natGatewayName string = natGateway.name
output networkSecurityGroupName string = networkSecurityGroup.name
