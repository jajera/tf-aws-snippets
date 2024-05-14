# Configure Cloudwatch permission

userdata log file: /var/log/cloud-init-output.log

# list ec2 instances

aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`].Value[]]'

# terminate ec2 instance

aws ec2 stop-instances --instance-ids i-0474b5c4d7d9b3cc7
