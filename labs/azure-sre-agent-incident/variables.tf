variable "subscription_id" {
  type        = string
  description = "Subscription reserved for the lab."
}
variable "location" {
  type        = string
  default     = "westeurope"
  description = "Workload region with Container Apps Consumption quota. Agent region is selected separately in its wizard."
}
variable "dependency_timeout_ms" {
  type        = number
  default     = 2000
  description = "Start healthy at 2000, inject the fault at 100, restore 2000. Backend deliberately waits 350ms."
  validation {
    condition     = contains([100, 2000], var.dependency_timeout_ms)
    error_message = "Use 100 (broken) or 2000 (healthy/fixed) to preserve the experiment."
  }
}
variable "agent_principal_id" {
  type        = string
  default     = null
  description = "Optional OBJECT/principal ID of the existing agent UAMI, not its client ID or ARM resource ID. Only reader roles on the workload RG are created."
  validation {
    condition     = var.agent_principal_id == null ? true : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.agent_principal_id))
    error_message = "Supply the agent identity principal UUID, or leave null."
  }
}
variable "container_image" {
  type        = string
  default     = "docker.io/library/python:3.12-slim-bookworm@sha256:0f086103b026048cc50cb5da25ec435c023c5241a83fc44daea593377abc61c4"
  description = "Official Python linux/amd64 manifest, verified against Docker Hub on 2026-11-10. Keep the same digest for every phase; review security updates for future use."
}
