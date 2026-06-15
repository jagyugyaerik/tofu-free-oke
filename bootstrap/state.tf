# Remote-state seed: an Object Storage bucket (Always-Free, ≤20 GB) plus a
# Customer Secret Key for the service user. The s3-compatible backend in
# environments/free uses these. The secret key is the single static secret in
# the system (see docs/adr/0003) — output once, store as a GitHub secret.

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.tenancy_ocid
}

resource "oci_objectstorage_bucket" "state" {
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  compartment_id = oci_identity_compartment.this.id
  name           = "${var.name}-tofu-state"
  versioning     = "Enabled"
  freeform_tags  = var.tags
}

# AWS-style access key/secret for the s3-compatible backend. The `key` (secret)
# is returned ONLY at creation — capture it from the output immediately.
resource "oci_identity_customer_secret_key" "state" {
  user_id      = oci_identity_user.ci.id
  display_name = "${var.name}-tofu-state-backend"
}
