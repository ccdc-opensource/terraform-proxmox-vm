# terraform-proxmox-vm

A VM module using `bpg/proxmox` that supports both Proxmox resource styles:
`proxmox_virtual_environment_vm` in the default legacy mode, and
`proxmox_cloned_vm` in the explicit experimental opt-in mode.

It creates and starts full clones of prepared Linux or Windows templates.
Set `vm_count` to the number of VMs you want, and choose the resource mode with
`vm_mode`:

| `vm_mode` | Resource | Behaviour |
| --- | --- | --- |
| `"legacy"` (default) | `proxmox_virtual_environment_vm` | Explicit boot-disk configuration; permits externally managed node placement. |
| `"experimental"` | `proxmox_cloned_vm` | Opt-in hardware management; fixed-node deployment. |

`experimental` uses the `proxmox_cloned_vm` resource.

## Mode requirements

- `"legacy"` (default): requires an explicit `root_disk` with `slot`,
  `size_gb`, and datastore values. The provider treats `node_name` as the
  initial placement input, and later changes are ignored after creation.
  Empty `tags = []` is not reliably cleared in this mode.
- `"experimental"`: clone-specific opt-in mode. `root_disk` can be omitted
  when the template defaults are acceptable. This mode uses the clone resource
  and supports `tags = []` as the explicit clear behaviour.

In legacy mode, Terraform ignores `node_name` changes after creation so that
ProxLB or another external system can own placement. The provider discovers
the current node during refresh, but placement changes, subsequent updates, and
destruction must be tested on your cluster before relying on this integration.
The module does not install, configure, or invoke ProxLB.

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
| `vm_count` | number | Number of VMs to create; default `1` (also used for null). |
| `source_vm_id` | number | Required positive integer template ID. |
| `source_node_name` | string | Source node; omitted means the target node. |
| `target_datastore` | string | Optional clone-storage override. |
| `vm_description` | string | Optional description override. |
| `tags` | set(string) | Optional tags; `[]` clears tags only in experimental mode. |
| `cpu_cores` | number | Cores per socket, integer 1-1024. |
| `memory_size` | number | RAM in MiB, integer 64-268435456. |
| `network_bridge` | string | Opt into managing `net0` as a VirtIO NIC on this bridge. |
| `root_disk` | object | OS disk `slot`, `size_gb`, and optional `datastore_id`; all three are required in legacy mode. |
| `additional_disks` | map(object) | Disk slot to `{ size_gb, datastore_id }`; default `{}`. |

In legacy mode, the provider may skip empty tag lists during clone creation and
refresh. Consequently, inherited template tags or previously unmanaged tags
may remain after setting `tags = []`, even when Terraform reports a clean plan.
Use experimental mode when relying on an empty set to clear tags.

CPU and memory configuration is omitted unless overrides are supplied.
Experimental mode sends only the requested fields. Legacy mode uses nested
blocks whose defaults can also affect sockets, CPU type, and ballooning.
Review the plan against the template rather than assuming partial-block
inheritance. A root disk is mandatory in legacy mode when `vm_count` is nonzero.

## Important caveats

- `legacy` mode requires an explicit `root_disk` and an accurate `additional_disks`
  set. Omitting or removing disks can detach or delete them during reconciliation.
- `experimental` mode is the opt-in clone path. It is simpler for disk/device
  management, but it does not preserve every inherited NIC or disk setting.
- `network_bridge` and other device overrides are intentionally simple: use them
  for a basic VirtIO setup or leave them unset.
- `tags = []` is only a supported clear action in `experimental` mode.
- Disks are integer **GiB**, grow-only, and the guest filesystems still need
  their own resize and mount operations.

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

The [disk example](examples/disks/main.tf) demonstrates a simple bridge override
and a multi-disk layout. Adapt the slots, sizes, and storage to your template.

- Sizes are integer **GiB**, from 1 to 10240.
- Supported slots are `ide0`-`ide3`, `sata0`-`sata5`, `scsi0`-`scsi30`, and
  `virtio0`-`virtio15`.
- `root_disk.slot` must match the existing OS disk slot. The module does not
  assume every template boots from `scsi0`.
- Use unused slots for additional disks. In legacy mode, unlisted/inherited data
  disks are still managed as part of the provider contract.
- Disks can grow, not shrink. Expanding a virtual disk does not resize the guest
  filesystem; that is a guest task.
- In experimental mode removing an entry stops management without deletion. In
  legacy mode removal can remove or detach the disk.

The module builds a simple disk map for `experimental` mode and `dynamic` disk
blocks for `legacy` mode.

## VM count

Use `vm_count` to set how many VMs to create.

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
```

This creates `sandbox-01`, `sandbox-02`, and `sandbox-03`.

## Outputs

| Output | Meaning |
| --- | --- |
| `vm_ids` | List of Proxmox-assigned numeric VM IDs, in index order. |
| `vm_names` | List of indexed VM names, in index order. |
| `node_names` | List of nodes in index order; legacy mode refreshes actual placement. |

Outputs are lists for every count, including one and zero.

## Lifecycle and scope

- Mode changes and clone settings can require replacement.
- `experimental` mode also requires replacement for target-node changes; legacy
  mode ignores node changes after creation.
- `delete_unreferenced_disks_on_destroy` is explicitly false. This does not
  prevent `terraform destroy` from removing the VM and attached disks.
- This is a baseline module. Static IPs, guest identity, advanced networking,
  template creation, HA, backups, and other operator-specific features are out of
  scope.

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
allocation, template inheritance, placement discovery, or guest readiness.

Validate the example configurations separately:

```sh
terraform -chdir=examples/minimal init -backend=false -input=false
terraform -chdir=examples/minimal validate
terraform -chdir=examples/disks init -backend=false -input=false
terraform -chdir=examples/disks validate
```

## Provider references

- [bpg/proxmox provider repository](https://github.com/bpg/terraform-provider-proxmox)
- [Cloned VM resource](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/docs/resources/cloned_vm.md)
- [Legacy VM resource](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/docs/resources/virtual_environment_vm.md)
- [Template inheritance guide](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/docs/guides/cloned-vm.md)
- [Device update implementation](https://github.com/bpg/terraform-provider-proxmox/blob/v0.118.1/fwprovider/nodes/clonedvm/resource.go)
