# OpenTofu state in OCI Object Storage (s3-compat)

OpenTofu state lives in OCI Object Storage via the `s3` backend pointed at OCI's S3-compatible endpoint, authenticated with one Customer Secret Key for the service user, and serialized with a GitHub Actions concurrency group. This keeps everything in OCI (Object Storage is Always-Free up to 20 GB) at the cost of one static secret — the single deliberate exception to the otherwise no-static-keys OIDC stance, and isolated to state access rather than provider auth.

## Considered Options

- **HCP Terraform free tier** — zero static keys (native OIDC) and real locking, but introduces a non-OCI vendor + account and moves state outside OCI; rejected to stay all-in-OCI.

## Consequences

- One static Customer Secret Key must be stored as a GitHub secret and rotated manually.
- OCI's S3-compatible endpoint may not support conditional-write lockfiles, so concurrent applies are prevented by a GitHub concurrency group rather than backend-native locking. Acceptable for a single-maintainer repo.
- Migrating to a different backend later requires a `tofu state` migration.
