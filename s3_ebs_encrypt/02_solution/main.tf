
locals {
  instance_id     = data.terraform_remote_state.example.outputs.instance_id
  suffix          = data.terraform_remote_state.example.outputs.suffix
}

data "aws_ebs_volume" "unencrypted" {
  most_recent = true

  filter {
    name   = "volume-type"
    values = ["gp2"]
  }

  filter {
    name   = "tag:Name"
    values = ["sdh-${local.suffix}"]
  }
}

data "aws_instance" "example" {
  instance_id = local.instance_id
}

resource "aws_ebs_snapshot" "unencrypted" {
  volume_id = data.aws_ebs_volume.unencrypted.id

  tags = {
    Name = "sdh-unencrypted-${local.suffix}"
  }
}

resource "aws_ebs_volume" "encrypted" {
  availability_zone = data.aws_instance.example.availability_zone
  size              = aws_ebs_snapshot.unencrypted.volume_size
  snapshot_id       = aws_ebs_snapshot.unencrypted.id
  encrypted         = true

  tags = {
    Name = "sdh-encrypted-${local.suffix}"
  }

  depends_on = [
    aws_ebs_snapshot.unencrypted
  ]
}

resource "null_resource" "detach_volume" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = <<-EOT
      unset AWS_VAULT
      if [ "${length(data.aws_ebs_volume.unencrypted.id)}" -gt "0" ]; then
        state=$(aws-vault exec dev -- aws ec2 describe-volumes --region ${data.aws_region.current.name} --volume-ids ${data.aws_ebs_volume.unencrypted.id} | jq -r '.Volumes[].State')

        if [ "$state" = "in-use" ]; then
          aws-vault exec dev -- aws ec2 detach-volume --region ${data.aws_region.current.name} --volume-id ${data.aws_ebs_volume.unencrypted.id} --force
          sleep 30
        else
          echo "${data.aws_ebs_volume.unencrypted.id} volume is not in 'in-use' state, skipping detach operation."
        fi
      else
        echo "${data.aws_ebs_volume.unencrypted.id} volume does not exist, skipping detach operation."
      fi
    EOT
  }

  depends_on = [
    aws_ebs_volume.encrypted
  ]
}

resource "aws_volume_attachment" "encrypted_attach" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.encrypted.id
  instance_id = data.aws_instance.example.instance_id
  
  depends_on = [
    null_resource.detach_volume
  ]
}
