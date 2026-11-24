output "frontdoor_url" { value = "https://${azurerm_cdn_frontdoor_endpoint.lab.host_name}" }
output "frontdoor_id" { value = azurerm_cdn_frontdoor_profile.lab.resource_guid }
output "deployment_id" { value = random_id.suffix.hex }
output "gateway_urls" { value = { for k, v in azurerm_public_ip.gateway : k => "http://${v.fqdn}" } }
output "resource_group" { value = azurerm_resource_group.lab.name }
output "gateway_names" { value = { for k, v in azurerm_application_gateway.region : k => v.name } }
output "gateway_nsg_names" { value = { for k, v in azurerm_network_security_group.gateway : k => v.name } }
output "vm_names" { value = { for k, v in azurerm_linux_virtual_machine.backend : k => v.name } }
output "profile_name" { value = azurerm_cdn_frontdoor_profile.lab.name }
