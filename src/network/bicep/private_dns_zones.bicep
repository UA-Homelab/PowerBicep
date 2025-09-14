param tags object
param privateDnsZoneNames array
param linkedVirtualNetworkIds string[]

resource privateDnsZonesRes 'Microsoft.Network/privateDnsZones@2020-06-01' = [for privateDnsZone in privateDnsZoneNames: {
  name: privateDnsZone
  location: 'global'
  tags: tags
}]


module privateDnsZoneVnetLink 'private_dns_zone_vnet_link.bicep' = [for privateDnsZone in privateDnsZoneNames: {
  name: 'vnet-links-${privateDnsZone}'
  params: {
    privateDnsZoneName: privateDnsZone
    linkedVirtualNetworkIds: linkedVirtualNetworkIds
  }
  dependsOn: [
    privateDnsZonesRes
  ]
}]
