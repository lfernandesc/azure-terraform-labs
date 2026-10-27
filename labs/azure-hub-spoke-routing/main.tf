resource "random_id" "suffix" {
  byte_length = 4
}
locals {
  tags = {
    project     = "hub-spoke-routing-lab"
    environment = "learning"
    managed_by  = "terraform"
  }
  nodes = {
    hub     = { cidr = "10.50.0.0/16", subnet = "10.50.0.0/24", ip = "10.50.0.4" }
    spoke-a = { cidr = "10.51.0.0/16", subnet = "10.51.0.0/24", ip = "10.51.0.4" }
    spoke-b = { cidr = "10.52.0.0/16", subnet = "10.52.0.0/24", ip = "10.52.0.4" }
  }
  spokes = {
    spoke-a = { destination = "10.52.0.0/16" }
    spoke-b = { destination = "10.51.0.0/16" }
  }
}
resource "azurerm_resource_group" "lab" {
  name     = "rg-hub-spoke-${random_id.suffix.hex}"
  location = var.location
  tags     = local.tags
}
resource "azurerm_virtual_network" "node" {
  for_each            = local.nodes
  name                = "vnet-${each.key}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [each.value.cidr]
  tags                = local.tags
}
resource "azurerm_subnet" "node" {
  for_each                        = local.nodes
  name                            = "snet-${each.key}"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.node[each.key].name
  address_prefixes                = [each.value.subnet]
  default_outbound_access_enabled = false
}
# Independent explicit egress keeps VM management outside the experimental route path.
# These three NATs are a teaching trade-off, not a production hub egress design.
resource "azurerm_public_ip" "nat" {
  for_each            = local.nodes
  name                = "pip-nat-${each.key}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}
resource "azurerm_nat_gateway" "node" {
  for_each            = local.nodes
  name                = "nat-${each.key}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "Standard"
  tags                = local.tags
}
resource "azurerm_nat_gateway_public_ip_association" "node" {
  for_each             = local.nodes
  nat_gateway_id       = azurerm_nat_gateway.node[each.key].id
  public_ip_address_id = azurerm_public_ip.nat[each.key].id
}
resource "azurerm_subnet_nat_gateway_association" "node" {
  for_each       = local.nodes
  subnet_id      = azurerm_subnet.node[each.key].id
  nat_gateway_id = azurerm_nat_gateway.node[each.key].id
}
resource "azurerm_network_security_group" "node" {
  for_each            = local.nodes
  name                = "nsg-${each.key}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
  security_rule {
    name                       = "AllowLabHttp"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefixes    = [for node in local.nodes : node.subnet]
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "DenyOtherInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_subnet_network_security_group_association" "node" {
  for_each                  = local.nodes
  subnet_id                 = azurerm_subnet.node[each.key].id
  network_security_group_id = azurerm_network_security_group.node[each.key].id
}
# Four directional peering resources; there is deliberately no A<->B peering.
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each                     = local.spokes
  name                         = "hub-to-${each.key}"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.node["hub"].name
  remote_virtual_network_id    = azurerm_virtual_network.node[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each                     = local.spokes
  name                         = "${each.key}-to-hub"
  resource_group_name          = azurerm_resource_group.lab.name
  virtual_network_name         = azurerm_virtual_network.node[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.node["hub"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
resource "azurerm_route_table" "spoke" {
  for_each            = local.spokes
  name                = "rt-${each.key}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}
resource "azurerm_subnet_route_table_association" "spoke" {
  for_each       = local.spokes
  subnet_id      = azurerm_subnet.node[each.key].id
  route_table_id = azurerm_route_table.spoke[each.key].id
}
# The fix adds TWO narrow routes, one for each direction. No default route is changed.
resource "azurerm_route" "spoke_transit" {
  for_each               = var.enable_spoke_transit ? local.spokes : {}
  name                   = "to-other-spoke"
  resource_group_name    = azurerm_resource_group.lab.name
  route_table_name       = azurerm_route_table.spoke[each.key].name
  address_prefix         = each.value.destination
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = local.nodes.hub.ip
}
resource "azurerm_network_interface" "node" {
  for_each              = local.nodes
  name                  = "nic-${each.key}"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  ip_forwarding_enabled = each.key == "hub"
  tags                  = local.tags
  ip_configuration {
    name                          = "private"
    subnet_id                     = azurerm_subnet.node[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
}
resource "azurerm_linux_virtual_machine" "node" {
  for_each                        = local.nodes
  name                            = "vm-${each.key}"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.node[each.key].id]
  tags                            = local.tags
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
    azurerm_nat_gateway_public_ip_association.node,
    azurerm_subnet_nat_gateway_association.node,
    azurerm_subnet_network_security_group_association.node,
    azurerm_virtual_network_peering.hub_to_spoke,
    azurerm_virtual_network_peering.spoke_to_hub,
  ]
}
resource "azurerm_virtual_machine_extension" "setup" {
  for_each             = local.nodes
  name                 = "lab-setup"
  virtual_machine_id   = azurerm_linux_virtual_machine.node[each.key].id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"
  settings = jsonencode({
    commandToExecute = "printf '%s' '${base64encode(file("${path.module}/scripts/setup-vm.sh"))}' | base64 -d | bash -s -- '${each.key}' '${each.key == "hub" ? "true" : "false"}'"
  })
  tags = local.tags
}
