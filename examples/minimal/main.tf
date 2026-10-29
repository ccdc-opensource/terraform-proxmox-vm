terraform {
  required_version = ">= 1.7.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.118.1"
    }
  }
}

provider "proxmox" {}

variable "node_name" {
  description = "Target Proxmox node."
  type        = string
}

variable "source_vm_id" {
  description = "Prepared Linux or Windows template ID."
  type        = number
}

variable "vm_name" {
  description = "Base VM name; the module adds an indexed suffix."
  type        = string
}

module "vm" {
  source = "../.."

  node_name    = var.node_name
  source_vm_id = var.source_vm_id
  vm_name      = var.vm_name
}

output "vm_ids" {
  description = "Proxmox-assigned VM identifiers."
  value       = module.vm.vm_ids
}
