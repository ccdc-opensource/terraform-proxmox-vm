# terraform-proxmox-vm

A VM module using `bpg/proxmox`, defaulting to the legacy VM resource.
It creates and starts full clones of prepared Linux or Windows templates.
Set `vm_count` to change the number of VMs, or explicitly opt into the
experimental clone-specific implementation.

## Resource modes

| `vm_mode` | Resource | Behaviour |
| --- | --- | --- |
| `"legacy"` (default) | `proxmox_virtual_environment_vm` | Explicit boot-disk configuration; permits externally managed node placement. |
| `"experimental"` | `proxmox_cloned_vm` | Opt-in hardware management; fixed-node deployment. |

`experimental` is this module's label for the clone-specific implementation.
It does not select the separate provider resource named `proxmox_vm`.

In legacy mode, Terraform ignores `node_name` changes after creation so that
ProxLB or another external system can own placement. Editing `node_name` will
not request a Terraform migration. The provider discovers the current node
during refresh, but live migration, subsequent updates, and destruction must
be tested on your cluster before relying on this integration. The module does
not install, configure, or invoke ProxLB.

## Requirements

- Terraform >= 1.7.0.
- `bpg/proxmox ~> 0.118.1`.
- An existing, bootable template and permissions to clone/configure VMs on the
  target node and storage.
- Provider authentication configured in the calling root module. Use the
  provider's supported environment variables, such as
  `PROXMOX_VE_ENDPOINT` and `PROXMOX_VE_API_TOKEN`; do not commit credentials.

Provider configuration belongs in the root module, not this child module.
Keep TLS verification enabled and configure trust for your Proxmox certificate.

## Minimal deployment

From a checkout, see the runnable [minimal example](examples/minimal/main.tf).
When referencing this repository remotely, use an approved immutable module
revision rather than a moving branch.

```hcl
provider "proxmox" {}

module "vm" {
  source = "./modules/terraform-proxmox-vm"

  node_name    = "pve"
  source_vm_id = 100
  vm_name      = "sandbox"

  root_disk = {
    slot         = "scsi0"
    size_gb      = 128
    datastore_id = "local-lvm"
  }
}
```

The local source above assumes the module is checked out at that path. Your root
configuration must also declare the `bpg/proxmox` provider requirement; complete
examples include that declaration.

This creates `sandbox-01`; `vm_count` defaults to `1`. Proxmox allocates each VM
ID. Replace the illustrative boot-disk slot, capacity, and datastore with your
template's settings. Legacy mode requires these explicitly to avoid the
provider's implicit 8 GiB / `local-lvm` disk defaults. The datastore must match
the desired OS disk location after cloning; changing it can move the disk.

For the previous minimal template-only behaviour, set
`vm_mode = "experimental"` and omit `root_disk`. Only the target node, template
ID, and base name are then required.

## Template preparation

Templates, not this module, configure DHCP and the operating system.

- **Linux:** prepare unique machine identity and DHCP client identity on cloning,
  enable DHCP, install required disk/NIC drivers, and prepare any cloud-init
  configuration in advance.
- **Windows:** use a suitably generalised template and first-boot process, enable
  DHCP, and include required disk/NIC drivers. Configure EFI, secure boot, and
  TPM on the template when required.
- **Both:** confirm the boot disk slot and size, network bridge, DHCP availability,
  boot order, and any guest-agent configuration before cloning.

The VM name in Proxmox does not set the guest hostname. A successful apply or a
started VM does not prove that the guest has booted or obtained a DHCP lease.
The module does not expose guest IP addresses, keeping outputs consistent
between resource modes.

## Inputs

Optional inputs default to `null` unless shown otherwise. Null means the module
does not supply that override; it does not restore an earlier template setting.
Legacy provider defaults may still apply.

| Input | Type | Purpose |
| --- | --- | --- |
| `vm_mode` | string | `"legacy"` by default; `"experimental"` is an explicit opt-in. |
| `node_name` | string | Required initial node; only experimental mode enforces later changes. |
| `vm_name` | string | Required base name; each VM gets an indexed suffix such as `-01`. |
| `vm_count` | number | Non-negative integer VM count; default `1` (also used for null). |
| `source_vm_id` | number | Required positive integer template ID. |
| `source_node_name` | string | Source node; omitted means the target node. |
| `target_datastore` | string | Optional clone-storage override. |
| `vm_description` | string | Optional description override. |
| `tags` | set(string) | Optional tags; `[]` explicitly clears tags. |
| `cpu_cores` | number | Cores per socket, integer 1-1024. |
| `memory_size` | number | RAM in MiB, integer 64-268435456. |
| `network_bridge` | string | Opt into managing `net0` as a VirtIO NIC on this bridge. |
| `root_disk` | object | OS disk `slot`, `size_gb`, and optional `datastore_id`; all three are required in legacy mode. |
| `additional_disks` | map(object) | Disk slot to `{ size_gb, datastore_id }`; default `{}`. |

CPU and memory configuration is omitted unless overrides are supplied.
Experimental mode sends only the requested fields. Legacy mode uses nested
blocks whose defaults can also affect sockets, CPU type, and ballooning.
Review the plan against the template rather than assuming partial-block
inheritance. A root disk is mandatory in legacy mode when `vm_count` is nonzero.

### Legacy configuration ownership

Legacy mode does not provide the clone-specific resource's opt-in management
contract:

- Supply the OS disk datastore explicitly. The module does not guess it or
  silently use `local-lvm`.
- Include the complete intended data-disk set in `additional_disks`. Removing
  entries, or omitting inherited data disks, can remove/detach disks during
  reconciliation. Do not treat omission as relinquishing management.
- When `network_bridge` is supplied, the resource manages a single VirtIO NIC
  list. This can remove additional NICs and reset VLAN/firewall/other options.
  Leave it null to avoid supplying a network override.
- Review BIOS, EFI, TPM, cloud-init, agent, CPU, and memory settings against the
  provider's defaults for both Linux and Windows templates.
- Changing disk datastores can move existing volumes.

### Experimental device-override limitations

Omitted devices are unmanaged, but partial device overrides do not guarantee
preservation of other options. In provider v0.118.1:

- Setting `network_bridge` reconstructs `net0` as VirtIO. Unspecified VLAN,
  firewall, MTU, MAC, and other NIC settings can change/reset. Use this override
  only for a simple network with VirtIO drivers; leave it unset when you need
  the inherited NIC configuration.
- Managing an existing disk preserves its volume reference but can reset
  unspecified cache, discard, I/O-thread, and other disk options. Use root-disk
  growth only where those provider/default options are acceptable.

These are provider constraints, not inheritance guarantees the module can add.
Templates requiring custom NIC or disk tuning should retain their inherited
devices until explicit support for those settings is added.

## Growing disks and adding data disks

```hcl
module "vm" {
  source = "./modules/terraform-proxmox-vm"

  node_name    = "pve"
  source_vm_id = 100
  vm_name      = "sandbox"
  cpu_cores    = 4
  memory_size  = 8192

  root_disk = {
    slot         = "scsi0"
    size_gb      = 128
    datastore_id = "local-lvm"
  }

  additional_disks = {
    scsi1 = { size_gb = 64, datastore_id = "local-lvm" }
    scsi2 = { size_gb = 256, datastore_id = "local-lvm" }
  }
}
```

The [disk example](examples/disks/main.tf) also demonstrates an explicit bridge
override. Adapt the slots, sizes, and storage to your template.

- Sizes are integer **GiB**, from 1 to 10240, the module's shared range.
- Supported slots are `ide0`-`ide3`, `sata0`-`sata5`, `scsi0`-`scsi30`, and
  `virtio0`-`virtio15`. Guest machine/controller constraints still apply.
- `root_disk.slot` must already contain the OS disk. The module does not assume
  that every template boots from `scsi0`.
- Use unused slots when creating additional disks. In legacy mode also describe
  inherited data disks you intend to retain. The module rejects a collision
  with the declared root slot but cannot inspect template devices statically.
- Disks can grow, not shrink. A smaller requested size produces a provider error
  against the actual disk size. Existing template sizes are not known to static
  input validation.
- `target_datastore` controls clone placement. In legacy mode per-disk
  `datastore_id` also controls placement and can move existing disks. In
  experimental mode it allocates additional disks but does not migrate existing
  volumes; `root_disk.datastore_id` is unused in that mode.
- Expanding a virtual disk does not guarantee expansion of the guest partition
  or filesystem. Formatting/mounting new data disks is also a guest task.
- In experimental mode removing an entry stops management without deletion.
  In legacy mode removal can remove/detach the disk. Changing a slot is not a
  disk rename in either mode.

The module constructs a disk map for experimental mode and uses `dynamic`
disk blocks for legacy mode.

## Built-in VM count

Set `vm_count` directly on the module. No caller-level `count` is required:

```hcl
module "vm" {
  source = "./modules/terraform-proxmox-vm"

  node_name    = "pve"
  source_vm_id = 100
  vm_name      = "sandbox"
  vm_count     = 3

  root_disk = {
    slot         = "scsi0"
    size_gb      = 128
    datastore_id = "local-lvm"
  }
}

output "vm_ids" {
  value = module.vm.vm_ids
}
```

This creates `sandbox-01`, `sandbox-02`, and `sandbox-03` with the same template
and configuration. Names always include the suffix, even for one VM, so changing
the count does not rename existing instances. Choose the Linux or Windows
template ID for each fleet.

Reducing `vm_count` destroys the highest-index VMs. Setting it to zero destroys
all managed VMs and returns empty output lists. The count must be known at plan
time. Use separate module calls if you need different per-VM configurations.

## Outputs

| Output | Meaning |
| --- | --- |
| `vm_ids` | List of Proxmox-assigned numeric VM IDs, in index order. |
| `vm_names` | List of indexed VM names, in index order. |
| `node_names` | List of nodes in index order; legacy mode refreshes actual placement. |

Outputs are lists for every count, including one and zero.

## Lifecycle and scope

Mode changes and clone settings can require replacement. Experimental mode also
requires replacement for target-node changes; legacy mode ignores node changes
after creation. Always inspect the plan before applying. No explicit `ide2`
deletion is configured, but legacy resource defaults and reconciliation still
need review.

`delete_unreferenced_disks_on_destroy` is explicitly false. **This does not
protect the VM or its attached disks from `terraform destroy`.** Standard
provider shutdown/purge behaviour still applies.

Deferred features include static IPs, per-VM cloud-init/Cloudbase-Init, credentials
or SSH key injection, guest hostname/domain join, template creation, additional
NICs, VLAN/firewall controls, device tuning/deletion, linked clones, passthrough,
HA, backups, and advanced timeouts.

Legacy mode provides a foundation for externally managed placement; actual
ProxLB configuration and live acceptance are outside this module.

### Changes from the initial draft

- Node, VM name, and template ID are required instead of environment-specific
  defaults.
- Optional values use null, not invalid empty-string numeric/boolean defaults.
- `disk_size_gb` and `disk_datastore_id` are replaced by `root_disk` and
  `additional_disks`. Select the existing root slot explicitly.
- CPU architecture/type/sockets, ballooning/shares, NIC tuning, disk tuning, VGA,
  deletion, timeouts, clone retries, and destroy-option inputs are not exposed
  in the baseline. Full clone is fixed to true.
- The default `ide2` deletion is removed.
- `vm_count` is built in and defaults to one. `vm_name` is now a base name;
  the module appends `-01`, `-02`, and so on.
- Singular outputs are replaced by `vm_ids`, `vm_names`, and `node_names`.
  Update callers to consume lists.
- `vm_mode` now defaults to `"legacy"`. Existing clone-backed deployments need
  an explicit `"experimental"` selection to preserve the old resource type.

The module retains a `moved` block from the earlier singleton cloned resource to
index zero in experimental mode. It does not convert state between modes.
An existing VM's name gains the `-01` suffix. Inspect the migration plan before
applying. If migrating from caller-level module `count` to this built-in input,
the caller must also explicitly migrate module addresses; the internal `moved`
block does not handle that change.

Review existing callers and Terraform state before adopting this draft API.

## Validation

From the module directory:

```sh
terraform init -backend=false -input=false
terraform fmt -check -recursive
terraform validate
terraform test
```

Tests use a mocked provider and do not contact Proxmox. They cover minimal
experimental inheritance wiring, legacy block mappings, mode validation,
explicit overrides, disk maps, outputs, and the two examples. Tests cover
default/null/zero/one/multiple VM counts, scaling, and legacy node-change
suppression. Mocked IDs are fixed test values, not evidence of real Proxmox
allocation, template inheritance, migration discovery, or guest readiness.

Validate the example configurations separately:

```sh
terraform -chdir=examples/minimal init -backend=false -input=false
terraform -chdir=examples/minimal validate
terraform -chdir=examples/disks init -backend=false -input=false
terraform -chdir=examples/disks validate
```

### Live acceptance checklist

Run only in an authorised disposable environment:

1. Clone a prepared Linux template and a prepared Windows template in each mode.
2. Verify guest boot and DHCP; inspect inherited firmware, devices, and CPU/RAM.
3. Check explicitly managed NIC/disk options against the limitations above.
4. Grow an OS disk, add two data disks, and grow a managed data disk. Inspect
   slot identity and actual virtual capacity separately from guest filesystems.
5. Verify the next plan is clean and a shrink request fails clearly.
6. Create multiple VMs and verify unique names and IDs.
7. In legacy mode, migrate a disposable VM externally, then verify refresh, a
   clean plan, and a configuration update on the new node.
8. Obtain explicit approval before destructive checks; verify legacy destruction
   still reaches the correct VM after migration.

Local mocked tests do not replace this checklist.

## Provider references

- [Cloned VM resource](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/docs/resources/cloned_vm.md)
- [Legacy VM resource](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/docs/resources/virtual_environment_vm.md)
- [Template inheritance guide](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/docs/guides/cloned-vm.md)
- [Device update implementation](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/fwprovider/nodes/clonedvm/resource.go)
