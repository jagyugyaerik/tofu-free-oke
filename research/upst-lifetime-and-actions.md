# UPST lifetime, mid-run refresh, and OIDC-to-UPST GitHub Actions

Research for issue #18 (parent #16, blocks #23). Researched 2026-10-18.

## Direct answer

1. **Lifetime: at most 60 minutes, and possibly much less.** Oracle's A-Team says a WIF-issued UPST lives for *min(remaining lifetime of the IdP JWT, API-supplied value, 60 minutes)*. The token-exchange request has no lifetime parameter for a UPST. GitHub's own example OIDC token has `exp - iat = 300 s`. If OCI really does cap the UPST at the JWT's remaining lifetime, a UPST minted from a GitHub JWT could live **about 5 minutes**. Oracle does not document this for GitHub, so the first live run must decode the UPST and measure it (see Risks).
2. **"Refresh" means a new exchange.** No documented call refreshes a WIF UPST in place. Oracle's SDKs (Go and Python) handle expiry by asking the issuer for a new JWT and running the token exchange again. A GitHub job can mint new OIDC JWTs at any point while it runs, so a run of 20+ minutes needs a background loop that re-exchanges every few minutes.
3. **Picking up a refreshed token:**
   - **OCI Terraform provider, `auth = "SecurityToken"`:** re-reads `security_token_file` on **every signed request**. It caches `key_file` for the life of the process. A refresher can therefore overwrite the token file mid-apply, **as long as it reuses the same keypair** (sends the same `public_key` on each exchange).
   - **OCI CLI (`--auth security_token`):** reads the token **once per process**. Oracle has confirmed that a running command does not pick up a refreshed file. Each new `oci` invocation reads the current file.
   - **New option: the provider's native `auth = "WorkloadIdentityFederation"`** (added in v8.22.0, 2026-07-08). The provider runs the exchange itself and renews automatically within 5 minutes of expiry. It reads the subject JWT from `workload_identity_token_path` each time it renews, so something still has to keep that file filled with a fresh GitHub JWT.
4. **No Oracle-published action does the exchange.** All 7 repos under `github.com/oracle-actions` were checked. The CLI-related ones (`run-oci-cli-command`, `configure-kubectl-oke`) take static API keys (`OCI_CLI_KEY_CONTENT`), and the org was last pushed in 2024. The only reusable, versioned third-party action is **`gtrevorrow/oci-token-exchange-action`** (v2.0.0, 2026-07-28, UPL-1.0, 6 stars, single maintainer). It does the full exchange and writes `~/.oci/config`, but it is **one-shot** (no mid-run refresh) and it is not Oracle-published.
5. **Recommendation for #23:** use our own small composite action. The exchange is about 20 lines of shell and is already specified in the PRD. Run the exchange in a **background re-exchange loop inside the same step as `tofu apply`**, reusing one session keypair. A third-party action does not remove the refresh work, and it adds supply-chain trust on a single maintainer. Revisit native `WorkloadIdentityFederation` auth once a live run confirms the UPST lifetime. It needs provider ≥ 8.22, and `bootstrap/versions.tf` pins `~> 5.0`.

## Evidence

### UPST lifetime

- **Oracle docs, token-exchange request parameters.** The parameters are `grant_type`, `requested_token_type=urn:oci:token-type:oci-upst`, `public_key`, `subject_token_type=jwt`, and `subject_token`. There is no expiry parameter. The page describes the UPST only as "short-lived". https://docs.oracle.com/en-us/iaas/Content/Identity/api-getstarted/json_web_token_exchange.htm
- **Oracle A-Team, "Workload Identity Federation".** Quote: "UPST tokens, also known as temporary tokens, are valid for 60 minutes. However, the duration of UPST will be calculated based on the minimum of (IDP Issued token remaining duration, API Supplied value, 60 minutes)." https://www.ateam-oracle.com/workload-identity-federation (Oracle-authored, but a blog rather than reference docs. The page returns 403 to automated fetch, so this quote comes from the search-index extract.)
- **Oracle blog on WIF with ephemeral RPST.** "an RPST can be valid for up to 12 hours, versus the 60-minute UPST." https://blogs.oracle.com/cloud-infrastructure/wif-with-ephemeral-rpst and https://www.ateam-oracle.com/oci-workload-identity-federation-using-ephemeral-rpst
- **GitHub OIDC docs.** The example token has `iat: 1632493567` and `exp: 1632493867` (300 s). https://docs.github.com/en/actions/concepts/security/openid-connect
- **Observed RPST lifetime.** A public demo run from 2026-10-08 decoded its WIF RPST (no `rpst_exp` set) and logged `"lifetime_seconds":1200`, which is 20 minutes. https://github.com/dgutierrezcolodra/oci-terraform-github-actions-wif-example/actions/runs/37766831245
- **CLI session tokens are a different mechanism.** Tokens from `oci session authenticate` default to 1 h and can be refreshed up to 24 h with `oci session refresh`. https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/clitoken.htm. `oci session refresh` POSTs `{"currentToken": ...}` to `auth.<region>/v1/authentication/refresh` and rewrites `security_token_file` (`oracle/oci-cli` `src/oci_cli/cli_session.py`, `refresh()`). No Oracle source says this endpoint accepts a WIF-issued UPST, so treat it as **unverified**.

### How the provider and CLI consume the token (source, `main` on 2026-10-18)

- **Provider, `auth = "SecurityToken"`.** It builds `oci_common.ConfigurationProviderForSessionTokenWithProfile(~/.oci/config, profile, …)` (`oracle/terraform-provider-oci` `internal/provider/provider.go`, case `AuthSecurityToken`, ~L495). The path is hard-coded to `~/.oci/config` and `config_file_profile` is required.
- **Go SDK, `common/configuration.go`.**
  - `sessionTokenConfigurationProvider.KeyID()` calls `getTokenContent(filePath)` → `readFile()` (plain `os.ReadFile`, **no cache**) and returns `"ST$"+token`.
  - `PrivateRSAKey()` uses `readFileFromCache()`, a process-global `fileCache` map, so **the key is read once**.
  - `readAndParseConfigFile()` has a value receiver, so the config is effectively re-parsed on each call.
  - The request signer calls `KeyID()` and `PrivateRSAKey()` on **every request** (`common/http_signer.go` L292, L335).
  - `sessionTokenConfigurationProvider.Refreshable()` returns `true`, which enables one retry on 401 (`common/client.go` `RefreshableTokenWrappedCallWithDetails`).
  - Net effect: overwrite the token file in place (same path) and keep the key file unchanged.
- **The fingerprint gotcha** (found on a sibling pipeline, origoss/tofu-oci-foundation ADR 0013): the `SecurityToken` profile must also contain `fingerprint=` or the provider aborts. Also, `public_key` in the exchange must be the base64 DER body only, with no PEM markers and no newlines. https://github.com/origoss/tofu-oci-foundation/blob/main/docs/adr/0013-oci-oidc-upst-gotchas.md
- **CLI.** `cli_util.py` opens `security_token_file` once while building the signer (~L317–352). Oracle maintainer, oracle/oci-cli#998 (closed 2025-11-10): a running CLI process does not pick up a refreshed token, and session-token auth is "only for quick, temporary authentication". https://github.com/oracle/oci-cli/issues/998. The CLI has no native WIF auth mode (`cli_constants.py` lists `api_key`, `security_token`, `instance_principal`, `resource_principal`, `oke_workload_identity`, `instance_obo_user`, `pkcs11`).
- **Provider native WIF.** `auth = "WorkloadIdentityFederation"` (`internal/provider/workload_identity_federation.go`; CHANGELOG 8.22.0, 2026-07-08, "Support generic WorkloadIdentityFederation authentication"; the file is absent at v8.21.0).
  - Inputs: `workload_identity_token_path`, `token_exchange_domain_url`, `token_exchange_client_id` / `token_exchange_client_secret` (auth `OAuthClientCredentials`), `token_exchange_requested_token_type` (`oci-upst` or `oci-rpst`), and, for RPST, `token_exchange_resource_type` / `token_exchange_rpst_exp`.
  - Renewal: it uses `oci_common_auth.TokenExchangeConfigurationProviderFromIssuer` with a `fileBackedTokenIssuer` that re-reads the JWT file on each renewal. The Go SDK (`common/auth/federation_client.go` `renewSecurityTokenIfNotValid` / `renewSecurityToken`) re-exchanges when the token is within `bufferTimeBeforeTokenExpiration = 5 * time.Minute` of `exp` (`common/auth/jwt.go`), generating a **new 3072-bit key** each time.
  - The Python SDK `TokenExchangeSigner` follows the same pattern: it refreshes past half-life by calling a `jwt_or_func` again (`oracle/oci-python-sdk` `src/oci/auth/signers/token_exchange_signer.py`).
- **Working public example of native provider WIF from GitHub Actions (RPST variant).** https://github.com/dgutierrezcolodra/oci-terraform-github-actions-wif-example (OCI provider 9.8.0, green runs on 2026-10-08). A step writes `core.getIDToken()` to `$RUNNER_TEMP/oci-wif/github-oidc.jwt` and exports `OCI_WORKLOAD_IDENTITY_TOKEN_PATH`. Its demos are short, so they never exercise renewal.

### Actions surveyed

| Action | Does exchange? | Refresh mid-run? | Maintenance | Notes |
| --- | --- | --- | --- | --- |
| `oracle-actions/run-oci-cli-command` | No (static API key secrets `OCI_CLI_USER/TENANCY/FINGERPRINT/KEY_CONTENT/REGION`) | n/a | last push 2024-11 | Installs and runs the CLI only. https://github.com/oracle-actions/run-oci-cli-command |
| `oracle-actions/configure-kubectl-oke` | No (same API-key model) | n/a | last push 2024-12 | Out of scope (pipeline never touches the K8s API). |
| `gtrevorrow/oci-token-exchange-action` | **Yes**: generates a 2048-bit RSA pair, gets the GitHub JWT (default `aud=https://cloud.oracle.com`), exchanges for a UPST (or an RPST if `res_type` is set), and writes the `~/.oci/config` profile including the fingerprint | **No** (one-shot) | v2.0.0 2026-07-28, semantic-release, node24, last push 2026-09-14, 6 stars, single maintainer, not Oracle-published | Inputs: `oidc_client_identifier` (`id:secret`), `domain_base_url`, `oci_tenancy`, `oci_region`, `oidc_audience`, `oci_profile`, `oci_home`, `retry_count`, `res_type`, `rpst_exp`. Outputs: config, token, and key paths. Also works as a CLI for GitLab and Bitbucket. https://github.com/gtrevorrow/oci-token-exchange-action |
| `devopshouse/oci-oidc-auth-config` | Yes (composite curl) | No | 4 stars, created 2026-04 | Too small to depend on. |

## Risks and open questions

- **UPST lifetime from a GitHub JWT is unverified.** If OCI applies the min(JWT remaining, 60 min) rule, a UPST lasts only about 5 minutes. Native provider WIF would then treat it as already inside its 5-minute renewal buffer and re-exchange on nearly every request. **Action for #23:** in the first live run, log `exp - iat` from the decoded UPST (not the token itself) and choose the refresh interval from that number (for example, every `lifetime/2`).
- **The refresher must reuse the keypair** when used with `auth = "SecurityToken"`, because the provider caches `key_file` for the whole process. If a refresher rotates the key, the next request is signed with a stale key and fails.
- **Background-process lifetime.** A loop started with `&` in a step keeps running into later steps, but its failures go unnoticed. Start it in the same step as `tofu apply`, use `trap 'kill $pid' EXIT`, and write the token atomically (`mv` of a temp file) so the provider never reads a half-written file.
- **Partial-apply blast radius.** If the token lapses during an OKE create, the provider fails while polling the work request. OCI keeps creating the resource, but it is missing from state. This argues for a large refresh margin, and for documenting a `tofu import` recovery path.
- **State backend is unaffected.** The S3-compatible backend uses the Customer Secret Key (ADR-0003), so the final state write does not depend on the UPST.
- **RPST alternative.** RPST is configurable up to 12 h (default observed at 20 min) and avoids the refresh problem for most runs. It needs a *Resource* trust (`res_type`), and policies are written against resource principals instead of the **Service user**, which contradicts ADR-0001. Worth a separate ticket if UPST refresh proves fragile.
- **Side finding, outside this ticket (low-trust source, verify):** a user comment on gtrevorrow/oci-token-exchange-action#70 (2026-08) reports four things:
  - Impersonation rules must be **unquoted** (quoted rules are stored but never match).
  - `impersonation_service_users.value` must be the user's **32-char identity-domain ID**, not the OCID (there is a 40-char cap).
  - The target user needs `serviceUser: true`.
  - GitHub `sub` claims now embed immutable IDs (`repo:Org@1234/Repo@5678:…`).

  `bootstrap/wif.tf` currently uses a quoted `sw` rule and `oci_identity_user.ci.id` (an OCID), so it may be affected. https://github.com/gtrevorrow/oci-token-exchange-action/issues/70
- **Provider version.** Native WIF requires ≥ 8.22.0. Bootstrap pins `~> 5.0`, and the pipeline root's pin is not written yet.
