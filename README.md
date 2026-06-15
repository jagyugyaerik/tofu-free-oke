# tofu-free-oke

OpenTofu that provisions a single **Always-Free OKE** (Kubernetes) cluster on
Oracle Cloud, applied by a GitHub Actions pipeline that authenticates with
**OIDC** (no static cloud keys).

> **Status:** documentation/design only. This repo captures the intended
> structure, glossary, and decisions; the OpenTofu + workflow code is
> implemented separately. Paths below describe the target layout.

> **Free-tier reality (2026-06-15):** Oracle halved the Always-Free Ampere A1
> allotment to **2 OCPU / 12 GB total**. This repo puts all of it into one
> worker node. See [docs/adr/0002](docs/adr/0002-private-endpoint-flannel-single-node.md).

## What you get

- BASIC OKE cluster (free control plane), **private** API endpoint, **flannel** CNI
- 1× `VM.Standard.A1.Flex` worker (2 OCPU / 12 GB)
- VCN: private api + nodes subnets, public LB subnet, NAT/Service/Internet gateways
- managed **OCI Bastion** (free) for human `kubectl` to the private endpoint
- GitHub Actions: plan-on-PR, apply-on-merge behind a protected Environment

## Layout

```
modules/
  network/      VCN, subnets, gateways, security lists   (leaf, tested)
  oke/          cluster, node pool, bastion              (leaf, tested)
bootstrap/      LOCAL admin apply: IAM + WIF + state seed
environments/
  free/         pipeline root -> composes the modules
.github/
  actions/oci-oidc-auth/   OIDC -> UPST token exchange
  workflows/    plan.yml (PR), apply.yml (main, gated)
docs/adr/       0001 OIDC/WIF, 0002 endpoint/CNI, 0003 state
CONTEXT.md      glossary (ubiquitous language)
```

## Order of operations

1. **Bootstrap (once, local).** `cd bootstrap` → fill `terraform.tfvars` →
   `tofu apply`. Creates the compartment, service user, policy, state bucket,
   Customer Secret Key, and the WIF trust. See [bootstrap/README.md](bootstrap/README.md).
   One manual console step: the token-exchange Confidential Application.
2. **Wire GitHub.** Paste the bootstrap outputs into repo secrets/variables and
   create a protected Environment `prod` (mapping table in bootstrap/README).
3. **Provision (pipeline).** Open a PR → `plan` runs. Merge to `main` → `apply`
   waits for approval on `prod`, then provisions the cluster.

## Auth model

```
GitHub OIDC JWT ──exchange──> OCI UPST ──> OCI management API (provider)
  (per run, short-lived)        (impersonates the service user via WIF)
```

The only static secret is the state-backend Customer Secret Key
([ADR-0003](docs/adr/0003-state-in-oci-object-storage-s3-compat.md)).

## Testing

```bash
cd modules/network && tofu init && tofu test   # mock provider, no creds
cd modules/oke     && tofu init && tofu test
```

## Reaching the cluster (humans)

The API is private. Open an OCI Bastion port-forward session to the cluster's
private endpoint, then point `kubectl` at `127.0.0.1:6443`. (The pipeline never
needs this — it only talks to the public OCI management API.)
