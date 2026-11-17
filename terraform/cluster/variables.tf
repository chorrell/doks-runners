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

variable "build_node_size" {
  description = "Droplet size for the build pool. c-32 is 32 vCPU / 64 GiB at $1.00/hour."
  type        = string
  default     = "c-32"
}

variable "build_max_nodes" {
  description = "Upper bound on build nodes. Each c-32 left running costs about $672/month, so keep this small."
  type        = number
  default     = 1

  validation {
    condition     = var.build_max_nodes >= 1 && var.build_max_nodes <= 4
    error_message = "build_max_nodes must be between 1 and 4."
  }
}
