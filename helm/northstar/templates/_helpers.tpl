{{- define "northstar.fullname" -}}
{{- printf "%s-%s" .Release.Name "northstar" | trunc 63 | trimSuffix "-" -}}
{{- end -}}
