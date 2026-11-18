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

variable "repositories" {
  description = "Repositories (owner/name) that get a runner scale set. chorrell is a personal account, so runners register per repository."
  type        = set(string)
  default     = ["chorrell/docker-node-minimal"]
}

variable "runner_scale_set_name" {
  description = "The `runs-on` label workflows use."
  type        = string
  default     = "doks-amd64"
}

variable "max_runners" {
  description = "Upper bound on runner pods per repository. Keep it at or below build_max_nodes in terraform/cluster; extra pods wait for a node."
  type        = number
  default     = 1

  validation {
    condition     = var.max_runners >= 1 && var.max_runners <= 4
    error_message = "max_runners must be between 1 and 4."
  }
}

variable "github_app_id" {
  description = "ID of the GitHub App ARC authenticates with. Not secret."
  type        = string
}

variable "github_app_installation_id" {
  description = "Installation ID of the GitHub App on the chorrell account. Not secret."
  type        = string
}

variable "github_app_private_key" {
  description = "PEM private key of the GitHub App. Set by hand as a sensitive variable on the HCP workspace; never in the repo."
  type        = string
  sensitive   = true
  # Kept out of state and plan files; it only feeds the write-only data_wo below.
  ephemeral = true
}

variable "github_app_secret_revision" {
  description = "Bump to push a new GitHub App key (or ID) to the cluster. Write-only values aren't compared, so changing the key alone does nothing."
  type        = number
  default     = 1
}
