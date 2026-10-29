locals {
  disks = merge(
    var.root_disk == null ? {} : {
      (var.root_disk.slot) = {
        size_gb = var.root_disk.size_gb
      }
    },
    {
      for slot, disk in var.additional_disks : slot => disk
    }
  )
}

resource "proxmox_cloned_vm" "vm" {
  count = var.vm_count

  node_name   = var.node_name
  name        = format("%s-%02d", var.vm_name, count.index + 1)
  description = var.vm_description
  tags        = var.tags
  started     = true

  clone = {
    source_vm_id     = var.source_vm_id
    source_node_name = var.source_node_name
    full             = true
    target_datastore = var.target_datastore
  }

  cpu = var.cpu_cores == null ? null : {
    cores = var.cpu_cores
  }

  memory = var.memory_size == null ? null : {
    size = var.memory_size
  }

  network = var.network_bridge == null ? null : {
    net0 = {
      bridge = var.network_bridge
      model  = "virtio"
    }
  }

  disk = length(local.disks) == 0 ? null : local.disks

  delete_unreferenced_disks_on_destroy = false

  lifecycle {
    precondition {
      condition     = var.root_disk == null ? true : !contains(keys(var.additional_disks), var.root_disk.slot)
      error_message = "additional_disks must not contain the root_disk slot."
    }
  }
}

moved {
  from = proxmox_cloned_vm.vm
  to   = proxmox_cloned_vm.vm[0]
}
