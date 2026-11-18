# doks-runners

[![zizmor](https://github.com/chorrell/doks-runners/actions/workflows/zizmor.yml/badge.svg)](https://github.com/chorrell/doks-runners/actions/workflows/zizmor.yml)

Self-hosted GitHub Actions runners on **DigitalOcean Kubernetes (DOKS)**: a
low-cost build fleet that can stay up all the time, because DOKS doesn't charge
for the control plane. Runner pods are ephemeral (one job each), and the
32-vCPU build pool scales down to zero between jobs.

The example workload is
[docker-node-minimal](https://github.com/chorrell/docker-node-minimal), which
compiles Node.js from source. Any Docker image with a long build works the same
way.

> **Status:** the cluster is running (applied 18 November 2026) with the build
> pool at 0 nodes. ARC isn't installed yet, so no jobs run here; see
> [Roadmap](#roadmap).

## Why DigitalOcean

The same idea on EKS ([eks-spot-runners](https://github.com/chorrell/eks-spot-runners))
pays $0.10/hour for the control plane, about $73/month, before any builds run,
so it's meant to be torn down after use. On DOKS the control plane is free and
there's no NAT gateway to pay for, so an always-available setup costs roughly a
quarter as much.

## Design

| Piece | Choice | Why |
| --- | --- | --- |
| Cluster | DOKS in `sfo2`, free control plane (`ha = false`) | No hourly cluster fee; the HA control plane would add $40/month |
| System pool | One fixed `s-2vcpu-4gb` node for the runner controller | DigitalOcean recommends one fixed pool when another scales to zero |
| Build pool | CPU-Optimized `c-32` (32 vCPU / 64 GiB), autoscaling **0 to 1**, tainted for runner pods only | Pay only while a job runs |
| Runners | **Actions Runner Controller (ARC)** runner scale set `doks-amd64` | Ephemeral runner pod per job |
| arm64 | Stays on GitHub's hosted arm64 runners | DOKS offers no ARM node sizes (checked November 2026); GitHub's are free for public repos |
| Compile cache | ccache in the **GitHub Actions cache**, as docker-node-minimal already does | About 1–2 GB in all, 70–100% hit rate when present, and served by GitHub to self-hosted runners too ([docker-node-minimal#351](https://github.com/chorrell/docker-node-minimal/issues/351)) |
| Infrastructure | Terraform with state in HCP Terraform: `terraform/cluster` now, `terraform/arc` for the ARC Helm release next | Two roots, because the Helm and Kubernetes providers shouldn't be configured from a cluster created in the same root |

CPU-Optimized sizes of 16 vCPU and up (`c-16`, `c-32`, `c-48`) are only
offered in `blr1` and `sfo2`, which is why the cluster is in `sfo2`.

### Scale to zero

"Scale to zero" means the build pool shrinks to **no nodes** when nothing is
building, so it costs nothing while idle:

1. While idle, the build pool has 0 nodes; only the system node runs.
2. A queued job makes ARC create a runner pod. The pod can only run on a build
   node, so it waits, and the cluster autoscaler adds a `c-32` node.
3. The pod runs one job and exits.
4. Once the node has been empty for 5 minutes (`scale_down_unneeded_time`), the
   autoscaler deletes it and the pool is back at 0.

A 30-minute build plus the 5-minute idle tail costs about $0.60. A pool that
couldn't go below one node would cost $672/month whether anything built or
not.

**The trade-off is a cold start.** The first job after an idle period waits
for a node to be created and join the cluster, which is likely a few minutes;
DigitalOcean doesn't publish a figure, so roadmap step 5 measures it.
Back-to-back jobs within the 5-minute window reuse the warm node.

**Scale-to-zero is half confirmed.** The Terraform provider's docs (2.108.0)
still call `min_nodes = 0` private preview, but the API accepted it on the
first apply, and the build pool sits at 0 nodes. What's left to confirm, once
ARC is installed (roadmap step 3), is the other half: the autoscaler adding a
node for a pending runner pod and removing it after the idle window. If that
doesn't work, the fallback is for the workflow to scale the build pool up with
`doctl` before the job and back down after, even when the job fails.

## Cost model

List prices as of November 2026, from
[DOKS pricing](https://docs.digitalocean.com/products/kubernetes/details/pricing/)
and `doctl compute size list`. Nothing has been measured yet.

| Item | Monthly |
| --- | --- |
| DOKS control plane (no HA) | $0 |
| System node, `s-2vcpu-4gb` | $24 |
| Build node, `c-32` at $1.00/hour, billed per second | ~$2–7 for a handful of builds, if it scales to zero |
| Compile cache (Actions cache, under the free 10 GB) | $0 |
| NAT gateway | $0 (nodes have public IPs) |
| **Total, always available** | **~$26–31** |

There are no spot instances on DigitalOcean, so build nodes are full price,
but only while a job runs. A `c-32` left running by mistake costs $672/month,
which is why scale-down has to be confirmed before real jobs run here and
`max_nodes` defaults to 1.

## Security

- Runners only take jobs from repositories and workflows you list. **Never let
  pull requests from forks run here.**
- ARC authenticates with a GitHub App. The DigitalOcean API token is a
  sensitive variable on the HCP Terraform workspace, not in the repo.
- The build pool is tainted, so only pods that tolerate it (the runners) are
  scheduled there.

## Deploying

The cluster root runs in the `doks-runners-cluster` workspace in the `horrell`
HCP Terraform organization, which is defined in
[hcp-terraform-horrell](https://github.com/chorrell/hcp-terraform-horrell).
Applies are confirmed by hand.

`DIGITALOCEAN_TOKEN` is a sensitive environment variable on the workspace. It
holds a personal access token named `hcp-terraform-doks-runners-cluster`,
created under **Account → API → Tokens** with **Custom Scopes**:

| Resource | Scopes | Why |
| --- | --- | --- |
| kubernetes | `create`, `read`, `update`, `delete`, `access_cluster` | Manage the cluster and build pool. The provider fetches the cluster credentials during create, so `access_cluster` is required: without it the apply fails with a 403 after the cluster exists, leaving it tainted. |
| regions, sizes, actions | `read` | Required by every kubernetes scope |
| tag | `read`, `create` | The cluster and build pool are tagged `doks-runners` |
| vpc | `read` | The cluster joins the region's default VPC |

A token's scopes can't be changed after it's created, so adding one means
generating a new token and replacing the variable's value. Rotate it before it
expires; an expired token makes every run fail.

After the first apply, fetch a kubeconfig with:

```sh
doctl kubernetes cluster kubeconfig save doks-runners
```

## Roadmap

1. ~~Terraform: DOKS cluster, system pool, autoscaling build pool~~
   (`terraform/cluster`).
2. ~~Apply it~~ (18 November 2026; the build pool sits at 0 nodes).
3. ARC controller and the `doks-amd64` runner scale set in `terraform/arc`;
   GitHub App auth. Confirm the build pool scales up for a job and back to 0
   after it (or add the `doctl` fallback).
4. Example workflow: docker-node-minimal amd64 on `doks-amd64`, arm64 on
   GitHub's hosted arm runner, ccache in the Actions cache for both.
5. Measure cold and warm build times and cost per build, against GitHub-hosted
   runners and eks-spot-runners.
6. Write up results here.

## Local development

Install [prek](https://github.com/j178/prek) (`brew install prek`) and run the
hooks before pushing:

```sh
prek install
prek run --all-files
```

The markdownlint hook needs Docker running; the Terraform hooks need
`terraform` and `trivy`.

## License

[MPL-2.0](LICENSE)
