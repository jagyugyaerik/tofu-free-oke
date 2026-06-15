# network

> OpenTofu leaf module. Builds the VCN for a **private** OKE (flannel) cluster.
> No backend, no provider config of its own — called by a root via `module {}`.

Creates a VCN with Internet, NAT and Service gateways and three regional subnets:

| Subnet  | Access  | Purpose                                                       |
|---------|---------|---------------------------------------------------------------|
| `api`   | private | OKE control-plane (K8s API) private endpoint                  |
| `nodes` | private | worker nodes (egress via NAT + Service GW)                    |
| `lb`    | public  | free flexible LB created on demand by future `LoadBalancer`s  |

Security lists carry the OKE **flannel** baseline ruleset. Tighten to per-service
NSGs for production hardening.

## Usage

```hcl
module "network" {
  source = "./modules/network"

  name           = "freeoke"
  compartment_id = var.compartment_id
}
```

## Inputs

| Name              | Type          | Default         | Required | Description                              |
|-------------------|---------------|-----------------|:--------:|------------------------------------------|
| enabled           | `bool`        | `true`          |    no    | Master on/off toggle.                    |
| name              | `string`      | —               |   yes    | Name prefix (1-100 chars, validated).    |
| compartment_id    | `string`      | —               |   yes    | Compartment OCID (validated).            |
| vcn_cidr          | `string`      | `10.0.0.0/16`   |    no    | VCN CIDR.                                |
| api_subnet_cidr   | `string`      | `10.0.0.0/28`   |    no    | Private control-plane subnet CIDR.       |
| nodes_subnet_cidr | `string`      | `10.0.1.0/24`   |    no    | Private worker-node subnet CIDR.         |
| lb_subnet_cidr    | `string`      | `10.0.2.0/27`   |    no    | Public LB subnet CIDR.                   |
| tags              | `map(string)` | `{}`            |    no    | Freeform tags applied to every resource. |

## Outputs

| Name            | Description                                  |
|-----------------|----------------------------------------------|
| vcn_id          | VCN OCID (null when disabled).               |
| api_subnet_id   | Private control-plane subnet OCID.           |
| nodes_subnet_id | Private worker-node subnet OCID.             |
| lb_subnet_id    | Public load-balancer subnet OCID.            |

## Testing

```bash
tofu init
tofu test          # plan-mode unit tests (mock provider, no creds, no infra)
```

## Versioning

Leaf declares a pessimistic provider **floor** (`>=`). The **root** pins exact
versions via its committed `.terraform.lock.hcl`.
