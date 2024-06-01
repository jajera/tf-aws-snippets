
variable "environment_name" {
  type    = string
  default = "test"
}

variable "domain" {
  type    = string
  default = "randomtestdomain.co.nz"
}

# variable "s3_bucket_prefix" {
#   type    = string
#   default = "examplebucket"
# }

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "s3-pre-signed-url-${random_string.suffix.result}"
  }
}

resource "aws_s3_bucket" "example" {
  bucket        = "s3-pre-signed-url-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_flow_log" "example" {
  log_destination      = aws_s3_bucket.example.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.example.id

  tags = {
    Name = "s3-pre-signed-url-${random_string.suffix.result}"
  }
}

resource "aws_default_security_group" "example" {
  vpc_id = aws_vpc.example.id
}

resource "aws_subnet" "private1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${data.aws_region.current.name}a"
  map_public_ip_on_launch = false

  tags = {
    Name = "private1"
  }
}

resource "aws_subnet" "private2" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${data.aws_region.current.name}b"
  map_public_ip_on_launch = false

  tags = {
    Name = "private2"
  }
}

# resource "aws_internet_gateway" "example" {
#   vpc_id = aws_vpc.example.id

#   tags = {
#     Name = "apg-test-igw"
#   }
# }

resource "aws_route_table" "private1" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "private1"
  }
}

resource "aws_route_table" "private2" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "private2"
  }
}

resource "aws_route_table_association" "private1" {
  route_table_id = aws_route_table.private1.id
  subnet_id      = aws_subnet.private1.id
}

resource "aws_route_table_association" "private2" {
  route_table_id = aws_route_table.private2.id
  subnet_id      = aws_subnet.private2.id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  bucket = aws_s3_bucket.example.id

  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket                  = aws_s3_bucket.example.id
  block_public_acls       = "true"
  ignore_public_acls      = "true"
  block_public_policy     = "true"
  restrict_public_buckets = "true"
}

resource "aws_s3_bucket_logging" "example" {
  bucket        = aws_s3_bucket.example.id
  target_bucket = aws_s3_bucket.example.id
  target_prefix = "s3_log/"
}

resource "aws_s3_bucket_versioning" "example" {
  bucket = aws_s3_bucket.example.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_elb_service_account" "example" {
  region = data.aws_region.current.name
}

resource "aws_s3_bucket_policy" "example" {
  bucket = aws_s3_bucket.example.bucket

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "arn:aws:iam::${data.aws_elb_service_account.example.id}:root"
        },
        "Action" : "s3:PutObject",
        "Resource" : "${aws_s3_bucket.example.arn}/lb-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      }
    ]
  })
}

resource "aws_globalaccelerator_accelerator" "example" {
  name            = "s3-pre-signed-url-${random_string.suffix.result}"
  ip_address_type = "IPV4"

  attributes {
    flow_logs_enabled   = true
    flow_logs_s3_bucket = aws_s3_bucket.example.bucket
    flow_logs_s3_prefix = "global_accelerator/"
  }
}

resource "aws_security_group" "alb_to_api_endpoint" {
  name   = "s3-pre-signed-url-${random_string.suffix.result}-alb-api"
  vpc_id = aws_vpc.example.id

  ingress {
    description = "Inbound from GA"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ingress {
  #   from_port   = 80
  #   to_port     = 80
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  egress {
    description = "Outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "s3-pre-signed-url-${random_string.suffix.result}-alb-api"
  }
}

resource "aws_security_group" "vpc_endpoint" {
  name   = "s3-pre-signed-url-${random_string.suffix.result}-api-endpoint"
  vpc_id = aws_vpc.example.id

  ingress {
    description = "Inbound from ALB"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"

    security_groups = [
      aws_security_group.alb_to_api_endpoint.id
    ]
  }

  ingress {
    description = "Inbound from ALB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"

    security_groups = [
      aws_security_group.alb_to_api_endpoint.id
    ]
  }

  egress {
    description = "Outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "s3-pre-signed-url-${random_string.suffix.result}-api-endpoint"
  }
}

resource "aws_vpc_endpoint" "api_endpoint" {
  vpc_id            = aws_vpc.example.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.execute-api"
  vpc_endpoint_type = "Interface"

  subnet_ids = [
    aws_subnet.private1.id,
    aws_subnet.private2.id
  ]

  security_group_ids = [
    aws_security_group.vpc_endpoint.id
  ]

  private_dns_enabled = false

  tags = {
    Name = "s3-pre-signed-url-${random_string.suffix.result}-api-endpoint"
  }
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id            = aws_vpc.example.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Interface"

  subnet_ids = [
    aws_subnet.private1.id,
    aws_subnet.private2.id
  ]

  security_group_ids = [
    aws_security_group.vpc_endpoint.id
  ]

  private_dns_enabled = false

  tags = {
    Name = "s3-pre-signed-url-${random_string.suffix.result}-s3-endpoint"
  }
}

resource "aws_lb" "alb_to_api_endpoint" {
  name               = "${random_string.suffix.result}-alb-api"
  ip_address_type    = "ipv4"
  load_balancer_type = "application"
  internal           = true

  security_groups = [
    aws_security_group.alb_to_api_endpoint.id
  ]

  subnets = [
    aws_subnet.private1.id,
    aws_subnet.private2.id
  ]

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  access_logs {
    bucket  = aws_s3_bucket.example.bucket
    prefix  = "lb-logs"
    enabled = true
  }
}

resource "aws_lb_target_group" "api_endpoint" {
  target_type      = "ip"
  name             = "${random_string.suffix.result}-api-endpoint"
  port             = "443"
  protocol         = "HTTPS"
  protocol_version = "HTTP1"
  vpc_id           = aws_vpc.example.id

  health_check {
    enabled             = "true"
    healthy_threshold   = "5"
    interval            = "30"
    matcher             = "200,403"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTPS"
    timeout             = "5"
    unhealthy_threshold = "2"
  }
}

resource "aws_lb_target_group" "s3_endpoint" {
  target_type      = "ip"
  name             = "${random_string.suffix.result}-s3-endpoint"
  port             = "80"
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  vpc_id           = aws_vpc.example.id

  health_check {
    enabled             = "true"
    healthy_threshold   = "5"
    interval            = "30"
    matcher             = "200,307,405"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = "5"
    unhealthy_threshold = "2"
  }
}

resource "aws_lb_listener" "alb_to_api_endpoint_80" {
  default_action {
    order = "1"

    redirect {
      host        = "#{host}"
      path        = "/#{path}"
      port        = "443"
      protocol    = "HTTPS"
      query       = "#{query}"
      status_code = "HTTP_301"
    }

    type = "redirect"
  }

  load_balancer_arn = aws_lb.alb_to_api_endpoint.arn
  port              = "80"
  protocol          = "HTTP"
}

resource "aws_route53_zone" "example" {
  name = var.domain

  # vpc {
  #   vpc_id = aws_vpc.example.id
  # }
}

resource "aws_acm_certificate" "example" {
  domain_name       = aws_route53_zone.example.name
  validation_method = "EMAIL"
  # subject_alternative_names = [
  #   ""
  # ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "s3-pre-signed-url-${random_string.suffix.result}"
  }
}

resource "aws_route53_record" "example" {
  for_each = {
    for dvo in aws_acm_certificate.example.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.example.zone_id
}

resource "aws_acm_certificate_validation" "example" {
  certificate_arn         = aws_acm_certificate.example.arn
  # validation_record_fqdns = [for record in aws_route53_record.example : record.fqdn]
}

# resource "null_resource" "wait_30_seconds" {
#   provisioner "local-exec" {
#     command = "sleep 30"
#   }

#   # The delay is triggered before creating the Route 53 record
#   triggers = {
#     before = "${aws_acm_certificate_validation.example.id}"
#   }
# }

# resource "aws_lb_listener" "alb_to_api_endpoint_443" {
#   certificate_arn = aws_acm_certificate.example.arn

#   default_action {
#     type = "fixed-response"

#     fixed_response {
#       content_type = "text/plain"
#       message_body = "Nothing to see here"
#       status_code  = "404"
#     }
#   }

#   load_balancer_arn = aws_lb.alb_to_api_endpoint.arn
#   port              = "443"
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
# }

# resource "aws_lb_listener_rule" "api_endpoint_listener_443" {
#   listener_arn = aws_lb_listener.alb_to_api_endpoint_443.arn
#   priority     = 1

#   action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.api_endpoint.arn
#   }

#   condition {
#     path_pattern {
#       values = ["/presign/*"]
#     }
#   }
# }

# resource "aws_lb_listener_rule" "s3_endpoint_listener_443" {
#   listener_arn = aws_lb_listener.alb_to_api_endpoint_443.arn
#   priority     = 2

#   action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.s3_endpoint.arn
#   }

#   condition {
#     path_pattern {
#       values = ["/objects/*"]
#     }
#   }
# }

# # output "vpc_id" {
# #   value = aws_vpc.example.id
# # }

# output "s3_pre_signed_url" {
#   value = {
#     global_accelerator_ips = tolist(aws_globalaccelerator_accelerator.example.ip_sets)[0].ip_addresses
#   }
# }
