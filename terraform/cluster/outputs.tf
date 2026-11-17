output "cluster_id" {
  description = "Cluster ID, for `doctl kubernetes cluster kubeconfig save` and the ARC root."
  value       = digitalocean_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "Cluster name."
  value       = digitalocean_kubernetes_cluster.this.name
}

output "kubernetes_version" {
  description = "Kubernetes version slug the cluster was created or last updated with."
  value       = digitalocean_kubernetes_cluster.this.version
}

output "build_pool_id" {
  description = "Build pool ID, for the doctl scale-up/scale-down fallback if autoscaling to zero doesn't work."
  value       = digitalocean_kubernetes_node_pool.build.id
}

output "build_pool_selector" {
  description = "Node label and taint that runner pods must select and tolerate."
  value       = local.build_pool_label
}
