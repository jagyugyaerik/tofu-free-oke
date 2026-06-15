# bootstrap

One-time, **locally-applied** root. Run by a human admin with the DEFAULT
`~/.oci/config` profile. It seeds everything the OIDC pipeline can't create for
itself (see [ADR-0001](../docs/adr/0001-oidc-wif-with-thin-local-bootstrap.md)):

- project **compartment**
- **service user** + group + least-privilege **policy** (compartment-scoped)
- OKE **service policy**
- **state bucket** (Object Storage) + **Customer Secret Key**
- **WIF** Identity Propagation Trust (GitHub OIDC → impersonate service user)

State is **local** and gitignored — it holds the secret key.

## Step 1 — create the token-exchange Confidential Application (console)

The OAuth client used on the `/oauth2/v1/token` call is a version-fragile SCIM
resource, so create it once in the console (Identity → Domains → *your domain* →
Integrated applications → Add application → **Confidential Application**):

- Allowed grant types: **Client Credentials** (+ token exchange if listed)
- Mark it active; note the generated **Client ID** and **Client Secret**

Put the Client ID in `oauth_client_id`. Keep the Client Secret for the pipeline
secrets (`OCI_CLIENT_ID` / `OCI_CLIENT_SECRET`).

> Prefer to do WIF entirely in the console? Set `configure_wif = false` and skip
> `identity_domain_id` / `oauth_client_id`; IAM + state still apply.

## Step 2 — apply

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # fill in
tofu init
tofu apply
```

## Step 3 — wire GitHub secrets/variables

From `tofu output` (run `tofu output -raw state_secret_key` for the sensitive one):

| Output                  | GitHub                         | Kind     |
|-------------------------|--------------------------------|----------|
| `state_access_key_id`   | `AWS_ACCESS_KEY_ID`            | secret   |
| `state_secret_key`      | `AWS_SECRET_ACCESS_KEY`        | secret   |
| (Client Secret, step 1) | `OCI_CLIENT_SECRET`            | secret   |
| `oauth_client_id`       | `OCI_CLIENT_ID`                | variable |
| `identity_domain_url`   | `OCI_DOMAIN_URL`               | variable |
| `compartment_ocid`      | `OCI_COMPARTMENT_OCID`         | variable |
| `region`                | `OCI_REGION`                   | variable |
| `objectstorage_namespace` | `OCI_NAMESPACE`              | variable |
| `state_bucket`          | `TF_STATE_BUCKET`              | variable |

Also create a protected GitHub **Environment** named `prod` (require manual
approval) — that approval is the apply gate.

## Verify

```bash
tofu validate   # provider-schema check, no creds needed
```
