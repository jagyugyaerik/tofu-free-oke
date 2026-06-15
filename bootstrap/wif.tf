# Workload Identity Federation: trust GitHub Actions OIDC tokens and let them
# impersonate the service user. Gated by configure_wif so IAM + state can be
# applied even if you create the trust in the console instead.
#
# PREREQUISITE (one console step, see README): create a Confidential Application
# in the identity domain as the token-exchange OAuth client; pass its Client ID
# as var.oauth_client_id. Its client_id/secret are the Basic-auth credentials
# the pipeline uses on the /oauth2/v1/token call.

data "oci_identity_domain" "this" {
  count     = var.configure_wif ? 1 : 0
  domain_id = var.identity_domain_id
}

resource "oci_identity_domains_identity_propagation_trust" "github" {
  count         = var.configure_wif ? 1 : 0
  idcs_endpoint = data.oci_identity_domain.this[0].url
  name          = "${var.name}-github-actions"
  issuer        = "https://token.actions.githubusercontent.com"
  type          = "JWT"
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]
  active        = true

  # The resulting UPST impersonates the service user. Only tokens whose `sub`
  # claim starts with this repo's prefix are accepted.
  # NOTE: verify the rule grammar against your provider version; tighten to a
  # specific ref (e.g. ':ref:refs/heads/main') if you want apply-only on main.
  allow_impersonation = true
  oauth_clients       = [var.oauth_client_id]

  impersonation_service_users {
    rule  = "sub sw 'repo:${var.github_repo}:'"
    value = oci_identity_user.ci.id
  }

  lifecycle {
    precondition {
      condition     = var.identity_domain_id != null && var.oauth_client_id != null
      error_message = "configure_wif = true requires identity_domain_id and oauth_client_id (create the Confidential App first — see README)."
    }
  }
}
