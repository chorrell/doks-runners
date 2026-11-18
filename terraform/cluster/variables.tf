variable "region" {
  description = "DigitalOcean region. CPU-Optimized sizes (c-16, c-32, c-48) are only offered in blr1 and sfo2."
  type        = string
  default     = "sfo2"
}

variable "kubernetes_version_prefix" {
  description = "Kubernetes minor version to track, e.g. \"1.37.\". Patch releases are applied by auto-upgrade."
  type        = string
  default     = "1.37."
}

variable "system_node_size" {
  description = "Droplet size for the one always-on node that runs the ARC controller and cluster add-ons."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "build_pools" {
  description = <<-EOT
    Autoscaling build pools, keyed by pool name. Each scales between 0 and max_nodes and gets its own runs-on label in
    terraform/arc. Every node left running costs its full hourly price (c-8 $0.25, c-32 $1.00), so keep max_nodes small.
  EOT
  type = map(object({
    size      = string
    max_nodes = number
  }))
  default = {
    general = { size = "c-8", max_nodes = 1 }
    large   = { size = "c-32", max_nodes = 1 }
  }

  validation {
    condition     = alltrue([for p in values(var.build_pools) : p.max_nodes >= 1 && p.max_nodes <= 4])
    error_message = "Each pool's max_nodes must be between 1 and 4."
  }

  validation {
    condition     = alltrue([for name in keys(var.build_pools) : can(regex("^[a-z][a-z0-9-]*$", name))])
    error_message = "Pool names must be lowercase letters, digits and hyphens; they become node labels and pool names."
  }
}
