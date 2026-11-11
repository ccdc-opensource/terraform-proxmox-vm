mock_provider "proxmox" {}

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

run "omitted_cloud_init_does_not_add_initialization" {
  command = plan

  assert {
    condition     = length(proxmox_virtual_environment_vm.vm[0].initialization) == 0
    error_message = "Existing deployments must not gain cloud-init configuration."
  }
}

run "null_cloud_init_does_not_add_initialization" {
  command = plan

  variables {
    cloud_init = null
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.vm[0].initialization) == 0
    error_message = "Explicit null must omit initialization."
  }
}

run "hostname_only_uses_each_indexed_vm_name_without_optional_blocks" {
  command = plan

  variables {
    vm_count   = 2
    cloud_init = {}
  }

  assert {
    condition = (
      output.vm_names == tolist(["sandbox-01", "sandbox-02"]) &&
      alltrue([
        for vm in proxmox_virtual_environment_vm.vm :
        vm.started &&
        vm.clone[0].vm_id == 100 &&
        length(vm.initialization) == 1 &&
        length(vm.initialization[0].dns) == 0 &&
        length(vm.initialization[0].user_account) == 0 &&
        length(vm.initialization[0].ip_config) == 0
      ])
    )
    error_message = "Hostname-only clones must use indexed names and omit DNS, account, and network overrides."
  }
}

run "dns_only_omits_account_and_network" {
  command = plan

  variables {
    cloud_init = {
      datastore_id = "cloud-storage"
      dns = {
        servers = ["192.168.1.1"]
      }
    }
  }

  assert {
    condition = (
      proxmox_virtual_environment_vm.vm[0].initialization[0].datastore_id == "cloud-storage" &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].dns[0].servers == tolist(["192.168.1.1"]) &&
      length(proxmox_virtual_environment_vm.vm[0].initialization[0].user_account) == 0 &&
      length(proxmox_virtual_environment_vm.vm[0].initialization[0].ip_config) == 0
    )
    error_message = "DNS-only settings must not emit account or networking blocks."
  }
}

run "account_only_omits_dns_and_network" {
  command = plan

  variables {
    cloud_init = {
      user_account = {
        username = "ubuntu"
      }
    }
  }

  assert {
    condition = (
      proxmox_virtual_environment_vm.vm[0].initialization[0].user_account[0].username == "ubuntu" &&
      length(proxmox_virtual_environment_vm.vm[0].initialization[0].dns) == 0 &&
      length(proxmox_virtual_environment_vm.vm[0].initialization[0].ip_config) == 0
    )
    error_message = "Account-only settings must not emit DNS or networking blocks."
  }
}

run "explicit_settings_map_to_native_cloud_init" {
  command = plan

  variables {
    cloud_init = {
      datastore_id = "cloud-storage"
      interface    = "ide0"
      file_format  = "raw"
      type         = "nocloud"
      upgrade      = false
      dns = {
        domain  = "example.internal"
        servers = ["192.168.1.1", "192.168.1.2"]
      }
      user_account = {
        username = "ubuntu"
        keys     = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest test@example"]
        password = "test-only-password"
      }
      ip_config = [
        { ipv4 = { address = "dhcp" } },
        { ipv6 = { address = "auto" } },
        {
          ipv4 = { address = "192.168.2.50/24", gateway = "192.168.2.1" }
          ipv6 = { address = "fd00::50/64", gateway = "fd00::1" }
        }
      ]
    }
  }

  assert {
    condition = (
      proxmox_virtual_environment_vm.vm[0].initialization[0].datastore_id == "cloud-storage" &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].interface == "ide0" &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].file_format == "raw" &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].type == "nocloud" &&
      !proxmox_virtual_environment_vm.vm[0].initialization[0].upgrade &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].dns[0].domain == "example.internal" &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].dns[0].servers == tolist(["192.168.1.1", "192.168.1.2"]) &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].user_account[0].username == "ubuntu" &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].user_account[0].keys == tolist(["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest test@example"]) &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].user_account[0].password == "test-only-password"
    )
    error_message = "Explicit storage, DNS, account, format, and upgrade settings must be forwarded."
  }

  assert {
    condition = (
      length(proxmox_virtual_environment_vm.vm[0].initialization[0].ip_config) == 3 &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].ip_config[0].ipv4[0].address == "dhcp" &&
      length(proxmox_virtual_environment_vm.vm[0].initialization[0].ip_config[0].ipv6) == 0 &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].ip_config[1].ipv6[0].address == "auto" &&
      length(proxmox_virtual_environment_vm.vm[0].initialization[0].ip_config[1].ipv4) == 0 &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].ip_config[2].ipv4[0].address == "192.168.2.50/24" &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].ip_config[2].ipv4[0].gateway == "192.168.2.1" &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].ip_config[2].ipv6[0].address == "fd00::50/64" &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].ip_config[2].ipv6[0].gateway == "fd00::1"
    )
    error_message = "NIC order and optional IPv4/IPv6 blocks must be preserved."
  }
}

run "custom_file_references_are_forwarded" {
  command = plan

  variables {
    cloud_init = {
      user_data_file_id    = "local:snippets/user.yaml"
      vendor_data_file_id  = "local:snippets/vendor.yaml"
      network_data_file_id = "local:snippets/network.yaml"
      meta_data_file_id    = "local:snippets/meta.yaml"
    }
  }

  assert {
    condition = (
      proxmox_virtual_environment_vm.vm[0].initialization[0].user_data_file_id == "local:snippets/user.yaml" &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].vendor_data_file_id == "local:snippets/vendor.yaml" &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].network_data_file_id == "local:snippets/network.yaml" &&
      proxmox_virtual_environment_vm.vm[0].initialization[0].meta_data_file_id == "local:snippets/meta.yaml" &&
      length(proxmox_virtual_environment_vm.vm[0].initialization[0].user_account) == 0 &&
      length(proxmox_virtual_environment_vm.vm[0].initialization[0].ip_config) == 0
    )
    error_message = "Custom files must be forwarded without conflicting generated configuration."
  }
}

run "experimental_mode_rejects_cloud_init" {
  command = plan

  variables {
    vm_mode    = "experimental"
    cloud_init = {}
  }

  expect_failures = [proxmox_cloned_vm.vm]
}

run "custom_user_data_conflicts_with_user_account" {
  command = plan

  variables {
    cloud_init = {
      user_data_file_id = "local:snippets/user.yaml"
      user_account      = { username = "ubuntu" }
    }
  }

  expect_failures = [var.cloud_init]
}

run "custom_network_data_conflicts_with_ip_config" {
  command = plan

  variables {
    cloud_init = {
      network_data_file_id = "local:snippets/network.yaml"
      ip_config            = [{ ipv4 = { address = "dhcp" } }]
    }
  }

  expect_failures = [var.cloud_init]
}

run "empty_ip_config_entry_is_rejected" {
  command = plan

  variables {
    cloud_init = { ip_config = [{}] }
  }

  expect_failures = [var.cloud_init]
}

run "null_ip_config_entry_is_rejected" {
  command = plan

  variables {
    cloud_init = { ip_config = [null] }
  }

  expect_failures = [var.cloud_init]
}
