# Changes against upstream

Vendored from `recoord/testkube-samples` at `a21ed43` (see `UPSTREAM_COMMIT`).

| File | Change | Why |
|---|---|---|
| `apps/web/src/App.tsx` | `API_ORIGIN` constant replaced by build-time `VITE_API_BASE` + `apiUrl()` helper | Upstream hardcodes `http://localhost:8080`; behind an ingress, `localhost` is the visitor's own machine |
| `apps/web/Dockerfile` | `ARG VITE_API_BASE=/api` | Relative base by default |
| `docker-compose.yaml` | Passes `VITE_API_BASE=http://localhost:8080` to the web build | Keeps the compose flow working (no ingress there) |
| `apps/api/k8s/` | Removed | Broken (expired image, no DB env, Ingress backend `demo` does not exist); replaced by `platform/charts/app` |
| `apps/*/Dockerfile` | Base `node:lts` -> `node:lts-slim` | Images drop from 1.8-2.7 GB to a few hundred MB: faster CI and pulls, fewer CVEs. Nothing here needs build tools |
