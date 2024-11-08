data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["979382823631"] # Bitnami
}

# data "aws_vpc" "default" {
#   default = true
# }

module "web_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs            = ["sa-east-1a", "sa-east-1b", "sa-east-1c"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "8.0.0"
  name    = "web"

  min_size            = 1
  max_size            = 2
  desired_capacity    = 1
  health_check_type   = "EC2"
  vpc_zone_identifier = module.web_vpc.public_subnets

  # create_iam_instance_profile = false
  # launch_template_name        = "web-asg"
  # launch_template_description = "Launch template for web"
  image_id      = data.aws_ami.app_ami.id
  instance_type = var.instance_type


  security_groups = [module.web_sg.security_group_id]
}

# Create a new ALB Target Group attachment
resource "aws_autoscaling_attachment" "web-aat" {
  autoscaling_group_name = module.alb.target_groups.ex-instance.name
  lb_target_group_arn    = module.alb.target_groups.ex-instance.arn
}

module "alb" {
  source = "terraform-aws-modules/alb/aws"

  name            = "web-alb"
  vpc_id          = module.web_vpc.vpc_id
  subnets         = module.web_vpc.public_subnets
  security_groups = module.web_sg.security_group_id

  listeners = {
    ex-http-https-redirect = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "ex-instance"
      }
    }
  }

  target_groups = {
    ex-instance = {
      name        = "web-instances"
      name_prefix = "web"
      protocol    = "HTTP"
      port        = 80
      target_type = "instance"
      target_id   = aws_instance.web.id
    }
  }

  tags = {
    Environment = "Development"
    Project     = "Web"
  }
}

module "web_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.2.0"
  name    = "web"

  vpc_id              = module.web_vpc.vpc_id
  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules        = ["all-all"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
}
