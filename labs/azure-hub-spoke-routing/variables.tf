variable "subscription_id" {
  description = "Azure learning subscription."
  type        = string
}
variable "location" {
  description = "Region with quota for three Linux VMs."
  type        = string
  default     = "westeurope"
}
variable "vm_size" {
  description = "Check availability, quota and price before applying."
  type        = string
  default     = "Standard_B1s"
}
variable "ssh_public_key" {
  description = "RSA or Ed25519 public key. No inbound SSH or public VM IP is configured."
  type        = string
  validation {
    condition     = can(regex("^ssh-(rsa|ed25519) ", var.ssh_public_key))
    error_message = "Use the contents of a valid RSA or Ed25519 public key, never a private key."
  }
}
variable "enable_spoke_transit" {
  description = "False: hub peerings only. True: add both spoke-to-spoke UDRs via the hub NVA."
  type        = bool
  default     = false
}
