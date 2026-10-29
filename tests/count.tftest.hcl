mock_provider "proxmox" {
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
}

run "count_omitted_when_applied_creates_one_indexed_vm" {
  command = apply

  assert {
    condition = (
      length(proxmox_cloned_vm.vm) == 1 &&
      output.vm_ids == tolist([200]) &&
      output.vm_names == tolist(["sandbox-01"]) &&
      output.node_names == tolist(["pve-test"])
    )
    error_message = "The default count must create one VM and expose ordered list outputs."
  }
}

run "count_increased_when_applied_keeps_first_name_and_adds_unique_vms" {
  command = apply

  variables {
    vm_count = 3
    root_disk = {
      slot    = "scsi0"
      size_gb = 128
    }
    additional_disks = {
      scsi1 = { size_gb = 64, datastore_id = "data-storage" }
    }
  }

  assert {
    condition = (
      length(proxmox_cloned_vm.vm) == 3 &&
      length(output.vm_ids) == 3 &&
      output.vm_names == tolist(["sandbox-01", "sandbox-02", "sandbox-03"]) &&
      output.vm_names[0] == run.count_omitted_when_applied_creates_one_indexed_vm.vm_names[0] &&
      output.node_names == tolist(["pve-test", "pve-test", "pve-test"])
    )
    error_message = "Scaling up must preserve the first name and produce unique indexed names and matching lists."
  }

  assert {
    condition = alltrue([
      for vm in proxmox_cloned_vm.vm :
      vm.clone.source_vm_id == 100 &&
      vm.disk.scsi0.size_gb == 128 &&
      vm.disk.scsi1.size_gb == 64 &&
      vm.disk.scsi1.datastore_id == "data-storage"
    ])
    error_message = "Every VM must receive the template and disk configuration."
  }
}

run "count_reduced_to_one_when_applied_keeps_first_name" {
  command = apply

  variables {
    vm_count = 1
  }

  assert {
    condition = (
      length(proxmox_cloned_vm.vm) == 1 &&
      output.vm_names == tolist(["sandbox-01"]) &&
      output.vm_names[0] == run.count_increased_when_applied_keeps_first_name_and_adds_unique_vms.vm_names[0]
    )
    error_message = "Scaling down to one must retain the first indexed name."
  }
}

run "count_zero_when_applied_returns_empty_lists" {
  command = apply

  variables {
    vm_count = 0
  }

  assert {
    condition = (
      length(proxmox_cloned_vm.vm) == 0 &&
      length(output.vm_ids) == 0 &&
      length(output.vm_names) == 0 &&
      length(output.node_names) == 0
    )
    error_message = "A count of zero must produce no VMs and empty lists."
  }
}

run "count_null_when_applied_uses_default" {
  command = apply

  variables {
    vm_count = null
  }

  assert {
    condition     = length(proxmox_cloned_vm.vm) == 1 && output.vm_names == tolist(["sandbox-01"])
    error_message = "A null count must use the non-null default of one."
  }
}

run "fractional_count_when_supplied_fails_validation" {
  command = plan

  variables {
    vm_count = 1.5
  }

  expect_failures = [var.vm_count]
}

run "negative_count_when_supplied_fails_validation" {
  command = plan

  variables {
    vm_count = -1
  }

  expect_failures = [var.vm_count]
}
