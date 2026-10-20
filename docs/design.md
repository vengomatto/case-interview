# Design: deploying testkube-samples to Kubernetes

Case interview, Platform Engineering (Senior and Staff) -- Francesco Nassano

Deliverable: a repeatable way to run `recoord/testkube-samples` on Kubernetes,
usable by a team that does not know Kubernetes.

Every statement that cannot be verified from the repository is marked **[assumption]**.

---

## 1. Critical analysis of the requirements

The brief has three sentences of requirements. Each one hides a decision.

| # | Requirement (from the brief) | What it really means | Design answer | Cost / risk |
|---|---|---|---|---|
| 1 | "The team ... are not familiar with [Kubernetes]" | The adoption surface is the product. Success = number of Kubernetes concepts a developer must learn. Target: zero. | One file per service (`services/<name>/service.yaml`): name, images, ports, paths. The platform chart renders everything else. | The chart is now a product: it needs an owner, versions and an escape hatch for teams that outgrow it. |
| 2 | "create the required deployment tooling" | Deploy is a pipeline, not a command. It must be repeatable, auditable and reversible. | CI builds and never deploys. A deploy is a PR that changes image tags. ArgoCD pulls after merge. | Two moving parts (CI, ArgoCD) and a PR per release. Slower than `kubectl apply`, safer. |
| 3 | "crafting a great developers' experience" | Fast feedback, and failures visible where the developer looks. | PostSync smoke test (hurl) per release, per-PR image build, same Dockerfiles for compose and cluster. | Smoke tests only cover what the team lists. They are not a test strategy. |
| 4 | "all their work is available at ..." (implicit) | The app was not written for Kubernetes. Some defects are not deployment problems. | Fix the app where the defect is (see section 2), do not hide it with platform tricks. | The platform repo now carries a patched copy of the app. See section 6. |

The requirement that decides the outcome is **#1**. The rest of the design follows from it.

---

## 2. What I found in the repo (facts, not opinions)

The app is three-tier: React/Vite (web, port 4173), Node/Express (api, port 8080) and
Postgres. It uses `turbo` and npm workspaces. Tests: `vitest` (api), `hurl` (HTTP), `cypress`
(web). The e2e tests run against an app that is already up.

| # | Defect | Evidence | Effect |
|---|---|---|---|
| 1 | Image `ttl.sh/wito-hello-app:1h` | `apps/api/k8s/deployment.yml` | Third-party image with a 1 hour TTL. Any deploy is broken by construction. |
| 2 | No `DB_HOST` / `DB_PORT` in the Pod | same file; the api defaults to `localhost:15432` | `/hello-pg` always fails. |
| 3 | Ingress backend `demo` | `apps/api/k8s/ingress.yml` | Service `demo` does not exist (the Service is `hello-app`). |
| 4 | `API_ORIGIN = "http://localhost:8080"` | `apps/web/src/App.tsx` | The browser runs the code, so `localhost` is the visitor's machine. Never works behind an ingress. |

Defect 4 is the interesting one. It is not a Kubernetes problem. No manifest can fix it.

---

## 3. Architecture

```
developer --PR--> GitHub repo ---------------------------+
                     |                                    |
                     | push to main (app/** changed)      | PR merged (service.yaml changed)
                     v                                    v
              GitHub Actions                          ArgoCD (in cluster)
              test, build multi-arch,                 pulls repo, renders chart,
              push image :<sha>,                      applies, runs smoke test
              open deploy PR  ------ review/merge --->
```

1. **CI (push-based, builds only).** Test, build `linux/amd64` and `linux/arm64`, push `:<commit sha>`,
   open a PR that bumps the tag. CI holds no cluster credential.
2. **CD (pull-based, ArgoCD).** The cluster pulls. Drift is corrected automatically (`selfHeal`).
3. **Golden path.** An `ApplicationSet` (git files generator) reads `services/*/service.yaml`.
   The same file is the Helm values file for `platform/charts/app`. Onboarding = one folder.
4. **Platform add-ons are Git too.** `ingress-nginx` is an ArgoCD Application, not a
   `kubectl apply` of a third-party URL.
5. **Cluster as a manifest.** `kind/cluster.yaml` defines the cluster (name, node label,
   host port). `bootstrap/` installs ArgoCD from a pinned kustomization.

What a developer does:

| Task | Developer action | Kubernetes concepts needed |
|---|---|---|
| Ship a code change | Merge to `main`, then merge the generated deploy PR | 0 |
| Add a service | Add `services/<name>/service.yaml` | 0 (ports, paths, env) |
| Add an env var | Edit `env:` in `service.yaml` | 0 |
| See why a release failed | Open ArgoCD, read the smoke test log | 1 (a failed Job) |

What the platform renders for each service: Namespace (Pod Security `baseline`), ResourceQuota,
LimitRange, default-deny NetworkPolicy plus explicit allows, Deployment + Service + Ingress per
component, Postgres StatefulSet (optional), PostSync smoke test.

Sync waves: `-10` namespace, `-5` guardrails, `10` db, `20` api, `30` web, `40` ingress, then PostSync.
Ordering is explicit instead of "hope the retry policy sorts it out".

---

## 4. Trade-offs

| Decision | Chosen | Rejected | Why |
|---|---|---|---|
| Frontend to API | Relative `/api` + one Ingress host | Separate API host; runtime-rewriting sidecar | One host, no CORS, no runtime config. Needs a build-time change in the app (section 6). |
| Abstraction | Helm chart + one values file | Raw manifests; Kustomize only; custom CLI | Native in ArgoCD, widely known, values file is a clean team interface. Cost: Go templates are unfriendly. |
| Deploy trigger | PR that bumps tags | CI pushes to `main`; CI runs `kubectl` | A deploy is reviewable and revertable. No cluster credentials in CI. |
| Database | StatefulSet + PVC | Operator (CloudNativePG); managed service | Honest for a demo. In production this is an ownership decision, not a technical one. |
| Image base | `node:lts-slim` | `node:lts` | 1.8 GB to 510 MB (api). Nothing in the app needs build tools. |
| Cluster tool | kind | minikube | Control plane as plain containers, `extraPortMappings` gives a host port without `minikube tunnel` (awkward on macOS), no VM. |
| Tests | One PostSync smoke Job | Full Testkube | The repo targets Testkube, but the brief is about deployment. Smoke tests are the cheapest verification that deploy worked. |

Multi-arch builds: QEMU makes the arm64 leg slower. The alternative (native arm64 runners) is
faster and not available on every plan. A single-arch image is a latent `exec format error`
for the first developer with an Apple Silicon laptop.

---

## 5. Guardrails

The platform applies them. The team does not request them.

| Guardrail | Effect |
|---|---|
| Pod Security Admission `baseline` (warn `restricted`) | Blocks privileged pods. |
| ResourceQuota | One team cannot take the cluster. |
| LimitRange | A container without resources gets defaults. Best single guard against a noisy neighbour. |
| NetworkPolicy default-deny (ingress) | Pods are unreachable unless the chart allows it. |
| Container security context | Non-root (uid 1000), no privilege escalation, all capabilities dropped. |

Note: kind's default CNI enforces NetworkPolicy. Verify on your version (runbook step 5).

---

## 6. Limits and what I did NOT do

| Item | Status | Why |
|---|---|---|
| Frontend patch lives in this repo (`app/`) | Compromise | I cannot push to `recoord/testkube-samples`. In a real engagement the fix goes upstream and `app/` disappears. See `app/PATCHES.md`. |
| Single repo for app and platform | Compromise | The ideal is separate repos (app / desired state). One repo keeps the MVP small. CI path filters prevent loops. |
| Cluster creation | Manifest, not controller | `kind/cluster.yaml` is declarative, but `kind create cluster` is still a command. A fully declarative cluster (Cluster API, Crossplane) needs a management cluster that already exists. The chicken-and-egg problem moves, it does not disappear. |
| Private registry pull | Not solved | CI pushes to private GHCR. A real cluster needs an `imagePullSecret` or public packages. Locally I load images into the node. |
| Secrets | Demo credentials in the chart | Use External Secrets or Sealed Secrets. Same as upstream `docker-compose.yaml`. |
| PR preview environments | Not done | Out of scope for an MVP. First item in future work. |
| Canary / Argo Rollouts | Not done | A stateless sample with no traffic. It would be theatre. |
| Web image size | 1.4 GB | `vite preview` needs `node_modules`. A multi-stage build serving static files would be about 50 MB. |
| Readiness | Checks `/hello`, not the database | Upstream has no `/healthz`. The smoke test covers `/hello-pg`. |

---

## 7. Future work (ordered by value/cost)

1. **Preview environments per PR**: `ApplicationSet` PR generator, one namespace per PR, TTL for abandoned ones.
2. **Secrets**: External Secrets or Sealed Secrets.
3. **Policy as code**: Kyverno forbids `latest`, requires limits and labels. Today these are conventions.
4. **Chart versioning**: publish the chart, pin a version per service, so a platform change does not hit every team at once.
5. **Progressive delivery**: Argo Rollouts with an AnalysisTemplate on error rate.
6. **Service catalog**: from "folder per service" to real self-service (Backstage).

---

## 8. How I demonstrate it

`docs/runbook.md`. In short: `scripts/local-up.sh`, then `curl` through the ingress, then the
self-heal demo (`kubectl scale deploy/api --replicas=0`, back to 2 replicas in about 15 seconds).

---

## 9. Verification status

See the "Verification log" in `docs/runbook.md` for what was executed and what was not.
