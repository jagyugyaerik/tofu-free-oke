# Project compartment + the single service user the OIDC pipeline impersonates,
# with a least-privilege policy scoped to that compartment.

resource "oci_identity_compartment" "this" {
  compartment_id = var.tenancy_ocid
  name           = var.name
  description    = "Always-Free OKE project (tofu-free-oke)."
  freeform_tags  = var.tags
}

resource "oci_identity_group" "ci" {
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-ci"
  description    = "CI/CD principals that provision the ${var.name} cluster."
  freeform_tags  = var.tags
}

# The "simple user": non-human, impersonated by the pipeline via WIF -> UPST.
resource "oci_identity_user" "ci" {
  compartment_id = var.tenancy_ocid
  name           = "${var.name}-ci"
  description    = "Service user for the ${var.name} GitHub Actions pipeline."
  email          = var.service_user_email
  freeform_tags  = var.tags
}

resource "oci_identity_user_group_membership" "ci" {
  group_id = oci_identity_group.ci.id
  user_id  = oci_identity_user.ci.id
}

# Least privilege: manage only the resource families the pipeline provisions,
# all scoped to the project compartment. object-family covers the state bucket.
resource "oci_identity_policy" "ci" {
  compartment_id = oci_identity_compartment.this.id
  name           = "${var.name}-ci"
  description    = "Provisioning rights for the ${var.name} pipeline."
  freeform_tags  = var.tags

  statements = [
    "Allow group ${oci_identity_group.ci.name} to manage cluster-family in compartment ${oci_identity_compartment.this.name}",
    "Allow group ${oci_identity_group.ci.name} to manage instance-family in compartment ${oci_identity_compartment.this.name}",
    "Allow group ${oci_identity_group.ci.name} to manage virtual-network-family in compartment ${oci_identity_compartment.this.name}",
    "Allow group ${oci_identity_group.ci.name} to manage volume-family in compartment ${oci_identity_compartment.this.name}",
    "Allow group ${oci_identity_group.ci.name} to manage load-balancers in compartment ${oci_identity_compartment.this.name}",
    "Allow group ${oci_identity_group.ci.name} to manage bastion-family in compartment ${oci_identity_compartment.this.name}",
    "Allow group ${oci_identity_group.ci.name} to manage object-family in compartment ${oci_identity_compartment.this.name}",
    "Allow group ${oci_identity_group.ci.name} to read all-resources in compartment ${oci_identity_compartment.this.name}",
  ]
}

# OKE service policy: lets the OKE service manage nodes/networking in the
# compartment on the cluster's behalf. Needed for managed node pools.
resource "oci_identity_policy" "oke_service" {
  compartment_id = oci_identity_compartment.this.id
  name           = "${var.name}-oke-service"
  description    = "Allow the OKE service to manage the cluster's nodes and networking."
  freeform_tags  = var.tags

  statements = [
    "Allow service OKE to manage instance-family in compartment ${oci_identity_compartment.this.name}",
    "Allow service OKE to manage virtual-network-family in compartment ${oci_identity_compartment.this.name}",
  ]
}
