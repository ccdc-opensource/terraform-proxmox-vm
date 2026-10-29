output "vm_ids" {
  description = "Proxmox-assigned VM identifiers in count-index order."
  value       = tolist(concat(proxmox_virtual_environment_vm.vm[*].vm_id, proxmox_cloned_vm.vm[*].id))
}

output "vm_names" {
  description = "Indexed VM names in count-index order."
  value       = tolist(concat(proxmox_virtual_environment_vm.vm[*].name, proxmox_cloned_vm.vm[*].name))
}

output "node_names" {
  description = "Proxmox nodes in count-index order. Legacy mode refreshes the current node after external migration."
  value       = tolist(concat(proxmox_virtual_environment_vm.vm[*].node_name, proxmox_cloned_vm.vm[*].node_name))
}
