# tofu-free-oke

OpenTofu that provisions a single Always-Free OKE (Kubernetes) cluster on Oracle Cloud, applied by a GitHub Actions pipeline that authenticates with OIDC (no static keys).

## Language

### Oracle Cloud

**Always Free**:
Oracle's perpetual no-charge resource allotment. As of 2026-06-15 the Ampere A1 portion is 2 OCPU + 12 GB RAM total (halved from 4/24).
_Avoid_: "free trial" (that is the separate 30-day credit tier).

**A1**:
The `VM.Standard.A1.Flex` Arm/Ampere compute shape — the only shape that carries the Always-Free A1 allotment.
_Avoid_: "ARM node", "Ampere instance".

**OCI management API**:
The public Oracle control-plane API (`*.oraclecloud.com`) used to create/destroy cloud resources, including the OKE cluster object itself. Reached with a UPST. Always public.
_Avoid_: calling this "the API" unqualified.

**K8s API**:
The Kubernetes apiserver endpoint of the provisioned cluster (`:6443`). In this project it is **private** and reachable only through the **Bastion**. Distinct from the **OCI management API**.
_Avoid_: "the cluster API" unqualified, "the endpoint" unqualified.

**Bastion**:
The managed OCI Bastion *service* (ephemeral port-forward sessions, free, no host VM) used by humans to reach the private **K8s API**. Not a bastion compute instance.
_Avoid_: "jump host", "bastion VM".

### Identity & pipeline

**UPST**:
User Principal Session Token — a short-lived OCI credential. The pipeline obtains one by exchanging a GitHub OIDC token via **WIF**.

**WIF**:
OCI IAM Workload Identity Federation — the trust that exchanges a third-party OIDC JWT for a **UPST**. Configured as an Identity Propagation Trust + token-exchange Confidential App in the identity domain.

**Service user**:
The single dedicated OCI IAM user the pipeline acts as after token exchange. The "simple user" of the request. Not a human; carries the least-privilege policy for provisioning.
_Avoid_: "CI user", "robot account" (pick one name: **service user**).

**Bootstrap**:
The one-time, single-command run, launched locally by the human admin (default `~/.oci/config` profile), that creates the **service user**, group, policy, compartment, state bucket, and **WIF** trust — and hands their identifiers to GitHub — so the OIDC pipeline can run. Automated end to end, but never run by the pipeline itself.
_Avoid_: "setup", "init", "manual bootstrap".

**Pipeline state**:
The OpenTofu state of the infrastructure the pipeline owns (network, cluster, node pool, **Bastion**). Read and written by the **Service user**.

**Bootstrap state**:
The OpenTofu state of the **Bootstrap** itself. Holds admin-created secrets, so it is kept where the **Service user** cannot read it. Distinct from **Pipeline state**.
_Avoid_: "the state" unqualified.

## Relationships

- The **Bootstrap** creates the **Service user** + **WIF** trust; the pipeline then assumes the **Service user** via **WIF** → **UPST**.
- The pipeline talks only to the **OCI management API**; it never touches the **K8s API**.
- Humans reach the **K8s API** only through the **Bastion**.

## Flagged ambiguities

- "the API" was used to mean both the **OCI management API** and the **K8s API** — resolved: these are distinct. Provisioning uses the former (public); kubectl uses the latter (private, via Bastion).
- "the user" / "simple user" — resolved to **Service user** (a non-human IAM principal), distinct from the human admin whose `~/.oci/config` runs the **Bootstrap**.
