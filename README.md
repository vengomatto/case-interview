# Case interview: Platform Engineering (Senior and Staff)

Deploy `recoord/testkube-samples` to Kubernetes for a team that does not know Kubernetes.

Read in this order:

1. **`docs/design.md`**: critical analysis, architecture, trade-offs, limits.
2. **`docs/runbook.md`**: run it on kind, with a verification log.

---

## The point

The requirement is not "run an app on Kubernetes". It is "a team that does not know Kubernetes
deploys without learning it". So the deliverable is a golden path:

- **Team writes:** `deploy/service.yaml` in its own app repo (name, images, ports, paths).
- **Platform renders:** namespace, quota, network policies, deployments, services, ingress, database, smoke test.
- **CI builds, ArgoCD deploys.** A deploy is a reviewed PR that bumps image tags.

---

## Two repos

| Repo | Contents | Owner |
|---|---|---|
| `vengomatto/case-interview` (this one) | Cluster manifest, ArgoCD bootstrap and add-ons, platform chart, service registry | Platform team |
| `vengomatto/testkube-samples` | Copy of upstream, patched; code, Dockerfiles, CI, `deploy/service.yaml` | App team |

Why two: the platform and the app have different owners and different release rhythms.
Why `service.yaml` sits in the app repo: the team changes its ports, paths and env vars next to
its code, and CI's tag-bump PR stays inside one repo (no cross-repo token). The platform repo
registers the service (one list entry in `argocd/apps/services-appset.yaml`) and bounds what a
team can set (`platform/charts/app/values.schema.json`).

---

## Layout (this repo)

| Path | Purpose |
|---|---|
| `kind/cluster.yaml` | The cluster as a manifest |
| `bootstrap/` | ArgoCD install (pinned kustomization) |
| `argocd/root-app.yaml` | The only manual apply (app-of-apps) |
| `argocd/apps/` | Add-ons (`ingress-nginx`) and the service ApplicationSet |
| `platform/charts/app/` | Golden-path chart; `templates/_platform.tpl` holds settings teams cannot override |
| `platform/charts/app/ci/` | Fixtures: one valid service, two inputs that must be rejected |
| `scripts/` | `local-up.sh`, `local-down.sh` |
| `.github/workflows/ci.yaml` | Chart lint, guardrail tests, manifest validation |
| `docs/` | Design and runbook |

---

## Assumptions worth stating

| Assumption | Consequence if wrong |
|---|---|
| The web image is built with a relative API base (`/api`) | Upstream hardcodes `http://localhost:8080`; the patch is a commit in the app repo, not upstream |
| Images are private on GHCR | A real cluster needs an `imagePullSecret`; locally images are loaded into kind |
| Both repos are private | ArgoCD needs a credential (the script creates a `repo-creds` Secret from `gh auth token`) |
