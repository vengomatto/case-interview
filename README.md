# A golden path for deploying a three-tier app to Kubernetes

Deploy `recoord/testkube-samples` to Kubernetes for a team that does not know Kubernetes.

## Where to start

| You want to | Open |
|---|---|
| Understand the design in plain language | [`docs/walkthrough.md`](docs/walkthrough.md): renders on GitHub, diagrams included |
| Present it | [`docs/presentation.html`](docs/presentation.html): download it and open it in a browser (GitHub shows the file as source; GitHub Pages would serve it on a public repository) |
| Check the reasoning, the numbers and the options not chosen | [`docs/design.md`](docs/design.md), [`docs/alternatives.md`](docs/alternatives.md) |
| Run it, roll back, or publish | [`docs/runbook.md`](docs/runbook.md) |

---

## Repositories

| Repo | Contents | Owner |
|---|---|---|
| `vengomatto/case-interview` (this one) | Cluster manifest, Argo CD bootstrap and add-ons, platform chart, service registry | Platform team |
| `vengomatto/testkube-samples` | Copy of upstream, patched; code, Dockerfiles, CI, `deploy/service.yaml` | App team |
| `vengomatto/service-template` | Template for a new service: pipeline, setup form, `deploy/service.yaml` placeholders | Platform team |
| `vengomatto/hello-service` | An example service generated from the template: the proof that the flow works end to end | App team |

---

## Layout (this repo)

| Path | Purpose |
|---|---|
| `kind/cluster.yaml` | The cluster as a manifest |
| `bootstrap/` | Argo CD install (pinned kustomization) |
| `argocd/root-app.yaml` | The only manual apply (app-of-apps) |
| `argocd/apps/` | Add-ons (`ingress-nginx`) and the service ApplicationSet (`services-appset.yaml`: the list of registered services) |
| `platform/charts/app/` | Golden-path chart; `templates/_platform.tpl` holds settings teams cannot override, `values.schema.json` bounds what a team can set |
| `platform/charts/app/ci/` | Fixtures: one valid service, two inputs that must be rejected |
| `scripts/` | `local-up.sh`, `local-down.sh` |
| `.github/workflows/ci.yaml` | Chart lint, guardrail tests, manifest validation |
| `docs/` | The documents above |
