# Case interview: Platform Engineering (Senior and Staff)

Deploy `recoord/testkube-samples` to Kubernetes for a team that does not know Kubernetes.

Read in this order:

1. **`docs/design.md`**: critical analysis, architecture, trade-offs, limits.
2. **`docs/runbook.md`**: run it on kind, with a verification log.

---

## The point

The requirement is not "run an app on Kubernetes". It is "a team that does not know Kubernetes
deploys without learning it". So the deliverable is a golden path:

- **Team writes:** `services/<name>/service.yaml` (name, images, ports, paths).
- **Platform renders:** namespace, quota, network policies, deployments, services, ingress, database, smoke test.
- **CI builds, ArgoCD deploys.** A deploy is a reviewed PR that bumps image tags.

---

## Layout

| Path | Purpose |
|---|---|
| `services/<name>/service.yaml` | The only file a team writes |
| `platform/charts/app/` | Golden-path Helm chart (the platform) |
| `argocd/` | Root app and add-ons; `apps/services-appset.yaml` is the onboarding mechanism |
| `bootstrap/` | ArgoCD install (pinned kustomization) |
| `kind/cluster.yaml` | The cluster as a manifest |
| `app/` | Vendored upstream app, patched (see `app/PATCHES.md`) |
| `.github/workflows/ci.yaml` | Test, chart lint, multi-arch build, deploy PR |
| `scripts/` | `local-up.sh`, `local-down.sh` |
| `docs/` | Design and runbook |

---

## Assumptions worth stating

| Assumption | Consequence if wrong |
|---|---|
| The web image is built with a relative API base (`/api`) | Upstream hardcodes `http://localhost:8080`; the patch is in `app/`, not upstream |
| Images are private on GHCR | A real cluster needs an `imagePullSecret`; locally images are loaded into kind |
| The repo is private | ArgoCD needs a repository credential (the script creates it from `gh auth token`) |
