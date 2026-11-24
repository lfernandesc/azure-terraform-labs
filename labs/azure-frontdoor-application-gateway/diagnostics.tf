resource "azurerm_log_analytics_workspace" "lab" {
  name                = "law-delivery-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = var.primary_location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}
resource "azurerm_monitor_diagnostic_setting" "gateway" {
  for_each                       = local.regions
  name                           = "lab-access"
  target_resource_id             = azurerm_application_gateway.region[each.key].id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.lab.id
  log_analytics_destination_type = "Dedicated"
  enabled_log { category = "ApplicationGatewayAccessLog" }
}
resource "azurerm_monitor_diagnostic_setting" "frontdoor" {
  name                       = "lab-edge"
  target_resource_id         = azurerm_cdn_frontdoor_profile.lab.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab.id
  enabled_log { category = "FrontDoorAccessLog" }
  enabled_log { category = "FrontDoorHealthProbeLog" }
}
output "workspace_id" { value = azurerm_log_analytics_workspace.lab.id }
