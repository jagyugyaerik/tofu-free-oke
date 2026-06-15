# OIDC/WIF authentication with a thin local bootstrap

The GitHub Actions pipeline authenticates to OCI by exchanging a GitHub OIDC token for a short-lived UPST via OCI IAM Workload Identity Federation (WIF) — no static OCI API keys are stored anywhere. Because a pipeline cannot create the very service user, WIF trust, and state bucket it authenticates with and writes to, those prerequisites are provisioned by a separate `bootstrap/` root applied once locally with the human admin's default `~/.oci/config`. The bootstrap stays thin (IAM + WIF + state seed only); the pipeline owns all infrastructure (VCN, OKE cluster, node pool, Bastion), keeping the pipeline the source of truth for infra.

## Consequences

- Rotating the trust or service user is a local admin operation, not a pipeline one.
- A single service user is used for both plan and apply; the apply is gated by a protected GitHub Environment on `main` (manual approval) rather than by a separate read-only principal. Splitting into two principals later means new WIF mappings + policies.
