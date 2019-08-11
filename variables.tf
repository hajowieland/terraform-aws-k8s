variable "enable_amazon" {
  description = "Enable / Disable Amazon Web Services k8s (e.g. `true`)"
  type        = bool
  default     = true
}

variable "random_cluster_suffix" {
  description = "Random 6 byte hex suffix for cluster name"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region (e.g. `eu-central-1` => Frankfurt)"
  type        = string
  default     = "eu-central-1"
}

variable "aws_profile" {
  description = "AWS cli profile (e.g. `default`)"
  type        = string
  default     = "default"
}

variable "eks_nodes" {
  description = "EKS Kubernetes worker nodes, desired ASG capacity (e.g. `2`)"
  default     = 2
  type        = number
}

variable "eks_min_nodes" {
  description = "EKS Kubernetes worker nodes, minimal ASG capacity (e.g. `1`)"
  default     = 1
  type        = number
}

variable "eks_max_nodes" {
  description = "EKS Kubernetes worker nodes, maximal ASG capacity (e.g. `3`)"
  default     = 3
  type        = number
}

variable "aws_cidr_block" {
  description = "AWS VPC CIDR block (e.g. `10.0.23.0/16`)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aws_subnets" {
  description = "List of 8-bit numbers of subnets base_cidr_block"
  type        = number
  default     = 2
}

variable "aws_cluster_name" {
  description = "AWS ELS cluster name (e.g. `k8s-eks`)"
  type        = string
  default     = "k8s-eks"
}

variable "aws_instance_type" {
  description = "AWS EC2 Instance Type (e.g. `t3.medium`)"
  type        = string
  default     = "t3.medium"
}

# variable "aws_eks_version" {
#   description = "AWS EKS cluster version (e.g. `1.13`)"
#   type = string
#   default = "1.13"
# }

