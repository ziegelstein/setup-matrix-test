# Output values for the Matrix EKS infrastructure

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}"
}

output "worker_node_role_arn" {
  description = "IAM role ARN for worker nodes"
  value       = module.eks.worker_node_role_arn
}


# SSM Secrets Management Outputs
output "ssm_kms_key_id" {
  description = "KMS key ID used for SSM parameter encryption"
  value       = module.ssm.kms_key_id
}

output "ssm_parameter_path" {
  description = "Base path for SSM parameters"
  value       = "/${var.cluster_name}/${var.environment}/"
}

output "secrets_management_guide" {
  description = "Link to secrets management documentation"
  value       = "See SECRETS_MANAGEMENT.md for detailed information about secrets management"
}
