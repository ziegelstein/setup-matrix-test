# EKS Module - Kubernetes cluster with self-managed worker nodes
# Deviation: Using self-managed nodes instead of managed node groups for explicit control
# This allows us to specify exactly 2 instances as requested

# EKS Cluster IAM Role
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

# Attach required policies to cluster role
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# Security group for EKS cluster
resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = "1.34" # Best Practice: Use recent stable version

  vpc_config {
    subnet_ids              = concat(var.private_subnets, var.public_subnets)
    endpoint_private_access = true
    endpoint_public_access  = true # Deviation: Enable for easier management; restrict in production
    security_group_ids      = [aws_security_group.cluster.id]
  }

  # Best Practice: Enable control plane logging for audit and troubleshooting
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_policy,
  ]
}

# IAM Role for Worker Nodes
resource "aws_iam_role" "worker" {
  name = "${var.cluster_name}-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach required policies to worker role
resource "aws_iam_role_policy_attachment" "worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "worker_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "worker_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.worker.name
}

# Attach SSM read policy for secrets management
resource "aws_iam_role_policy_attachment" "worker_ssm_policy" {
  count      = var.enable_ssm_policy ? 1 : 0
  policy_arn = var.ssm_policy_arn
  role       = aws_iam_role.worker.name
}

# IAM Instance Profile for Worker Nodes
resource "aws_iam_instance_profile" "worker" {
  name = "${var.cluster_name}-worker-profile"
  role = aws_iam_role.worker.name
}

# Security Group for Worker Nodes
resource "aws_security_group" "worker" {
  name_prefix = "${var.cluster_name}-worker-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name                                        = "${var.cluster_name}-worker-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Allow worker nodes to communicate with cluster API
resource "aws_security_group_rule" "worker_to_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.worker.id
  description              = "Allow worker nodes to communicate with cluster API"
}

# Allow cluster to communicate with worker nodes
resource "aws_security_group_rule" "cluster_to_worker" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.cluster.id
  description              = "Allow cluster to communicate with worker nodes"
}

# Allow worker nodes to communicate with each other
resource "aws_security_group_rule" "worker_to_worker" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  security_group_id = aws_security_group.worker.id
  self              = true
  description       = "Allow worker nodes to communicate with each other"
}

# Get latest EKS-optimized AMI (AL2023 for EKS 1.30+)
data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/${aws_eks_cluster.main.version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
}

# User data script to bootstrap worker nodes
# AL2023 uses nodeadm instead of bootstrap.sh
locals {
  userdata = <<-EOT
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/node.eks.aws

---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: ${var.cluster_name}
    apiServerEndpoint: ${aws_eks_cluster.main.endpoint}
    certificateAuthority: ${aws_eks_cluster.main.certificate_authority[0].data}
    cidr: ${aws_eks_cluster.main.kubernetes_network_config[0].service_ipv4_cidr}

--BOUNDARY--
  EOT
}

# Launch Template for Worker Nodes
resource "aws_launch_template" "worker" {
  name_prefix   = "${var.cluster_name}-worker-"
  image_id      = data.aws_ssm_parameter.eks_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.worker.name
  }

  vpc_security_group_ids = [aws_security_group.worker.id]

  user_data = base64encode(local.userdata)

  # Best Practice: Enable detailed monitoring for better observability
  monitoring {
    enabled = true
  }

  # Best Practice: Use encrypted EBS volumes
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20 # GB - sufficient for system + container images
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name                                        = "${var.cluster_name}-worker"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Best Practice: Require IMDSv2
    http_put_response_hop_limit = 1
  }
}

# Auto Scaling Group for Worker Nodes
resource "aws_autoscaling_group" "worker" {
  name                = "${var.cluster_name}-worker-asg"
  vpc_zone_identifier = var.private_subnets
  desired_capacity    = var.desired_size
  min_size            = var.min_size
  max_size            = var.max_size

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  # Best Practice: Use health checks to replace unhealthy instances
  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  depends_on = [
    aws_eks_cluster.main
  ]
}
