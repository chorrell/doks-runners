locals {
  name = "doks-runners"

  # Runner pods select the build pool with this label and tolerate its taint. Nothing else lands there, so the
  # autoscaler can remove the last build node as soon as the job's pod is gone.
  build_pool_label = { "doks-runners/pool" = "build" }
}

# A data source, not "latest", so a patch upgrade by auto_upgrade doesn't show up as drift.
data "digitalocean_kubernetes_versions" "this" {
  version_prefix = var.kubernetes_version_prefix
}

resource "digitalocean_kubernetes_cluster" "this" {
  name    = local.name
  region  = var.region
  version = data.digitalocean_kubernetes_versions.this.latest_version
  tags    = [local.name]

  # The HA control plane costs $40/month and can't be disabled once enabled. From 1.36 the API turns it on when
  # `ha` is omitted, so it must stay explicitly false.
  ha = false

  auto_upgrade  = true
  surge_upgrade = true

  maintenance_policy {
    day        = "sunday"
    start_time = "08:00"
  }

  # Applies to every autoscaling pool. The default waits 10 minutes before removing an idle node; at $1/hour a
  # shorter tail matters more than avoiding a cold start for back-to-back jobs.
  cluster_autoscaler_configuration {
    scale_down_unneeded_time = "5m"
  }

  # The default pool: one fixed node, always on, for the ARC controller and cluster add-ons. DigitalOcean
  # recommends keeping one fixed pool when another pool scales to zero.
  node_pool {
    name       = "system"
    size       = var.system_node_size
    node_count = 1
    labels     = { "doks-runners/pool" = "system" }
  }
}

resource "digitalocean_kubernetes_node_pool" "build" {
  cluster_id = digitalocean_kubernetes_cluster.this.id
  name       = "build"
  size       = var.build_node_size
  tags       = [local.name]
  labels     = local.build_pool_label

  # Scale to zero between jobs. node_count is left unset so Terraform doesn't fight the autoscaler.
  auto_scale = true
  min_nodes  = 0
  max_nodes  = var.build_max_nodes

  taint {
    key    = "doks-runners/pool"
    value  = "build"
    effect = "NoSchedule"
  }
}
