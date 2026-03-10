output "namespace" {
  description = "Kubernetes namespace where Matrix is deployed"
  value       = kubernetes_namespace.matrix.metadata[0].name
}

output "synapse_service_name" {
  description = "Name of the Synapse service"
  value       = kubernetes_service.synapse.metadata[0].name
}

output "element_service_name" {
  description = "Name of the Element service"
  value       = kubernetes_service.element.metadata[0].name
}
