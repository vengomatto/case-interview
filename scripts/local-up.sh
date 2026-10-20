#!/usr/bin/env bash
# Local bootstrap: cluster (from manifest) -> ArgoCD -> root app -> pull secret.
# Needs: docker (running), kind, kubectl, gh (logged in, scopes repo + read:packages).
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=case-interview
# The app lives in its own repo (sibling clone by default).
APP_DIR=${APP_DIR:-$(cd .. && pwd)/testkube-samples}
SERVICE=$APP_DIR/deploy/service.yaml
GH_OWNER=https://github.com/vengomatto
[ -f "$SERVICE" ] || { echo "missing $SERVICE (set APP_DIR)"; exit 1; }

echo "==> 1. Cluster from kind/cluster.yaml"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "    already exists"
else
  kind create cluster --config kind/cluster.yaml
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

echo "==> 2. Check that CI has released an image"
# Images are built by CI in the app repo and pulled from GHCR, as in a real cluster.
NS=$(awk '$1=="name:"{print $2; exit}' "$SERVICE")
TAG=$(awk '$1=="tag:"{print $2; exit}' "$SERVICE")
if [ "$TAG" = "unreleased" ]; then
  echo "    $SERVICE still has tag 'unreleased': merge the deploy PR in the app repo first"; exit 1
fi

echo "==> 3. ArgoCD"
kubectl apply -k bootstrap/ --server-side --force-conflicts >/dev/null
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-applicationset-controller --timeout=300s

echo "==> 4. Repo credential template (private repos; not stored in Git)"
# One credential for every repo under the owner URL prefix: platform repo and app repos.
kubectl -n argocd create secret generic repo-creds-vengomatto \
  --from-literal=type=git --from-literal=url="$GH_OWNER" \
  --from-literal=username=vengomatto --from-literal=password="$(gh auth token)" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n argocd label secret repo-creds-vengomatto argocd.argoproj.io/secret-type=repo-creds --overwrite >/dev/null

echo "==> 5. Root app (the only manual apply)"
kubectl apply -f argocd/root-app.yaml

echo "==> 6. Pull secret for private GHCR images"
# Known caveat: ArgoCD creates the namespace, then the pods fail with ImagePullBackOff
# until this secret exists. The kubelet retries with backoff (max 5 min), so they heal
# by themselves. Needs the read:packages scope: gh auth refresh -h github.com -s read:packages
# In production this step disappears: External Secrets / a replicated secret / node IAM (ECR).
echo "    waiting for namespace $NS (created by ArgoCD)"
for _ in $(seq 1 60); do
  kubectl get namespace "$NS" >/dev/null 2>&1 && break
  sleep 5
done
kubectl get namespace "$NS" >/dev/null 2>&1 || { echo "    namespace $NS not created after 5 min: kubectl -n argocd get applications"; exit 1; }
kubectl -n "$NS" create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username=vengomatto --docker-password="$(gh auth token)" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "Done. Watch: kubectl -n argocd get applications -w"
echo "ArgoCD UI:  http://argocd.localhost:8088   (user admin; password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo "App:        http://testkube-sample.localhost:8088/"
