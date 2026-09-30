# Plan-only, mocked provider: no credentials, no cloud calls. Covers the opt-in contract - a volume
# without `snapshot` must plan exactly as before, so dev and other consumers see no change.
mock_provider "aws" {}

variables {
  global = {
    environment_name = "test"
    deploy_region    = "ap-southeast-1"
    tags             = {}
  }
}

run "no_snapshot_creates_no_backup_resources" {
  command = plan

  variables {
    volumes = {
      data = { availability_zone = "ap-southeast-1a" }
    }
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.this) == 0
    error_message = "A volume without snapshot must not create a DLM policy."
  }

  assert {
    condition     = length(aws_iam_role.dlm) == 0 && length(aws_iam_role_policy_attachment.dlm) == 0
    error_message = "A volume without snapshot must not create the DLM role or its attachment."
  }

  assert {
    condition     = !contains(keys(aws_ebs_volume.this["data"].tags), "Backup")
    error_message = "A volume without snapshot must not carry the Backup tag."
  }
}

run "empty_snapshot_uses_defaults" {
  command = plan

  variables {
    volumes = {
      data = {
        availability_zone = "ap-southeast-1a"
        snapshot          = {}
      }
    }
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.this) == 1
    error_message = "snapshot = {} must create exactly one DLM policy."
  }

  assert {
    condition     = one(aws_dlm_lifecycle_policy.this["data"].policy_details[0].schedule[0].retain_rule).count == 7
    error_message = "Default retention must be 7 snapshots."
  }

  assert {
    condition     = one(aws_dlm_lifecycle_policy.this["data"].policy_details[0].schedule[0].create_rule).times == tolist(["18:00"])
    error_message = "Default snapshot time must be 18:00 UTC."
  }

  assert {
    condition     = aws_dlm_lifecycle_policy.this["data"].policy_details[0].target_tags == tomap({ Backup = "test-data" })
    error_message = "The policy must target the Backup tag, not Name."
  }

  assert {
    condition     = aws_dlm_lifecycle_policy.this["data"].policy_details[0].schedule[0].copy_tags == true
    error_message = "Snapshots must inherit the Backup tag so they can be listed by it."
  }

  assert {
    condition     = aws_ebs_volume.this["data"].tags["Backup"] == "test-data"
    error_message = "The volume must carry Backup = <env>-<key>."
  }

  assert {
    condition     = aws_iam_role.dlm[0].name == "test-ebs-volume-dlm"
    error_message = "The DLM role name must start with the environment name and a dash."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.dlm[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
    error_message = "The DLM role must use the AWS-managed service role policy."
  }
}

run "snapshot_overrides_apply_per_volume" {
  command = plan

  variables {
    volumes = {
      data = {
        availability_zone = "ap-southeast-1a"
        snapshot          = { times = ["03:30"], retain_count = 14 }
      }
      scratch = { availability_zone = "ap-southeast-1a" }
    }
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.this) == 1 && length(aws_iam_role.dlm) == 1
    error_message = "Only the volume with snapshot gets a policy, and the role is shared."
  }

  assert {
    condition     = one(aws_dlm_lifecycle_policy.this["data"].policy_details[0].schedule[0].retain_rule).count == 14
    error_message = "retain_count must pass through to the retain rule."
  }

  assert {
    condition     = !contains(keys(aws_ebs_volume.this["scratch"].tags), "Backup")
    error_message = "A sibling volume without snapshot must stay untagged."
  }
}

run "rejects_two_snapshot_times" {
  command = plan

  variables {
    volumes = {
      data = {
        availability_zone = "ap-southeast-1a"
        snapshot          = { times = ["01:00", "13:00"] }
      }
    }
  }

  expect_failures = [var.volumes]
}

run "rejects_malformed_snapshot_time" {
  command = plan

  variables {
    volumes = {
      data = {
        availability_zone = "ap-southeast-1a"
        snapshot          = { times = ["25:99"] }
      }
    }
  }

  expect_failures = [var.volumes]
}

run "rejects_zero_retention" {
  command = plan

  variables {
    volumes = {
      data = {
        availability_zone = "ap-southeast-1a"
        snapshot          = { retain_count = 0 }
      }
    }
  }

  expect_failures = [var.volumes]
}
