# oke

> OpenTofu leaf module. An **Always-Free** OKE cluster: BASIC type (free control
> plane), **private** API endpoint, **flannel** overlay CNI, one A1 worker, and a
> managed **Bastion** for human kubectl access. Called by a root via `module {}`.

Worker defaults consume the full Always-Free A1 quota (2 OCPU / 12 GB) in one
node. Per-node sizing is validated and the aggregate is guarded by a node-pool
precondition, so you cannot accidentally plan a cluster that leaves the free tier.

## Usage

```hcl
module "oke" {
  source = "./modules/oke"

  name                = "freeoke"
  compartment_id      = var.compartment_id
  kubernetes_version  = "v1.31.1"
  vcn_id              = module.network.vcn_id
  api_subnet_id       = module.network.api_subnet_id
  nodes_subnet_id     = module.network.nodes_subnet_id
  lb_subnet_id        = module.network.lb_subnet_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  node_image_id       = local.oke_image_id
}
```

## Inputs

| Name                  | Type           | Default          | Required | Description                                       |
|-----------------------|----------------|------------------|:--------:|---------------------------------------------------|
| enabled               | `bool`         | `true`           |    no    | Master on/off toggle.                             |
| name                  | `string`       | —                |   yes    | Name prefix (validated).                          |
| compartment_id        | `string`       | —                |   yes    | Compartment OCID (validated).                     |
| kubernetes_version    | `string`       | —                |   yes    | `vX.Y.Z` (validated).                             |
| vcn_id                | `string`       | —                |   yes    | VCN OCID.                                         |
| api_subnet_id         | `string`       | —                |   yes    | Private control-plane subnet OCID.                |
| nodes_subnet_id       | `string`       | —                |   yes    | Private worker subnet OCID.                       |
| lb_subnet_id          | `string`       | —                |   yes    | Public LB subnet OCID.                            |
| availability_domain   | `string`       | —                |   yes    | AD for the worker node(s).                        |
| node_image_id         | `string`       | —                |   yes    | OKE aarch64 worker image OCID.                    |
| node_count            | `number`       | `1`              |    no    | Worker count (≥1, validated vs free tier).        |
| node_ocpus            | `number`       | `2`              |    no    | OCPUs/node (1-2, validated).                      |
| node_memory_gbs       | `number`       | `12`             |    no    | Memory GB/node (1-12, validated).                 |
| boot_volume_gbs       | `number`       | `50`             |    no    | Boot volume GB/node (≥47).                        |
| pods_cidr             | `string`       | `10.244.0.0/16`  |    no    | Flannel pod CIDR.                                 |
| services_cidr         | `string`       | `10.96.0.0/16`   |    no    | ClusterIP services CIDR.                          |
| ssh_public_key        | `string`       | `null`           |    no    | Optional worker SSH key.                          |
| bastion_allowed_cidrs | `list(string)` | `["0.0.0.0/0"]`  |    no    | CIDRs allowed to open Bastion sessions.           |
| tags                  | `map(string)`  | `{}`             |    no    | Freeform tags.                                    |

## Outputs

| Name         | Description              |
|--------------|--------------------------|
| cluster_id   | OKE cluster OCID.        |
| node_pool_id | Worker node pool OCID.   |
| bastion_id   | Managed Bastion OCID.    |

## Testing

```bash
tofu init
tofu test          # plan-mode unit tests (mock provider, no creds, no infra)
```

## Versioning

Leaf declares a pessimistic provider **floor** (`>=`). The **root** pins exact
versions via its committed `.terraform.lock.hcl`.
