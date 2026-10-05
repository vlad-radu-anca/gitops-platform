{{/*
Shared sync policy. ServerSideApply avoids the annotation size limit that the
large CRDs (Prometheus, Gateway API) would otherwise hit, and the retry covers
the short window where a CRD exists but its API is not served yet.
*/}}
{{- define "apps.syncPolicy" -}}
automated:
  prune: true
  selfHeal: true
syncOptions:
  - CreateNamespace=true
  - ServerSideApply=true
retry:
  limit: 10
  backoff:
    duration: 10s
    factor: 2
    maxDuration: 3m
{{- end }}

{{- define "apps.destination" -}}
server: https://kubernetes.default.svc
namespace: {{ . }}
{{- end }}
