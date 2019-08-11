resource "random_id" "cluster_name" {
  count       = var.enable_amazon ? 1 : 0
  byte_length = 6
}

## Get your workstation external IPv4 address:
data "http" "workstation-external-ip" {
  count = var.enable_amazon ? 1 : 0
  url   = "http://ipv4.icanhazip.com"
}

locals {
  workstation-external-cidr = "${chomp(data.http.workstation-external-ip.0.body)}/32"
}

data "aws_availability_zones" "available" {
  count = var.enable_amazon ? 1 : 0
}

data "aws_region" "current" {
  count = var.enable_amazon ? 1 : 0
}

data "aws_ami" "eks-worker" {
  count = var.enable_amazon ? 1 : 0
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.cluster.0.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}


# VPC
resource "aws_vpc" "main" {
  count      = var.enable_amazon ? 1 : 0
  cidr_block = var.aws_cidr_block

  tags = map(
    "Project", "eks",
    "ManagedBy", "terraform",
    "kubernetes.io/cluster/${var.aws_cluster_name}-${random_id.cluster_name[count.index].hex}", "shared",
  )
}

resource "aws_subnet" "public" {
  count = var.enable_amazon ? var.aws_subnets : 0

  availability_zone = data.aws_availability_zones.available.0.names[count.index]
  cidr_block        = cidrsubnet(var.aws_cidr_block, 8, count.index)
  vpc_id            = aws_vpc.main.0.id

  tags = map(
    "Project", "k8s",
    "ManagedBy", "terraform",
    "kubernetes.io/cluster/${var.aws_cluster_name}-${random_id.cluster_name.0.hex}", "shared"
  )
}

resource "aws_internet_gateway" "igw" {
  count = var.enable_amazon ? 1 : 0

  vpc_id = aws_vpc.main.0.id

  tags = {
    Project   = "k8s",
    ManagedBy = "terraform"
  }
}

resource "aws_route_table" "rt" {
  count = var.enable_amazon ? 1 : 0

  vpc_id = aws_vpc.main.0.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.0.id
  }

  tags = {
    Project   = "k8s",
    ManagedBy = "terraform"
  }
}

resource "aws_route_table_association" "rtassoc" {
  count = var.enable_amazon ? var.aws_subnets : 0

  subnet_id      = aws_subnet.public.*.id[count.index]
  route_table_id = aws_route_table.rt.0.id
}


# Master IAM
resource "aws_iam_role" "cluster" {
  count = var.enable_amazon ? 1 : 0
  name  = var.aws_cluster_name

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY

  tags = {
    Project   = "k8s",
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "cluster-AmazonEKSClusterPolicy" {
  count = var.enable_amazon ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.0.name
}

resource "aws_iam_role_policy_attachment" "cluster-AmazonEKSServicePolicy" {
  count = var.enable_amazon ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.cluster.0.name
}


# Master Security Group
resource "aws_security_group" "cluster" {
  count = var.enable_amazon ? 1 : 0

  name        = var.aws_cluster_name
  description = "Cluster communication with worker nodes"
  vpc_id      = aws_vpc.main.0.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project   = "k8s",
    ManagedBy = "terraform"
  }
}

# OPTIONAL: Allow inbound traffic from your local workstation external IP
#           to the Kubernetes. See data section at the beginning of the
#           AWS section.
resource "aws_security_group_rule" "cluster-ingress-workstation-https" {
  count = var.enable_amazon ? 1 : 0

  cidr_blocks       = [local.workstation-external-cidr]
  description       = "Allow workstation to communicate with the cluster API Server"
  from_port         = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.cluster.0.id
  to_port           = 443
  type              = "ingress"
}


# EKS Master
resource "aws_eks_cluster" "cluster" {
  count = var.enable_amazon ? 1 : 0

  name     = "${var.aws_cluster_name}-${random_id.cluster_name[count.index].hex}"
  role_arn = aws_iam_role.cluster.0.arn
  #version = var.aws_eks_version

  vpc_config {
    security_group_ids = [aws_security_group.cluster.0.id]
    subnet_ids         = flatten([aws_subnet.public[*].id])
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster-AmazonEKSServicePolicy,
  ]
}


# EKS Worker IAM
resource "aws_iam_role" "node" {
  count = var.enable_amazon ? 1 : 0

  name = "${var.aws_cluster_name}-node"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
  tags = {
    Project   = "k8s",
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "node-AmazonEKSWorkerNodePolicy" {
  count      = var.enable_amazon ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.0.name
}

resource "aws_iam_role_policy_attachment" "node-AmazonEKS_CNI_Policy" {
  count      = var.enable_amazon ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.0.name
}

resource "aws_iam_role_policy_attachment" "node-AmazonEC2ContainerRegistryReadOnly" {
  count      = var.enable_amazon ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.0.name
}

resource "aws_iam_instance_profile" "node" {
  count = var.enable_amazon ? 1 : 0
  name  = var.aws_cluster_name
  role  = aws_iam_role.node.0.name
}


# EKS Worker Security Groups
resource "aws_security_group" "node" {
  count       = var.enable_amazon ? 1 : 0
  name        = "${var.aws_cluster_name}-node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = aws_vpc.main.0.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = map(
    "Project", "k8s",
    "ManagedBy", "terraform",
    "kubernetes.io/cluster/${var.aws_cluster_name}-${random_id.cluster_name[count.index].hex}", "owned",
  )
}

resource "aws_security_group_rule" "demo-node-ingress-self" {
  count                    = var.enable_amazon ? 1 : 0
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.node.0.id
  source_security_group_id = aws_security_group.node.0.id
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "demo-node-ingress-cluster" {
  count                    = var.enable_amazon ? 1 : 0
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.0.id
  source_security_group_id = aws_security_group.cluster.0.id
  to_port                  = 65535
  type                     = "ingress"
}


# EKS Master <--> Worker Security Group
resource "aws_security_group_rule" "cluster-ingress-node-https" {
  count                    = var.enable_amazon ? 1 : 0
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.0.id
  source_security_group_id = aws_security_group.node.0.id
  to_port                  = 443
  type                     = "ingress"
}


# EKS Worker Nodes AutoScalingGroup

# EKS currently documents this required userdata for EKS worker nodes to
# properly configure Kubernetes applications on the EC2 instance.
# We implement a Terraform local here to simplify Base64 encoding this
# information into the AutoScaling Launch Configuration.
# More information: https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html
locals {
  demo-node-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.cluster.0.endpoint}' --b64-cluster-ca '${aws_eks_cluster.cluster.0.certificate_authority.0.data}' '${var.aws_cluster_name}-${random_id.cluster_name.0.hex}'
USERDATA
}

resource "aws_launch_configuration" "lc" {
  count                       = var.enable_amazon ? 1 : 0
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.node.0.name
  image_id                    = data.aws_ami.eks-worker.0.id
  instance_type               = var.aws_instance_type
  name_prefix                 = var.aws_cluster_name
  security_groups             = [aws_security_group.node[0].id]
  user_data_base64            = base64encode(local.demo-node-userdata)
}

resource "aws_autoscaling_group" "asg" {
  count                = var.enable_amazon ? 1 : 0
  desired_capacity     = var.eks_nodes
  launch_configuration = aws_launch_configuration.lc.0.id
  max_size             = var.eks_max_nodes
  min_size             = var.eks_min_nodes
  name                 = var.aws_cluster_name
  vpc_zone_identifier  = aws_subnet.public.*.id

  tag {
    key                 = "Name"
    value               = var.aws_cluster_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "k8s"
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "terraform"
    propagate_at_launch = true
  }
  tag {
    key                 = "kubernetes.io/cluster/${var.aws_cluster_name}-${random_id.cluster_name[count.index].hex}"
    value               = "owned"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}


# EKS Join Worker Nodes
# EKS kubeconf
locals {
  config_map_aws_auth = <<CONFIGMAPAWSAUTH
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.node.0.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
CONFIGMAPAWSAUTH

  kubeconfig = <<KUBECONFIG
apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.cluster.0.endpoint}
    certificate-authority-data: ${aws_eks_cluster.cluster.0.certificate_authority.0.data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - "token"
        - "-i"
        - "${var.aws_cluster_name}-${random_id.cluster_name.0.hex}"
KUBECONFIG
}

resource "local_file" "kubeconfigaws" {
  count    = var.enable_amazon ? 1 : 0
  content  = local.kubeconfig
  filename = "${path.module}/kubeconfig_aws"

  depends_on = [aws_eks_cluster.cluster]
}

resource "local_file" "eks_config_map_aws_auth" {
  count    = var.enable_amazon ? 1 : 0
  content  = local.config_map_aws_auth
  filename = "${path.module}/aws_config_map_aws_auth"

  depends_on = [local_file.kubeconfigaws]
}

resource "null_resource" "aws_iam_authenticator" {
  count = var.enable_amazon ? 1 : 0
  provisioner "local-exec" {
    command = <<EOF
if [ \"$(uname)\" == \"Darwin\" ]; \
  then curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.13.7/2019-06-11/bin/darwin/amd64/aws-iam-authenticator; \
elif [ \"$(expr substr $(uname -s) 1 5)\" == \"Linux\" ]; \
  then curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.12.7/2019-03-27/bin/linux/amd64/aws-iam-authenticator; \
fi; \
chmod +x ./aws-iam-authenticator; \
mkdir -p $HOME/bin && \
cp ./aws-iam-authenticator $HOME/bin/aws-iam-authenticator && \
export PATH=$HOME/bin:$PATH
EOF
  }

  depends_on = [local_file.eks_config_map_aws_auth]
}

resource "null_resource" "apply_kube_configmap" {
  count = var.enable_amazon ? 1 : 0
  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/aws_config_map_aws_auth"
    environment = {
      KUBECONFIG = "${path.module}/kubeconfig_aws"
    }
  }

  depends_on = [null_resource.aws_iam_authenticator]
}
