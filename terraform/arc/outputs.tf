output "runs_on" {
  description = "runs-on label for each build pool."
  value       = { for pool, cfg in var.runner_pools : pool => cfg.runs_on }
}

output "runner_namespace" {
  description = "Namespace the runner pods run in."
  value       = kubernetes_namespace_v1.runners.metadata[0].name
}

output "repositories" {
  description = "Repositories with runners."
  value       = sort(var.repositories)
}
