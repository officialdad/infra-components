variable "global" {
  type = object({
    environment_name = string
    deploy_region    = string
    tags             = map(string)
  })
  description = "Environment-wide context injected by the environments repo (name, region, tags)."
}

variable "buckets" {
  type = map(object({
    bucket_name   = optional(string)
    versioning    = optional(bool, true)
    kms_key_arn   = optional(string)
    enforce_tls   = optional(bool, true)
    force_destroy = optional(bool, false)
    lifecycle_rules = optional(map(object({
      prefix                                 = optional(string, "")
      enabled                                = optional(bool, true)
      expiration_days                        = optional(number)
      noncurrent_version_expiration_days     = optional(number)
      noncurrent_versions_to_keep            = optional(number)
      abort_incomplete_multipart_upload_days = optional(number)
      expired_object_delete_marker           = optional(bool, false)
    })), {})
  }))
  description = "S3 buckets keyed by short name; each entry overrides only what it needs. Bucket name = \"<environment_name>-<key>\" unless bucket_name is set (S3 names are globally unique, so a taken name needs the override). Public access is blocked on all four settings, ACLs are disabled, and SSE is always on — none of those are inputs. versioning defaults true. kms_key_arn unset means SSE-S3 (AES256); set it for SSE-KMS. lifecycle_rules is keyed by rule id and each rule needs its own prefix (S3 rejects two rules sharing one). On a versioned bucket an object's total lifetime is expiration_days + noncurrent_version_expiration_days, so size both against any retention promise."
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.buckets) : can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$|^[a-z]$", k))])
    error_message = "Each buckets key must be: lowercase letter first, then lowercase/digits/hyphens, no trailing hyphen, ≤63 chars."
  }

  validation {
    condition = alltrue([
      for b in values(var.buckets) :
      b.bucket_name == null ? true : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", b.bucket_name))
    ])
    error_message = "Each bucket_name override must be a valid S3 bucket name: 3-63 chars, lowercase letters, digits, hyphens or dots, starting and ending alphanumeric."
  }

  validation {
    condition = alltrue(flatten([
      for b in values(var.buckets) : [
        for r in values(b.lifecycle_rules) :
        r.expiration_days != null || r.noncurrent_version_expiration_days != null ||
        r.noncurrent_versions_to_keep != null || r.abort_incomplete_multipart_upload_days != null ||
        r.expired_object_delete_marker
      ]
    ]))
    error_message = "Each lifecycle rule must set at least one action: expiration_days, noncurrent_version_expiration_days, noncurrent_versions_to_keep, abort_incomplete_multipart_upload_days, or expired_object_delete_marker."
  }

  validation {
    condition = alltrue(flatten([
      for b in values(var.buckets) : [
        for r in values(b.lifecycle_rules) : !(r.expiration_days != null && r.expired_object_delete_marker)
      ]
    ]))
    error_message = "A lifecycle rule cannot set both expiration_days and expired_object_delete_marker — S3 rejects the pair. With expiration_days set, S3 already removes expired delete markers once they reach that age, so drop expired_object_delete_marker."
  }

  validation {
    condition = alltrue([
      for b in values(var.buckets) :
      length(distinct([for r in values(b.lifecycle_rules) : r.prefix])) == length(b.lifecycle_rules)
    ])
    error_message = "Two lifecycle rules in one bucket cannot share a prefix — S3 answers InvalidRequest \"Found two rules with same prefix\". Merge them into one rule."
  }
}
