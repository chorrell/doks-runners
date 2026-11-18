variable "cluster_name" {
  description = "Name of the DOKS cluster created by terraform/cluster."
  type        = string
  default     = "doks-runners"
}

variable "arc_chart_version" {
  description = "Version of both ARC charts. Helm can't upgrade ARC's CRDs, so a bump needs the uninstall/reinstall in AGENTS.md."
  type        = string
  default     = "0.15.1"
}

variable "github_organization" {
  description = "GitHub organization the runners register in. Every repository in it can use them."
  type        = string
  default     = "horrell-consulting"
}

variable "runners_enabled" {
  description = <<-EOT
    Create the GitHub App secret and one runner scale set per pool. Before setting it: the GitHub App is installed on
    the organization and its variables are set, and the organization's fork-PR approval is all external contributors.
  EOT
  type        = bool
  default     = false
}

variable "runner_pools" {
  description = <<-EOT
    Runner label and limit for each build pool. Keys must match build_pools in terraform/cluster. Keep max_runners at
    or below that pool's max_nodes: extra pods just wait for a node.
  EOT
  type = map(object({
    runs_on     = string
    max_runners = number
  }))
  default = {
    general = { runs_on = "doks-amd64", max_runners = 1 }
    large   = { runs_on = "doks-amd64-large", max_runners = 1 }
  }

  validation {
    condition     = alltrue([for p in values(var.runner_pools) : p.max_runners >= 1 && p.max_runners <= 4])
    error_message = "Each pool's max_runners must be between 1 and 4."
  }
}

variable "github_app_id" {
  description = "ID of the GitHub App ARC authenticates with. Not secret. Needed once runners_enabled is set."
  type        = string
  default     = null
}

variable "github_app_installation_id" {
  description = "Installation ID of the GitHub App on the organization. Not secret. Needed once runners_enabled is set."
  type        = string
  default     = null
}

variable "github_app_private_key" {
  description = "PEM private key of the GitHub App. Set by hand as a sensitive variable on the HCP workspace; never in the repo."
  type        = string
  sensitive   = true
  # Kept out of state and plan files; it only feeds the write-only data_wo.
  ephemeral = true
  default   = null
}

variable "github_app_secret_revision" {
  description = "Bump to push a new GitHub App key (or ID) to the cluster. Write-only values aren't compared, so changing the key alone does nothing."
  type        = number
  default     = 1
}
