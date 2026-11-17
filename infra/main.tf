terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

variable "my_ip" {
  description = "My public IP in CIDR form"
  type = string
}

resource "aws_security_group" "echo" {
  name        = "echo-terraform"
  description = "SSH and echo ports from my IP"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "TCP echo"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "UDP echo"
    from_port   = 5001
    to_port     = 5001
    protocol    = "udp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
variable "key_name" {
  description = "Name of an existing EC2 key pair"
  type        = string
  default     = "Key-Pair"
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "echo" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.echo.id]

  user_data = templatefile("${path.module}/userdata.sh.tftpl", {
    tcp_b64 = base64encode(file("${path.module}/../servers/tcp_echo.py"))
    udp_b64 = base64encode(file("${path.module}/../servers/udp_echo.py"))
  })
  user_data_replace_on_change = true

  credit_specification {
    cpu_credits = "standard"
  }

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "echo-terraform"
  }
}

output "public_ip" {
  value = aws_instance.echo.public_ip
}
