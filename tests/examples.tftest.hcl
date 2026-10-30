mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_vm" {
    defaults = {
      vm_id = 200
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
}

run "minimal_example_when_applied_exposes_vm_ids" {
  command = apply

  module {
    source = "./examples/minimal"
  }

  variables {
    vm_name = "minimal-test"
    root_disk = {
      slot         = "scsi0"
      size_gb      = 128
      datastore_id = "root-storage"
    }
  }

  assert {
    condition     = output.vm_ids == tolist([200])
    error_message = "The minimal example must expose its module VM IDs."
  }
}

run "disk_example_when_applied_exposes_vm_ids" {
  command = apply

  module {
    source = "./examples/disks"
  }

  variables {
    vm_name        = "disk-test"
    datastore_id   = "data-storage"
    network_bridge = "vmbr-test"
  }

  assert {
    condition     = output.vm_ids == tolist([200])
    error_message = "The disk override example must be usable with the module interface."
  }
}
