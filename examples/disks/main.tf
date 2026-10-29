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
  description = "Prepared template with a scsi0 boot disk no larger than 128 GiB and unused scsi1/scsi2 slots."
  type        = number
}

variable "vm_name" {
  description = "Base VM name; the module adds an indexed suffix."
  type        = string
}

variable "datastore_id" {
  description = "Datastore for the new data disks."
  type        = string
}

variable "network_bridge" {
  description = "Bridge for net0. This example opts into VirtIO and provider-default NIC options."
  type        = string
}

module "vm" {
  source = "../.."

  node_name      = var.node_name
  source_vm_id   = var.source_vm_id
  vm_name        = var.vm_name
  cpu_cores      = 4
  memory_size    = 8192
  network_bridge = var.network_bridge

  root_disk = {
    slot    = "scsi0"
    size_gb = 128
  }

  additional_disks = {
    scsi1 = {
      datastore_id = var.datastore_id
      size_gb      = 64
    }
    scsi2 = {
      datastore_id = var.datastore_id
      size_gb      = 256
    }
  }
}

output "vm_ids" {
  description = "Proxmox-assigned VM identifiers."
  value       = module.vm.vm_ids
}
