#!/usr/bin/env bash
# Local bootstrap: cluster (from manifest) -> images -> ArgoCD -> root app.
# Needs: docker (running), kind, kubectl, gh (logged in, repo access).
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=case-interview
SERVICE=services/testkube-sample/service.yaml
REPO_URL=https://github.com/vengomatto/case-interview

echo "==> 1. Cluster from kind/cluster.yaml"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "    already exists"
else
  kind create cluster --config kind/cluster.yaml
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

echo "==> 2. Build images with the tag that Git declares, load them into the node"
# Local stand-in for CI + registry: same image names and tags as $SERVICE, so
# ArgoCD sees exactly what a registry pull would have given it.
for c in api web; do
  image=$(awk -v c="$c" '$1==c":"{f=1} f&&$1=="image:"{print $2; exit}' "$SERVICE")
  tag=$(awk -v c="$c" '$1==c":"{f=1} f&&$1=="tag:"{print $2; exit}' "$SERVICE")
  docker build -q -t "$image:$tag" -f "app/apps/$c/Dockerfile" app
  kind load docker-image "$image:$tag" --name "$CLUSTER"
done

echo "==> 3. ArgoCD"
kubectl apply -k bootstrap/ --server-side --force-conflicts >/dev/null
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-applicationset-controller --timeout=300s

echo "==> 4. Repo credential (private repo; not stored in Git)"
kubectl -n argocd create secret generic repo-case-interview \
  --from-literal=type=git --from-literal=url="$REPO_URL" \
  --from-literal=username=vengomatto --from-literal=password="$(gh auth token)" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n argocd label secret repo-case-interview argocd.argoproj.io/secret-type=repository --overwrite >/dev/null

echo "==> 5. Root app (the only manual apply)"
kubectl apply -f argocd/root-app.yaml

echo "Done. Watch: kubectl -n argocd get applications -w"
echo "App:        http://testkube-sample.localhost:8088/"
