output "buckets" {
  description = "Created S3 buckets keyed by their buckets-map key. `arn` is what a consumer scopes an IAM policy to: the bucket ARN itself for bucket-level actions, and the ARN plus \"/<prefix>/*\" for the objects."
  value = {
    for k, b in aws_s3_bucket.this : k => {
      bucket                      = b.id
      arn                         = b.arn
      bucket_domain_name          = b.bucket_domain_name
      bucket_regional_domain_name = b.bucket_regional_domain_name
      region                      = b.region
    }
  }
}
