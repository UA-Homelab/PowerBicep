targetScope = 'resourceGroup'

param location string = resourceGroup().location
param name string
param addressPrefix string
param tags object = {}
param subnets object[] = []

param deployAzureFirewall bool
param azureFirewallSku string

param deployAzureBastion bool
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param bastionSku string = 'Standard'
param deployEntraPrivateAccess bool
param deployAzureVpnGateway bool

var bastionNsgName = 'nsg-AzureBastionSubnet-${name}'
var bastionPublicIpName = 'pip-bastion-${name}'
var bastionName = 'bastion-${name}'
var bastionSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', name, 'AzureBastionSubnet')

resource bastionNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: bastionNsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttpsInbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowGatewayManagerInbound'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          priority: 140
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionHostCommunication'
        properties: {
          priority: 150
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['8080','5701']
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'AllowSshRdpOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['22','3389']
        }
      }
      {
        name: 'AllowAzureCloudOutbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionCommunication'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['8080', '5701']
        }
      }
      {
        name: 'AllowHttpOutbound'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '80'
        }
      }
      {
        name: 'DenyAllOutbound'
        properties: {
          priority: 4096
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [for subnet in subnets: {
      name: subnet.name
      properties: (subnet.name == 'AzureBastionSubnet') ? {
        addressPrefix: subnet.addressPrefix
        networkSecurityGroup: {
          id: bastionNetworkSecurityGroup.id
        }
      } : {
        addressPrefix: subnet.addressPrefix
      }
    }]
  }
}

resource publicIpBastion 'Microsoft.Network/publicIPAddresses@2024-07-01' = if (deployAzureBastion) {
  name: bastionPublicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2024-07-01' =  if (deployAzureBastion)  {
  name: bastionName
  location: location
  tags: tags
  sku: {
    name: bastionSku
  }
  properties: {
    ipConfigurations: [{
      name: 'bastionIpConfig'
      properties: {
        subnet: {
          id: bastionSubnetId
        }
        publicIPAddress: {
          id: publicIpBastion.id
        }
      }
    }]
  }
  dependsOn: [
    bastionNetworkSecurityGroup
  ]
}

output id string = virtualNetwork.id
output name string = virtualNetwork.name
output addressPrefixes array = virtualNetwork.properties.addressSpace.addressPrefixes
output location string = virtualNetwork.location
output resourceGroupName string = resourceGroup().name
output subscriptionId string = subscription().id
output tags object = virtualNetwork.tags
output subnets array = virtualNetwork.properties.subnets
output firewallPrivateIp string = '192.168.0.196'
