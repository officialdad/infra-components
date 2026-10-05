provider "aws" {
  region = var.global.deploy_region
}

locals {
  common_tags = merge(var.global.tags, {
    ManagedBy   = "terraform"
    Environment = var.global.environment_name
  })

  # Built from the region, not looked up: the automate action ARN is a fixed format, and a data
  # source would break greenfield planning.
  recover_action_arn = "arn:aws:automate:${var.global.deploy_region}:ec2:recover"

  disk_alarm_instances = var.disk_alarm == null ? {} : var.instances
}

# One topic for every alarm in the environment. The default topic policy already lets CloudWatch
# alarms in this account publish, so no custom policy is needed. Not KMS-encrypted: the
# AWS-managed SNS key blocks CloudWatch from publishing, and a customer key is a knob no consumer
# has asked for.
resource "aws_sns_topic" "alarms" {
  name = "${var.global.environment_name}-cloudwatch-alarms"

  tags = local.common_tags
}

# Email subscriptions stay pending until the recipient confirms; Terraform cannot confirm for them.
resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alarm_emails)

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = each.value
}

# A failed system check means the underlying host is impaired, so AWS moves the instance to new
# hardware (ec2:recover keeps instance id, IPs and EBS volumes). The topic is notified too, so a
# recovery never happens silently. Period 60 with Maximum is what the recover action requires.
resource "aws_cloudwatch_metric_alarm" "status_check_system" {
  for_each = var.instances

  alarm_name          = "${var.global.environment_name}-${each.key}-status-check-system"
  alarm_description   = "EC2 system status check failing on ${var.global.environment_name}-${each.key}; runs ec2:recover."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  dimensions          = { InstanceId = each.value.instance_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  # A stopped instance publishes no status checks, and that is not an outage.
  treat_missing_data = "notBreaching"

  alarm_actions = [local.recover_action_arn, aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = local.common_tags
}

# Instance check failures (guest OS, network config, exhausted memory) are inside the guest, so a
# hardware move would not fix them. Notify only.
resource "aws_cloudwatch_metric_alarm" "status_check_instance" {
  for_each = var.instances

  alarm_name          = "${var.global.environment_name}-${each.key}-status-check-instance"
  alarm_description   = "EC2 instance status check failing on ${var.global.environment_name}-${each.key}."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  dimensions          = { InstanceId = each.value.instance_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = local.common_tags
}

# Missing data stays missing (no state change): a stopped instance or a restarting agent must not
# page, and status_check_instance already covers an instance that is down.
resource "aws_cloudwatch_metric_alarm" "disk_used" {
  for_each = local.disk_alarm_instances

  alarm_name          = "${var.global.environment_name}-${each.key}-disk-used"
  alarm_description   = "Disk used above ${var.disk_alarm.threshold}% on ${var.global.environment_name}-${each.key}."
  namespace           = var.disk_alarm.namespace
  metric_name         = var.disk_alarm.metric_name
  dimensions          = merge(var.disk_alarm.dimensions, { InstanceId = each.value.instance_id })
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.disk_alarm.threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = local.common_tags
}

# Backup age is a gauge the environment publishes on a schedule. Missing data is breaching because
# a dead backup job stops publishing, and that silence is the failure to catch.
resource "aws_cloudwatch_metric_alarm" "backup_age" {
  count = var.backup_age_alarm == null ? 0 : 1

  alarm_name          = "${var.global.environment_name}-backup-age"
  alarm_description   = "Backup age above ${var.backup_age_alarm.threshold} (metric unit) in ${var.global.environment_name}, or no backup-age datapoints."
  namespace           = var.backup_age_alarm.namespace
  metric_name         = var.backup_age_alarm.metric_name
  dimensions          = var.backup_age_alarm.dimensions
  statistic           = "Maximum"
  period              = var.backup_age_alarm.period
  evaluation_periods  = 1
  threshold           = var.backup_age_alarm.threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = local.common_tags
}
