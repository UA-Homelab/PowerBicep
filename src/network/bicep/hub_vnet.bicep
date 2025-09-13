targetScope = 'resourceGroup'

param location string = resourceGroup().location
param name string
param addressPrefix string
param tags object = {}
param subnets object[] = []

param deployAzureFirewall bool
param azureFirewallSku string
param allowOutboundInternetAccess bool
param natRuleCollections array = []
param networkRuleCollections array = []
param applicationRuleCollections array = []
param customDnsServers array = []

param deployAzureBastion bool
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param bastionSku string = 'Standard'
// param deployAzureVpnGateway bool

var bastionNsgName = 'nsg-AzureBastionSubnet-${name}'
var bastionName = 'bastion-${name}'
var bastionPublicIpName = 'pip-${bastionName}'
var bastionSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', name, 'AzureBastionSubnet')


var azureFirewallName = 'fw-${name}'
var azureFirewallPublicIpName = 'pip-${azureFirewallName}'
var azureFirewallManagementPublicIpName = 'pip-mgmt-${azureFirewallName}'
var azureFirewallPolicyName = 'policy-${azureFirewallName}'
var azureFirewallSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', name, 'AzureFirewallSubnet')
var azureFirewallManagementSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', name, 'AzureFirewallManagementSubnet')
var microsoftKvmIps = [
  '20.118.99.224'
  '40.83.235.53'
  '23.102.135.246' 
]

var azureFirewallApplicationRuleCollectionInternetAccess = {
  ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
  action: {
    type: 'Allow'
  }
  name: 'InternetAccess'
  priority: 1000
  rules: [
    {
      ruleType: 'ApplicationRule'
      name: 'Allow443ToAnyFqdn'
      protocols: [
        {
          protocolType: 'Https'
          port: 443
        }
      ]
      targetFqdns: [
        '*'
      ]
      sourceAddresses: [
        '*'
      ]
    }
  ]
}

var azureFirewallNetworkRuleCollectionNecessaryServices = {
  ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
  action: {
    type: 'Allow'
  }
  name: 'NecessaryServices'
  priority: 1000
  rules: [
    {
      ruleType: 'NetworkRule'
      name: 'Allow1688ToMicrosoftKMS'
      ipProtocols: [
        'TCP'
      ]
      destinationAddresses: microsoftKvmIps

      sourceAddresses: [
        '*'
      ]
      destinationPorts: [
        '1688'
      ]
    }
  ]
}

var azureFirewallNetworkRuleCollections = networkRuleCollections != [] ? flatten([
  networkRuleCollections
  [azureFirewallNetworkRuleCollectionNecessaryServices]
]) : [
  azureFirewallNetworkRuleCollectionNecessaryServices
]

var azureFirewallApplicationRuleCollections = (applicationRuleCollections != [] && allowOutboundInternetAccess) ? flatten([
  applicationRuleCollections
  [azureFirewallApplicationRuleCollectionInternetAccess]
]) : allowOutboundInternetAccess ? [
  azureFirewallApplicationRuleCollectionInternetAccess
] : []


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

resource publicIpFirewall 'Microsoft.Network/publicIPAddresses@2024-07-01' = if (deployAzureFirewall) {
  name: azureFirewallPublicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

resource publicIpFirewallManagement 'Microsoft.Network/publicIPAddresses@2024-07-01' = if (deployAzureFirewall) {
  name: azureFirewallManagementPublicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2021-05-01' = if (deployAzureFirewall) {
  name: azureFirewallPolicyName
  location: location
  properties: {
    dnsSettings: (azureFirewallSku == 'Premium' || azureFirewallSku == 'Standard') ? {
      enableProxy: true
      servers: (customDnsServers != []) ? customDnsServers : ['168.63.129.16']
    } : {}
    sku: {
      tier: azureFirewallSku
    }
  }
}

resource natRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-01-01' = if (deployAzureFirewall) {
  parent: firewallPolicy
  name: 'DefaultNatRuleCollectionGroup'
  properties: {
    priority: 200
    ruleCollections: natRuleCollections
  }
}

resource networkRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-01-01' = if (deployAzureFirewall) {
  parent: firewallPolicy
  name: 'DefaultNetworkRuleCollectionGroup'
  dependsOn: [
    natRuleCollectionGroup
  ]
  properties: {
    priority: 300
    ruleCollections: azureFirewallNetworkRuleCollections
  }
}

resource applicationRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-01-01' = if (deployAzureFirewall) {
  parent: firewallPolicy
  name: 'DefaultApplicationRuleCollectionGroup'
  dependsOn: [
    networkRuleCollectionGroup
  ]
  properties: {
    priority: 400
    ruleCollections: azureFirewallApplicationRuleCollections
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2021-05-01' = if (deployAzureFirewall) {
  name: azureFirewallName
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: azureFirewallSku
    }    
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: azureFirewallSubnetId
          }
          publicIPAddress: {
            id: publicIpFirewall.id
          }
        }
      }
    ]
    managementIpConfiguration: {
      name: 'ipconfigManagement'
      properties: {
        publicIPAddress: {
          id: publicIpFirewallManagement.id
        }
        subnet: {
          id: azureFirewallManagementSubnetId
        }
      }
    }
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
output bastionId string = deployAzureBastion ? bastionHost.id : ''
output bastionName string = deployAzureBastion ? bastionHost.name : ''
output azureFirewallId string = deployAzureFirewall ? firewall.id : ''
output azureFirewallName string = deployAzureFirewall ? firewall.name : ''
output azureFirewallPrivateIp string = deployAzureFirewall ? firewall.properties.ipConfigurations[0].properties.privateIPAddress : ''

