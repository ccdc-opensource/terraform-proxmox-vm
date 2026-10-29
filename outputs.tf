output "vm_ids" {
  description = "Proxmox-assigned VM identifiers in count-index order."
  value       = tolist(proxmox_cloned_vm.vm[*].id)
}

output "vm_names" {
  description = "Indexed VM names in count-index order."
  value       = tolist(proxmox_cloned_vm.vm[*].name)
}

output "node_names" {
  description = "Proxmox nodes hosting the VMs in count-index order."
  value       = tolist(proxmox_cloned_vm.vm[*].node_name)
}