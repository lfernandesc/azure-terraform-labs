resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  suffix = random_id.suffix.hex
  tags = {
    project     = "private-endpoint-dns-lab"
    environment = "learning"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-pe-dns-${local.suffix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-lab"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.42.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "client" {
  name                 = "snet-client"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.42.1.0/24"]
  service_endpoints    = var.enable_service_endpoint_comparison ? ["Microsoft.Storage"] : []
}

resource "azurerm_subnet" "endpoint" {
  name                              = "snet-private-endpoints"
  resource_group_name               = azurerm_resource_group.lab.name
  virtual_network_name              = azurerm_virtual_network.lab.name
  address_prefixes                  = ["10.42.2.0/24"]
  private_endpoint_network_policies = "Disabled"
}

# Explicit outbound access for the VM agent; never an inbound public IP on the VM.
resource "azurerm_public_ip" "nat" {
  name                = "pip-nat"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "client" {
  name                = "nat-client"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "client" {
  nat_gateway_id       = azurerm_nat_gateway.client.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "client" {
  subnet_id      = azurerm_subnet.client.id
  nat_gateway_id = azurerm_nat_gateway.client.id
}

resource "azurerm_network_security_group" "client" {
  name                = "nsg-client"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
  security_rule {
    name                       = "DenyInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "client" {
  subnet_id                 = azurerm_subnet.client.id
  network_security_group_id = azurerm_network_security_group.client.id
}

# ARM-only creation and refresh: Terraform does not need access to the Blob endpoint.
# No Storage containers or other data-plane resources are managed from the laptop.
resource "azapi_resource" "storage" {
  type      = "Microsoft.Storage/storageAccounts@2023-05-01"
  name      = "stpedns${local.suffix}"
  parent_id = azurerm_resource_group.lab.id
  location  = azurerm_resource_group.lab.location
  tags      = local.tags
  body = {
    kind = "StorageV2"
    sku  = { name = "Standard_LRS" }
    properties = {
      accessTier                   = "Hot"
      publicNetworkAccess          = "Disabled"
      allowSharedKeyAccess         = false
      allowBlobPublicAccess        = false
      defaultToOAuthAuthentication = true
      minimumTlsVersion            = "TLS1_2"
      supportsHttpsTrafficOnly     = true
    }
  }
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-blob"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  subnet_id           = azurerm_subnet.endpoint.id
  tags                = local.tags
  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azapi_resource.storage.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "blob-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

# This single link is deliberately missing in the broken scenario.
# Autoregistration is for VM records, not Private Endpoint records.
resource "azurerm_private_dns_zone_virtual_network_link" "client" {
  count                 = var.enable_private_dns_link ? 1 : 0
  name                  = "link-client-vnet"
  resource_group_name   = azurerm_resource_group.lab.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.lab.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_network_interface" "probe" {
  name                = "nic-probe"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
  ip_configuration {
    name                          = "private"
    subnet_id                     = azurerm_subnet.client.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "probe" {
  name                            = "vm-probe"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.probe.id]
  tags                            = local.tags
  identity {
    type = "SystemAssigned"
  }
  admin_ssh_key {
    username   = "labadmin"
    public_key = var.ssh_public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  depends_on = [
    azurerm_nat_gateway_public_ip_association.client,
    azurerm_subnet_nat_gateway_association.client,
    azurerm_subnet_network_security_group_association.client,
  ]
}

resource "azurerm_role_assignment" "blob_reader" {
  scope                            = azapi_resource.storage.id
  role_definition_name             = "Storage Blob Data Reader"
  principal_id                     = azurerm_linux_virtual_machine.probe.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Optional comparison uses a DIFFERENT account: public service endpoint + subnet ACL.
# It never changes the private account's publicNetworkAccess=Disabled.
resource "azapi_resource" "service_storage" {
  count     = var.enable_service_endpoint_comparison ? 1 : 0
  type      = "Microsoft.Storage/storageAccounts@2023-05-01"
  name      = "stse${local.suffix}"
  parent_id = azurerm_resource_group.lab.id
  location  = azurerm_resource_group.lab.location
  tags      = local.tags
  body = {
    kind = "StorageV2"
    sku  = { name = "Standard_LRS" }
    properties = {
      accessTier                   = "Hot"
      publicNetworkAccess          = "Enabled"
      allowSharedKeyAccess         = false
      allowBlobPublicAccess        = false
      defaultToOAuthAuthentication = true
      minimumTlsVersion            = "TLS1_2"
      supportsHttpsTrafficOnly     = true
      networkAcls = {
        defaultAction = "Deny"
        bypass        = "None"
        ipRules       = []
        virtualNetworkRules = var.allow_service_endpoint_subnet ? [{
          id     = azurerm_subnet.client.id
          action = "Allow"
        }] : []
      }
    }
  }
}

resource "azurerm_role_assignment" "service_blob_reader" {
  count                            = var.enable_service_endpoint_comparison ? 1 : 0
  scope                            = azapi_resource.service_storage[0].id
  role_definition_name             = "Storage Blob Data Reader"
  principal_id                     = azurerm_linux_virtual_machine.probe.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
