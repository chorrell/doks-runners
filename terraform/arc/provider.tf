# Token from DIGITALOCEAN_TOKEN on the HCP workspace. This root only reads the cluster, so the token needs
# kubernetes:read and kubernetes:access_cluster, not create/update/delete.
provider "digitalocean" {}

# The cluster is created by terraform/cluster. Reading it here, rather than in the same root, means these providers
# are never configured from a resource that doesn't exist yet. The kube token lands in this workspace's state, as it
# does in the cluster workspace's; DOKS rotates it, and each run reads a fresh one.
data "digitalocean_kubernetes_cluster" "this" {
  name = var.cluster_name
}

locals {
  kube = data.digitalocean_kubernetes_cluster.this.kube_config[0]
}

provider "kubernetes" {
  host                   = local.kube.host
  token                  = local.kube.token
  cluster_ca_certificate = base64decode(local.kube.cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = local.kube.host
    token                  = local.kube.token
    cluster_ca_certificate = base64decode(local.kube.cluster_ca_certificate)
  }
}
