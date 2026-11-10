resource "random_id" "suffix" { byte_length = 3 }
locals {
  tags = { project = "sre-agent-incident-lab", environment = "learning", managed_by = "terraform" }
}
resource "azurerm_resource_group" "workload" {
  name     = "rg-sre-workload-${random_id.suffix.hex}"
  location = var.location
  tags     = local.tags
}
resource "azurerm_resource_group" "agent" {
  name     = "rg-sre-agent-${random_id.suffix.hex}"
  location = var.location
  tags     = local.tags
}
resource "azurerm_log_analytics_workspace" "lab" {
  name                = "law-sre-${random_id.suffix.hex}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}
resource "azurerm_container_app_environment" "lab" {
  name                = "cae-sre-${random_id.suffix.hex}"
  location            = azurerm_resource_group.workload.location
  resource_group_name = azurerm_resource_group.workload.name
  logs_destination    = "azure-monitor"
  tags                = local.tags
}
resource "azurerm_monitor_diagnostic_setting" "logs" {
  name                           = "lab-logs"
  target_resource_id             = azurerm_container_app_environment.lab.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.lab.id
  log_analytics_destination_type = "Dedicated"
  enabled_log { category = "ContainerAppConsoleLogs" }
  enabled_log { category = "ContainerAppSystemLogs" }
}
resource "azurerm_container_app" "backend" {
  name                         = "ca-backend-${random_id.suffix.hex}"
  resource_group_name          = azurerm_resource_group.workload.name
  container_app_environment_id = azurerm_container_app_environment.lab.id
  revision_mode                = "Single"
  tags                         = local.tags
  ingress {
    external_enabled           = false
    allow_insecure_connections = false
    target_port                = 8080
    transport                  = "http"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
  template {
    min_replicas = 1
    max_replicas = 1
    container {
      name    = "backend"
      image   = var.container_image
      cpu     = 0.25
      memory  = "0.5Gi"
      command = ["python", "-u", "-c"]
      args    = [file("${path.module}/app/server.py")]
      env {
        name  = "APP_ROLE"
        value = "backend"
      }
      env {
        name  = "BACKEND_DELAY_MS"
        value = "350"
      }
      readiness_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/healthz"
        interval_seconds        = 5
        success_count_threshold = 1
      }
    }
  }
  depends_on = [azurerm_monitor_diagnostic_setting.logs]
}
resource "azurerm_container_app" "api" {
  name                         = "ca-checkout-${random_id.suffix.hex}"
  resource_group_name          = azurerm_resource_group.workload.name
  container_app_environment_id = azurerm_container_app_environment.lab.id
  revision_mode                = "Single"
  tags                         = local.tags
  ingress {
    external_enabled           = true
    allow_insecure_connections = false
    target_port                = 8080
    transport                  = "http"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
  template {
    min_replicas = 1
    max_replicas = 1
    container {
      name    = "checkout"
      image   = var.container_image
      cpu     = 0.25
      memory  = "0.5Gi"
      command = ["python", "-u", "-c"]
      args    = [file("${path.module}/app/server.py")]
      env {
        name  = "APP_ROLE"
        value = "api"
      }
      env {
        name  = "BACKEND_URL"
        value = "https://${azurerm_container_app.backend.ingress[0].fqdn}"
      }
      env {
        name  = "DEPENDENCY_TIMEOUT_MS"
        value = tostring(var.dependency_timeout_ms)
      }
      readiness_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/healthz"
        interval_seconds        = 5
        success_count_threshold = 1
      }
    }
  }
}
# These assignments do not create an SRE Agent or configure its connectors/run modes.
resource "azurerm_role_assignment" "agent_readers" {
  for_each                         = var.agent_principal_id == null ? toset([]) : toset(["Reader", "Log Analytics Reader", "Monitoring Reader"])
  scope                            = azurerm_resource_group.workload.id
  role_definition_name             = each.value
  principal_id                     = var.agent_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
