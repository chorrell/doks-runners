locals {
  charts = "oci://ghcr.io/actions/actions-runner-controller-charts"

  # Must match terraform/cluster (its build_pool_scheduling output): runner pods select a pool by this label, whose
  # value is the pool name, and tolerate the taint every build pool carries.
  pool_label_key = "doks-runners/pool"
  build_taint    = { key = "doks-runners/runner", value = "true", effect = "NoSchedule" }

  # Runners register once for the organization, in its Default runner group, so every repository in it can use them.
  github_config_url = "https://github.com/${var.github_organization}"

  # One scale set per pool, named by its runs-on label. None until runners_enabled, so the controller can be installed
  # before the GitHub App exists.
  scale_sets = var.runners_enabled ? {
    for pool, cfg in var.runner_pools : cfg.runs_on => {
      pool = pool
      max  = cfg.max_runners
    }
  } : {}
}

# The controller and the runners get separate namespaces, as GitHub recommends.
resource "kubernetes_namespace_v1" "controller" {
  metadata {
    name = "arc-systems"
  }
}

resource "kubernetes_namespace_v1" "runners" {
  metadata {
    name = "arc-runners"
  }
}

# GitHub App credentials for every scale set. data_wo is write-only, so the private key never reaches state. Not
# created until runners_enabled, so the controller can be installed before the App exists.
resource "kubernetes_secret_v1" "github_app" {
  count = var.runners_enabled ? 1 : 0

  metadata {
    name      = "arc-github-app"
    namespace = kubernetes_namespace_v1.runners.metadata[0].name
  }

  data_wo = {
    github_app_id              = var.github_app_id
    github_app_installation_id = var.github_app_installation_id
    github_app_private_key     = var.github_app_private_key
  }
  data_wo_revision = var.github_app_secret_revision

  lifecycle {
    precondition {
      condition     = var.github_app_id != null && var.github_app_installation_id != null
      error_message = "Set github_app_id, github_app_installation_id and github_app_private_key before setting runners_enabled."
    }
  }
}

# The controller and the listener pods it creates have no toleration, so they run on the system node.
resource "helm_release" "controller" {
  name       = "arc"
  namespace  = kubernetes_namespace_v1.controller.metadata[0].name
  repository = local.charts
  chart      = "gha-runner-scale-set-controller"
  version    = var.arc_chart_version
}

resource "helm_release" "runners" {
  for_each = local.scale_sets

  name       = each.key
  namespace  = kubernetes_namespace_v1.runners.metadata[0].name
  repository = local.charts
  chart      = "gha-runner-scale-set"
  version    = var.arc_chart_version

  values = [yamlencode({
    githubConfigUrl    = local.github_config_url
    githubConfigSecret = kubernetes_secret_v1.github_app[0].metadata[0].name
    runnerScaleSetName = each.key

    # An idle runner would keep a build node up at its full hourly price. 0 lets the pool scale to zero.
    minRunners = 0
    maxRunners = each.value.max

    # A privileged Docker daemon sidecar, so jobs can build images and use container jobs, services and Docker
    # actions as on GitHub-hosted runners. Acceptable because build nodes run nothing else and fork pull requests
    # need approval before they run.
    containerMode = { type = "dind" }

    # "<release>-gha-rs-controller" is the controller chart's service account name.
    controllerServiceAccount = {
      namespace = helm_release.controller.namespace
      name      = "${helm_release.controller.name}-gha-rs-controller"
    }

    # ARC's default runner image and containers. No resource requests: a request bigger than the node can hold
    # would leave the pod pending forever, with no node added. One runner fills one node.
    template = {
      spec = {
        nodeSelector = { (local.pool_label_key) = each.value.pool }
        tolerations = [{
          key      = local.build_taint.key
          operator = "Equal"
          value    = local.build_taint.value
          effect   = local.build_taint.effect
        }]
      }
    }
  })]
}
