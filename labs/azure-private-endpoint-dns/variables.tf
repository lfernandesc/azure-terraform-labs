variable "subscription_id" {
  description = "Azure subscription used exclusively for this learning environment."
  type        = string
}

variable "location" {
  description = "Azure region; choose one with quota for the selected VM size."
  type        = string
  default     = "westeurope"
}

variable "vm_size" {
  description = "Small Linux VM; availability and quotas vary by subscription and region."
  type        = string
  default     = "Standard_B1s"
}

variable "ssh_public_key" {
  description = "Existing SSH public key. The VM has no public IP or open SSH ingress. Never supply a private key."
  type        = string
  validation {
    condition     = can(regex("^ssh-(rsa|ed25519) ", var.ssh_public_key))
    error_message = "Supply the contents of an RSA or Ed25519 public key."
  }
}

variable "enable_private_dns_link" {
  description = "False reproduces the incident; true applies the DNS fix. Public Storage access stays disabled."
  type        = bool
  default     = false
}
