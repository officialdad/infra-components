output "topic_arn" {
  description = "ARN of the SNS topic every alarm notifies. Other alarms or event rules in the environment can publish to it."
  value       = aws_sns_topic.alarms.arn
}

output "alarm_names" {
  description = "Alarm names by kind: status_check_system, status_check_instance and disk_used are keyed by instances-map key; backup_age is the single alarm name, or null when backup_age_alarm is unset."
  value = {
    status_check_system   = { for k, a in aws_cloudwatch_metric_alarm.status_check_system : k => a.alarm_name }
    status_check_instance = { for k, a in aws_cloudwatch_metric_alarm.status_check_instance : k => a.alarm_name }
    disk_used             = { for k, a in aws_cloudwatch_metric_alarm.disk_used : k => a.alarm_name }
    backup_age            = one(aws_cloudwatch_metric_alarm.backup_age[*].alarm_name)
  }
}
