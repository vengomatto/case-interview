# Alternatives we did not choose

An analysis of the options we looked at and left out, and what would make us reconsider each one. It does not
change the design. `walkthrough.md` describes what we built; this file describes what we did not, and why.

---

## 1. A developer portal (Backstage and similar)

Backstage is an open-source framework from Spotify (a CNCF project) for building an internal developer portal.
You do not install a finished product: you build and host your own web application and add plugins.

| Backstage part | The equivalent in our design |
|---|---|
| Software Catalog (services, owners, dependencies) | The list of registered services in the platform repository |
| Software Templates (a form that creates a repository from a template) | The template repository plus the Setup service form |
| TechDocs, Kubernetes and Argo CD plugins, CI plugins | The runbook and READMEs, the Argo CD screen, GitHub Actions |

**What it would add:** one front door, a real catalog that answers "who owns this?", and a way to do the two
manual steps of a new service (walkthrough 3.2) in one run, because a portal runs with its own credentials
(a GitHub App) and our setup form holds only the repository's own token. **What it would not replace:** the
pipeline, Argo CD, the chart and the guardrails. It is the front door, not the engine.

**Why not now:** it is an application to run (upgrades, plugins, sign-in, hosting, an accurate catalog), which
costs more than the problem it solves for one team and one service. It does not shorten the first service, and the
two steps it would remove are only two steps today. Hosted Backstage and managed portals (Port, Cortex, OpsLevel)
remove the hosting or the building, at the price of a vendor and a licence.

**Reconsider when:** more than a few teams use the platform, people ask what services exist and who owns them, or
creating a service needs more than a form can hold. The design already fits: the template repository becomes a
Backstage template, and the registry list becomes the catalog source.

---

## 2. A platform orchestrator, or an abstraction layer

Our file plus chart is a small, hand-made version of a workload abstraction. Other tools offer it as a product or
a framework.

| Option | What it is | Why not chosen |
|---|---|---|
| **Score with a platform orchestrator** (Score is an open workload specification; the best-known orchestrator is a commercial product) | The team writes a standard `score.yaml`; the orchestrator decides how to run it per environment | Replaces our file and chart with a standard and a product we would depend on. Worth it when many teams and many environments need the same file to mean different things |
| **Kratix** | A framework to build platform APIs ("promises") on Kubernetes | More flexible than our chart, and it has to be installed, run and hardened by us. Right for a platform team with several kinds of service to offer |
| **Crossplane compositions as the developer API** | Teams create a resource such as "Application" and a composition expands it, cloud resources included | Strong for infrastructure (design 4.2); heavy as the only interface for a web app. We kept Helm for the workload |
| **KubeVela, Radius** | Application models with their own vocabulary and controllers | A new concept for the team to learn, which is what we avoided. |

Reconsider when the file has to describe resources beyond one web service and a database (queues, buckets,
several kinds of workload) and the schema grows into something we would be rewriting a product for.

---

## 3. Not using Kubernetes

The brief says Kubernetes, but a platform engineer should say what the alternative looks like.

| Option | What it gives | What it costs |
|---|---|---|
| **Managed container services** (Cloud Run, App Runner, ECS on Fargate) | Run a container with a port and a health check; no cluster | Lock-in to the provider, fewer controls, and a different model for network rules and previews |
| **Application platforms** (Render, Fly.io, Railway) | The shortest path from repository to URL | A vendor in the middle, limited access to the network and the data |
| **A Heroku-like layer on Kubernetes** (Knative, Cloud Foundry on Kubernetes, Dokku and Coolify on a single host) | The "one file, one URL" experience, with Kubernetes underneath | Another layer to operate, with its own limits and its own vocabulary |

For a team with no Kubernetes experience and a three-tier web application, a managed container service would
likely give the shortest time to first deploy. We kept Kubernetes because the brief requires it and because the
platform team's skills and the other workloads of the organisation are assumed to be there (assumption 1 in the
walkthrough). The contract, a small file with an image and a port, would carry over to any of these.

---

## 4. The delivery engine

| Choice | Alternative | Why we chose as we did |
|---|---|---|
| **Argo CD** | Flux | Flux is smaller and works well with Helm and OCI charts, Argo CD ships with a screen, which is how a developer who does not know Kubernetes diagnoses a release, so its UI decided it. Argo CD's ApplicationSet also gave us the service list. |
| **Pull-based, with Git as the source** | Push-based: CI runs `kubectl` or `helm` | The cluster would need credentials in CI, and drift would go unseen. Git also gives reviewable, revertable releases |
| **Helm chart plus one values file** | Kustomize only; plain manifests | Kustomize leaves Kubernetes objects in the team's hands, and cannot loop over components or validate input. We use it only to install Argo CD |
| **A pull request as the release** | Image Updater or Kargo write the tag | Simple and visible. They fit when automation is more important than a visible release step, or when several environments need promoting (design 4.5) |
| **GitHub Actions** | An external system (Jenkins, a deployment tool such as Octopus or Spinnaker) | The code, the checks and the release live in one place. A separate tool makes sense when deployment has to cover things GitHub cannot reach |
| **A separate approval step** | GitHub Environments with required reviewers | A built-in alternative for gating production. It could replace the promotion pull request if the team prefers the Actions screen to a PR |

---

## 5. Environments and the inner loop

| Choice | Alternative | Notes |
|---|---|---|
| **Namespace per preview** | A virtual cluster per preview (vCluster) | A namespace is cheaper and simpler. A virtual cluster isolates much better, which matters when a change touches cluster-wide resources (operators, CRDs, the ingress controller). It costs extra control-plane overhead per preview. Reconsider when previews have to test platform changes |
| **Docker Compose for local development** (what the sample has) | Tilt, Skaffold, DevSpace, Okteto, Garden | These run the real manifests against a cluster and reload on every save. They give a developer the same environment as production, at the price of needing a cluster and some Kubernetes vocabulary. Compose keeps the inner loop free of Kubernetes, which is the point here |
| **Previews on a shared cluster** | Previews in a separate account or cluster | Better blast-radius control; more to build. Reconsider if previews become a larger share of the load |
