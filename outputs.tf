output "hotrod_url" {
  description = "Local URL for HotROD after running the port-forward command."
  value       = "http://localhost:8080"
}

output "hotrod_port_forward_command" {
  description = "Run locally to access the HotROD UI."
  value       = "kubectl -n ${kubernetes_namespace.observability.metadata[0].name} port-forward svc/${kubernetes_service.hotrod.metadata[0].name} 8080:8080"
}

output "jaeger_url" {
  description = "Local URL for Jaeger after running the port-forward command."
  value       = "http://localhost:16686"
}

output "jaeger_port_forward_command" {
  description = "Run locally to access the Jaeger UI."
  value       = "kubectl -n ${kubernetes_namespace.observability.metadata[0].name} port-forward svc/${kubernetes_service.jaeger_ui.metadata[0].name} 16686:16686"
}
