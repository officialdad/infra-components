provider "aws" {
  region = var.global.deploy_region
}

locals {
  common_tags = merge(var.global.tags, {
    ManagedBy   = "terraform"
    Environment = var.global.environment_name
  })

  bucket_names = {
    for k, b in var.buckets : k => coalesce(b.bucket_name, "${var.global.environment_name}-${k}")
  }

  # Buckets that actually declare rules — an empty aws_s3_bucket_lifecycle_configuration is invalid.
  lifecycle_buckets = { for k, b in var.buckets : k => b if length(b.lifecycle_rules) > 0 }

  tls_buckets = { for k, b in var.buckets : k => b if b.enforce_tls }
}

# One bucket per entry. Name is deterministic (no suffix) unless the caller overrides it, which
# S3's global namespace sometimes forces.
resource "aws_s3_bucket" "this" {
  for_each = var.buckets

  bucket        = local.bucket_names[each.key]
  force_destroy = each.value.force_destroy

  tags = merge(local.common_tags, {
    Name = local.bucket_names[each.key]
  })
}

# Hardcoded, not an input: a consumer opts into exposure, never out of it. All four settings block
# both ACL- and policy-granted public access.
resource "aws_s3_bucket_public_access_block" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# BucketOwnerEnforced disables ACLs entirely, so object ownership can never be split and an ACL can
# never widen access. Required for the public access block to be the only grant path.
resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = each.value.versioning ? "Enabled" : "Suspended"
  }
}

# Encryption at rest is always on. kms_key_arn unset -> SSE-S3 (AES256), which needs no key grant on
# the writer's role; set it for SSE-KMS and grant the writer kms:GenerateDataKey.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = each.value.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = each.value.kms_key_arn
    }
    bucket_key_enabled = each.value.kms_key_arn != null
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = local.lifecycle_buckets

  bucket = aws_s3_bucket.this[each.key].id

  dynamic "rule" {
    for_each = each.value.lifecycle_rules

    content {
      id     = rule.key
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [rule.value.expiration_days] : []
        content {
          days = expiration.value
        }
      }

      # S3 rejects expired_object_delete_marker alongside days. With days set it cleans expired
      # delete markers itself; this action is for a rule that only expires noncurrent versions.
      dynamic "expiration" {
        for_each = rule.value.expired_object_delete_marker ? [true] : []
        content {
          expired_object_delete_marker = true
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = (rule.value.noncurrent_version_expiration_days != null ||
        rule.value.noncurrent_versions_to_keep != null) ? [true] : []
        content {
          noncurrent_days           = rule.value.noncurrent_version_expiration_days
          newer_noncurrent_versions = rule.value.noncurrent_versions_to_keep
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload_days != null ? [rule.value.abort_incomplete_multipart_upload_days] : []
        content {
          days_after_initiation = abort_incomplete_multipart_upload.value
        }
      }
    }
  }

  # Versioning decides whether an expiration writes a delete marker or removes the object outright.
  depends_on = [aws_s3_bucket_versioning.this]
}

# Refuse plaintext HTTP. The public access block already stops anonymous reads; this stops a
# credentialed caller from sending an object or its key over an unencrypted connection.
resource "aws_s3_bucket_policy" "tls_only" {
  for_each = local.tls_buckets

  bucket = aws_s3_bucket.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.this[each.key].arn,
        "${aws_s3_bucket.this[each.key].arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })

  # A bucket policy applied before the public access block can be read as public for a moment.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
