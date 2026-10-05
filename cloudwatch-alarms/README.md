# cloudwatch-alarms

CloudWatch alarms on **AWS** EC2 instances and backup freshness, all notifying **one SNS topic with
email subscriptions** - the module never installs agents or publishes metrics, the environment does.

## What it creates

- **An SNS topic** - `<environment_name>-cloudwatch-alarms`, with one **email subscription** per
  `alarm_emails` entry. Every alarm notifies it on `ALARM` and on `OK`.
- **A `StatusCheckFailed_System` alarm per `instances` entry** - `<environment_name>-<key>-status-check-system`.
  Runs the **`ec2:recover` action** (moves the instance to healthy hardware, keeping its instance id,
  private IP, and EBS volumes) and notifies the topic.
- **A `StatusCheckFailed_Instance` alarm per `instances` entry** - `<environment_name>-<key>-status-check-instance`.
  Notifies only: a fault inside the guest is not fixed by a hardware move.
- **A disk-used alarm per `instances` entry, opt-in** - set `disk_alarm` to get
  `<environment_name>-<key>-disk-used` on a custom metric, default `CWAgent` /
  `disk_used_percent` above `80`. Its `dimensions` must match the published series - see
  [Disk alarm dimensions](#disk-alarm-dimensions). `null` (default) creates none.
- **One backup-age alarm, opt-in** - set `backup_age_alarm` to get `<environment_name>-backup-age`
  on a custom metric whose namespace, name, and threshold you supply. `null` (default) creates none.

> ⚠️ **Confirm the email subscriptions** - AWS sends each address a confirmation link, and nothing
> is delivered until it is clicked. Terraform cannot do this step.
>
> ⚠️ **`ec2:recover` has limits** - it does not recover instances with instance-store volumes, and
> only some instance types support it. A recovery reboots the instance, so the topic is notified too.
>
> ⚠️ **The metrics must exist** - the disk metric needs a publisher (usually the CloudWatch agent),
> and the backup-age metric needs a publisher. An alarm whose `dimensions` do not match the
> published metric exactly never sees data. Missing disk data moves the alarm to
> `INSUFFICIENT_DATA`, which notifies nobody. Missing backup-age data always raises the alarm, so the
> publisher must emit a datapoint at least once per `period` (default `3600` seconds).
>
> ⚠️ **The topic is not KMS-encrypted** - the AWS-managed SNS key blocks CloudWatch from publishing.
> Alarm messages carry alarm names and metric values, no secrets.

## Auth

Provider needs AWS credentials (env vars / shared config / CI role) - supplied out-of-band, none
stored here. Region comes from `var.global.deploy_region`. The principal running `apply` needs
`cloudwatch:PutMetricAlarm` / `cloudwatch:DeleteAlarms` / `cloudwatch:TagResource` and `sns:*` on
`<env>-cloudwatch-alarms` (and `sns:Subscribe`). `automation-roles` does not grant these yet.

## Dependencies

- Consumes `instances` from the **`ec2`** component → `instances`. The map passes as is: only
  `instance_id` is read and extra attributes are ignored.

### Entry shapes

The generated Inputs table collapses objects into one type. Per-field intent:

- `instances` - keyed by the same short name as the `ec2` entry, which names the alarms.
  - `instance_id` (required) - the instance the alarms watch.
- `disk_alarm` (`null`) - one alarm per `instances` entry.
  - `namespace` (`CWAgent`) - namespace the agent publishes to.
  - `metric_name` (`disk_used_percent`) - metric name.
  - `threshold` (`80`) - percent used, above `0` and at most `100`.
  - `dimensions` (`{}`) - extra dimensions. `InstanceId` is added per instance and must not be set
    here.
- `backup_age_alarm` (`null`) - one alarm for the environment.
  - `namespace` (required) - namespace of the publisher's metric.
  - `metric_name` (required) - metric name.
  - `threshold` (required) - age limit in the metric's own unit. No default, because the unit is the
    publisher's choice.
  - `dimensions` (`{}`) - used verbatim, so add `InstanceId` here if the metric has it.
  - `period` (`3600`) - seconds per datapoint window, a multiple of `60`.

#### Disk alarm dimensions

`disk_alarm = {}` matches only a series whose sole dimension is `InstanceId`. Two publishers emit
one:

- **A custom publisher** - `aws cloudwatch put-metric-data` with only `InstanceId`.
- **The CloudWatch agent with aggregation** - `aggregation_dimensions = [["InstanceId"]]` in its
  config.

The agent's default series also carries `path`, `device`, and `fstype`. Match them to watch one
filesystem:

```hcl
disk_alarm = {
  dimensions = { path = "/", device = "nvme0n1p1", fstype = "xfs" }
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| alarm\_emails | Email addresses subscribed to the alarm topic. Required: an alarm nobody hears is worse than a failed plan. Each address must confirm its subscription from the email AWS sends before it receives anything. | `list(string)` | n/a | yes |
| global | Environment-wide context injected by the environments repos (name, region, tags). | <pre>object({<br/>    environment_name = string<br/>    deploy_region    = string<br/>    tags             = map(string)<br/>  })</pre> | n/a | yes |
| backup\_age\_alarm | One alarm on a custom backup-age metric that the consuming environment publishes; null (default) creates none. threshold uses the metric's own unit (for example seconds), so it has no default. dimensions are used verbatim. The publisher must emit at least one datapoint per period (seconds, default 3600). Missing data counts as breaching, so a publisher that stops running raises the alarm. | <pre>object({<br/>    namespace   = string<br/>    metric_name = string<br/>    threshold   = number<br/>    dimensions  = optional(map(string), {})<br/>    period      = optional(number, 3600)<br/>  })</pre> | `null` | no |
| disk\_alarm | Per-instance alarm on a custom disk-used-percent metric; null (default) creates none. The consuming environment publishes the metric, usually with the CloudWatch agent. InstanceId is always added to the dimensions; dimensions adds the rest, and the set must match the published metric exactly or the alarm never sees data. {} matches only a series whose sole dimension is InstanceId, such as one from aws cloudwatch put-metric-data with only InstanceId, or from the CloudWatch agent with aggregation\_dimensions = [["InstanceId"]]. The agent's default series also carries path, device and fstype, for example { path = "/", device = "nvme0n1p1", fstype = "xfs" }. threshold is a percentage. | <pre>object({<br/>    namespace   = optional(string, "CWAgent")<br/>    metric_name = optional(string, "disk_used_percent")<br/>    threshold   = optional(number, 80)<br/>    dimensions  = optional(map(string), {})<br/>  })</pre> | `null` | no |
| instances | EC2 instances to alarm on, keyed by short name (the ec2 component's instances output fits as is - extra attributes are ignored). Each gets a StatusCheckFailed\_System alarm that also runs the ec2:recover action, and a StatusCheckFailed\_Instance alarm. ec2:recover cannot recover instances with instance-store volumes. | <pre>map(object({<br/>    instance_id = string<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alarm\_names | Alarm names by kind: status\_check\_system, status\_check\_instance and disk\_used are keyed by instances-map key; backup\_age is the single alarm name, or null when backup\_age\_alarm is unset. |
| topic\_arn | ARN of the SNS topic every alarm notifies. Other alarms or event rules in the environment can publish to it. |
<!-- END_TF_DOCS -->
