{{- define "ckyc.fullname" -}}
{{ include "ckyc.name" . }}-{{ .Release.Name }}
{{- end }}

{{- define "ckyc.name" -}}
{{ .Chart.Name }}
{{- end }}

{{- define "ckyc.labels" -}}
app.kubernetes.io/name: {{ include "ckyc.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "ckyc.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ckyc.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "ckyc.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "ckyc.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
{{ .Values.serviceAccount.name }}
{{- end -}}
{{- end }}
