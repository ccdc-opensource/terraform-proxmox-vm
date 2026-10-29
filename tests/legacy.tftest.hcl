mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_vm" {
    defaults = {
      vm_id = 300
    }
  }

  mock_resource "proxmox_cloned_vm" {
    defaults = {
      id = 200
    }
  }
}

variables {
  node_name    = "pve-test"
  source_vm_id = 100
  vm_name      = "sandbox"
  root_disk = {
    slot         = "scsi0"
    size_gb      = 128
    datastore_id = "root-storage"
  }
}

run "mode_omitted_when_applied_creates_only_legacy_vm" {
  command = apply

  assert {
    condition = (
      length(proxmox_virtual_environment_vm.vm) == 1 &&
      length(proxmox_cloned_vm.vm) == 0 &&
      output.vm_ids == tolist([300]) &&
      output.vm_names == tolist(["sandbox-01"]) &&
      output.node_names == tolist(["pve-test"])
    )
    error_message = "Legacy must be the default, with numeric VM IDs and the existing list output interface."
  }

  assert {
    condition = (
      proxmox_virtual_environment_vm.vm[0].clone[0].vm_id == 100 &&
      proxmox_virtual_environment_vm.vm[0].clone[0].full &&
      proxmox_virtual_environment_vm.vm[0].started &&
      !proxmox_virtual_environment_vm.vm[0].delete_unreferenced_disks_on_destroy &&
      length(proxmox_virtual_environment_vm.vm[0].cpu) == 0 &&
      length(proxmox_virtual_environment_vm.vm[0].memory) == 0 &&
      length(proxmox_virtual_environment_vm.vm[0].disk) == 1 &&
      proxmox_virtual_environment_vm.vm[0].disk[0].interface == "scsi0" &&
      proxmox_virtual_environment_vm.vm[0].disk[0].size == 128 &&
      proxmox_virtual_environment_vm.vm[0].disk[0].datastore_id == "root-storage"
    )
    error_message = "Legacy must map the clone and root disk explicitly without adding CPU/RAM overrides or unsafe destroy settings."
  }
}

run "legacy_node_input_changed_when_planned_preserves_current_placement" {
  command = plan

  variables {
    node_name = "another-node"
  }

  assert {
    condition     = output.node_names == tolist(["pve-test"])
    error_message = "Legacy must ignore requested placement changes after creation so external placement remains authoritative."
  }
}

run "legacy_overrides_when_applied_map_all_shared_inputs" {
  command = apply

  variables {
    vm_count         = 3
    source_node_name = "pve-source"
    target_datastore = "clone-storage"
    cpu_cores        = 4
    memory_size      = 8192
    network_bridge   = "vmbr-test"
    vm_description   = "Legacy test"
    tags             = ["test-vms", "requestor-test"]
    root_disk = {
      slot         = "sata0"
      size_gb      = 256
      datastore_id = "clone-storage"
    }
    additional_disks = {
      scsi1 = { size_gb = 64, datastore_id = "data-storage" }
      scsi2 = { size_gb = 128, datastore_id = "data-storage" }
    }
  }

  assert {
    condition = (
      length(proxmox_virtual_environment_vm.vm) == 3 &&
      length(proxmox_cloned_vm.vm) == 0 &&
      length(output.vm_ids) == 3 &&
      output.vm_names == tolist(["sandbox-01", "sandbox-02", "sandbox-03"])
    )
    error_message = "Legacy count must produce uniquely indexed names and matching list outputs."
  }

  assert {
    condition = alltrue([
      for vm in proxmox_virtual_environment_vm.vm :
      vm.clone[0].node_name == "pve-source" &&
      vm.clone[0].datastore_id == "clone-storage" &&
      vm.cpu[0].cores == 4 &&
      vm.memory[0].dedicated == 8192 &&
      vm.network_device[0].bridge == "vmbr-test" &&
      vm.network_device[0].model == "virtio" &&
      vm.description == "Legacy test" &&
      toset(vm.tags) == toset(["test-vms", "requestor-test"])
    ])
    error_message = "Legacy must forward placement, sizing, network, and metadata overrides to every instance."
  }

  assert {
    condition = alltrue([
      for vm in proxmox_virtual_environment_vm.vm :
      length(vm.disk) == 3 &&
      alltrue([
        for disk in vm.disk :
        disk.interface == "sata0" ? disk.size == 256 && disk.datastore_id == "clone-storage" :
        disk.interface == "scsi1" ? disk.size == 64 && disk.datastore_id == "data-storage" :
        disk.interface == "scsi2" ? disk.size == 128 && disk.datastore_id == "data-storage" : false
      ])
    ])
    error_message = "Legacy dynamic disk blocks must preserve explicit slots, sizes, and datastores."
  }
}

run "mode_switched_when_planned_selects_experimental_not_a_state_conversion" {
  command = plan

  variables {
    vm_mode   = "experimental"
    vm_count  = 3
    root_disk = null
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.vm) == 0 && length(proxmox_cloned_vm.vm) == 3
    error_message = "Switching mode selects different resource addresses; it must not pretend to migrate existing state."
  }
}

run "legacy_count_reduced_when_applied_keeps_first_name" {
  command = apply

  variables {
    vm_count = 1
  }

  assert {
    condition     = output.vm_names == tolist(["sandbox-01"]) && length(output.vm_ids) == 1
    error_message = "Reducing legacy count to one must retain the first indexed name."
  }
}

run "legacy_zero_count_when_applied_returns_empty_lists" {
  command = apply

  variables {
    vm_count  = 0
    root_disk = null
  }

  assert {
    condition = (
      length(proxmox_virtual_environment_vm.vm) == 0 &&
      length(proxmox_cloned_vm.vm) == 0 &&
      length(output.vm_ids) == 0 &&
      length(output.vm_names) == 0 &&
      length(output.node_names) == 0
    )
    error_message = "Zero count must create neither resource type and return empty lists."
  }
}

run "null_mode_when_applied_uses_legacy_default" {
  command = apply

  variables {
    vm_mode = null
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.vm) == 1 && length(proxmox_cloned_vm.vm) == 0
    error_message = "A null mode must use the legacy default."
  }
}

run "legacy_without_root_disk_when_planned_fails_explicitly" {
  command = plan

  variables {
    root_disk = null
  }

  expect_failures = [proxmox_virtual_environment_vm.vm]
}

run "legacy_without_root_datastore_when_planned_fails_explicitly" {
  command = plan

  variables {
    root_disk = { slot = "scsi0", size_gb = 128 }
  }

  expect_failures = [proxmox_virtual_environment_vm.vm]
}

run "legacy_duplicate_root_slot_when_planned_fails_explicitly" {
  command = plan

  variables {
    additional_disks = {
      scsi0 = { size_gb = 64, datastore_id = "data-storage" }
    }
  }

  expect_failures = [proxmox_virtual_environment_vm.vm]
}

run "invalid_mode_when_supplied_fails_validation" {
  command = plan

  variables {
    vm_mode = "migration_aware"
  }

  expect_failures = [var.vm_mode]
}

run "empty_root_datastore_when_supplied_fails_validation" {
  command = plan

  variables {
    root_disk = { slot = "scsi0", size_gb = 128, datastore_id = " " }
  }

  expect_failures = [var.root_disk]
}
