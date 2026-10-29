locals {
  disks = merge(
    var.root_disk == null ? {} : {
      (var.root_disk.slot) = {
        size_gb      = var.root_disk.size_gb
        datastore_id = null
      }
    },
    {
      for slot, disk in var.additional_disks : slot => disk
    }
  )
}

resource "proxmox_cloned_vm" "vm" {
  count = var.vm_mode == "experimental" ? var.vm_count : 0

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

resource "proxmox_virtual_environment_vm" "vm" {
  count = var.vm_mode == "legacy" ? var.vm_count : 0

  node_name   = var.node_name
  name        = format("%s-%02d", var.vm_name, count.index + 1)
  description = var.vm_description
  tags        = var.tags
  started     = true

  clone {
    vm_id        = var.source_vm_id
    node_name    = var.source_node_name
    full         = true
    datastore_id = var.target_datastore
  }

  dynamic "cpu" {
    for_each = var.cpu_cores == null ? [] : [var.cpu_cores]
    content {
      cores = cpu.value
    }
  }

  dynamic "memory" {
    for_each = var.memory_size == null ? [] : [var.memory_size]
    content {
      dedicated = memory.value
    }
  }

  network_device = var.network_bridge == null ? null : [{
    bridge       = var.network_bridge
    model        = "virtio"
    enabled      = null
    disconnected = false
    firewall     = false
    mac_address  = null
    mtu          = 0
    queues       = 0
    rate_limit   = 0
    trunks       = null
    vlan_id      = 0
  }]

  dynamic "disk" {
    for_each = local.disks
    content {
      interface = disk.key
      size      = disk.value.size_gb
      datastore_id = var.root_disk == null ? disk.value.datastore_id : (
        disk.key == var.root_disk.slot ? var.root_disk.datastore_id : disk.value.datastore_id
      )
    }
  }

  delete_unreferenced_disks_on_destroy = false

  lifecycle {
    ignore_changes = [node_name]

    precondition {
      condition     = var.root_disk != null
      error_message = "Legacy mode requires root_disk with the existing boot-disk slot, desired size_gb, and datastore_id."
    }

    precondition {
      condition     = var.root_disk == null ? true : var.root_disk.datastore_id != null
      error_message = "Legacy mode requires root_disk.datastore_id; omitting it would use the provider's local-lvm default."
    }

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
