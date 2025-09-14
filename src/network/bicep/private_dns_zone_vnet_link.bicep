param linkedVirtualNetworkIds string[]
param privateDnsZoneName string

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: privateDnsZoneName
}

resource privateDnsZoneNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for linkedVirtualNetworkId in linkedVirtualNetworkIds: {
  name: guid(linkedVirtualNetworkId, privateDnsZoneName)
  parent: privateDnsZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: linkedVirtualNetworkId
    }
    registrationEnabled: false
  }
}]
