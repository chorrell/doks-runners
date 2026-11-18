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

output "build_pool_ids" {
  description = "Build pool IDs by pool name, for the doctl scale-up/scale-down fallback if autoscaling to zero doesn't work."
  value       = { for name, pool in digitalocean_kubernetes_node_pool.build : name => pool.id }
}

output "build_pool_scheduling" {
  description = "Node label key (its value is the pool name) and the taint that runner pods must select and tolerate."
  value = {
    label_key = local.pool_label_key
    taint     = local.build_taint
  }
}
