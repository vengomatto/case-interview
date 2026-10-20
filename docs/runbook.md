# Runbook: MVP on kind

Why this exists: one sequence you can run in front of the interviewer, with the expected output.

Prerequisites: `docker` (running), `kind`, `kubectl`, `helm`, `gh` (logged in).

On macOS with Colima: `colima start <profile> --cpu 4 --memory 6 --disk 30`, then
`docker context use colima-<profile>`.

---

## Quick path

```bash
./scripts/local-up.sh        # cluster, images, ArgoCD, root app
./scripts/local-down.sh      # teardown
```

The script is the five steps below. Read them once so you can explain each.

---

### 1. Cluster from a manifest

```bash
kind create cluster --config kind/cluster.yaml
```

`kind/cluster.yaml` sets the cluster name, the `ingress-ready` node label and the host port
mapping `8088 -> 80`. Port 8088 needs no root on macOS.

### 2. Images

```bash
docker build -t ghcr.io/vengomatto/case-interview-api:local -f app/apps/api/Dockerfile app
docker build -t ghcr.io/vengomatto/case-interview-web:local -f app/apps/web/Dockerfile app
kind load docker-image <image> --name case-interview
```

This replaces CI plus a registry for the local run. The tag matches `services/testkube-sample/service.yaml`,
so ArgoCD cannot tell the difference.

### 3. ArgoCD

```bash
kubectl apply -k bootstrap/ --server-side
kubectl -n argocd rollout status deploy/argocd-server
```

### 4. Repository credential (the repo is private)

The script creates a Secret in `argocd` from `gh auth token`. It is never committed.

### 5. Root app (the only manual apply)

```bash
kubectl apply -f argocd/root-app.yaml
```

From here Git is the source of truth. The root app creates `ingress-nginx` and the
`services` ApplicationSet, which creates one Application per `services/*/service.yaml`.

---

## Verify

```bash
kubectl -n argocd get applications
kubectl -n testkube-sample get pods,svc,ingress,networkpolicy
curl -s http://testkube-sample.localhost:8088/api/hello?name=veo      # {"message":"hello, veo"}
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
| Network policy | `kubectl run t --rm -it --image=busybox -n default -- wget -qO- -T3 http://db.testkube-sample:5432` | Cross-namespace access to the db is denied |
| Onboard a service | Copy `services/testkube-sample` to `services/foo`, edit, push | One folder = one service |

## Preflight checks

| Check | Command | Expect |
|---|---|---|
| Image is multi-arch (after CI) | `docker manifest inspect ghcr.io/vengomatto/case-interview-api:<sha> \| grep architecture` | `amd64` and `arm64` |
| Disk | `docker system df` | At least 10 GB free |

If an image shows only `amd64` and you run on Apple Silicon, pods die with `exec format error`
and almost empty logs. It looks like a manifest bug. Fix it in CI.

## Without ArgoCD

```bash
helm template testkube-sample platform/charts/app -n testkube-sample -f services/testkube-sample/service.yaml | kubectl apply -f -
```

Sync waves are ignored, so the api may restart once while the db starts.

---

## Verification log

| Step | Status | Evidence |
|---|---|---|
| `helm lint` + `helm template` | Done | 0 failures, 11 resource kinds rendered |
| Images build (api 510 MB, web 1.4 GB) | Done | Run as uid 1000; web bundle contains `"/api"`, no `localhost:8080` |
| Cluster, ArgoCD, end-to-end | **Not done yet** | Needs the repo pushed to GitHub so ArgoCD can pull it |
