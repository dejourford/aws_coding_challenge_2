variable "project_name" {
  type = string
  default = "aws_coding_challenge_2"
}

variable "environment" {
  type = string
  default = "dev"
}

variable "region" {
  type = string
  default = "us-east-2"
}

variable "vpc_cidr" {
  type = string
  default = "10.0.0.0/16"
}

variable "instance_type" {
  type = string
  default = "t3.small"
}

variable "key_name" {
  type    = string
  default = "1PU"
}
