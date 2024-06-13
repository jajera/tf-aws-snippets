
# resource "aws_instance" "example" {
#   ami                         = data.aws_ami.amzn2_ecs.id
#   associate_public_ip_address = false
#   instance_type               = "t3.micro"
#   subnet_id                   = aws_subnet.private.id

#   vpc_security_group_ids = [
#     aws_security_group.example.id
#   ]
# }

# resource "aws_ec2_instance_connect_endpoint" "example" {
#   subnet_id = aws_subnet.public.id
# }