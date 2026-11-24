variable "subscription_id" { type = string }
variable "operator_ipv4_cidr" {
  type        = string
  description = "Public IPv4 of the lab operator, exactly /32. Never use 0.0.0.0/0."
  validation {
    condition     = can(cidrnetmask(var.operator_ipv4_cidr)) && can(regex("/32$", var.operator_ipv4_cidr))
    error_message = "Provide a valid single IPv4 address in /32 notation."
  }
}
variable "ssh_public_key" {
  type        = string
  description = "Existing OpenSSH PUBLIC key. No SSH ingress is opened by this lab. Never provide a private key."
  validation {
    condition     = can(regex("^ssh-(rsa|ed25519) ", var.ssh_public_key))
    error_message = "Use an RSA or Ed25519 public key."
  }
}
variable "primary_location" {
  type    = string
  default = "westeurope"
}
variable "secondary_location" {
  type    = string
  default = "northeurope"
}
variable "vm_size" {
  type    = string
  default = "Standard_B1s"
}
variable "break_primary_probe" {
  type        = bool
  default     = false
  description = "Fault injection: primary Application Gateway probes /missing instead of /health."
}
variable "allow_direct_tests" {
  type        = bool
  default     = true
  description = "Temporary /32 exception for direct gateway comparison. Set false for final origin isolation."
}
