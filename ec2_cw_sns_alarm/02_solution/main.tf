
locals {
  instance_id             = data.terraform_remote_state.example.outputs.instance_id
  cloudwatch_metric_alarm = data.terraform_remote_state.example.outputs.cloudwatch_metric_alarm
}

data "aws_instance" "example" {
  instance_id = local.instance_id
}

output "name" {
  value = local.cloudwatch_metric_alarm.dimensions.InstanceId
}
resource "aws_cloudwatch_metric_alarm" "example" {
  alarm_name          = local.cloudwatch_metric_alarm.alarm_name
  comparison_operator = local.cloudwatch_metric_alarm.comparison_operator
  evaluation_periods  = local.cloudwatch_metric_alarm.evaluation_periods
  metric_name         = local.cloudwatch_metric_alarm.metric_name
  namespace           = local.cloudwatch_metric_alarm.namespace
  period              = local.cloudwatch_metric_alarm.period
  statistic           = local.cloudwatch_metric_alarm.statistic
  threshold           = local.cloudwatch_metric_alarm.threshold
  alarm_description   = local.cloudwatch_metric_alarm.alarm_description
  
  dimensions          = {
    InstanceId = local.cloudwatch_metric_alarm.dimensions["InstanceId"]
  }

  # disable the alarm
  alarm_actions = []
}
