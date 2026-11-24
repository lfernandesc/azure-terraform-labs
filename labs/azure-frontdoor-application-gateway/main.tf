resource "random_id" "suffix" { byte_length = 3 }
locals {
  regions = {
    primary   = { location = var.primary_location, cidr = "10.81.0.0/16", gateway = "10.81.0.0/24", backend = "10.81.1.0/24", priority = 1 }
    secondary = { location = var.secondary_location, cidr = "10.82.0.0/16", gateway = "10.82.0.0/24", backend = "10.82.1.0/24", priority = 2 }
  }
  tags = { project = "frontdoor-appgateway-lab", environment = "learning", managed_by = "terraform" }
}
resource "azurerm_resource_group" "lab" {
  name     = "rg-delivery-${random_id.suffix.hex}"
  location = var.primary_location
  tags     = local.tags
  lifecycle {
    precondition {
      condition     = var.primary_location != var.secondary_location
      error_message = "Choose two different regions."
    }
  }
}
resource "azurerm_cdn_frontdoor_profile" "lab" {
  name                = "fd-delivery-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = local.tags
}
resource "azurerm_virtual_network" "region" {
  for_each            = local.regions
  name                = "vnet-${each.key}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = each.value.location
  address_space       = [each.value.cidr]
  tags                = local.tags
}
resource "azurerm_subnet" "gateway" {
  for_each             = local.regions
  name                 = "snet-appgateway"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.region[each.key].name
  address_prefixes     = [each.value.gateway]
}
resource "azurerm_subnet" "backend" {
  for_each                        = local.regions
  name                            = "snet-backend"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.region[each.key].name
  address_prefixes                = [each.value.backend]
  default_outbound_access_enabled = false
}
resource "azurerm_network_security_group" "gateway" {
  for_each            = local.regions
  name                = "nsg-appgateway-${each.key}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = each.value.location
  tags                = local.tags
  security_rule {
    name                       = "FrontDoorBackend"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "AzureFrontDoor.Backend"
    destination_address_prefix = each.value.gateway
  }
  dynamic "security_rule" {
    for_each = var.allow_direct_tests ? [1] : []
    content {
      name                       = "TemporaryOperatorTest"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = var.operator_ipv4_cidr
      destination_address_prefix = each.value.gateway
    }
  }
  security_rule {
    name                       = "GatewayManager"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AzureLoadBalancer"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "DenyOtherInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  # Keep default outbound rules required by a standard public Application Gateway v2.
}
resource "azurerm_network_security_group" "backend" {
  for_each            = local.regions
  name                = "nsg-backend-${each.key}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = each.value.location
  tags                = local.tags
  security_rule {
    name                       = "OnlyRegionalGateway"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = each.value.gateway
    destination_address_prefix = each.value.backend
  }
  security_rule {
    name                       = "DenyOtherInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_subnet_network_security_group_association" "gateway" {
  for_each                  = local.regions
  subnet_id                 = azurerm_subnet.gateway[each.key].id
  network_security_group_id = azurerm_network_security_group.gateway[each.key].id
}
resource "azurerm_subnet_network_security_group_association" "backend" {
  for_each                  = local.regions
  subnet_id                 = azurerm_subnet.backend[each.key].id
  network_security_group_id = azurerm_network_security_group.backend[each.key].id
}
resource "azurerm_network_interface" "backend" {
  for_each            = local.regions
  name                = "nic-${each.key}"
  location            = each.value.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
  ip_configuration {
    name                          = "private"
    subnet_id                     = azurerm_subnet.backend[each.key].id
    private_ip_address_allocation = "Dynamic"
  }
}
resource "azurerm_linux_virtual_machine" "backend" {
  for_each                        = local.regions
  name                            = "vm-${each.key}-${random_id.suffix.hex}"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = each.value.location
  size                            = var.vm_size
  admin_username                  = "labadmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.backend[each.key].id]
  tags                            = local.tags
  boot_diagnostics {}
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
  custom_data = base64encode(templatefile("${path.module}/app/cloud-init.yaml.tftpl", {
    server_b64    = filebase64("${path.module}/app/server.py")
    region        = each.key
    deployment_id = random_id.suffix.hex
    frontdoor_id  = azurerm_cdn_frontdoor_profile.lab.resource_guid
  }))
  depends_on = [azurerm_subnet_network_security_group_association.backend]
}
resource "azurerm_public_ip" "gateway" {
  for_each            = local.regions
  name                = "pip-gateway-${each.key}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = each.value.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "delivery-${each.key}-${random_id.suffix.hex}"
  tags                = local.tags
}
resource "azurerm_application_gateway" "region" {
  for_each            = local.regions
  name                = "agw-${each.key}-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = each.value.location
  tags                = local.tags
  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }
  gateway_ip_configuration {
    name      = "gateway"
    subnet_id = azurerm_subnet.gateway[each.key].id
  }
  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.gateway[each.key].id
  }
  frontend_port {
    name = "http"
    port = 80
  }
  backend_address_pool {
    name         = "private-vm"
    ip_addresses = [azurerm_network_interface.backend[each.key].private_ip_address]
  }
  backend_http_settings {
    name                  = "http-backend"
    cookie_based_affinity = "Disabled"
    port                  = 8080
    protocol              = "Http"
    request_timeout       = 10
    probe_name            = "readiness"
  }
  probe {
    name                = "readiness"
    protocol            = "Http"
    host                = "lab.internal"
    path                = each.key == "primary" && var.break_primary_probe ? "/missing" : "/health"
    interval            = 10
    timeout             = 5
    unhealthy_threshold = 3
    match { status_code = ["200"] }
  }
  http_listener {
    name                           = "http"
    frontend_ip_configuration_name = "public"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }
  request_routing_rule {
    name                       = "all-requests"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "http"
    backend_address_pool_name  = "private-vm"
    backend_http_settings_name = "http-backend"
  }
  depends_on = [azurerm_subnet_network_security_group_association.gateway, azurerm_linux_virtual_machine.backend]
}
resource "azurerm_cdn_frontdoor_endpoint" "lab" {
  name                     = "delivery-${random_id.suffix.hex}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.lab.id
  tags                     = local.tags
}
resource "azurerm_cdn_frontdoor_origin_group" "lab" {
  name                     = "regional-gateways"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.lab.id
  session_affinity_enabled = false
  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }
  health_probe {
    path                = "/health"
    protocol            = "Http"
    request_type        = "HEAD"
    interval_in_seconds = 30
  }
}
resource "azurerm_cdn_frontdoor_origin" "region" {
  for_each                       = local.regions
  name                           = each.key
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.lab.id
  host_name                      = azurerm_public_ip.gateway[each.key].fqdn
  origin_host_header             = azurerm_public_ip.gateway[each.key].fqdn
  http_port                      = 80
  https_port                     = 443
  enabled                        = true
  certificate_name_check_enabled = true
  priority                       = each.value.priority
  weight                         = 1000
  depends_on                     = [azurerm_application_gateway.region]
}
resource "azurerm_cdn_frontdoor_route" "lab" {
  name                          = "checkout"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.lab.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.lab.id
  cdn_frontdoor_origin_ids      = [for o in azurerm_cdn_frontdoor_origin.region : o.id]
  supported_protocols           = ["Http", "Https"]
  patterns_to_match             = ["/*"]
  forwarding_protocol           = "HttpOnly"
  https_redirect_enabled        = true
  link_to_default_domain        = true
  # No cache block: failover must be observed at the live application.
}
