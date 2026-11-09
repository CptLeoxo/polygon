# Polygon - shared Terraform configuration.
# scripts/render_lab.py copies this file once into every generated main.tf.

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc3"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = var.pm_tls_insecure
}

variable "pm_api_url" {
  type        = string
  description = "Proxmox API URL, e.g. https://pve01.example.local:8006/api2/json"
}

variable "pm_api_token_id" {
  type        = string
  description = "Proxmox API token ID, e.g. terraform@pve!polygon"
}

variable "pm_api_token_secret" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret"
}

variable "pm_tls_insecure" {
  type        = bool
  default     = false
  description = "Skip TLS verification. Only for an isolated lab with a self-signed certificate."
}

variable "manage_fw_vlan" {
  type        = bool
  default     = true
  description = "Create/remove the per-student VLAN gateway on the firewall over SSH."
}

variable "fw_host" {
  type        = string
  default     = ""
  description = "Management address of the main firewall (required when manage_fw_vlan = true)."
}

variable "fw_user" {
  type        = string
  default     = "polygon"
  description = "SSH user on the firewall (needs sudo for the two VLAN scripts only)."
}

variable "fw_parent_if" {
  type        = string
  default     = "igb3"
  description = "Trunk interface on the firewall that carries the student VLANs."
}
