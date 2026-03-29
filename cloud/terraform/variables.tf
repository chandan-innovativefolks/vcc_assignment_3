variable "aws_region" {
  description = "AWS region to deploy the instance"
  type        = string
  default     = "us-east-1"
}

variable "instance_name" {
  description = "Name tag for the auto-scaled EC2 instance"
  type        = string
  default     = "vcc-scaled-instance"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.medium"
}

variable "key_pair_name" {
  description = "Name of an existing AWS EC2 key pair for SSH access"
  type        = string
}
