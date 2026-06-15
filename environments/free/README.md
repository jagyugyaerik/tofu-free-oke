# environments/free

The **pipeline root**. Composes `modules/network` + `modules/oke` into one
Always-Free OKE cluster. Applied by GitHub Actions via OIDC (no static keys);
state lives in OCI Object Storage (ADR-0003).

## What it builds

- VCN (private api + nodes subnets, public lb subnet, NAT/Service/Internet GWs)
- BASIC OKE cluster, private endpoint, flannel CNI
- 1× A1 worker (2 OCPU / 12 GB — the full free quota)
- managed Bastion for human kubectl

The aarch64 worker image and availability domain are resolved automatically from
`kubernetes_version` and `ad_index`.

## Local run (optional, uses your own creds)

```bash
cd environments/free
cp terraform.tfvars.example terraform.tfvars   # fill in
# init against the real backend:
tofu init \
  -backend-config="bucket=freeoke-tofu-state" \
  -backend-config="region=<region>" \
  -backend-config='endpoints={s3="https://<ns>.compat.objectstorage.<region>.oraclecloud.com"}'
tofu plan
```

For a purely local run, set `auth = "ApiKey"` in `providers.tf` (the pipeline
uses `SecurityToken`).

## CI

`.github/workflows/plan.yml` runs `tofu plan` on PRs; `apply.yml` runs `tofu
apply` on merge to `main` behind the protected `prod` Environment. Both obtain a
UPST by exchanging the GitHub OIDC token (see workflow comments).

## Notes

- A1 free capacity can be exhausted in AD-1 — bump `ad_index` if node creation
  fails on capacity.
- `bastion_allowed_cidrs` defaults to `0.0.0.0/0`; narrow it to your IP.
