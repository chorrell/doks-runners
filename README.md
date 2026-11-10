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

> **Status:** planning. Nothing is deployed yet; see [Roadmap](#roadmap).

## Why DigitalOcean

The same idea on EKS ([eks-spot-runners](https://github.com/chorrell/eks-spot-runners))
pays $0.10/hour for the control plane, about $73/month, before any builds run,
so it's meant to be torn down after use. On DOKS the control plane is free and
there's no NAT gateway to pay for, so an always-available setup costs roughly a
quarter as much.

## Design

| Piece | Choice | Why |
| --- | --- | --- |
| Cluster | DOKS, free control plane (no HA add-on) | No hourly cluster fee |
| System pool | One small node for the runner controller | DOKS needs at least one fixed node |
| Build pool | CPU-Optimized 32 vCPU droplets, autoscaling **down to zero** | Pay only while a job runs |
| Runners | **Actions Runner Controller (ARC)** runner scale set `doks-amd64` | Ephemeral runner pod per job |
| arm64 | Stays on GitHub's hosted arm64 runners | DigitalOcean doesn't offer ARM droplets (verify); GitHub's are free for public repos |
| Compile cache | sccache with a **DigitalOcean Spaces** bucket (S3-compatible) | Never evicted, unlike the Actions cache; shared by both platforms ([docker-node-minimal#351](https://github.com/chorrell/docker-node-minimal/issues/351)) |
| Infrastructure | Terraform (`terraform/`), Helm release for ARC | One `apply` / `destroy` |

**Open question:** DigitalOcean's docs say the cluster autoscaler can scale a
node pool to zero, but a 2025 release note called it a preview and older docs
required at least one node. Confirm before relying on it. The fallback: the
workflow scales the build pool up with `doctl` before the job and back down
after.

## Cost model

Approximate prices as of November 2026; verify against
[DOKS](https://www.digitalocean.com/pricing/kubernetes) and
[Spaces](https://docs.digitalocean.com/products/spaces/details/pricing/) pricing.

| Item | Monthly |
| --- | --- |
| DOKS control plane | $0 |
| System node (2 vCPU / 4 GB) | ~$24 |
| Build node, CPU-Optimized 32 vCPU (~$1/hr, estimated from smaller sizes) | ~$2–7 for a handful of builds, if it scales to zero |
| Spaces (sccache) | $5 for 250 GB + 1 TB transfer |
| NAT gateway | $0 (nodes have public IPs) |
| **Total, always available** | **~$30–40** |

There are no spot instances on DigitalOcean, so build nodes are full price,
but only while a job runs. A 32-vCPU node left running by mistake costs about
$670/month, which is why scale-to-zero has to be confirmed first.

## Security

- Runners only take jobs from repositories and workflows you list. **Never let
  pull requests from forks run here.**
- ARC authenticates with a GitHub App; Spaces keys are scoped to the cache
  bucket and stored as repository secrets.

## Roadmap

1. Terraform: DOKS cluster, system pool, autoscaling build pool, Spaces bucket.
2. Confirm scale-to-zero (or add the `doctl` fallback).
3. ARC controller and the `doks-amd64` runner scale set; GitHub App auth.
4. Example workflow: docker-node-minimal amd64 on `doks-amd64`, arm64 on
   GitHub's hosted arm runner, sccache on Spaces for both.
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
