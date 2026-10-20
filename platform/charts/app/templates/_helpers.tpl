{{- define "app.labels" -}}
app.kubernetes.io/part-of: {{ .root.Values.name }}
app.kubernetes.io/managed-by: platform
{{- end }}

{{/* Merge componentDefaults under a component. Usage: include "app.component" (dict "root" . "c" $c) */}}
{{- define "app.component" -}}
{{- toYaml (mergeOverwrite (deepCopy (include "platform.defaults" .root | fromYaml).componentDefaults) .c) -}}
{{- end }}
