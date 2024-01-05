param baseName string
param location string = resourceGroup().location

@secure()
param defaultVmPassword string

param vmAdminUserName string = 'azureuser'

var vnetName = 'sl-vnet'
var vnetAddressPrefix = '10.0.0.0/16'

// Default subnet is where VMs will be created for testing on
var defaultSubnetName = 'default'
var defaultSubnetPrefix = '10.0.0.0/24'

// Proxy subnet is where the proxy VM will be created that traffic in the default subnet will be routed through
var proxySubnetName = 'proxy'
var proxySubnetPrefix = '10.0.1.0/24'

var proxyVmName = 'proxy-vm-${baseName}'
var proxyVmSize = 'Standard_D4s_v3'
var proxyVmIpAddress = '10.0.1.4'

var defaultVmName = 'vm-${baseName}'
var defaultVmSize = 'Standard_D4s_v3'
var defaultVmIpAddress = '10.0.0.4'

////////////////////////////////////////////////////////////////////////////////////////////////
//
// Virtual Network

resource defaultNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: defaultSubnetName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttpToProxy'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: proxySubnetPrefix
          destinationPortRanges: [ '80', '443', '3128' ] // 3128 is squid proxy
          access: 'Allow'
          direction: 'Outbound'
          description: 'Allow HTTP to Proxy'
        }
      }
      // TODO - could probably just set a DenyAllOutbound instead of Http/Https explicityly?
      {
        name: 'DenyHttpOutbound'
        properties: {
          priority: 1100
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
          access: 'Deny'
          direction: 'Outbound'
          description: 'Deny HTTP Outbound'
        }
      }
      {
        name: 'DenyHttpsOutbound'
        properties: {
          priority: 1101
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          access: 'Deny'
          direction: 'Outbound'
          description: 'Deny HTTPS Outbound'
        }
      }
    ]
  }
}

resource proxyNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: proxySubnetName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttpxInbound'
        properties: {
          priority: 1001
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [ '80', '443', '3128' ] // 3128 is squid proxy
          access: 'Allow'
          direction: 'Inbound'
          description: 'Allow HTTP(S) Inbound'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: defaultSubnetName
        properties: {
          addressPrefix: defaultSubnetPrefix
          networkSecurityGroup: {
            id: defaultNetworkSecurityGroup.id
          }
        }
      }
      { 
        name: proxySubnetName
        properties: {
          addressPrefix: proxySubnetPrefix
          networkSecurityGroup: {
            id: proxyNetworkSecurityGroup.id
          }
        }
      }
    ]
  }

}

////////////////////////////////////////////////////////////////////////////////////////////////
//
// SSH key

resource sshKey 'Microsoft.Compute/sshPublicKeys@2023-07-01' = {
  name: 'azureuser'
  location: location
  properties: {
    publicKey: loadTextContent('../../../home/vscode/.ssh/azureuser.pub')
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////
//
// Proxy VM

resource proxyPublicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: proxyVmName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}
resource proxyNic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: proxyVmName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[1].id
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: proxyVmIpAddress
          publicIPAddress: {
            id: proxyPublicIp.id
          }
          privateIPAddressVersion: 'IPv4'
          primary: true
        }
      }
    ]
  }
}

resource proxyVm 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: proxyVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: proxyVmSize
    }
    osProfile: {
      computerName: proxyVmName
      adminUsername: vmAdminUserName

      customData: loadFileAsBase64('proxy-cloud-init.yml')
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/azureuser/.ssh/authorized_keys'
              keyData: sshKey.properties.publicKey
            }
          ]
        }
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
          assessmentMode: 'AutomaticByPlatform'
          automaticByPlatformSettings: {
            bypassPlatformSafetyChecksOnUserSchedule: true
          }
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: proxyNic.id

        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////
//
// Windows VM


resource defaultPublicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: defaultVmName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}
resource defaultNic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: defaultVmName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: defaultVmIpAddress
          publicIPAddress: {
            id: defaultPublicIp.id
          }
          privateIPAddressVersion: 'IPv4'
          primary: true
        }
      }
    ]
  }
}

resource defaultVm 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: defaultVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: defaultVmSize
    }
    osProfile: {
      computerName: defaultVmName
      adminUsername: vmAdminUserName
      adminPassword: defaultVmPassword
      allowExtensionOperations: true

      windowsConfiguration: {
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'microsoftwindowsdesktop'
        offer: 'windows-11'
        sku: 'win11-23h2-pro'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: defaultNic.id

        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////
//
// Output

output proxyPublicIpAddress string = proxyPublicIp.properties.ipAddress
output defaultPublicIpAddress string = defaultPublicIp.properties.ipAddress
