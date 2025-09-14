param location string = resourceGroup().location
param storageAccountName string
param storageAccountKind string = 'StorageV2'
param storageAccountSku string = 'Standard_LRS'

param allowSharedKeyAccess bool = true
@allowed(['None', 'Logging', 'Metrics', 'AzureServices'])
param networkAclBypass string

param subnetId string
param privateLinkGroupIds string[] = [
  'blob'
  'file'
  'queue'
  'table'
]
param privateDnsZoneId string

var allowBlobPublicAccess = false
var denyPublicNetworkAccess = true
var privateEndpointName = 'pe-${storageAccountName}'
var networkAclsDefaultAction = denyPublicNetworkAccess ? 'Deny' : 'Allow'

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-02-01' = {
  name: storageAccountName
  location: location
  kind: storageAccountKind
  sku: {
    name: storageAccountSku
  }
  properties: {
    allowBlobPublicAccess: allowBlobPublicAccess
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
    networkAcls: {
      bypass: networkAclBypass 
      defaultAction: networkAclsDefaultAction
      virtualNetworkRules: []
      ipRules: []
      resourceAccessRules: []
    }
    allowSharedKeyAccess: allowSharedKeyAccess
    largeFileSharesState: 'Disabled'

  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: privateLinkGroupIds
        }
      }
    ]
  }
}

resource privateEndpointDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
  name: 'privateDns'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [ for privateLinkGroupId in privateLinkGroupIds: {
        name: privateLinkGroupId
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}
