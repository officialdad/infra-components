# Mocked provider: no credentials, no cloud calls. Runs that read alarm_actions use `apply` because
# the topic ARN is unknown at plan time. The mock must return a well-formed ARN because the
# provider validates alarm_actions entries.
mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:ap-southeast-1:123456789012:test-cloudwatch-alarms"
    }
  }
}

variables {
  global = {
    environment_name = "test"
    deploy_region    = "ap-southeast-1"
    tags             = {}
  }
  alarm_emails = ["ops@example.com"]
}

run "topic_and_subscriptions_without_instances" {
  command = plan

  variables {
    alarm_emails = ["a@example.com", "b@example.com"]
  }

  assert {
    condition     = aws_sns_topic.alarms.name == "test-cloudwatch-alarms"
    error_message = "Topic name must be <environment_name>-cloudwatch-alarms."
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 2
    error_message = "Each alarm_emails entry must create one email subscription."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.status_check_system) == 0 && length(aws_cloudwatch_metric_alarm.backup_age) == 0
    error_message = "No instances and no backup_age_alarm must create no alarms."
  }
}

run "status_checks_per_instance" {
  command = apply

  variables {
    instances = {
      app = { instance_id = "i-0123456789abcdef0" }
      db  = { instance_id = "i-0fedcba9876543210" }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.status_check_system) == 2 && length(aws_cloudwatch_metric_alarm.status_check_instance) == 2
    error_message = "Each instance must get one system and one instance status check alarm."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.status_check_system["app"].alarm_name == "test-app-status-check-system"
    error_message = "Alarm name must be <environment_name>-<key>-status-check-system."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.status_check_system["app"].dimensions["InstanceId"] == "i-0123456789abcdef0"
    error_message = "The alarm must target its own instance id."
  }

  assert {
    condition     = contains(aws_cloudwatch_metric_alarm.status_check_system["app"].alarm_actions, "arn:aws:automate:ap-southeast-1:ec2:recover")
    error_message = "The system status check alarm must run ec2:recover in the deploy region."
  }

  assert {
    condition     = contains(aws_cloudwatch_metric_alarm.status_check_system["app"].alarm_actions, aws_sns_topic.alarms.arn)
    error_message = "The system status check alarm must also notify the topic."
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.status_check_instance : !contains(a.alarm_actions, "arn:aws:automate:ap-southeast-1:ec2:recover")])
    error_message = "The instance status check alarm must not run ec2:recover."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.disk_used) == 0
    error_message = "disk_alarm = null must create no disk alarms."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.status_check_system["app"].tags["ManagedBy"] == "terraform" && aws_cloudwatch_metric_alarm.status_check_system["app"].tags["Environment"] == "test"
    error_message = "Alarms must carry the common tags."
  }
}

run "empty_disk_alarm_uses_defaults" {
  command = plan

  variables {
    instances  = { app = { instance_id = "i-0123456789abcdef0" } }
    disk_alarm = {}
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.disk_used["app"].threshold == 80
    error_message = "Default disk threshold must be 80."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.disk_used["app"].namespace == "CWAgent" && aws_cloudwatch_metric_alarm.disk_used["app"].metric_name == "disk_used_percent"
    error_message = "Default disk metric must be CWAgent disk_used_percent."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.disk_used["app"].dimensions == tomap({ InstanceId = "i-0123456789abcdef0" })
    error_message = "With no extra dimensions the disk alarm must use InstanceId only."
  }
}

run "disk_alarm_overrides_and_extra_dimensions" {
  command = plan

  variables {
    instances = { app = { instance_id = "i-0123456789abcdef0" } }
    disk_alarm = {
      namespace   = "Custom/Disk"
      metric_name = "used"
      threshold   = 90
      dimensions  = { path = "/data" }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.disk_used["app"].namespace == "Custom/Disk" && aws_cloudwatch_metric_alarm.disk_used["app"].metric_name == "used" && aws_cloudwatch_metric_alarm.disk_used["app"].threshold == 90
    error_message = "Namespace, metric name and threshold must be overridable."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.disk_used["app"].dimensions == tomap({ InstanceId = "i-0123456789abcdef0", path = "/data" })
    error_message = "Extra dimensions must merge with the per-instance InstanceId."
  }
}

run "backup_age_alarm" {
  command = plan

  variables {
    backup_age_alarm = {
      namespace   = "Custom/Backup"
      metric_name = "BackupAgeSeconds"
      threshold   = 129600
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.backup_age) == 1 && aws_cloudwatch_metric_alarm.backup_age[0].alarm_name == "test-backup-age"
    error_message = "backup_age_alarm must create one alarm named <environment_name>-backup-age."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backup_age[0].treat_missing_data == "breaching"
    error_message = "A silent backup publisher must raise the alarm."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backup_age[0].period == 3600 && aws_cloudwatch_metric_alarm.backup_age[0].threshold == 129600
    error_message = "Default period must be 3600 and the threshold must pass through."
  }
}

run "rejects_no_emails" {
  command = plan

  variables {
    alarm_emails = []
  }

  expect_failures = [var.alarm_emails]
}

run "rejects_malformed_email" {
  command = plan

  variables {
    alarm_emails = ["not-an-email"]
  }

  expect_failures = [var.alarm_emails]
}

run "rejects_bad_instance_key" {
  command = plan

  variables {
    instances = { "Bad_Key" = { instance_id = "i-0123456789abcdef0" } }
  }

  expect_failures = [var.instances]
}

run "rejects_disk_threshold_over_100" {
  command = plan

  variables {
    disk_alarm = { threshold = 101 }
  }

  expect_failures = [var.disk_alarm]
}

run "rejects_disk_instance_id_dimension" {
  command = plan

  variables {
    disk_alarm = { dimensions = { InstanceId = "i-0123456789abcdef0" } }
  }

  expect_failures = [var.disk_alarm]
}
