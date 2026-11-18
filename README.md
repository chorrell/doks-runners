# doks-runners

[![zizmor](https://github.com/chorrell/doks-runners/actions/workflows/zizmor.yml/badge.svg)](https://github.com/chorrell/doks-runners/actions/workflows/zizmor.yml)

Generic self-hosted GitHub Actions runners on **DigitalOcean Kubernetes
(DOKS)** for any repository that opts in: bigger machines than GitHub's
standard runners, available all the time at a low idle cost, because DOKS
doesn't charge for the control plane and the build pools scale down to zero
between jobs. Runner pods are ephemeral (one job each).

Jobs pick a size with `runs-on`:

| Label | Node | When to use it |
| --- | --- | --- |
| `doks-amd64` | `c-8`: 8 vCPU, 16 GiB, $0.25/hour | Everyday builds and tests |
| `doks-amd64-large` | `c-32`: 32 vCPU, 64 GiB, $1.00/hour | Heavy compiles, such as building Node.js from source |

Runners use ARC's default image, which is minimal: jobs install what they need
with `setup-*` actions or run in containers, and Docker is available.

> **Status:** the cluster is running (applied 18 November 2026) with one
> `c-32` build pool at 0 nodes; the `c-8` pool comes with the next apply. The
> ARC root (`terraform/arc`) is written but not applied, and no repository has
> runners yet; see [Roadmap](#roadmap).

## Why DigitalOcean

The same idea on EKS ([eks-spot-runners](https://github.com/chorrell/eks-spot-runners))
pays $0.10/hour for the control plane, about $73/month, before any jobs run,
so it's meant to be torn down after use. On DOKS the control plane is free and
there's no NAT gateway to pay for, so an always-available setup costs roughly a
quarter as much.

## Design

| Piece | Choice | Why |
| --- | --- | --- |
| Cluster | DOKS in `sfo2`, free control plane (`ha = false`) | No hourly cluster fee; the HA control plane would add $40/month |
| System pool | One fixed `s-2vcpu-4gb` node for the runner controller | DigitalOcean recommends one fixed pool when another scales to zero |
| Build pools | CPU-Optimized `general` (`c-8`) and `large` (`c-32`), each autoscaling **0 to 1**, tainted for runner pods only | Pay only while a job runs; one runner per node |
| Runners | **Actions Runner Controller (ARC)**: one runner scale set per repository and pool, ARC's default image, `dind` mode | Ephemeral runner pod per job; Docker builds, container jobs and service containers work |
| Repositories | Opt in one at a time (`repositories` in `terraform/arc`) | chorrell is a personal account, so runners register per repository rather than once for an organization |
| arm64 | Stays on GitHub's hosted arm64 runners | DOKS offers no ARM node sizes (checked November 2026); GitHub's are free for public repos |
| Caching | The **GitHub Actions cache**, as on hosted runners | GitHub serves it to self-hosted runners too, so there's no cache storage to run ([docker-node-minimal#351](https://github.com/chorrell/docker-node-minimal/issues/351)) |
| Infrastructure | Terraform with state in HCP Terraform: `terraform/cluster` for the cluster, `terraform/arc` for the ARC Helm releases | Two roots, because the Helm and Kubernetes providers shouldn't be configured from a cluster created in the same root |

CPU-Optimized sizes of 16 vCPU and up (`c-16`, `c-32`, `c-48`) are only
offered in `blr1` and `sfo2`, which is why the cluster is in `sfo2`. Pools and
their sizes are a map (`build_pools` in `terraform/cluster`, `runner_pools` in
`terraform/arc`), so adding a size is a config change.

### Scale to zero

"Scale to zero" means each build pool shrinks to **no nodes** when nothing is
running, so it costs nothing while idle:

1. While idle, the build pools have 0 nodes; only the system node runs.
2. A queued job makes ARC create a runner pod. The pod can only run on a node
   in the pool its label asks for, so it waits, and the cluster autoscaler
   adds one.
3. The pod runs one job and exits.
4. Once the node has been empty for 5 minutes (`scale_down_unneeded_time`), the
   autoscaler deletes it and the pool is back at 0.

A 30-minute job plus the 5-minute idle tail costs about $0.15 on `c-8` or
$0.60 on `c-32`. Pools that couldn't go below one node would cost $168 and
$672 a month whether anything ran or not.

**The trade-off is a cold start.** The first job after an idle period waits
for a node to be created and join the cluster, which is likely a few minutes;
DigitalOcean doesn't publish a figure, so the roadmap measures it.
Back-to-back jobs within the 5-minute window reuse the warm node.

**Scale-to-zero is half confirmed.** The Terraform provider's docs (2.108.0)
still call `min_nodes = 0` private preview, but the API accepted it on the
first apply, and the `c-32` pool sits at 0 nodes. What's left to confirm,
once ARC is installed, is the other half: the autoscaler adding a node for a
pending runner pod and removing it after the idle window. If that doesn't
work, the fallback is for workflows to scale the pool up with `doctl` before
the job and back down after, even when the job fails.

## Cost model

List prices as of November 2026, from
[DOKS pricing](https://docs.digitalocean.com/products/kubernetes/details/pricing/)
and `doctl compute size list`. Nothing has been measured yet.

| Item | Monthly |
| --- | --- |
| DOKS control plane (no HA) | $0 |
| System node, `s-2vcpu-4gb` | $24 |
| Build nodes, `c-8` at $0.25/hour and `c-32` at $1.00/hour, billed per second | Per job, if the pools scale to zero: ~$0.15 or ~$0.60 for a 30-minute job |
| Caching (Actions cache, under the free 10 GB per repository) | $0 |
| NAT gateway | $0 (nodes have public IPs) |
| **Total, always available** | **$24 plus usage** |

There are no spot instances on DigitalOcean, so build nodes are full price,
but only while a job runs. A node left running by mistake costs $168/month
(`c-8`) or $672/month (`c-32`), which is why scale-down has to be confirmed
before real jobs run here and each pool's `max_nodes` defaults to 1.

## Security

- **Never let pull requests from forks run here.** A runner registered on a
  repository runs any job that asks for its label, including a
  workflow a fork pull request adds or edits, and a personal account can't
  restrict a runner to selected workflows. On a public repository the guard is
  its fork-PR approval policy: **Require approval for all external
  contributors**. Set it before the repository gets a scale set; the GitHub
  provider can't manage it, so it isn't in github-settings.
- ARC authenticates with a GitHub App. The DigitalOcean API token is a
  sensitive variable on the HCP Terraform workspace, not in the repo.
- The build pools are tainted, so only pods that tolerate it (the runners)
  are scheduled there.
- Runner pods use ARC's `dind` mode, a **privileged** Docker daemon sidecar,
  so jobs can build images and use container jobs and services as on hosted
  runners. A job that runs here effectively has root on its build node.
  That's acceptable only because build nodes run nothing else, each runs one
  job and is removed when idle, and fork pull requests can't run without your
  approval. Only add repositories you control.
- The GitHub App needs **Administration: read and write** on each repository
  to register runners there, which also lets it change that repository's
  settings. Install it on the selected repositories only, never on all of
  them. Its private key is written to the cluster through a write-only
  argument, so it isn't in Terraform state; the cluster's kube token is in
  both workspaces' state.

## Deploying

Each root has its own workspace in the `horrell` HCP Terraform organization,
defined in
[hcp-terraform-horrell](https://github.com/chorrell/hcp-terraform-horrell).
Applies are confirmed by hand in both.

| Root | Workspace | Creates |
| --- | --- | --- |
| `terraform/cluster` | `doks-runners-cluster` | The cluster, system pool and build pools |
| `terraform/arc` | `doks-runners-arc` | The ARC controller, a runner scale set per repository and pool, and the GitHub App secret |

Apply `terraform/cluster` first; `terraform/arc` reads the cluster by name.

### Cluster token

`DIGITALOCEAN_TOKEN` on `doks-runners-cluster` is a sensitive environment
variable. It holds a personal access token named
`hcp-terraform-doks-runners-cluster`, created under **Account → API → Tokens**
with **Custom Scopes**:

| Resource | Scopes | Why |
| --- | --- | --- |
| kubernetes | `create`, `read`, `update`, `delete`, `access_cluster` | Manage the cluster and build pools. The provider fetches the cluster credentials during create, so `access_cluster` is required: without it the apply fails with a 403 after the cluster exists, leaving it tainted. |
| regions, sizes, actions | `read` | Required by every kubernetes scope |
| tag | `read`, `create` | The cluster and build pools are tagged `doks-runners` |
| vpc | `read` | The cluster joins the region's default VPC |

### ARC token

`doks-runners-arc` only reads the cluster, so its `DIGITALOCEAN_TOKEN` is a
separate, read-only token named `hcp-terraform-doks-runners-arc`:

| Resource | Scopes | Why |
| --- | --- | --- |
| kubernetes | `read`, `access_cluster` | Read the cluster and fetch its credentials for the Helm and Kubernetes providers |
| regions, sizes, actions | `read` | Required by every kubernetes scope |

A token's scopes can't be changed after it's created, so adding one means
generating a new token and replacing the variable's value. Rotate both tokens
before they expire; an expired token makes every run fail.

### GitHub App

ARC registers runners through a GitHub App owned by the chorrell account. The
controller installs without it; it's needed once `repositories` lists a
repository.

1. Register a GitHub App under the personal account. Disable the webhook.
   Repository permissions: **Administration: read and write**, **Metadata:
   read-only**. Install it **only on this account**, with **Only select
   repositories**.
2. Generate a private key.
3. On `doks-runners-arc`, set:
   - `github_app_id` and `github_app_installation_id`: plain Terraform
     variables (not secret), managed in hcp-terraform-horrell's
     `workspace_variables.tf`.
   - `github_app_private_key`: a **sensitive** Terraform variable holding the
     full PEM.

To rotate the key, set the new value and bump `github_app_secret_revision`;
write-only values aren't compared, so changing the key alone does nothing.

### Adding a repository

1. Set its fork-PR approval policy to **Require approval for all external
   contributors** (Settings → Actions → General); see [Security](#security).
2. Add it to the GitHub App's installation (**Only select repositories**).
3. Add `owner/name` to `repositories` in `terraform/arc` and apply. It gets a
   scale set for each pool.
4. Use `runs-on: doks-amd64` or `runs-on: doks-amd64-large` in workflows that
   run on push or `workflow_dispatch`.

### Kubeconfig

After the cluster's first apply, fetch a kubeconfig with:

```sh
doctl kubernetes cluster kubeconfig save doks-runners
```

## Roadmap

1. ~~Terraform: DOKS cluster, system pool, autoscaling build pool~~
   (`terraform/cluster`).
2. ~~Apply it~~ (18 November 2026; the build pool sits at 0 nodes).
3. ARC controller and runner scale sets in `terraform/arc`, and a second,
   `c-8` build pool for generic jobs (written, not applied). Apply with no
   repositories, so only the controller is installed.
4. GitHub App, then the first repository. Confirm each pool scales up for a
   job and back to 0 after it (or add the `doctl` fallback).
5. Measure cold-start time and cost per job on both labels, against
   GitHub-hosted runners.
6. Write up results here, and decide whether a custom runner image with
   common tools preinstalled is worth maintaining.

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
