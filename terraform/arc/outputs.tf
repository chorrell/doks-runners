output "runs_on" {
  description = "Label for `runs-on` in workflows."
  value       = var.runner_scale_set_name
}

output "runner_namespace" {
  description = "Namespace the runner pods run in."
  value       = kubernetes_namespace_v1.runners.metadata[0].name
}

output "repositories" {
  description = "Repositories with a runner scale set."
  value       = sort(var.repositories)
}
