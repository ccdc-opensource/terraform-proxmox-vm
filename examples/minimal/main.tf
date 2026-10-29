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

variable "vm_mode" {
  description = "Legacy by default; experimental opts into the clone-specific resource."
  type        = string
  default     = "legacy"
}

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

variable "root_disk" {
  description = "Existing boot disk slot, desired GiB capacity, and datastore after cloning."
  type = object({
    slot         = string
    size_gb      = number
    datastore_id = string
  })
}

module "vm" {
  source = "../.."

  node_name    = var.node_name
  source_vm_id = var.source_vm_id
  vm_name      = var.vm_name
  vm_mode      = var.vm_mode
  root_disk    = var.root_disk
}

output "vm_ids" {
  description = "Proxmox-assigned VM identifiers."
  value       = module.vm.vm_ids
}
