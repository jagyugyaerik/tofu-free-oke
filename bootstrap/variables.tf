variable "tenancy_ocid" {
  description = "Tenancy OCID (root compartment). Parent of the project compartment."
  type        = string
  validation {
    condition     = startswith(var.tenancy_ocid, "ocid1.tenancy.")
    error_message = "tenancy_ocid must be a tenancy OCID (ocid1.tenancy.*)."
  }
}

variable "region" {
  description = "OCI region identifier (e.g. eu-frankfurt-1). Should match your DEFAULT ~/.oci/config."
  type        = string
}

variable "name" {
  description = "Name prefix for bootstrap resources."
  type        = string
  default     = "freeoke"
}

variable "service_user_email" {
  description = "Primary email for the service user. Identity-domain tenancies require it on user creation; it is not used for login."
  type        = string
  default     = "freeoke-ci@example.com"
}

variable "objectstorage_domain" {
  description = "Realm domain suffix for the Object Storage S3-compatible endpoint. Commercial (OC1) = oraclecloud.com; EU Sovereign = oci.oraclecloud.eu."
  type        = string
  default     = "oraclecloud.com"
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the service user, as owner/name."
  type        = string
  default     = "jagyugyaerik/tofu-free-oke"
  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repo))
    error_message = "github_repo must be in owner/name form."
  }
}

# ----- WIF (Workload Identity Federation). Toggle off to do WIF via the console
# ----- and still apply IAM + state. See README.
variable "configure_wif" {
  description = "Whether to create the Identity Propagation Trust in OpenTofu."
  type        = bool
  default     = true
}

variable "identity_domain_id" {
  description = "OCID of the identity domain that hosts the trust (e.g. the Default domain). Required when configure_wif = true."
  type        = string
  default     = null
}

variable "oauth_client_id" {
  description = "Client ID of the token-exchange Confidential Application (created once in the console — see README). Authorized as an OAuth client on the trust. Required when configure_wif = true."
  type        = string
  default     = null
}

variable "tags" {
  description = "Freeform tags applied to bootstrap resources."
  type        = map(string)
  default     = { managed_by = "opentofu", project = "tofu-free-oke", layer = "bootstrap" }
}
