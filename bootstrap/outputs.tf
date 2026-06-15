# Paste these into GitHub repo secrets/variables for the pipeline. The secret
# key is sensitive and shown ONLY on the apply that creates it.

output "compartment_ocid" {
  description = "Project compartment OCID -> environments/free var + GH variable."
  value       = oci_identity_compartment.this.id
}

output "service_user_ocid" {
  description = "Service user OCID (impersonated by the pipeline)."
  value       = oci_identity_user.ci.id
}

output "region" {
  description = "Region -> GH variable."
  value       = var.region
}

output "objectstorage_namespace" {
  description = "Object Storage namespace -> backend endpoint + GH variable."
  value       = data.oci_objectstorage_namespace.ns.namespace
}

output "state_bucket" {
  description = "State bucket name -> backend config."
  value       = oci_objectstorage_bucket.state.name
}

output "s3_backend_endpoint" {
  description = "s3-compatible endpoint for the OpenTofu backend."
  value       = "https://${data.oci_objectstorage_namespace.ns.namespace}.compat.objectstorage.${var.region}.${var.objectstorage_domain}"
}

output "state_access_key_id" {
  description = "Customer Secret Key id -> GH secret AWS_ACCESS_KEY_ID."
  value       = oci_identity_customer_secret_key.state.id
}

output "state_secret_key" {
  description = "Customer Secret Key secret -> GH secret AWS_SECRET_ACCESS_KEY (shown once)."
  value       = oci_identity_customer_secret_key.state.key
  sensitive   = true
}

output "identity_domain_url" {
  description = "Identity domain base URL -> GH variable OCI_DOMAIN_URL (token-exchange endpoint host)."
  value       = var.configure_wif ? data.oci_identity_domain.this[0].url : null
}
