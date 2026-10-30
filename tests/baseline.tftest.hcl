mock_provider "proxmox" {
  mock_resource "proxmox_cloned_vm" {
    defaults = {
      id = 200
    }
  }
}

variables {
  vm_mode      = "experimental"
  node_name    = "pve-test"
  source_vm_id = 100
  vm_name      = "baseline-test"
}

run "minimal_configuration_when_applied_preserves_unmanaged_settings" {
  command = apply

  assert {
    condition = (
      proxmox_cloned_vm.vm[0].cpu == null &&
      proxmox_cloned_vm.vm[0].memory == null &&
      proxmox_cloned_vm.vm[0].network == null &&
      proxmox_cloned_vm.vm[0].disk == null &&
      proxmox_cloned_vm.vm[0].delete == null &&
      proxmox_cloned_vm.vm[0].vga == null
    )
    error_message = "Minimal clones must not manage inherited hardware or delete devices."
  }

  assert {
    condition = (
      proxmox_cloned_vm.vm[0].clone.full &&
      proxmox_cloned_vm.vm[0].clone.source_vm_id == 100 &&
      proxmox_cloned_vm.vm[0].clone.source_node_name == null &&
      proxmox_cloned_vm.vm[0].clone.target_datastore == null &&
      proxmox_cloned_vm.vm[0].started &&
      !proxmox_cloned_vm.vm[0].delete_unreferenced_disks_on_destroy &&
      proxmox_cloned_vm.vm[0].description == null &&
      proxmox_cloned_vm.vm[0].tags == null
    )
    error_message = "The baseline must start a full clone without environment-specific metadata or storage overrides."
  }

  assert {
    condition = (
      output.vm_ids == tolist([200]) &&
      output.vm_names == tolist(["baseline-test-01"]) &&
      output.node_names == tolist(["pve-test"])
    )
    error_message = "Outputs must expose the resource ID, VM name, and target node."
  }
}

run "explicit_overrides_when_planned_manage_only_supported_fields" {
  command = plan

  variables {
    source_node_name = "pve-source"
    target_datastore = "clone-storage"
    cpu_cores        = 4
    memory_size      = 8192
    network_bridge   = "vmbr-test"
    vm_description   = "Test clone"
    tags             = ["test", "linux"]
  }

  assert {
    condition = (
      proxmox_cloned_vm.vm[0].cpu.cores == 4 &&
      proxmox_cloned_vm.vm[0].cpu.sockets == null &&
      proxmox_cloned_vm.vm[0].cpu.type == null &&
      proxmox_cloned_vm.vm[0].memory.size == 8192 &&
      proxmox_cloned_vm.vm[0].memory.balloon == null &&
      proxmox_cloned_vm.vm[0].memory.shares == null
    )
    error_message = "CPU and RAM overrides must not set unrelated CPU or memory fields."
  }

  assert {
    condition = (
      length(proxmox_cloned_vm.vm[0].network) == 1 &&
      proxmox_cloned_vm.vm[0].network.net0.bridge == "vmbr-test" &&
      proxmox_cloned_vm.vm[0].network.net0.model == "virtio" &&
      proxmox_cloned_vm.vm[0].network.net0.tag == null &&
      proxmox_cloned_vm.vm[0].network.net0.firewall == null &&
      proxmox_cloned_vm.vm[0].disk == null
    )
    error_message = "The bridge override must explicitly use VirtIO on net0 without managing disks or additional NICs."
  }

  assert {
    condition = (
      proxmox_cloned_vm.vm[0].clone.source_node_name == "pve-source" &&
      proxmox_cloned_vm.vm[0].clone.target_datastore == "clone-storage" &&
      proxmox_cloned_vm.vm[0].description == "Test clone" &&
      proxmox_cloned_vm.vm[0].tags == toset(["test", "linux"])
    )
    error_message = "Explicit clone placement and metadata must reach the resource."
  }
}

run "root_disk_when_supplied_manages_only_its_slot_and_size" {
  command = plan

  variables {
    root_disk = {
      slot    = "virtio0"
      size_gb = 128
    }
  }

  assert {
    condition = (
      length(proxmox_cloned_vm.vm[0].disk) == 1 &&
      proxmox_cloned_vm.vm[0].disk.virtio0.size_gb == 128 &&
      proxmox_cloned_vm.vm[0].disk.virtio0.datastore_id == null &&
      proxmox_cloned_vm.vm[0].disk.virtio0.file == null &&
      proxmox_cloned_vm.vm[0].disk.virtio0.cache == null
    )
    error_message = "OS disk growth must target the supplied slot without supplying a new volume or tuning."
  }
}

run "additional_disks_when_supplied_manage_multiple_stable_slots" {
  command = plan

  variables {
    additional_disks = {
      scsi1 = { size_gb = 64, datastore_id = "data-storage" }
      scsi2 = { size_gb = 256, datastore_id = "data-storage" }
    }
  }

  assert {
    condition = (
      toset(keys(proxmox_cloned_vm.vm[0].disk)) == toset(["scsi1", "scsi2"]) &&
      proxmox_cloned_vm.vm[0].disk.scsi1.size_gb == 64 &&
      proxmox_cloned_vm.vm[0].disk.scsi2.size_gb == 256 &&
      proxmox_cloned_vm.vm[0].disk.scsi1.datastore_id == "data-storage" &&
      proxmox_cloned_vm.vm[0].disk.scsi2.datastore_id == "data-storage"
    )
    error_message = "Multiple additional disks must use their configured slots, sizes, and datastores without managing the root disk."
  }
}

run "combined_disks_when_supplied_merge_root_and_data_disks" {
  command = plan

  variables {
    root_disk = {
      slot    = "sata0"
      size_gb = 128
    }
    additional_disks = {
      scsi1 = { size_gb = 64, datastore_id = "data-storage" }
      scsi2 = { size_gb = 256, datastore_id = "data-storage" }
    }
  }

  assert {
    condition = (
      toset(keys(proxmox_cloned_vm.vm[0].disk)) == toset(["sata0", "scsi1", "scsi2"]) &&
      proxmox_cloned_vm.vm[0].disk.sata0.size_gb == 128 &&
      proxmox_cloned_vm.vm[0].disk.sata0.datastore_id == null &&
      proxmox_cloned_vm.vm[0].disk.scsi1.size_gb == 64 &&
      proxmox_cloned_vm.vm[0].disk.scsi2.size_gb == 256
    )
    error_message = "The merged map must retain the root disk and all additional disks."
  }
}

run "duplicate_root_slot_when_supplied_fails_before_deployment" {
  command = plan

  variables {
    root_disk = { slot = "scsi0", size_gb = 128 }
    additional_disks = {
      scsi0 = { size_gb = 64, datastore_id = "data-storage" }
    }
  }

  expect_failures = [proxmox_cloned_vm.vm]
}

run "empty_identifiers_when_supplied_fail_validation" {
  command = plan

  variables {
    node_name        = " "
    vm_name          = ""
    source_node_name = " "
    target_datastore = ""
    network_bridge   = " "
    tags             = [" "]
  }

  expect_failures = [
    var.node_name, var.vm_name, var.source_node_name,
    var.target_datastore, var.network_bridge, var.tags,
  ]
}

run "non_positive_numbers_when_supplied_fail_validation" {
  command = plan

  variables {
    source_vm_id = 0
    cpu_cores    = 0
    memory_size  = 63
    root_disk    = { slot = "scsi0", size_gb = 0 }
    additional_disks = {
      scsi1 = { size_gb = -1, datastore_id = "data-storage" }
    }
  }

  expect_failures = [var.source_vm_id, var.cpu_cores, var.memory_size, var.root_disk, var.additional_disks]
}

run "fractional_numbers_when_supplied_fail_validation" {
  command = plan

  variables {
    source_vm_id = 100.5
    cpu_cores    = 1.5
    memory_size  = 1024.5
    root_disk    = { slot = "scsi0", size_gb = 32.5 }
    additional_disks = {
      scsi1 = { size_gb = 32.5, datastore_id = "data-storage" }
    }
  }

  expect_failures = [var.source_vm_id, var.cpu_cores, var.memory_size, var.root_disk, var.additional_disks]
}

run "above_provider_limits_when_supplied_fail_validation" {
  command = plan

  variables {
    cpu_cores   = 1025
    memory_size = 268435457
    root_disk   = { slot = "scsi0", size_gb = 10241 }
    additional_disks = {
      scsi1 = { size_gb = 10241, datastore_id = "data-storage" }
    }
  }

  expect_failures = [var.cpu_cores, var.memory_size, var.root_disk, var.additional_disks]
}

run "invalid_disk_slots_when_supplied_fail_validation" {
  command = plan

  variables {
    root_disk = { slot = "scsi31", size_gb = 128 }
    additional_disks = {
      virtio16 = { size_gb = 64, datastore_id = "data-storage" }
      sata6    = { size_gb = 64, datastore_id = "data-storage" }
      ide4     = { size_gb = 64, datastore_id = "data-storage" }
      scsi01   = { size_gb = 64, datastore_id = "data-storage" }
      net0     = { size_gb = 64, datastore_id = "data-storage" }
    }
  }

  expect_failures = [var.root_disk, var.additional_disks]
}

run "disk_slot_boundaries_when_supplied_are_accepted" {
  command = plan

  variables {
    cpu_cores   = 1024
    memory_size = 64
    root_disk   = { slot = "scsi30", size_gb = 10240 }
    additional_disks = {
      virtio15 = { size_gb = 1, datastore_id = "data-storage" }
      sata5    = { size_gb = 1, datastore_id = "data-storage" }
      ide3     = { size_gb = 1, datastore_id = "data-storage" }
    }
  }

  assert {
    condition     = toset(keys(proxmox_cloned_vm.vm[0].disk)) == toset(["scsi30", "virtio15", "sata5", "ide3"])
    error_message = "Supported disk slot and numeric boundaries must be accepted."
  }
}

run "missing_disk_values_when_supplied_fail_validation" {
  command = plan

  variables {
    root_disk = { slot = "scsi0", size_gb = null }
    additional_disks = {
      scsi1 = { size_gb = null, datastore_id = null }
      scsi2 = { size_gb = 64, datastore_id = " " }
    }
    tags = [null]
  }

  expect_failures = [var.root_disk, var.additional_disks, var.tags]
}

run "null_disk_entries_when_supplied_fail_validation" {
  command = plan

  variables {
    additional_disks = { scsi1 = null }
  }

  expect_failures = [var.additional_disks]
}

run "null_root_slot_when_supplied_fails_validation" {
  command = plan

  variables {
    root_disk = { slot = null, size_gb = 128 }
  }

  expect_failures = [var.root_disk]
}

run "empty_tags_when_supplied_explicitly_clear_tags" {
  command = plan

  variables {
    tags = []
  }

  assert {
    condition     = length(proxmox_cloned_vm.vm[0].tags) == 0
    error_message = "An explicit empty tag set must not be treated as an omitted override."
  }
}
