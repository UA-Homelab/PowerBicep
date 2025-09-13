> ⚠️ **WARNING: Work In Progress**
>
> This repository is currently under active development. The documentation is incomplete and subject to change. Features, code, and instructions may not work as intended. Use at your own risk!

# PowerBicep PowerShell Module

This module enables you to leverage the advantages of deploying your infrastructure with Bicep, using your existing PowerShell skills.

## Table of Contents

- [PowerBicep PowerShell Module](#powerbicep-powershell-module)
- [Advantages](#advantages)
- [Installation](#installation)
    - [Prerequisities](#prerequisities)
    - [Instructions](#instructions)
- [Cmdlets](#network-cmdlets)
    - [Network](#network-cmdlets)
        - [New-PBIsolatedVirtualNetwork](#new-pbisolatedvirtualnetwork)
        - [New-PBSpokeVirtualNetwork](#new-pbspokevirtualnetwork)
        - [New-PBHubVirtualNetwork](#new-pbhubvirtualnetwork)
- [See Also](#see-also)

## Advantages
|                      |                 |
|-----------------------------------|-------------------------------------------------------------------------------------------|
| Simplicity        | Deploy complex Azure infrastructure using simple PowerShell commands.                                                |
| Comply with Microsoft best practices    | All templates are designed according to Microsoft best practices, using the Well-Architected Framework.              |
| No Bicep knowledge needed             |  You get the advantages of Bicep without having to learn a new language/skill          |
| Parameter minimization            | Commands automatically discover and use existing resources via Azure Resource Graph, reducing required parameters. |
| Protect against manual changes | This module uses deployment stacks and you can enable deny assignments to prevent manual changes. |

# Installation

## Prerequisities
- Azure PowerShell must be installed on your system. Please follow [these instructions](https://learn.microsoft.com/en-us/powershell/azure/install-azure-powershell?view=azps-14.4.0) to install it.
- Bicep CLI must be installed on your system. Please follow [these instructions](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install) to install it.
- Download or clone this repository to your device

## Instructions

1. Open PowerShell and navigate to the location of this repository on your local computer
    ```powershell
    cd <path to the downloaded PowerBicep folder>
    ```
2. Import the module

    ```powershell
    Import-Module ./PowerBicep.psm1
    ```

# Network cmdlets

## New-PBIsolatedVirtualNetwork

Creates an isolated virtual network with automated subnet allocation and input validation.

### Syntax

```powershell
New-PBIsolatedVirtualNetwork
    -ApplicationNameShort <string>
    -Environment <string>
    -Location <string>
    -AddressPrefix <string>
    [-Index <string>]
    [-Tags <object>]
    [-Subnets <hashtable>]
    [-DenyManualChanges]
    [-Force]
    [-AcceptOverlappingIpAddresses]
```

### Description

Creates an Azure virtual network without hub connection, automatically allocates subnets and checks if there are virtual networks with overlapping IP-Ranges.

### Parameters

| Name                        | Type      | Description                                                                                  | Required | Default         |
|-----------------------------|-----------|----------------------------------------------------------------------------------------------|----------|-----------------|
| ApplicationNameShort        | string    | Short name for the application                                                              | Yes      |                 |
| Environment                 | string    | Environment name (e.g., dev, prod)                                                          | Yes      |                 |
| Location                    | string    | Azure region  (e.g., westeurope, germanywestcentral)                                                                            | Yes      |                 |
| AddressPrefix               | string    | VNet address prefix (e.g., 192.168.0.0/24)                                                  | Yes      |                 |
| Index                       | string    | Resource index                                                                             | No       | '001'           |
| Tags                        | object    | Tags to apply to resources                                                                  | No       | @{}             |
| Subnets                     | hashtable | Subnet definitions using **name=size** (e.g., @{subnet1=26; subnet2=27})                                       | No       | @{}             |
| DenyManualChanges           | switch    | Deny manual changes to resources                                                            | No       |                 |
| Force                       | switch    | Ignores approval prompts                                                   | No       |                 |
| AcceptOverlappingIpAddresses| switch    | Allow the virtual networks address space to overlap with other virtual networks. <span style="color:red">**This may cause issues, if you decide to peer this network with the hub in the future!**</span>                                                                                | No       |                 |

### Examples
1. Create a virtual network without hub connection and two subnets named "subnet1" with a subnet size of 26 and "subnet2" with a subnet size of 27.
    ```powershell
    New-PBIsolatedVirtualNetwork -ApplicationNameShort 'app' -Environment 'test' -Location 'northeurope' -AddressPrefix '10.1.0.0/16' -Subnets @{subnet1=26; subnet2=27} -Verbose
    ```

## New-PBHubVirtualNetwork

Creates a hub virtual network with optional Azure Firewall, Bastion, VPN Gateway and advanced tagging.

### Syntax

```powershell
New-PBHubVirtualNetwork
    -ApplicationNameShort <string>
    -Environment <string>
    -Location <string>
    -AddressPrefix <string>
    [-Index <string>]
    [-Tags <object>]
    [-DenyManualChanges]
    [-Force]
    [-DeployAzureFirewall]
    [-AzureFirewallSku <string>]
    [-DeployAzureBastion]
    [-AzureBastionSku <string>]
    [-DeployAzureVpnGateway]
```

### Description

Creates a hub VNet in Azure, with options to deploy Azure Firewall, Bastion, VPN Gateway, and Entra Private Access. Automatically tags resources, allocates required subnets, and supports deployment stacks.

### Parameters

| Name                   | Type      | Description                                                                                  | Required | Default         |
|------------------------|-----------|----------------------------------------------------------------------------------------------|----------|-----------------|
| ApplicationNameShort   | string    | Short name for the application.                                                              | Yes      | 'hub'           |
| Environment            | string    | Environment name (e.g., dev, prod).                                                          | Yes      |                 |
| Location               | string    | Azure region.                                                                                | Yes      |                 |
| AddressPrefix          | string    | VNet address prefix (e.g., 10.0.0.0/16).                                                     | Yes      |                 |
| Index                  | string    | Resource index.                                                                              | No       | '001'           |
| Tags                   | object    | Tags to apply to resources.                                                                  | No       | @{}             |
| DenyManualChanges      | switch    | Deny manual changes to resources.                                                            | No       |                 |
| Force                  | switch    | Forces deployment using deployment stack.                                                    | No       |                 |
| DeployAzureFirewall    | switch    | Deploy Azure Firewall in the hub VNet.                                                       | No       |                 |
| AzureFirewallSku       | string    | Azure Firewall SKU ('Basic', 'Standard', 'Premium').                                         | No       |                 |
| DeployAzureBastion     | switch    | Deploy Azure Bastion in the hub VNet.                                                        | No       |                 |
| AzureBastionSku        | string    | Azure Bastion SKU ('Basic', 'Standard', 'Premium').                                          | No       | 'Basic'         |
| DeployAzureVpnGateway  | switch    | Deploy Azure VPN Gateway in the hub VNet.                                                    | No       |                 |

### Examples

1. Deploy a hub network with Azure Firewall
    ```powershell
    New-PBHubVirtualNetwork -Environment 'prod' -Location 'westeurope' -AddressPrefix '10.0.0.0/16' -DeployAzureFirewall -AzureFirewallSku 'Standard'
    ```
1. Deploy a hub network with Bastion
    ```powershell
    New-PBHubVirtualNetwork -Environment 'prod' -Location 'westeurope' -AddressPrefix '10.0.0.0/16' -DeployAzureBastion -AzureBastionSku 'Standard'
    ```

## New-PBSpokeVirtualNetwork

### Description

Creates an Azure virtual network with hub connection, automatically allocates subnets, detects overlapping IPs, and implements routing over the hubs NVA or (if no NVA is available) creates a NAT gateway for outbound internet access.

#### Routing

Creates a spoke virtual network with automated subnet allocation, hub connection, overlapping IP detectionand routing.

### Syntax

```powershell
New-PBSpokeVirtualNetwork
    -ApplicationNameShort <string>
    -Environment <string>
    -Location <string>
    -AddressPrefix <string>
    [-Index <string>]
    [-Tags <object>]
    [-Subnets <hashtable>]
    [-DenyManualChanges]
    [-Force]
    [-AcceptOverlappingIpAddresses]
    [-HubNetworkLocation <string>]
```



### Parameters

| Name                        | Type      | Description                                                                                  | Required | Default         |
|-----------------------------|-----------|----------------------------------------------------------------------------------------------|----------|-----------------|
| ApplicationNameShort        | string    | Short name for the application.                                                              | Yes      |                 |
| Environment                 | string    | Environment name (e.g., dev, prod).                                                          | Yes      |                 |
| Location                    | string    | Azure region.                                                                                | Yes      |                 |
| AddressPrefix               | string    | VNet address prefix (e.g., 192.168.0.0/24).                                                  | Yes      |                 |
| Index                       | string    | Resource index                                                                             | No       | '001'           |
| Tags                        | object    | Tags to apply to resources.                                                                  | No       | @{}             |
| Subnets                     | hashtable | Subnet definitions using **name=size** (e.g., @{subnet1=26; subnet2=27}).                    | No       | @{}             |
| DenyManualChanges           | switch    | Deny manual changes to resources.                                                            | No       |                 |
| Force                       | switch    | Forces deployment using deployment stack.                                                    | No       |                 |
| AcceptOverlappingIpAddresses| switch    | Allow the virtual networks address space to overlap with other virtual networks. <span style="color:red">**This will cause issues, if the overlapping network is already peered with the hub or if you decide to peer it in the future!**</span>                           | No       |                 |
| HubNetworkLocation          | string    | Location of the hub network if no hub is available in the spoke subnets region.                                        | No       |                 |

### Examples

1. Create a spoke network, that automatically connects to the available hub network in the same location
    ```powershell
    New-PBSpokeVirtualNetwork -ApplicationNameShort 'app' -Environment 'dev' -Location 'westeurope' -AddressPrefix '192.168.0.0/24' -Subnets @{subnet1=26; subnet2=27} -Verbose
    ```
2. Create a spoke network, that automatically connects to a hub network in another location
    ```powershell
    New-PBSpokeVirtualNetwork -ApplicationNameShort 'app' -Environment 'dev' -Location 'westeurope' -AddressPrefix '192.168.0.0/24' -Subnets @{subnet1=26; subnet2=27} -HubNetworkLocation 'germanywestcentral'
    ```





---

# See Also

- [Microsoft PowerShell Documentation](https://docs.microsoft.com/powershell/)
- [Azure PowerShell Reference](https://docs.microsoft.com/powershell/azure/)

---
