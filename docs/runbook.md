# Runbook: MVP on kind

Why this exists: one sequence you can run in front of an audience, with the expected output.

Prerequisites: `docker` (running), `kind`, `kubectl`, `helm`, `gh` (logged in). The app repo is cloned next to this one (`../testkube-samples`), or set `APP_DIR`.

On macOS with Colima: `colima start <profile> --cpu 4 --memory 6 --disk 30`, then
`docker context use colima-<profile>`.

---

## Quick path

```bash
./scripts/local-up.sh        # cluster, Argo CD, root app, image pull secret
./scripts/local-down.sh      # teardown
```

The script does the steps below and finishes by creating the image pull secret. Read them once so you can explain each.

---

### 1. Cluster from a manifest

```bash
kind create cluster --config kind/cluster.yaml
```

`kind/cluster.yaml` sets the cluster name, the `ingress-ready` node label and the host port
mapping `8088 -> 80`. Port 8088 needs no root on macOS.

### 2. Images: built by CI, pulled from GHCR

You build nothing locally. The sequence before the first run:

1. Push the app repo to `main`. The workflow tests, builds `amd64` + `arm64` images and pushes `ghcr.io/vengomatto/testkube-samples-{api,web}:<sha>`.
2. The last job verifies that both images cover `amd64` and `arm64`, opens a `chore(deploy)` PR that replaces `tag: unreleased` with the SHA, and merges it. If the repository requires reviews on `main`, the merge fails and the PR stays open: merge it by hand.
3. `local-up.sh` refuses to continue while the tag is `unreleased`.

The cluster pulls from private GHCR, so it needs an `imagePullSecret` (`ghcr-pull`) built from
`gh auth token` (scope `read:packages`: `gh auth refresh -h github.com -s read:packages`).
The secret is never committed, and it can only be created after Argo CD creates the namespace.
So the script creates it last (the last step of the script) and **accepts a short `ImagePullBackOff`**: the kubelet
retries with backoff (max 5 minutes) and the pods heal once the secret exists. Argo CD shows the
app as Progressing or Degraded in the meantime. This is cosmetic; do not retry the sync.

On Apple Silicon, kind pulls the `arm64` half of the manifest list. This is the multi-arch build working.

### 3. Argo CD

```bash
kubectl apply -k bootstrap/ --server-side --force-conflicts
kubectl -n argocd rollout status deploy/argocd-server
```

Argo CD UI: `http://argocd.localhost:8088` (user `admin`). `bootstrap/` sets `server.insecure` so the
ingress can talk plain HTTP to `argocd-server`, and adds an Ingress for it. Password:
`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.
TLS is out of scope locally; in a real cluster terminate TLS at the ingress (cert-manager).

### 4. Repository credential (the repo is private)

The script creates a `repo-creds-vengomatto` Secret in `argocd` from `gh auth token`, valid for every repo under `github.com/vengomatto`. It is never committed.

### 5. Root app (the only manual apply)

```bash
kubectl apply -f argocd/root-app.yaml
```

From here Git is the source of truth. Releasing = merging a deploy PR. The root app creates `ingress-nginx` and the
`services` ApplicationSet, which creates one Application per list entry (chart from this repo, values from the app repo).

---

## Verify

```bash
kubectl -n argocd get applications
kubectl -n testkube-sample get pods,svc,ingress,networkpolicy
curl -s http://testkube-sample.localhost:8088/api/hello?name=demo     # {"message":"hello, demo"}
curl -s http://testkube-sample.localhost:8088/api/hello-pg            # {"message":"hello world from postgres"}
open http://testkube-sample.localhost:8088/
```

If `*.localhost` does not resolve: `curl --resolve testkube-sample.localhost:8088:127.0.0.1 ...`.

Smoke test result: `kubectl -n testkube-sample logs job/smoke`.

## Demos

| Demo | Command | Shows |
|---|---|---|
| Self-heal | `kubectl -n testkube-sample scale deploy/api --replicas=0`, wait 15 s, `get deploy api` | Desired state lives in Git |
| Guardrail | `kubectl -n testkube-sample run x --image=busybox -- sleep 1` | Quota and LimitRange apply defaults |
| Network policy | `kubectl run t --rm -it --image=busybox -n default -- wget -qO- -T3 http://db.testkube-sample:5432` | Cross-namespace access to the db should be denied. Not verified: whether this cluster enforces network policies, so check first |
| Onboard a service | Add `deploy/service.yaml` to an app repo, add one list entry to `argocd/apps/services-appset.yaml` | One file + one reviewed PR |
| Guardrail holds | Add `guardrails:` or `tag: latest` to a `service.yaml` | `helm lint` rejects it (see `platform/charts/app/ci/`) |

## Rollback

One procedure for any service and any environment. A release is a Git commit that changes image tags,
so a rollback is a Git revert. You do not need `kubectl`, and you do not need to know which cluster it runs on.

### 1. Decide: roll back or fix forward

| Situation | Choose |
|---|---|
| The smoke test failed, or the app is down or clearly broken | Roll back now, investigate afterwards |
| A small bug with a known one-line fix and a fast pipeline | Fix forward |
| The release included a database migration | Stop. Check "What a rollback does not undo" first |

### 2. Roll back

1. Open the deploy PR (`chore(deploy): <sha>`). Its comment lists the previous tag.
2. Click **Revert** on the merged PR. GitHub opens a new PR that restores the previous tag in `deploy/service.yaml`.
3. Merge the revert PR.
4. The cluster syncs the old tag by itself (auto-sync). If the environment uses manual sync, press **Sync** in Argo CD.
5. Verify: the Application is **Synced** and **Healthy**, and the smoke test passed (it runs after every sync that applies a change).

Command-line equivalent: `git revert <merge-commit-of-the-deploy-pr>`, push it as a PR, merge it.

### 3. What a rollback does not undo

| Not undone | What to do |
|---|---|
| Database schema or data changes | Prefer backward-compatible migrations (add, then remove later), so the old version still works with the new schema |
| Changes in other repositories (platform chart, other services) | Roll those back in their own repository |
| Secrets and external resources | Restore them from their own source |
| Messages already published or emails already sent | Handle as an incident, not as a rollback |

### 4. Preconditions

| Needs | Why |
|---|---|
| Immutable SHA tags in the registry | The old image must still exist. Never reuse or overwrite a tag |
| A registry retention rule that keeps the last releases | A cleanup rule must not delete the image you need to return to |
| The previous tag in Git | It is, in the deploy PR and in its comment |

### 5. If the platform changed, not the app

The chart is shared. If a platform change broke a service, revert the commit in the platform repo.
Once the chart is pinned per service (design 4.6), revert the `chartVersion` bump for that service instead.

### 6. Break glass (only when Git is unavailable)

Argo CD self-heal reverts any manual change, so a manual `kubectl rollout undo` is undone within seconds.
In a real emergency: pause auto-sync for that Application, roll back by hand, then make the Git revert
and re-enable auto-sync. Write down every manual step.

## When a deploy is red

Where to look, in this order: the GitHub Actions run, the deploy pull request, the Application in Argo CD (`argocd.localhost:8088` here), the pod's **Logs** and **Events** tabs. You do not need `kubectl`. In Argo CD, **Synced** means the cluster matches Git, **Healthy** means everything that should run is running, and **Degraded** means something failed: click the red item.

| What you see | Likely cause | What to do |
|---|---|---|
| Web pods in `CrashLoopBackOff`, log says `EACCES` | The image writes to a folder owned by root and the pod runs as a normal user | Pod Logs tab shows the line; fix the Dockerfile (done in this project) |
| Site returns **404** but pods are running | The Ingress is created last (sync wave 40); an earlier wave is not healthy, so it does not exist yet | In the resource tree the Ingress is missing and an earlier item is red: fix that one |
| Application stays **OutOfSync** | The chart left a field the API server fills in itself | Platform issue; report it (fixed here for the database volume) |
| `ImagePullBackOff` | The tag does not exist or the registry credential is missing | Check the tag in `deploy/service.yaml`; confirm the image exists; ask the platform team about the pull secret |
| Pod **Pending**, event "exceeded quota" | The namespace quota is full | Lower replicas or resources, or ask for more |
| **502 / 503** | No pod is ready (readiness probe failing) | Events tab: "Readiness probe failed" |
| Smoke test red | The named endpoint failed (for example `/hello-pg`: the database is unreachable) | Open the smoke Job logs, then roll back |
| Deploy PR left open | The app repo requires reviews | Approve and merge it |
| Smoke test never ran | Hooks run only in a sync that applies changes; a no-op sync skips them | Trigger a real sync |

---

## Publishing the repositories (public showcase)

A review gate on `main` is optional. A visitor to a public repository cannot push to `main` without write access, and a
fork pull request cannot merge itself, so the gate adds protection only against your own mistakes or a stolen token.
This is what the gate does to the flow, and the settings to use if you want it. Settings live in the repository, not in Git, so they are
commands or clicks, not files.

### What breaks and what does not

| Part of the flow | With "require 1 approval" on `main` |
|---|---|
| Your own feature PRs | Work, but you cannot approve your own PR. Add yourself (repository admin) to the ruleset **bypass list** and merge as admin, or use a second account |
| Deploy PR from CI (image tag bump) | **Degrades to a human gate, does not break.** The merge step fails, the job falls back to a queued merge or to leaving the PR open, stays green, and comments on the PR "Waiting for review". The PR author is the bot, so **you can approve it**. One click, then Argo CD syncs |
| Required status checks | **Stall.** Events from `GITHUB_TOKEN` do not trigger workflows, and `deploy/**` is path-ignored, so the deploy PR never gets its checks. Do not require status checks until CI uses a GitHub App token (design 4.1) |
| Pull requests from forks (visitors) | Tests and image builds run without secrets and without pushing; the deploy job is skipped. They cannot merge |
| Argo CD reading the repos | No credential needed for public repositories (see below) |

If you enable the gate, the image-tag step needs one approval (accepted trade-off). The PR comment tells the reviewer what changed
and how to roll back, so the approval is quick. A GitHub App added to the ruleset bypass list restores full
automation of the release pull request (design 4.5).

### Settings (both repositories)

| Setting | Value | Why |
|---|---|---|
| Ruleset or branch protection on `main` (optional) | Require a pull request; require 1 approval; block force pushes and deletion; bypass list: you (admin) | A mistake or a stolen token cannot change `main` alone; you can still work |
| Allow auto-merge (app repo) | On | The deploy job queues the merge and it completes right after your approval |
| Actions: fork pull request workflows | Require approval for all outside collaborators | A first-time visitor cannot run workflows unreviewed |
| Actions: workflow permissions | Default read-only; the workflows ask for more per job | Least privilege |
| Allow GitHub Actions to create and approve pull requests (app repo) | On, because the deploy job opens PRs | It also lets a workflow approve PRs. Keep the number of people who can change workflows small |
| Secret scanning and push protection | On (default for public repositories) | Catches pasted tokens |

Commands for the app repo (run them yourself; the second needs the setting to exist for the first PR):

```bash
gh api -X PATCH repos/<owner>/testkube-samples -F allow_auto_merge=true
gh api -X PUT repos/<owner>/testkube-samples/actions/permissions/workflow -F can_approve_pull_request_reviews=true
```

### Running the demo from the public repositories

| Item | Detail |
|---|---|
| Argo CD credential | Not needed: public repositories are readable anonymously. `local-up.sh` still creates one from your `gh` token; for a public setup remove that step so no personal token enters the cluster |
| Image pull secret | Needed only while the GHCR packages are private. Set the two packages (`testkube-samples-api`, `testkube-samples-web`) to public in the package settings and the secret step disappears too |
| Visitors who want to run it | They need images they can pull (public packages) and `kind`, `kubectl`, `docker` and `gh` (the script calls `gh auth token`; see the first row). The rest of the quick path works unchanged |
| Wording in the docs | Replace "private" in the README repository table and the design quick reference when you switch visibility |

## Adding another service on the demo cluster

After the registration pull request is merged, Argo CD creates the namespace named after the service. Its
pods cannot pull images from the private registry until the namespace has the pull secret. This one command is
the manual step; run it once per service namespace (replace `<service>`):

```bash
kubectl -n <service> create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username=vengomatto --docker-password="$(gh auth token)"
```

The pods show `ImagePullBackOff` until the secret exists and then recover by themselves. It is manual because a
secret cannot live in Git, and a cluster-wide copy needs an extra component (a secret replicator or an admission
policy). Production answers: node permissions to the registry, a replicated or externally managed secret, or
public images.

## Preflight checks

| Check | Command | Expect |
|---|---|---|
| Image is multi-arch (after CI) | `docker manifest inspect ghcr.io/vengomatto/testkube-samples-api:<sha> \| grep architecture` | `amd64` and `arm64` |
| Disk | `docker system df` | At least 10 GB free |

If an image shows only `amd64` and you run on Apple Silicon, pods die with `exec format error`
and almost empty logs. It looks like a manifest bug. Fix it in CI.

## Without Argo CD

```bash
helm template testkube-sample platform/charts/app -n testkube-sample -f ../testkube-samples/deploy/service.yaml | kubectl apply -f -
```

Sync waves are ignored, so the api may restart once while the db starts.

---

## Verification log

| Step | Status | Evidence |
|---|---|---|
| `helm lint` + `helm template` | Done | 0 failures; valid fixture renders; `bad-override-guardrail` and `bad-latest-tag` are rejected |
| Images build locally (api 510 MB, web 1.4 GB) | Done | Run as uid 1000; web bundle contains `"/api"`, no `localhost:8080` |
| CI build, push to GHCR, deploy PR | Done | Deploy PR opened and merged; images pulled from private GHCR by kind |
| Cluster, Argo CD, end-to-end | Done | App reachable at `testkube-sample.localhost:8088`; Argo CD Synced and Healthy |
| PostSync smoke test | Done | `hurl`: 3 requests, 100% succeeded (triggered by a real sync) |
| Bug found while running | Fixed | `vite preview` needs a writable dir as uid 1000; PVC template defaults caused permanent OutOfSync |
