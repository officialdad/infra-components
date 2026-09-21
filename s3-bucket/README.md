# s3-bucket

One or more **AWS S3 buckets**, defined as a map (`buckets`) and fanned out with `for_each` —
**private by construction**: public access blocked on all four settings, ACLs disabled, encryption
at rest always on, and versioning on unless the caller turns it off.

## What it creates

- **An `aws_s3_bucket` per `buckets` entry** — named `<environment_name>-<key>` (or that entry's
  `bucket_name` override) and tagged with `common_tags`. Its name, ARN, domain names and region come
  back in the `buckets` output under the same map key.
- **`aws_s3_bucket_public_access_block`** — all four settings `true`. Hardcoded, not an input.
- **`aws_s3_bucket_ownership_controls`** — `BucketOwnerEnforced`, so ACLs are disabled outright and
  the bucket policy is the only grant path.
- **`aws_s3_bucket_server_side_encryption_configuration`** — `AES256` (SSE-S3) by default; setting
  `kms_key_arn` switches the entry to `aws:kms` with an S3 Bucket Key.
- **`aws_s3_bucket_versioning`** — `Enabled` by default, `Suspended` when `versioning = false`.
- **`aws_s3_bucket_lifecycle_configuration`** — one rule per `lifecycle_rules` entry, keyed by rule
  id. Created only for entries that declare rules.
- **`aws_s3_bucket_object_lock_configuration`** — WORM default retention, only for an entry that
  sets `object_lock_default_retention`. Off by default.
- **`aws_s3_bucket_policy`** — a single `Deny` on `aws:SecureTransport = false`, refusing plaintext
  HTTP. On by default, off with `enforce_tls = false`.

> ⚠️ **S3 names are global, not per-account** — the default `<environment_name>-<key>` can collide
> with a bucket someone else already owns, and the apply fails with `BucketAlreadyExists`. Set that
> entry's `bucket_name` to something you own the name of.
>
> ⚠️ **On a versioned bucket, retention is the sum of two numbers** — `expiration_days` only writes a
> delete marker and makes the object noncurrent. The bytes survive until
> `noncurrent_version_expiration_days` elapses *after that*. Total worst-case lifetime is
> `expiration_days + noncurrent_version_expiration_days`. Size both against whatever retention you
> promised, not `expiration_days` alone.
>
> ⚠️ **One prefix, one rule** — S3 answers `InvalidRequest: Found two rules with same prefix` when a
> configuration carries two rules over the same prefix. A `validation` block rejects that at plan
> time. Put every action for a prefix in one rule.
>
> ⚠️ **Object Lock is decided once, at creation** — S3 cannot add it to a bucket that already
> exists. Turning `object_lock_enabled` on later replaces the bucket and loses every object in it.
> Decide before the first apply.
>
> ⚠️ **Object Lock outranks the lifecycle rule** — a version under retention cannot be removed by
> anyone, the lifecycle included, until the window closes. Set
> `object_lock_default_retention.days` **below** `expiration_days + noncurrent_version_expiration_days`
> or objects outlive the retention you promised.
>
> ⚠️ **`force_destroy = true` deletes every object and version** on a `terraform destroy`. Default
> `false`. The hard guard is the env's Terragrunt `prevent_destroy`.

## What S3 lifecycle cannot do

Lifecycle expires objects by **age** under a **prefix**. It cannot thin an existing set down — there
is no rule that means "keep one copy per day and drop the rest". A retention policy shaped like
"hourly for a week, then daily for a month" needs the **writer** to put the two classes under two
prefixes, and then a rule per prefix. Deciding that is the consuming environment's job; this
component only applies the rules it is handed.

## Auth

Provider needs AWS credentials (env vars / shared config / CI role) — supplied out-of-band, none
stored here. Region comes from `var.global.deploy_region`. The principal running `apply` needs
`s3:CreateBucket`, `s3:PutBucketPublicAccessBlock`, `s3:PutBucketOwnershipControls`,
`s3:PutBucketVersioning`, `s3:PutEncryptionConfiguration`, `s3:PutLifecycleConfiguration` and
`s3:PutBucketPolicy` (plus `s3:PutBucketTagging` and the matching `Get*`/`Delete*` for reads and
destroys).

## Dependencies

None — a leaf store. Consumers go the other way: feed `buckets[<key>].arn` into an **`iam-policy`**
document to scope a writer or reader grant, then attach that policy ARN to a role (e.g. `ec2`'s
`iam_role_policy_arns`).

### `buckets` entry shape

The generated Inputs table renders `buckets` as one `map(object({…}))`. Per-field intent (the map
**key** is the bucket's purpose — it sets the default name `<env>-<key>`):

- `bucket_name` (unset) — full bucket name, overriding the derived one. Use it when the derived name
  is taken in S3's global namespace.
- `versioning` (`true`) — `Enabled` when true, `Suspended` when false. Keep it on wherever a
  prior version is the recovery path.
- `kms_key_arn` (unset) — unset means SSE-S3 (`AES256`), which needs no KMS grant on the writer's
  role. Set it for SSE-KMS, and grant that role `kms:GenerateDataKey` on the key or every put fails.
- `enforce_tls` (`true`) — attaches the `DenyInsecureTransport` bucket policy. Turn it off only for a
  client that genuinely cannot speak HTTPS.
- `force_destroy` (`false`) — when true, `terraform destroy` empties the bucket first. Opt-in.
- `object_lock_enabled` (`false`) — creation-time only, and requires `versioning`. On its own it
  only makes the bucket capable of holding locks; nothing is locked until a retention is set.
- `object_lock_default_retention` (unset) — `{ mode, days }` applied to every new version.
  `GOVERNANCE` lets a caller holding `s3:BypassGovernanceRetention` override it; `COMPLIANCE` lets
  nobody, including the root account. Needs `object_lock_enabled = true`.
- `lifecycle_rules` (`{}`) — rules keyed by rule id, which becomes the S3 rule `ID`.

### Overwrite is a write, and a write is not a delete

A principal holding only `s3:PutObject` on a prefix can still replace an object under it. Versioning
turns that into a new version rather than a loss — the previous bytes become noncurrent and survive
until `noncurrent_version_expiration_days` elapses. **That number is the window in which a bad or
malicious overwrite is still recoverable.** A short one (1 day) makes write-only access nearly as
destructive as delete access. Size it against how long detection takes, not against storage cost.
`object_lock_default_retention` is the hard version of the same guarantee.

### `lifecycle_rules` entry shape

- `prefix` (`""`) — key prefix the rule matches. `""` is the whole bucket. Unique per bucket.
- `enabled` (`true`) — `Enabled` or `Disabled`. Disable to park a rule without deleting it.
- `expiration_days` (unset) — age in days at which a current object expires. On a versioned bucket
  this writes a delete marker; see the retention warning above.
- `noncurrent_version_expiration_days` (unset) — days after a version becomes noncurrent before S3
  removes the bytes. This is the number that actually ends retention on a versioned bucket.
- `noncurrent_versions_to_keep` (unset) — `NewerNoncurrentVersions`. S3 expires a version only once
  **both** this count and `noncurrent_version_expiration_days` are exceeded, so setting it extends
  retention. Leave it unset unless you want that floor.
- `abort_incomplete_multipart_upload_days` (unset) — days before S3 drops the parts of an upload that
  never completed. Otherwise those parts are billed forever and are invisible in a normal listing.
- `expired_object_delete_marker` (`false`) — remove a delete marker once it is the only version.
  Mutually exclusive with `expiration_days` in one rule, and unnecessary alongside it: with
  `expiration_days` set, S3 already clears expired delete markers at that age.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| global | Environment-wide context injected by the environments repo (name, region, tags). | <pre>object({<br/>    environment_name = string<br/>    deploy_region    = string<br/>    tags             = map(string)<br/>  })</pre> | n/a | yes |
| buckets | S3 buckets keyed by short name; each entry overrides only what it needs. Bucket name = "<environment\_name>-<key>" unless bucket\_name is set (S3 names are globally unique, so a taken name needs the override). Public access is blocked on all four settings, ACLs are disabled, and SSE is always on — none of those are inputs. versioning defaults true. kms\_key\_arn unset means SSE-S3 (AES256); set it for SSE-KMS. lifecycle\_rules is keyed by rule id and each rule needs its own prefix (S3 rejects two rules sharing one). On a versioned bucket an object's total lifetime is expiration\_days + noncurrent\_version\_expiration\_days, so size both against any retention promise. | <pre>map(object({<br/>    bucket_name   = optional(string)<br/>    versioning    = optional(bool, true)<br/>    kms_key_arn   = optional(string)<br/>    enforce_tls   = optional(bool, true)<br/>    force_destroy = optional(bool, false)<br/><br/>    object_lock_enabled = optional(bool, false)<br/>    object_lock_default_retention = optional(object({<br/>      mode = string<br/>      days = number<br/>    }))<br/><br/>    lifecycle_rules = optional(map(object({<br/>      prefix                                 = optional(string, "")<br/>      enabled                                = optional(bool, true)<br/>      expiration_days                        = optional(number)<br/>      noncurrent_version_expiration_days     = optional(number)<br/>      noncurrent_versions_to_keep            = optional(number)<br/>      abort_incomplete_multipart_upload_days = optional(number)<br/>      expired_object_delete_marker           = optional(bool, false)<br/>    })), {})<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| buckets | Created S3 buckets keyed by their buckets-map key. `arn` is what a consumer scopes an IAM policy to: the bucket ARN itself for bucket-level actions, and the ARN plus "/<prefix>/*" for the objects. |
<!-- END_TF_DOCS -->
