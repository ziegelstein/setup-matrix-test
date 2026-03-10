output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS cluster API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64 encoded certificate data for cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.cluster.id
}

output "worker_security_group_id" {
  description = "Security group ID attached to worker nodes"
  value       = aws_security_group.worker.id
}

output "worker_node_role_arn" {
  description = "IAM role ARN for worker nodes"
  value       = aws_iam_role.worker.arn
}
