{{/*
Platform-owned settings. They are constants here, NOT values, on purpose: a team
controls the values file (it lives in the app repo), so anything a team must not
change cannot be a value. values.schema.json rejects unknown keys.
*/}}
{{- define "platform.defaults" -}}
ingressClassName: nginx
imagePullPolicy: IfNotPresent
databaseImage: postgres:16-alpine
componentDefaults:
  replicas: 2
  path: /
  health: /
  resources:
    requests: {cpu: 50m, memory: 128Mi}
    limits: {cpu: 500m, memory: 256Mi}
guardrails:
  quota:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    persistentvolumeclaims: "2"
  limitRange:
    default: {cpu: 250m, memory: 256Mi}
    defaultRequest: {cpu: 50m, memory: 64Mi}
    max: {cpu: "2", memory: 2Gi}
{{- end }}
