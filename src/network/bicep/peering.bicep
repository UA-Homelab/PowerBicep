param peeringName string
param sourceVirtualNetworkName string
param remoteVirtualNetworkId string
param allowGatewayTransit bool
param useRemoteGateways bool

resource existingSourceVirtualNetwork 'Microsoft.Network/virtualNetworks@2020-07-01' existing = {
  name: sourceVirtualNetworkName
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2020-07-01' = {
  parent: existingSourceVirtualNetwork
  name: peeringName
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: useRemoteGateways
    remoteVirtualNetwork: {
      id: remoteVirtualNetworkId
    }
  }
}

output peeringId string = peering.id
output peeringNameOutput string = peering.name
output peeringProperties object = peering.properties
output sourceVirtualNetworkId string = existingSourceVirtualNetwork.id
output sourceVirtualNetworkNameOutput string = existingSourceVirtualNetwork.name
output sourceVirtualNetworkProperties object = existingSourceVirtualNetwork.properties
output remoteVirtualNetworkId string = peering.properties.remoteVirtualNetwork.id
