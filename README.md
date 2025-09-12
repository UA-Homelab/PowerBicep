> ⚠️ **WARNING: Work In Progress**
>
> This repository is currently under active development. The documentation is incomplete and subject to change. Features, code, and instructions may not work as intended. Use at your own risk!

# PowerBicep PowerShell Module

The **PowerBicep** module provides advanced functions for deploying and managing Azure resources using Bicep templates, including automated subnet allocation, hub-spoke network topologies, and more.

## Module Overview

| Name         | Description                                                                 |
|--------------|-----------------------------------------------------------------------------|
| PowerBicep   | Automates Azure resource deployments, subnet allocation, hub-spoke peering, and extensible infra management. |

## Installation

```powershell
Import-Module ./PowerBicep.psm1
```

## Cmdlets

### New-PBIsolatedVirtualNetwork

Creates an isolated virtual network with automated subnet allocation and input validation.

#### Syntax

```powershell
New-PBIsolatedVirtualNetwork
    -ApplicationNameShort <string>
    -Environment <string>
    -Location <string>
    -AddressPrefix <string>
    [-Index <string>]
    [-Tags <object>]
    [-Subnets <hashtable>]
    [-NamingConventionOption <int>]
    [-DenyManualChanges]
    [-Force]
    [-AcceptOverlappingIpAddresses]
```

#### Description

Creates an isolated VNet in Azure, allocates subnets from the specified address prefix, and performs input validation for all parameters. Supports deployment stacks and advanced scenarios.

#### Parameters

| Name                        | Type      | Description                                                                                  | Required | Default         |
|-----------------------------|-----------|----------------------------------------------------------------------------------------------|----------|-----------------|
| ApplicationNameShort        | string    | Short name for the application.                                                              | Yes      |                 |
| Environment                 | string    | Environment name (e.g., dev, prod).                                                          | Yes      |                 |
| Location                    | string    | Azure region.                                                                                | Yes      |                 |
| AddressPrefix               | string    | VNet address prefix (e.g., 192.168.0.0/24).                                                  | Yes      |                 |
| Index                       | string    | Resource index.                                                                              | No       | '001'           |
| Tags                        | object    | Tags to apply to resources.                                                                  | No       | @{}             |
| Subnets                     | hashtable | Subnet definitions (e.g., @{subnet1=26; subnet2=27}).                                       | No       | @{}             |
| NamingConventionOption      | int       | Naming convention option.                                                                    | No       | 1               |
| DenyManualChanges           | switch    | Deny manual changes to resources.                                                            | No       |                 |
| Force                       | switch    | Forces deployment using deployment stack.                                                    | No       |                 |
| AcceptOverlappingIpAddresses| switch    | Allow overlapping IP address spaces.                                                         | No       |                 |

#### Examples

```powershell
New-PBIsolatedVirtualNetwork -ApplicationNameShort 'app' -Environment 'test' -Location 'northeurope' -AddressPrefix '10.1.0.0/16' -Subnets @{subnet1=26; subnet2=27} -Verbose
```

---

### New-PBSpokeVirtualNetwork

Creates a spoke virtual network with automated subnet allocation, hub connection, overlapping IP detection, and advanced routing options.

#### Syntax

```powershell
New-PBSpokeVirtualNetwork
    -ApplicationNameShort <string>
    -Environment <string>
    -Location <string>
    -AddressPrefix <string>
    [-Tags <object>]
    [-Subnets <hashtable>]
    [-NamingConventionOption <int>]
    [-ConnectToHubNetwork]
    [-NextHopDefaultRouteIP <string>]
    [-NextHopType <string>]
    [-DenyManualChanges]
    [-Force]
    [-AcceptOverlappingIpAddresses]
    [-HubNetworkLocation <string>]
```

#### Description

Creates a spoke VNet in Azure, allocates subnets from the specified address prefix, detects overlapping IPs, and optionally connects to a hub VNet with custom routing. Supports deployment stacks and advanced peering scenarios.

#### Parameters

| Name                        | Type      | Description                                                                                  | Required | Default         |
|-----------------------------|-----------|----------------------------------------------------------------------------------------------|----------|-----------------|
| ApplicationNameShort        | string    | Short name for the application.                                                              | Yes      |                 |
| Environment                 | string    | Environment name (e.g., dev, prod).                                                          | Yes      |                 |
| Location                    | string    | Azure region.                                                                                | Yes      |                 |
| AddressPrefix               | string    | VNet address prefix (e.g., 192.168.0.0/24).                                                  | Yes      |                 |
| Tags                        | object    | Tags to apply to resources.                                                                  | No       | @{}             |
| Subnets                     | hashtable | Subnet definitions (e.g., @{subnet1=26; subnet2=27}).                                       | No       | @{}             |
| NamingConventionOption      | int       | Naming convention option.                                                                    | No       | 1               |
| ConnectToHubNetwork         | switch    | Connects the spoke VNet to a hub VNet.                                                      | No       |                 |
| NextHopDefaultRouteIP       | string    | Next hop IP for default route (required if ConnectToHubNetwork is set).                      | Cond.    |                 |
| NextHopType                 | string    | Next hop type for routing.                                                                  | No       | VirtualAppliance|
| DenyManualChanges           | switch    | Deny manual changes to resources.                                                            | No       |                 |
| Force                       | switch    | Forces deployment using deployment stack.                                                    | No       |                 |
| AcceptOverlappingIpAddresses| switch    | Allow overlapping IP address spaces.                                                         | No       |                 |
| HubNetworkLocation          | string    | Location of the hub network for cross-region peering.                                        | No       |                 |

#### Examples

```powershell
New-PBSpokeVirtualNetwork -ApplicationNameShort 'app' -Environment 'dev' -Location 'westeurope' -AddressPrefix '192.168.0.0/24' -Subnets @{subnet1=26; subnet2=27} -Verbose
```

```powershell
New-PBSpokeVirtualNetwork -ApplicationNameShort 'app' -Environment 'dev' -Location 'westeurope' -AddressPrefix '192.168.0.0/24' -Subnets @{subnet1=26; subnet2=27} -ConnectToHubNetwork -NextHopDefaultRouteIP '192.168.0.4' -HubNetworkLocation 'northeurope'
```

---

### New-PBHubVirtualNetwork

Creates a hub virtual network with optional Azure Firewall, Bastion, VPN Gateway, Entra Private Access, and advanced tagging.

#### Syntax

```powershell
New-PBHubVirtualNetwork
    -ApplicationNameShort <string>
    -Environment <string>
    -Location <string>
    -AddressPrefix <string>
    [-Index <string>]
    [-Tags <object>]
    [-NamingConventionOption <int>]
    [-DenyManualChanges]
    [-Force]
    [-DeployAzureFirewall]
    [-AzureFirewallSku <string>]
    [-DeployAzureBastion]
    [-AzureBastionSku <string>]
    [-DeployEntraPrivateAccess]
    [-DeployAzureVpnGateway]
```

#### Description

Creates a hub VNet in Azure, with options to deploy Azure Firewall, Bastion, VPN Gateway, and Entra Private Access. Automatically tags resources, allocates required subnets, and supports deployment stacks.

#### Parameters

| Name                   | Type      | Description                                                                                  | Required | Default         |
|------------------------|-----------|----------------------------------------------------------------------------------------------|----------|-----------------|
| ApplicationNameShort   | string    | Short name for the application.                                                              | Yes      | 'hub'           |
| Environment            | string    | Environment name (e.g., dev, prod).                                                          | Yes      |                 |
| Location               | string    | Azure region.                                                                                | Yes      |                 |
| AddressPrefix          | string    | VNet address prefix (e.g., 10.0.0.0/16).                                                     | Yes      |                 |
| Index                  | string    | Resource index.                                                                              | No       | '001'           |
| Tags                   | object    | Tags to apply to resources.                                                                  | No       | @{}             |
| NamingConventionOption | int       | Naming convention option.                                                                    | No       | 1               |
| DenyManualChanges      | switch    | Deny manual changes to resources.                                                            | No       |                 |
| Force                  | switch    | Forces deployment using deployment stack.                                                    | No       |                 |
| DeployAzureFirewall    | switch    | Deploy Azure Firewall in the hub VNet.                                                       | No       |                 |
| AzureFirewallSku       | string    | Azure Firewall SKU ('Basic', 'Standard', 'Premium').                                         | No       |                 |
| DeployAzureBastion     | switch    | Deploy Azure Bastion in the hub VNet.                                                        | No       |                 |
| AzureBastionSku        | string    | Azure Bastion SKU ('Basic', 'Standard', 'Premium').                                          | No       | 'Basic'         |
| DeployEntraPrivateAccess| switch   | Deploy Entra Private Access in the hub VNet.                                                 | No       |                 |
| DeployAzureVpnGateway  | switch    | Deploy Azure VPN Gateway in the hub VNet.                                                    | No       |                 |

#### Examples

```powershell
New-PBHubVirtualNetwork -Environment 'prod' -Location 'westeurope' -AddressPrefix '10.0.0.0/16' -DeployAzureFirewall -AzureFirewallSku 'Standard' -Verbose
```

---

## See Also

- [Microsoft PowerShell Documentation](https://docs.microsoft.com/powershell/)
- [Azure PowerShell Reference](https://docs.microsoft.com/powershell/azure/)

---
