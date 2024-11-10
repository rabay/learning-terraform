data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami_filter.name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.ami_filter.owner] # Bitnami
}

module "web_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.environment.name
  cidr = "${var.environment.network_prefix}.0.0/16"

  azs            = ["sa-east-1a", "sa-east-1b", "sa-east-1c"]
  public_subnets = ["${var.environment.network_prefix}.101.0/24", "${var.environment.network_prefix}.102.0/24", "${var.environment.network_prefix}.103.0/24"]

  tags = {
    Terraform   = "true"
    Environment = var.environment.name
  }
}

module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "8.0.0"
  
  name                = "${var.environment.name}-web-asg"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = 1
  health_check_type   = "EC2"
  vpc_zone_identifier = module.web_vpc.public_subnets

  image_id      = data.aws_ami.app_ami.id
  instance_type = var.instance_type

  security_groups = [module.web_sg.security_group_id]
}


module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "8.0.0"

  name               = "${var.environment.name}-web-alb"
  load_balancer_type = "application"
  vpc_id             = module.web_vpc.vpc_id
  subnets            = module.web_vpc.public_subnets
  security_groups    = [module.web_sg.security_group_id]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  target_groups = [
    {
      name_prefix        = "${var.environment.name}-tg"
      backend_protocol   = "HTTP"
      backend_port       = 80
      target_type        = "instance"
      health_check_path  = "/"
      health_check_port  = "traffic-port"
      health_check_protocol = "HTTP"
    }
  ]

  tags = {
    Environment = var.environment.name
    Project     = "Web"
  }
}

resource "aws_autoscaling_attachment" "web_tg_attachment" {
  autoscaling_group_name = module.autoscaling.autoscaling_group_id
  lb_target_group_arn    = module.alb.target_group_arns[0]
}

module "web_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.2.0"
  name    = "${var.environment.name}-web-sg"

  vpc_id              = module.web_vpc.vpc_id
  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules        = ["all-all"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
}
