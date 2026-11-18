output "runs_on" {
  description = "runs-on label for each build pool."
  value       = { for pool, cfg in var.runner_pools : pool => cfg.runs_on }
}

output "runner_namespace" {
  description = "Namespace the runner pods run in."
  value       = kubernetes_namespace_v1.runners.metadata[0].name
}

output "github_config_url" {
  description = "Where the runners register: the organization. Empty scale sets until runners_enabled is set."
  value       = local.github_config_url
}

output "runners_enabled" {
  description = "Whether the runner scale sets exist."
  value       = var.runners_enabled
}
