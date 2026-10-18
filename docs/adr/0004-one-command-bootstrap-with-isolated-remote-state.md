# One-command Bootstrap that owns the token-exchange app and keeps isolated remote state

Partly supersedes [ADR-0001](0001-oidc-wif-with-thin-local-bootstrap.md). The trust model (GitHub OIDC → WIF → UPST impersonating one service user) is unchanged. What changes is *how the Bootstrap runs*.

The **Bootstrap** is one local command (`bootstrap/bootstrap.sh`). The human admin runs it with the DEFAULT `~/.oci/config` profile, and the pipeline never runs it. In one run it applies the OpenTofu root and pushes a single `github` output (`{secrets, variables}`, keyed by GitHub name) into the repo with `gh`. It also creates the protected `prod` Environment. The token-exchange Confidential Application moves into OpenTofu (`oci_identity_domains_app`), so the console step, the `oauth_client_id` input and the `configure_wif` toggle go away. The WIF trust uses two exact impersonation rules: `…:environment:prod` for apply/destroy and `…:pull_request` for plan.

**Bootstrap state** lives in its own Object Storage bucket in the tenancy root, outside the project compartment. The **service user**'s object rights are narrowed to the **pipeline state** bucket, so the pipeline cannot read the admin-created secrets (the Customer Secret Key and the app's client secret). OpenTofu has no native OCI backend (opentofu#1011), so this state also uses the s3-compatible backend. It authenticates with a **per-run Customer Secret Key** that the script mints for the admin user through the OCI CLI and deletes on exit, so no long-lived Bootstrap credential exists. The first run applies with local state, then migrates it into the new bucket.

## Considered Options

- **Keep the Confidential App in the console** (the PRD's original position). Rejected: research showed `oci_identity_domains_app` is workable, and the console step was the main manual hand-off.
- **Run the Bootstrap in GitHub Actions with a temporary admin key.** Rejected: it brings back a static admin credential, contradicting ADR-0001.
- **Local Bootstrap state (gitignored).** Rejected: a lost laptop means re-importing everything.
- **Same bucket, `bootstrap/` prefix.** Rejected: the service user could read admin secrets.
- **A long-lived admin Customer Secret Key, or Terraform ≥ 1.12 for its native `oci` backend.** Rejected: the first leaves a second static secret, the second runs two tools.

## Consequences

- Re-running the script is safe. `--rotate` replaces the service user's Customer Secret Key and the app secret, then re-syncs GitHub.
- The admin must hold Identity Domain Administrator rights and have one free Customer Secret Key slot (OCI allows 2 per user).
- `oracle/oci` moves to `~> 9.10`, which is required for the current IdentityPropagationTrust/App attributes.
