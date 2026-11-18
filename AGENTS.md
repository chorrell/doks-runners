# AGENTS.md

Generic self-hosted GitHub Actions runners on DigitalOcean Kubernetes (DOKS)
for any horrell-consulting repository that opts in: always available at a low idle cost,
with `c-8` and `c-32` build pools (`runs-on: doks-amd64` and
`doks-amd64-large`) that scale to zero between jobs. See [README.md](README.md) for the design,
cost model and roadmap. The AWS version of the same idea is
[eks-spot-runners](https://github.com/chorrell/eks-spot-runners).

## Structure

```text
├── terraform/
│   ├── cluster/                # DOKS cluster, fixed system pool, build pools (map, each 0–N, tainted); HCP workspace doks-runners-cluster
│   └── arc/                    # ARC controller, scale set per repo × pool (dind), GitHub App secret; HCP workspace doks-runners-arc
├── .pre-commit-config.yaml     # gitleaks, markdownlint-cli2 (Docker), hygiene hooks, zizmor, terraform fmt/validate/trivy
├── .markdownlint.yaml          # MD013 (line length) disabled
├── AGENTS.md / CLAUDE.md       # Agent guidance; CLAUDE.md only imports AGENTS.md
├── LICENSE                     # MPL-2.0
└── .github/
    ├── CODEOWNERS              # * @chorrell
    ├── dependabot.yml          # `tooling` group (Actions + pre-commit) plus a separate terraform entry for /terraform/*
    ├── zizmor.yml              # chorrell/* may be tag-pinned; everything else hash-pinned
    └── workflows/              # Stubs calling chorrell/workflows (markdownlint, pre-commit, zizmor, automerge)
```

## Rules

- **Keep the always-on cost low.** The only things running between jobs are
  the free control plane and one small system node. No HA control plane
  (`ha = false` must stay explicit: from Kubernetes 1.36 the API enables it
  when omitted, it costs $40/month, and it can't be turned off), no load
  balancers, no always-on build nodes. If a change adds a cost that runs while
  idle, call it out in the PR.
- **Every build pool must scale to zero.** A node left running costs its
  full price: $168/month for `c-8`, $672/month for `c-32`. Don't set
  `node_count` on build pools (it fights the autoscaler) and keep `max_nodes`
  small. If autoscaler scale-to-zero isn't reliable, workflows scale the pool
  with `doctl` and must scale it back down even when the job fails.
- **Pool names tie the two roots together.** `build_pools` (cluster) and
  `runner_pools` (arc) use the same keys; the key is the node label value
  runner pods select. The label key and the shared taint are repeated in both
  roots' locals; change them together.
- **Region is `sfo2`** because CPU-Optimized sizes of 16 vCPU and up are only
  offered there and in `blr1`. Check `doctl compute size list` before
  changing the region or build size.
- **Keep the cluster and the in-cluster resources in separate roots.**
  `terraform/cluster` creates the cluster; Helm and Kubernetes provider
  resources go in another root that reads the cluster through a data source.
- **The runners are generic.** Don't tailor the cluster or runner config to
  one repository's build. Repositories bring their own tools (`setup-*`
  actions or containers) and use the GitHub Actions cache; there's no shared
  cache storage.
- **amd64 builds here; arm64 stays on GitHub's hosted arm runners** unless
  DigitalOcean offers ARM droplets.
- **Never run fork pull requests on these runners.** Workflows that use them
  run on push or `workflow_dispatch`, but a fork PR brings its own workflow
  files, and the runners are privileged. What actually enforces this is each
  repository's fork-PR approval policy, set to "all external contributors".
  Don't add a repository to `repositories` until it has that policy, and only
  add horrell-consulting repositories.
- **The tokens' scopes are listed in the README's Deploying section**, one
  table per workspace. If a change needs a new DigitalOcean API scope, update
  that table in the same PR. The `terraform/arc` token stays read-only.
- **Runner scale sets keep `minRunners = 0`** and each pool's `max_runners`
  at or below its `max_nodes`. An idle runner holds a build node up. Runner
  pods get their pool's node selector and the shared toleration but no resource
  requests: a request larger than the node leaves the pod pending with no
  node added.
- **The GitHub App private key only goes through `data_wo`.** Never pass it in
  `helm_release` values or `set`, which are stored in state. Bump
  `github_app_secret_revision` when the key changes.
- **Upgrading ARC isn't a plain chart bump.** Helm can't upgrade ARC's CRDs, so
  a new `arc_chart_version` means removing the scale sets, then the
  controller, then the `actions.github.com` CRDs if they changed, and
  reinstalling. Keep both charts on the same version. Dependabot doesn't track
  the chart version.
- Don't use `kubernetes_manifest` for ARC's custom resources: it fails at plan
  time while the CRDs don't exist yet.
- **No secrets in the repo.** ARC uses a GitHub App. `DIGITALOCEAN_TOKEN` is a
  sensitive variable on the HCP Terraform workspace (workspaces are defined in
  [hcp-terraform-horrell](https://github.com/chorrell/hcp-terraform-horrell)).
  Variable files with values (`*.auto.tfvars`) are gitignored. Don't create
  DigitalOcean resources outside Terraform.
- Commit `.terraform.lock.hcl` locked for both `linux_amd64` (HCP runs) and
  `darwin_arm64`: `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`.
- Cost figures in the README are estimates with a date; replace them with
  measured numbers as builds run, and say which are which.
- **Reusable workflows live in [chorrell/workflows](https://github.com/chorrell/workflows).**
  Workflows here are stubs that call them by tag (`@v1`). Third-party actions
  are pinned by commit hash with a version comment; zizmor enforces this.
  Reference same-repository workflows with `$/` syntax, not `./`.
- **Repository settings aren't configured here.** Merge settings, rulesets and
  required status checks live in
  [horrell-consulting/github-settings](https://github.com/horrell-consulting/github-settings)
  (`repos.yaml`). Don't change them in the GitHub UI.
- Run `prek run --all-files` before pushing (markdownlint needs Docker; the
  Terraform hooks need `terraform` and `trivy`, and CI skips them).
- Dependabot opens one monthly `tooling` PR for Actions and pre-commit hooks,
  auto-merged when every update is minor or patch. Terraform updates arrive in
  their own PR and are never auto-merged.
- Commits and PR titles use conventional commits (`feat: ...`, `ci: ...`,
  `chore(deps): ...`). Branch from `main` with a `feature/` prefix. PRs are
  squash-merged, so keep PR bodies short and focused on intent.
