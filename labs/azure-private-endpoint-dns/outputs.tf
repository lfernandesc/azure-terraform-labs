output "resource_group" {
  value = azurerm_resource_group.lab.name
}
output "vm_name" {
  value = azurerm_linux_virtual_machine.probe.name
}
output "storage_account" {
  value = azapi_resource.storage.name
}
output "private_ip" {
  value = azurerm_private_endpoint.blob.private_service_connection[0].private_ip_address
}
output "dns_link_enabled" {
  value = var.enable_private_dns_link
}

output "client_subnet_id" {
  value = azurerm_subnet.client.id
}
output "probe_nic_name" {
  value = azurerm_network_interface.probe.name
}
output "service_endpoint_comparison" {
  value = var.enable_service_endpoint_comparison ? {
    account      = azapi_resource.service_storage[0].name
    id           = azapi_resource.service_storage[0].id
    subnet_id    = azurerm_subnet.client.id
    subnet_allow = var.allow_service_endpoint_subnet
  } : null
}
