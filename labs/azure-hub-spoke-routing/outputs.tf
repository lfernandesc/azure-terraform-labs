output "resource_group" {
  value = azurerm_resource_group.lab.name
}
output "node_ips" {
  value = { for name, node in local.nodes : name => node.ip }
}
output "vm_names" {
  value = { for name, vm in azurerm_linux_virtual_machine.node : name => vm.name }
}
output "nic_names" {
  value = { for name, nic in azurerm_network_interface.node : name => nic.name }
}
output "spoke_transit_enabled" {
  value = var.enable_spoke_transit
}
