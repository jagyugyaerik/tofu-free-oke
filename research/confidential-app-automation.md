# Can the token-exchange Confidential App be created without the console?

Research for issue #17 (parent map #16, blocks #20). Researched 2026-10-18 against the OCI provider at `master` (latest release v9.10.0), the OCI CLI reference, and the Identity Domains REST API.

## Answer

**Yes.** You can create the token-exchange Confidential Application without the console, using any of these three:

- the OCI provider resource `oci_identity_domains_app`
- the OCI CLI command `oci identity-domains app create`
- a REST call, `POST {domainUrl}/admin/v1/Apps`

In each case you set `based_on_template = CustomWebAppTemplateId`, `is_oauth_client = true`, `client_type = confidential`, `allowed_grants = ["client_credentials"]` and `active = true`. That gives an active OAuth client. Its `name` is the **Client ID**, and the create response returns `client_secret`. The Bootstrap can therefore own the app and pass `.name` directly into the trust's `oauth_clients`.

**"Token exchange" is not an app grant type.** It is not in the documented `allowedGrants` enum. The JWT→UPST exchange works because the trust lists the app in `oauthClients`, and the app authenticates with HTTP Basic auth. So `client_credentials` is the only grant the app needs.

**`bootstrap/wif.tf` will not work as written.** It has four defects:

1. **`sw` is not a supported rule operator.** The only documented operators are `eq` (allows the `*` wildcard) and `co` (no wildcard). Use `sub eq repo:<owner>/<name>:*`, without quotes.
2. **No signing key source is set.** A trust needs either `public_key_endpoint` or `public_certificate`. Set `public_key_endpoint = "https://token.actions.githubusercontent.com/.well-known/jwks"`.
3. **`impersonation_service_users.value` probably expects the identity-domain SCIM user id, not the OCID.** Oracle's examples use `<user_id>` and return the OCID in a separate `ocid` field. `oci_identity_user.ci.id` is an OCID. This needs a live check (see Risks).
4. **The trust has no audience field.** You enforce the audience with `client_claim_name = "aud"` and `client_claim_values = [<audience>]`. The pipeline must ask GitHub for that same audience. Without these two settings, OCI accepts any `aud`.

There is also a gotcha with a stricter rule. The planned `apply` job runs in the `prod` Environment, so GitHub sets its `sub` to `repo:<o>/<n>:environment:prod`, not `…:ref:refs/heads/main`. The PR `plan` job's `sub` is `repo:<o>/<n>:pull_request`. If you tighten the rule to `:ref:refs/heads/main`, both jobs stop matching.

## Evidence

### 1. Creating the Confidential App

**OCI provider: `oci_identity_domains_app`**

- The resource documents `based_on_template { value / well_known_id = "CustomWebAppTemplateId" }`, `allowed_grants`, `client_type`, `is_oauth_client`, `active`, `display_name`, `schemas = ["urn:ietf:params:scim:schemas:oracle:idcs:App"]` and `force_delete`. Source: https://raw.githubusercontent.com/oracle/terraform-provider-oci/master/website/docs/r/identity_domains_app.html.markdown (also https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/identity_domains_app).
- `name` is documented as: "Name of the application. Also serves as username if the application authenticates to Oracle Public Cloud infrastructure … cannot be changed once an App is created". This is the OAuth Client ID. It is Optional+Computed, so the server generates it.
- In the provider source, `client_secret` is `Computed`, **not** `Sensitive`. Read sets it into state with `s.D.Set("client_secret", *s.Res.ClientSecret)`. Source: https://raw.githubusercontent.com/oracle/terraform-provider-oci/master/internal/service/identity_domains/identity_domains_app_resource.go
- In the SDK model, `clientSecret` has `returned: default`, so GET responses return it as well as create responses. Source: https://raw.githubusercontent.com/oracle/oci-go-sdk/master/identitydomains/app.go
- There is a working example in a provider issue. It uses `CustomWebAppTemplateId`, `is_oauth_client = true`, `client_type = "confidential"`, `allowed_grants` including `client_credentials`, and `active = true`. Its only failure was caused by `attribute_sets = ["all"]`, and the workaround was to drop that line. Source: https://github.com/oracle/terraform-provider-oci/issues/2542
- Another open provider issue reports that the app's `id` holds the OCID rather than the SCIM id. This is why you should reference `.name`, not `.id`, as the client ID. Source: https://github.com/oracle/terraform-provider-oci/issues/2369

**OCI CLI: `oci identity-domains app create`**

- The command takes `--based-on-template` (JSON), `--display-name`, `--schemas`, `--is-o-auth-client`, `--client-type` (accepted values: `confidential`, `public`, `trusted`), `--allowed-grants` (JSON), `--active` and `--endpoint`. Source: https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/identity-domains/app/create.html

**REST API: `POST /admin/v1/Apps`**

- `basedOnTemplate` is required and immutable.
- `clientType` takes `confidential | public | trusted`.
- The `allowedGrants` enum is `authorization_code, client_credentials, password, refresh_token, implicit, tls_client_auth, urn:ietf:params:oauth:grant-type:jwt-bearer, urn:ietf:params:oauth:grant-type:saml2-bearer, urn:ietf:params:oauth:grant-type:device_code`. **The token-exchange URN is not in it.**
- `clientSecret` is readOnly and is returned.
- Source: https://docs.oracle.com/en/cloud/paas/iam-domains-rest-api/op-admin-v1-apps-post.html

**The console doesn't offer a token-exchange grant either.** The console's grant-type list is Resource Owner, Client credentials, JWT assertion, SAML2 assertion, Refresh token, Authorization code, Implicit, Device code and TLS client auth. There is no token-exchange option. Source: https://docs.oracle.com/en-us/iaas/Content/Identity/applications/add-confidential-application.htm

**Oracle's own JWT→UPST guide** only says to "create a confidential application" and keep its client_id and client_secret. It recommends a *separate* token-exchange app **without** the Identity Domain Administrator role, authorized through the trust's `oauthClients`. The token call is `POST /oauth2/v1/token` with `Authorization: Basic` and `grant_type=urn:ietf:params:oauth:grant-type:token-exchange`. Source: https://docs.oracle.com/en-us/iaas/Content/Identity/api-getstarted/json_web_token_exchange.htm

### 2. `oci_identity_domains_identity_propagation_trust` against `bootstrap/wif.tf`

Source for the rule grammar and payload: https://docs.oracle.com/en-us/iaas/Content/Identity/api-getstarted/json_web_token_exchange.htm

**Rule grammar.** The guide says: "Condition: contains (`co`) or equals (`eq`) … With equals condition: wild card (*) is allowed. With contains condition: wild card (*) isn't supported." Its examples are `sub eq *` and `"username" eq kafka*`. Evaluation stops at the first rule that matches. If no rule matches, the token request fails.

`sw` is not documented, so `sub sw 'repo:…:'` will either be rejected or fail to match. The quotes are not documented either: the examples have no quotes around the value.

**`oauthClients`** is mandatory. It is "a list of OAuth clients who are allowed to get tokens", and the example value `"25d123....."` is a Client ID. `oauth_clients = [var.oauth_client_id]` is therefore correct in shape.

**Key source.** You need `publicCertificate` "if the public key endpoint is not provided", and `publicKeyEndpoint` otherwise. `wif.tf` sets neither. GitHub's `jwks_uri` is `https://token.actions.githubusercontent.com/.well-known/jwks`; this was verified live from https://token.actions.githubusercontent.com/.well-known/openid-configuration.

**`impersonationServiceUsers.value`.** The request uses `"value": "<<user_id>>"`. The response echoes a separate `"ocid": "ocid1.user…"` and `"$ref": ".../admin/v1/Users/<<user_id>>"`. So `value` is the domain's SCIM user id, and `ocid` is its own optional attribute. The provider example likewise sets `value = oci_identity_domains_user.<x>.id` and has a separate optional `ocid` argument. Source: https://raw.githubusercontent.com/oracle/terraform-provider-oci/master/website/docs/r/identity_domains_identity_propagation_trust.html.markdown

**Audience.** The trust has no `audience` attribute. The provider documents `client_claim_name` as the claim that identifies the token's recipient, e.g. "aud" for GCP and "aud"/"client_id" for AWS, with `client_claim_values` as the allowed values.

On GitHub's side, the default `aud` is the repository owner's URL. You can request a custom audience with `core.getIDToken(audience)`, or with `&audience=` on `ACTIONS_ID_TOKEN_REQUEST_URL`. Source: https://docs.github.com/en/actions/reference/security/oidc

Oracle A-Team's reference action defaults to `https://cloud.oracle.com`. Source: https://github.com/gtrevorrow/oci-token-exchange-action (README, `oidc_audience`).

**GitHub `sub` precedence.** When a job references an environment, the environment wins (`repo:O/R:environment:NAME`). Otherwise a PR job gets `repo:O/R:pull_request`, and anything else gets `repo:O/R:ref:refs/heads/BRANCH`. Source: https://docs.github.com/en/actions/reference/security/oidc

**Provider version.** The changelog entry "Support for IdentityDomains IDCS Token Exchange" is in 5.23.0 (2023-12-12). That release added the trust resource, so `~> 5.0` in `bootstrap/versions.tf` works, but only on the 5.x line. Later changes are on newer majors: "IdentityDomains fixes for App resource" in 6.32.0, and "Support for IdentityPropagationTrust JWT/RPST and X509/UPST attributes" in 8.18.0. The current major is 9 (v9.10.0, 2026-10-14). Source: https://github.com/oracle/terraform-provider-oci/blob/master/CHANGELOG.md

## Minimal working example (HCL)

This is untested against a live tenancy. It is built from the documented schema above.

```hcl
data "oci_identity_domain" "this" {
  domain_id = var.identity_domain_id
}

# Token-exchange OAuth client. No admin app roles (Oracle PoLP guidance).
resource "oci_identity_domains_app" "token_exchange" {
  idcs_endpoint = data.oci_identity_domain.this.url
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:App"]
  display_name  = "${var.name}-github-token-exchange"
  description   = "GitHub Actions OIDC -> UPST token-exchange client (managed by bootstrap)."

  based_on_template {
    value = "CustomWebAppTemplateId"
  }
  is_oauth_client = true
  client_type     = "confidential"
  allowed_grants  = ["client_credentials"] # token-exchange is authorized by the trust, not a grant here
  active          = true
  force_delete    = true # lets `tofu destroy` remove an active app (apply once before destroy)
  # do NOT set attribute_sets = ["all"] (provider issue #2542)
}

# Resolve the service user's identity-domain (SCIM) id from its OCID.
data "oci_identity_domains_users" "ci" {
  idcs_endpoint = data.oci_identity_domain.this.url
  user_filter   = "ocid eq \"${oci_identity_user.ci.id}\""
}

resource "oci_identity_domains_identity_propagation_trust" "github" {
  idcs_endpoint       = data.oci_identity_domain.this.url
  schemas             = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]
  name                = "${var.name}-github-actions"
  type                = "JWT"
  issuer              = "https://token.actions.githubusercontent.com"
  public_key_endpoint = "https://token.actions.githubusercontent.com/.well-known/jwks"
  active              = true
  subject_type        = "User"

  # Audience check: the pipeline must request exactly this audience.
  client_claim_name   = "aud"
  client_claim_values = [var.oidc_audience] # e.g. "https://cloud.oracle.com"

  oauth_clients       = [oci_identity_domains_app.token_exchange.name] # .name == Client ID
  allow_impersonation = true

  impersonation_service_users {
    # eq + trailing wildcard; covers :pull_request and :environment:prod
    rule  = "sub eq repo:${var.github_repo}:*"
    value = data.oci_identity_domains_users.ci.users[0].id
    ocid  = oci_identity_user.ci.id
  }
}

output "oauth_client_id" {
  value = oci_identity_domains_app.token_exchange.name
}

output "oauth_client_secret" {
  value     = oci_identity_domains_app.token_exchange.client_secret
  sensitive = true # schema does not mark it sensitive; we must
}
```

If you want separate rules for plan and apply, use two `impersonation_service_users` blocks in this order. The first rule that matches wins.

- `sub eq repo:<o>/<n>:environment:prod`
- `sub eq repo:<o>/<n>:pull_request`

### CLI equivalent (app only)

```bash
oci identity-domains app create \
  --endpoint "$DOMAIN_URL" \
  --schemas '["urn:ietf:params:scim:schemas:oracle:idcs:App"]' \
  --display-name freeoke-github-token-exchange \
  --based-on-template '{"value":"CustomWebAppTemplateId"}' \
  --is-o-auth-client true \
  --client-type confidential \
  --allowed-grants '["client_credentials"]' \
  --active true
# response: .data.name = Client ID, .data."client-secret" = Client Secret
```

## Open risks / verify on first live apply

1. **`value` as SCIM id vs OCID.** The docs point to the SCIM id. Provider issue #2369 shows that some domains resources return the OCID in `id`, so check that `data.oci_identity_domains_users…users[0].id` really is the SCIM id. Also check whether passing the OCID in `value` would simply be accepted. The `user_filter` attribute name and the SCIM filter syntax (`ocid eq "…"`) come from the provider's data-source pattern. Confirm both with `tofu plan`. If needed, fall back to `userName eq "freeoke-ci"`.
2. **Wildcard matching semantics.** Only trailing-`*` examples are documented (`kafka*`). `repo:o/n:*` relies on prefix matching. Test that a PR run and a `prod` run both get a UPST, and that a fork or another repo does not.
3. **Client secret in state.** `client_secret` is stored in plaintext in the local Bootstrap state. The schema doesn't mark it `Sensitive`. This is the same exposure the Customer Secret Key already has (local, gitignored state), but it is one more secret there. Re-creating the app rotates both the ID and the secret, so the GitHub secrets/variables must be updated afterwards.
4. **Destroying an active app.** `force_delete` must already be in state, i.e. applied before `destroy`. This is per the provider doc note.
5. **Plain user vs "service user".** Oracle's guide recommends, but doesn't require, a domain user with `serviceUser: true`. Bootstrap creates a normal user with `oci_identity_user`. That should be fine for impersonation, but it isn't confirmed.
6. **Provider pin.** `~> 5.0` caps the provider at 5.x and misses the 6.32 App fixes and the 8.18 trust attributes. Consider moving to a current major, accepting the breaking-change review that comes with it.
7. **`type` casing.** The guide's table says `jwt` but its JSON uses `"JWT"`. Keep `"JWT"`, as the payload examples do.
8. **Who can call the API.** Creating apps and trusts needs Identity Domain Administrator (or Application Administrator for the app). Bootstrap's admin `~/.oci/config` user must have that in the target domain. Tenancy Administrators normally do in the Default domain.
