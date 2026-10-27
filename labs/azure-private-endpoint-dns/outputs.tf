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
