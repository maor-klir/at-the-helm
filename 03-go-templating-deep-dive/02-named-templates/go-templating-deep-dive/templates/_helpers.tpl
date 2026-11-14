{{- define "go-templating-deep-dive.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-"  -}}
{{- end -}}

{{- define "go-templating-deep-dive.selectorLabels" -}}
app: {{ .Chart.Name }}
release: {{ .Release.Name }}
managed-by: "helm"
{{- end -}}