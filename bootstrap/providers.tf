# Bootstrap is applied LOCALLY by a human admin using the DEFAULT ~/.oci/config
# profile (API-key auth). It seeds the trust + state that the OIDC pipeline needs.
provider "oci" {
  config_file_profile = "DEFAULT"
  region              = var.region
}
