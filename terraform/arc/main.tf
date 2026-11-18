locals {
  charts = "oci://ghcr.io/actions/actions-runner-controller-charts"

  # Must match terraform/cluster (its build_pool_scheduling output): runner pods select a pool by this label, whose
  # value is the pool name, and tolerate the taint every build pool carries.
  pool_label_key = "doks-runners/pool"
  build_taint    = { key = "doks-runners/runner", value = "true", effect = "NoSchedule" }

  # One scale set per repository and pool. Release names must be unique; runs-on labels repeat across repositories.
  scale_sets = {
    for pair in setproduct(sort(var.repositories), keys(var.runner_pools)) :
    "${replace(pair[0], "/", "-")}-${pair[1]}" => {
      repository = pair[0]
      pool       = pair[1]
      runs_on    = var.runner_pools[pair[1]].runs_on
      max        = var.runner_pools[pair[1]].max_runners
    }
  }
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
# created until a repository is listed, so the controller can be installed before the App exists.
resource "kubernetes_secret_v1" "github_app" {
  count = length(var.repositories) > 0 ? 1 : 0

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
      error_message = "Set github_app_id, github_app_installation_id and github_app_private_key before listing repositories."
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
    githubConfigUrl    = "https://github.com/${each.value.repository}"
    githubConfigSecret = kubernetes_secret_v1.github_app[0].metadata[0].name
    runnerScaleSetName = each.value.runs_on

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
