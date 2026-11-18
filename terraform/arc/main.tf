locals {
  charts = "oci://ghcr.io/actions/actions-runner-controller-charts"

  # Runner pods go to the build pool and tolerate its taint; nothing else does. These must match the label and taint
  # in terraform/cluster (its build_pool_selector output).
  build_pool = { key = "doks-runners/pool", value = "build" }

  # Release names must be unique; the runs-on label (runner_scale_set_name) is the same for every repository.
  scale_sets = { for repo in var.repositories : replace(repo, "/", "-") => repo }
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

# GitHub App credentials for every scale set. data_wo is write-only, so the private key never reaches state.
resource "kubernetes_secret_v1" "github_app" {
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
    githubConfigUrl    = "https://github.com/${each.value}"
    githubConfigSecret = kubernetes_secret_v1.github_app.metadata[0].name
    runnerScaleSetName = var.runner_scale_set_name

    # An idle runner would keep a c-32 node up at $672/month. 0 lets the build pool scale to zero.
    minRunners = 0
    maxRunners = var.max_runners

    # docker-node-minimal builds images, which needs a Docker daemon: a privileged dind sidecar. Acceptable because
    # only these pods run on the build pool and workflows never run for fork pull requests.
    containerMode = { type = "dind" }

    # "<release>-gha-rs-controller" is the controller chart's service account name.
    controllerServiceAccount = {
      namespace = helm_release.controller.namespace
      name      = "${helm_release.controller.name}-gha-rs-controller"
    }

    # No resource requests: a request bigger than a c-32 can hold would leave the pod pending forever, with no
    # node added. ARC fills in the runner and dind containers.
    template = {
      spec = {
        nodeSelector = { (local.build_pool.key) = local.build_pool.value }
        tolerations = [{
          key      = local.build_pool.key
          operator = "Equal"
          value    = local.build_pool.value
          effect   = "NoSchedule"
        }]
      }
    }
  })]
}
