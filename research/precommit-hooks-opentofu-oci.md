# Pre-commit hooks for OpenTofu on OCI

Research for [#19](https://github.com/jagyugyaerik/tofu-free-oke/issues/19) (parent #16, blocks #22). Versions checked on 2026-10-18 via each project's GitHub "latest release" API.

Runtimes are **estimates** for a repo this size (about 3 root modules: `bootstrap/`, `environments/free`, `modules/*`). Nothing was benchmarked here. The only published benchmark cited is pre-commit-terraform's own parallelism table.

## Summary

| Need | Recommended hook (repo @ version) | Covers OCI? | Network at hook runtime | Rough runtime | pre-commit.ci-compatible |
|---|---|---|---|---|---|
| fmt | `terraform_fmt` from [antonbabenko/pre-commit-terraform] @ v1.109.2, tofu selected via `--tf-path=tofu` | n/a (syntax) | No | <1 s | No (`language: script`, needs `tofu` on PATH) |
| validate | `terraform_validate` (same repo) | Yes, schema-checks every `oci_*` attribute | **Yes**: `tofu init -backend=false` downloads `oracle/oci` (~70 MB zip for v9.10.0 linux_amd64) per root | 5-30 s cold, ~2-5 s warm with plugin cache | No |
| test | none upstream; use a `local` / `language: system` hook running `tofu test` | Yes, with `mock_provider` | Yes (init); no OCI creds needed if mocked | seconds per dir after init | No |
| docs | `terraform_docs` (same repo), terraform-docs v0.24.0 | n/a | No | <1 s | No |
| lint | `terraform_tflint`, tflint v0.64.0 (bundled terraform ruleset) | Generic only. OCI plugin is a 6-rule hobby project | Only for `tflint --init` (plugin download from GitHub API) | 1-3 s | No |
| IaC security | `checkov` from [bridgecrewio/checkov] @ 3.3.29 | **28 OCI checks** (22 resource + 6 graph, 3 of them OKE) | Tries Prisma Cloud metadata unless `--skip-download` | 10-30 s (Python startup) | Yes if offline flags are set |
| IaC security (alt) | `terraform_trivy`, trivy v0.76.0 | **Effectively none**: one check, targeting legacy `opc_*` (Classic), not `oracle/oci` | Checks bundle download (embedded fallback) | 2-10 s | No |
| Workflows | `actionlint` @ v1.7.12 (+ shellcheck inside `run:`) | n/a | No | <1 s | Yes (`language: golang`) |
| Workflows security | `zizmor` from [zizmorcore/zizmor-pre-commit] @ v1.31.1 | n/a | Online audits only if a GitHub token is set; offline otherwise | <1-2 s offline | Yes (offline mode) |
| Secrets | `gitleaks` @ v8.30.1 | n/a | No | <1 s staged | Yes (`language: golang`) |
| Secrets (alt) | `detect-secrets` @ v1.5.0 (May 2024) | n/a | No | 1-3 s | Yes (`language: python`) |
| Shell | `shellcheck` via [shellcheck-py/shellcheck-py] @ v0.11.0.1 | n/a | No (wheel bundles the binary) | <1 s | Yes |

[antonbabenko/pre-commit-terraform]: https://github.com/antonbabenko/pre-commit-terraform
[bridgecrewio/checkov]: https://github.com/bridgecrewio/checkov
[zizmorcore/zizmor-pre-commit]: https://github.com/zizmorcore/zizmor-pre-commit
[shellcheck-py/shellcheck-py]: https://github.com/shellcheck-py/shellcheck-py

**Bottom line:** use pre-commit-terraform with tofu forced through `--tf-path`, checkov for OCI security (not trivy), actionlint + zizmor for workflows, gitleaks for secrets and shellcheck-py for scripts. Run the same config in GitHub Actions with `pre-commit run --all-files`, installing tools with mise. pre-commit.ci cannot run the tofu/tflint hooks because it has no network and no system tools.

## Per-tool notes

### OpenTofu fmt / validate / docs: pre-commit-terraform (v1.109.2, 2026-09-30)

- The README says it supports "Terraform, OpenTofu, and Terragrunt". Binary discovery, first match wins ([README §1.1](https://github.com/antonbabenko/pre-commit-terraform#11-custom-terraform-binaries-and-opentofu-support)):
  1. `--hook-config=--tf-path=<bin>`
  2. `PCT_TFPATH`
  3. `TERRAGRUNT_TFPATH`
  4. `terraform` on `$PATH`
  5. `tofu` on `$PATH`

  **`terraform` wins if both are installed**, so set `PCT_TFPATH=tofu` or `--tf-path=tofu` explicitly.
- New in recent releases: `--hook-config=--tool-version=X` with `--tf-path=opentofu` downloads the pinned OpenTofu from GitHub releases into `~/.cache/pre-commit-terraform/`. That means network access on first use, and `GITHUB_TOKEN` is honoured. The default mode is `strict` (the pin wins over PATH); `prefer-local` inverts that. Renovate needs a `customManagers` regex to bump it (same README).
- Every hook is `language: script` (the repo's [.pre-commit-hooks.yaml](https://github.com/antonbabenko/pre-commit-terraform/blob/master/.pre-commit-hooks.yaml)). pre-commit installs **none** of the tools, so `tofu`, `tflint`, `terraform-docs` and `trivy` must already be on PATH. The alternative is the all-in-one Docker image `ghcr.io/antonbabenko/pre-commit-terraform`, whose README advises building your own.
- `terraform_validate` runs `init -backend=false` in each changed root (`hooks/_common.sh`, `common::terraform_init`). It needs no backend or credentials, but it **does download providers**. The README benchmark puts validate at "Network & Disk heavy" (1m30s for 45 dirs). It recommends `TF_PLUGIN_CACHE_DIR` and notes that OpenTofu ≥1.10 locks the cache, so parallelism is safe.
- There is **no `terraform_test` / `tofu_test` hook**. Write it as a `repo: local` hook.
- Alternative: [tofuutils/pre-commit-opentofu](https://github.com/tofuutils/pre-commit-opentofu) v2.4.2 (2026-06-12, about 100 stars). It is an OpenTofu-only fork with `tofu_fmt`, `tofu_validate`, `tofu_docs`, `tofu_tflint`, `tofu_trivy`, `tofu_checkov` and others, and also has no `tofu_test`. It is smaller and its releases lag. Upstream's explicit `--tf-path` is enough, so it is not worth switching to.
- terraform-docs v0.24.0 parses HCL itself and needs no init or network.

### `tofu test`

- OpenTofu v1.13.1 is current. `tofu test` looks in `tests/` and the current directory, and the documented flow is `tofu init` then `tofu test` ([docs](https://opentofu.org/docs/cli/commands/test/)).
- With `mock_provider "oci"` and `command = plan`, tests need **no OCI credentials**. They still need the provider binary from `init`, so network or a cache is required.
- Suggested local hook: `entry: bash -c 'for d in modules/*/; do (cd "$d" && tofu init -backend=false -input=false >/dev/null && tofu test); done'`, `language: system`, `pass_filenames: false`, `files: \.(tf|tftest\.hcl)$`. Consider putting it at `stages: [pre-push]` or CI-only, because of the init cost.

### tflint (v0.64.0, 2026-07-17)

- The terraform ruleset (v0.15.0) is **bundled**, so it needs no download ([README](https://github.com/terraform-linters/tflint#getting-started)). Any other plugin needs `tflint --init`, which calls the GitHub API: 60 req/h unauthenticated and shared on Actions runners, so set `GITHUB_TOKEN` ([plugins.md](https://github.com/terraform-linters/tflint/blob/master/docs/user-guide/plugins.md)).
- **OpenTofu is not officially supported.** The maintainer said "there are no plans to support OpenTofu at this time" ([tflint#2609](https://github.com/terraform-linters/tflint/issues/2609), `.tofu` extension, closed 2026-07). Plain `.tf` HCL works. Tofu-only syntax may confuse it (e.g. `.tofu` files, early-evaluated backend variables, [#2194](https://github.com/terraform-linters/tflint/issues/2194)).
- **No official OCI ruleset.** Official cloud rulesets exist only for AWS, Azure and Google. The only community one is [joelp172/tflint-ruleset-oci](https://github.com/joelp172/tflint-ruleset-oci): v0.1.2 (2025-03), 1 star, last push 2025-11, and [6 rules](https://github.com/joelp172/tflint-ruleset-oci/blob/main/docs/rules/README.md). Those rules are hardcoded provider keys, instance in-transit encryption, instance monitoring, NSG SSH 0.0.0.0/0, public bucket and bucket versioning. All of them overlap checkov. **Not recommended.**

### checkov vs trivy for `oracle/oci`

- **checkov 3.3.29 (2026-10-13)** has 22 Python resource checks in [`checkov/terraform/checks/resource/oci/`](https://github.com/bridgecrewio/checkov/tree/main/checkov/terraform/checks/resource/oci) plus 6 YAML graph checks in [`graph_checks/oci/`](https://github.com/bridgecrewio/checkov/tree/main/checkov/terraform/checks/graph_checks/oci).
  - **Resource checks:** IAM password policy (5), object storage public/versioning/encryption/events, block and file storage encryption/backup, instance IMDS/monitoring/in-transit encryption, and security list/NSG ingress (22/3389/stateless/unrestricted).
  - **Graph checks:** OKE boot-volume in-transit encryption, OKE endpoint with NSG (`CKV2_OCI_3`), OKE PodSecurityPolicy (`CKV2_OCI_6`), admin user with API key, NFS root, and NSG RDP.
  - **Quality caveat:** `CKV2_OCI_6` requires `is_pod_security_policy_enabled = true`. PSP was removed in Kubernetes 1.25, so this check should be `skip-check`ed for a current OKE cluster. Expect the bucket-versioning/events and instance checks to need skips for a deliberately minimal Always-Free state bucket.
  - **Hooks:** `checkov` (`language: python`, `checkov -d .`), `checkov_diff`, `checkov_secrets` and `_container` variants ([.pre-commit-hooks.yaml](https://github.com/bridgecrewio/checkov/blob/main/.pre-commit-hooks.yaml)).
  - **Network:** by default checkov fetches guideline metadata from Prisma Cloud. `--skip-download` disables that, and `--download-external-modules` is opt-in ([CLI reference](https://github.com/bridgecrewio/checkov/blob/main/docs/2.Basics/CLI%20Command%20Reference.md)).
- **trivy v0.76.0 (2026-10-14)**: trivy-checks v2.3.0 has a single Oracle check, [`OCI-0001` no_public_ip](https://github.com/aquasecurity/trivy-checks/tree/main/checks/cloud/oracle/compute). Trivy's Terraform adapter for Oracle reads only `opc_compute_ip_address_reservation` ([adapt.go](https://github.com/aquasecurity/trivy/blob/main/pkg/iac/adapters/terraform/oracle/adapt.go)). That is the legacy Oracle Cloud *Classic* `opc` provider, **so trivy has zero coverage of `oracle/oci` resources.**
  - It still catches generic things such as secrets in files.
  - Network: misconfig scanning downloads a checks bundle, with an embedded fallback ([air-gap docs](https://trivy.dev/latest/docs/advanced/air-gap/)). Use `--skip-check-update` / `--offline-scan` for determinism.
  - **Verdict: checkov.** trivy is not worth the runtime for this repo.

### actionlint (v1.7.12, 2026-03-30) and zizmor (v1.31.1, 2026-10-15)

- **actionlint** hooks are `actionlint` (`language: golang`, built by pre-commit), `actionlint-docker` and `actionlint-system` ([.pre-commit-hooks.yaml](https://github.com/rhysd/actionlint/blob/main/.pre-commit-hooks.yaml)). It needs no network at runtime, and it lints `run:` blocks with shellcheck when shellcheck is on PATH.
  - The mise registry now marks `actionlint` **deprecated** in favour of [jdx/jactionlint](https://github.com/jdx/jactionlint) (v2.2.0, a fork created 2026-10-05 by mise's author, citing unmerged upstream fixes). Upstream rhysd/actionlint is not archived. Staying on upstream for now is fine; revisit if upstream stalls.
- **zizmor**: use the hook from `zizmorcore/zizmor-pre-commit`, which installs a prebuilt PyPI wheel (`language: python`).
  - Modes ([usage docs](https://docs.zizmor.sh/usage/)): offline when `ZIZMOR_OFFLINE` is set or no token is present; online with audits when `GH_TOKEN`/`GITHUB_TOKEN` is set. Online audits include impostor commits, known-vulnerable actions and ref pinning.
  - Run offline in pre-commit for speed and determinism. Optionally run online in CI by passing `GITHUB_TOKEN` to the job.
  - The hook also audits `.pre-commit-config.yaml` and `dependabot.yml`.
  - These two tools are complementary: actionlint covers correctness, zizmor covers security (template injection, `pull_request_target`, credential persistence). Both matter here because the pipeline uses OIDC → WIF.

### Secret detection

- **gitleaks v8.30.1** ([hooks](https://github.com/gitleaks/gitleaks/blob/master/.pre-commit-hooks.yaml)): `gitleaks`, `gitleaks-docker` and `gitleaks-system`, entry `gitleaks git --pre-commit --redact --staged`.
  - Because it uses `--staged`, `pre-commit run --all-files` in CI scans **only staged changes, which is effectively nothing**. CI therefore needs its own full scan: `gitleaks git` over history, or [gitleaks-action](https://github.com/gitleaks/gitleaks-action) v3.0.0, which needs a free licence key only for org-owned repos. This repo is personal, so no key is needed.
  - It is fast, needs no network, and is a single Go binary.
- **detect-secrets v1.5.0** (last release 2024-05; commits until 2026-04): baseline-file workflow (`.secrets.baseline`) and `language: python`. It is slower to tune and less actively released. **Prefer gitleaks.**
- checkov (`checkov_secrets`) and trivy also scan for secrets, but use them as belt-and-braces only.
- OCI-specific risks: `~/.oci/config` key paths and private-key PEMs, plus `oci_identity_customer_secret_key` outputs (see `bootstrap/state.tf`). gitleaks' default rules cover PEM private keys. Mark the outputs `sensitive`; a scanner will not catch state.

### shellcheck (v0.11.0)

- Use [shellcheck-py](https://github.com/shellcheck-py/shellcheck-py) at `rev: v0.11.0.1`. The pip wheel ships the binary, so it works on pre-commit.ci with no Docker and no system install. The upstream koalaman repo has no `.pre-commit-hooks.yaml`.
- It needs no network at runtime and runs in milliseconds.

## CI parity options

**pre-commit.ci constraints** (primary source: maintainer statements on its issue tracker, since the site does not document them):

- **No network at hook runtime** ("pre-commit ci does not allow network at runtime", [issue #189](https://github.com/pre-commit-ci/issues/issues/189); asottile declined to document it publicly in [#249](https://github.com/pre-commit-ci/issues/issues/249)). Tool installation for supported languages happens beforehand.
- **No Docker** ([#11](https://github.com/pre-commit-ci/issues/issues/11), open).
- **No way to install system/script dependencies** ([#13](https://github.com/pre-commit-ci/issues/issues/13), open).
- It is free for public repos and offers `ci: skip: [...]` for per-hook exclusion ([pre-commit.ci](https://pre-commit.ci/)).
- Consequence: every pre-commit-terraform hook (`language: script`) and any `tofu test` / `tflint --init` hook **cannot run there**. Only actionlint, zizmor (offline), gitleaks, shellcheck-py and checkov (with `--skip-download`) could.

**Option A, recommended: a GitHub Actions job runs `pre-commit run --all-files`.**

1. Install tools with [jdx/mise-action](https://github.com/jdx/mise-action) v5.2.0 from a committed `mise.toml`. Every tool here is in the mise registry with an `aqua:` backend: `opentofu`, `tflint`, `terraform-docs`, `trivy`, `checkov`, `actionlint`, `zizmor`, `shellcheck`, `gitleaks`, `pre-commit`, `prek` ([registry/](https://github.com/jdx/mise/tree/main/registry)). Developers use the same `mise.toml` locally, so versions match exactly.
2. Cache `~/.cache/pre-commit`, `TF_PLUGIN_CACHE_DIR` (OCI provider about 70 MB) and `~/.tflint.d`.
3. Set `PCT_TFPATH=tofu` and pass `GITHUB_TOKEN` (needed for tflint `--init`, pct `--tool-version` and optionally zizmor online).
4. Run `pre-commit run --all-files --show-diff-on-failure`.
5. Add a separate full-history gitleaks step, because the hook is `--staged`.

- `pre-commit/action` v3.0.1 is maintenance-only and its README steers users to pre-commit.ci. A plain `pip install pre-commit` (or the mise-installed one) plus `run` is equivalent.
- [prek](https://github.com/j178/prek) v0.5.5 is a Rust drop-in for pre-commit that reads the same config and is faster. It is optional.

**Option B: hybrid.** Use pre-commit.ci for autofix PRs and the fast hooks, with `ci: skip: [terraform_fmt, terraform_validate, terraform_docs, terraform_tflint, tofu-test]`, plus the Actions job from option A for the skipped hooks. This adds two places that run checks and still needs option A, so it only pays off if autofix commits are wanted.

**Option C: Docker image.** `ghcr.io/antonbabenko/pre-commit-terraform:<tag>` bundles tofu, tflint, trivy, checkov and terraform-docs, and is run as a container. The README recommends building your own image for supply-chain reasons. Versions are coupled to the image rather than to `mise.toml`, so local runs and CI diverge unless developers also use Docker. **Not recommended** here.

**Nix** (devenv / `git-hooks.nix`) can also pin all of these. It is heavier than mise for a single-maintainer repo and was not researched further.

## Side observation

`bootstrap/versions.tf` pins `oracle/oci ~> 5.0`, while the latest provider release is v9.10.0 (2026-10-14). That is out of scope for this ticket, but it affects what `validate` downloads and which schema it checks against.
