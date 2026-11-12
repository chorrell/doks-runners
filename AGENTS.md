# AGENTS.md

Self-hosted GitHub Actions runners on DigitalOcean Kubernetes (DOKS): a
low-cost build fleet that can stay up all the time, with a 32-vCPU build pool
that scales to zero between jobs. See [README.md](README.md) for the design,
cost model and roadmap. The AWS version of the same idea is
[eks-spot-runners](https://github.com/chorrell/eks-spot-runners).

## Structure

```text
├── terraform/                  # (planned) DOKS cluster, system pool, build pool, Spaces bucket, ARC Helm release
├── kubernetes/                 # (planned) runner scale set values
├── .pre-commit-config.yaml     # gitleaks, markdownlint-cli2 (Docker), hygiene hooks, zizmor, terraform fmt/validate/trivy
├── .markdownlint.yaml          # MD013 (line length) disabled
├── AGENTS.md / CLAUDE.md       # Agent guidance; CLAUDE.md only imports AGENTS.md
├── LICENSE                     # MPL-2.0
└── .github/
    ├── CODEOWNERS              # * @chorrell
    ├── dependabot.yml          # `tooling` group (Actions + pre-commit) plus a separate terraform entry
    ├── zizmor.yml              # chorrell/* may be tag-pinned; everything else hash-pinned
    └── workflows/              # Stubs calling chorrell/workflows (markdownlint, pre-commit, zizmor, automerge)
```

## Rules

- **Keep the always-on cost low.** The only things running between jobs are
  the free control plane, one small system node and the Spaces bucket. No HA
  control plane, no load balancers, no always-on build nodes. If a change adds
  a cost that runs while idle, call it out in the PR.
- **The build pool must scale to zero.** A 32-vCPU node left running costs
  about $670/month. If autoscaler scale-to-zero isn't reliable, the workflow
  scales the pool with `doctl` and must scale it back down even when the build
  fails.
- **amd64 builds here; arm64 stays on GitHub's hosted arm runners** unless
  DigitalOcean offers ARM droplets.
- **Never run fork pull requests on these runners.** The runner scale set is
  scoped to named repositories, and example workflows only run on push or
  `workflow_dispatch`.
- **No secrets in the repo.** ARC uses a GitHub App; Spaces keys are scoped to
  the cache bucket and stored as repository secrets. Variable files with values
  (`*.auto.tfvars`) are gitignored. Don't create DigitalOcean resources outside
  Terraform.
- Cost figures in the README are estimates with a date; replace them with
  measured numbers as builds run, and say which are which.
- **Reusable workflows live in [chorrell/workflows](https://github.com/chorrell/workflows).**
  Workflows here are stubs that call them by tag (`@v1`). Third-party actions
  are pinned by commit hash with a version comment; zizmor enforces this.
  Reference same-repository workflows with `$/` syntax, not `./`.
- **Repository settings aren't configured here.** Merge settings, rulesets and
  required status checks live in
  [chorrell/github-settings](https://github.com/chorrell/github-settings)
  (`repos.yaml`). Don't change them in the GitHub UI.
- Run `prek run --all-files` before pushing (markdownlint needs Docker; the
  Terraform hooks need `terraform` and `trivy`, and CI skips them).
- Dependabot opens one monthly `tooling` PR for Actions and pre-commit hooks,
  auto-merged when every update is minor or patch. Terraform updates arrive in
  their own PR and are never auto-merged.
- Commits and PR titles use conventional commits (`feat: ...`, `ci: ...`,
  `chore(deps): ...`). Branch from `main` with a `feature/` prefix. PRs are
  squash-merged, so keep PR bodies short and focused on intent.
