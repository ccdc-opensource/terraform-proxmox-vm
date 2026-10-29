variable "vm_mode" {
  description = "VM implementation: legacy (default) or experimental (clone-specific). Changing modes requires a state migration or VM replacement."
  type        = string
  default     = "legacy"
  nullable    = false

  validation {
    condition     = contains(["legacy", "experimental"], var.vm_mode)
    error_message = "vm_mode must be legacy or experimental."
  }
}

variable "node_name" {
  description = "Initial Proxmox node. Legacy mode ignores later node changes to permit external placement; experimental mode enforces this node."
  type        = string
  nullable    = false

  validation {
    condition     = trimspace(var.node_name) != ""
    error_message = "node_name must not be empty or whitespace."
  }
}

variable "vm_name" {
  description = "Base VM name. Each clone gets an indexed suffix such as -01; does not configure guest hostnames."
  type        = string
  nullable    = false

  validation {
    condition     = trimspace(var.vm_name) != ""
    error_message = "vm_name must not be empty or whitespace."
  }
}

variable "vm_count" {
  description = "Number of identical VMs to create. Reducing this destroys the highest-index instances."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.vm_count >= 0 && floor(var.vm_count) == var.vm_count
    error_message = "vm_count must be a non-negative integer."
  }
}

variable "source_vm_id" {
  description = "ID of the prepared Linux or Windows template to clone."
  type        = number
  nullable    = false

  validation {
    condition     = var.source_vm_id >= 1 && floor(var.source_vm_id) == var.source_vm_id
    error_message = "source_vm_id must be a positive integer."
  }
}

variable "source_node_name" {
  description = "Source template node. When null, the provider uses node_name."
  type        = string
  default     = null

  validation {
    condition     = var.source_node_name == null ? true : trimspace(var.source_node_name) != ""
    error_message = "source_node_name must be null or a non-empty node name."
  }
}

variable "target_datastore" {
  description = "Optional datastore for the full clone. Changing clone settings requires replacement."
  type        = string
  default     = null

  validation {
    condition     = var.target_datastore == null ? true : trimspace(var.target_datastore) != ""
    error_message = "target_datastore must be null or a non-empty datastore name."
  }
}

variable "vm_description" {
  description = "Optional description override. When null, leave the template description unmanaged."
  type        = string
  default     = null
}

variable "tags" {
  description = "Optional tag override. Null leaves tags unmanaged; an empty set clears them."
  type        = set(string)
  default     = null

  validation {
    condition = var.tags == null ? true : alltrue([
      for tag in var.tags : tag == null ? false : trimspace(tag) != ""
    ])
    error_message = "tags must contain only non-empty, non-null strings."
  }
}

variable "cpu_cores" {
  description = "Optional cores per socket (1-1024). Legacy CPU-block defaults can also affect other CPU settings."
  type        = number
  default     = null

  validation {
    condition     = var.cpu_cores == null ? true : var.cpu_cores >= 1 && var.cpu_cores <= 1024 && floor(var.cpu_cores) == var.cpu_cores
    error_message = "cpu_cores must be null or an integer between 1 and 1024."
  }
}

variable "memory_size" {
  description = "Optional RAM in MiB (64-268435456). Review legacy memory-block defaults and template ballooning settings."
  type        = number
  default     = null

  validation {
    condition     = var.memory_size == null ? true : var.memory_size >= 64 && var.memory_size <= 268435456 && floor(var.memory_size) == var.memory_size
    error_message = "memory_size must be null or an integer between 64 and 268435456 MiB."
  }
}

variable "network_bridge" {
  description = "Optional VirtIO net0 bridge override. Can reset NIC options; legacy mode manages the entire NIC list when supplied."
  type        = string
  default     = null

  validation {
    condition     = var.network_bridge == null ? true : trimspace(var.network_bridge) != ""
    error_message = "network_bridge must be null or a non-empty bridge name."
  }
}

variable "root_disk" {
  description = "Existing OS disk slot and desired GiB size. Required with datastore_id in legacy mode; optional in experimental mode. Grow only."
  type = object({
    slot         = string
    size_gb      = number
    datastore_id = optional(string)
  })
  default = null

  validation {
    condition     = var.root_disk == null ? true : can(regex("^(ide[0-3]|sata[0-5]|scsi([0-9]|[12][0-9]|30)|virtio([0-9]|1[0-5]))$", var.root_disk.slot))
    error_message = "root_disk.slot must be ide0-ide3, sata0-sata5, scsi0-scsi30, or virtio0-virtio15."
  }

  validation {
    condition = var.root_disk == null ? true : (
      var.root_disk.size_gb == null ? false :
      var.root_disk.size_gb >= 1 && var.root_disk.size_gb <= 10240 && floor(var.root_disk.size_gb) == var.root_disk.size_gb
    )
    error_message = "root_disk.size_gb must be an integer between 1 and 10240 GiB."
  }

  validation {
    condition = var.root_disk == null ? true : (
      var.root_disk.datastore_id == null ? true : trimspace(var.root_disk.datastore_id) != ""
    )
    error_message = "root_disk.datastore_id must be null or a non-empty datastore name."
  }
}

variable "additional_disks" {
  description = "Data disks keyed by slot. Legacy mode requires the complete data-disk set and can remove omitted disks; experimental mode only manages listed slots."
  type = map(object({
    size_gb      = number
    datastore_id = string
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for slot in keys(var.additional_disks) :
      can(regex("^(ide[0-3]|sata[0-5]|scsi([0-9]|[12][0-9]|30)|virtio([0-9]|1[0-5]))$", slot))
    ])
    error_message = "additional_disks keys must be ide0-ide3, sata0-sata5, scsi0-scsi30, or virtio0-virtio15."
  }

  validation {
    condition = alltrue([
      for disk in var.additional_disks : disk == null ? false : (
        disk.size_gb == null ? false :
        disk.size_gb >= 1 && disk.size_gb <= 10240 && floor(disk.size_gb) == disk.size_gb
      )
    ])
    error_message = "Each additional disk must have an integer size_gb between 1 and 10240 GiB."
  }

  validation {
    condition = alltrue([
      for disk in var.additional_disks : disk == null ? false : (
        disk.datastore_id == null ? false : trimspace(disk.datastore_id) != ""
      )
    ])
    error_message = "Each additional disk must have a non-empty datastore_id."
  }
}
