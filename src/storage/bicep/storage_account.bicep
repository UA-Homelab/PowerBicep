param location string = resourceGroup().location
param storageAccountName string
param storageAccountKind string = 'StorageV2'
param storageAccountSku string = 'Standard_LRS'
param privateEndpointName string = 'pe-${storageAccountName}'
param subnetId string
param privateLinkGroupId string
param privateDnsZoneId string


resource storageaccount 'Microsoft.Storage/storageAccounts@2021-02-01' = {
  name: 'name'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Premium_LRS'
  }
}
