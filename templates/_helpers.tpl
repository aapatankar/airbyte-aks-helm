{{/*
Expand the name of the chart.
*/}}
{{- define "airbyte-aks.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "airbyte-aks.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "airbyte-aks.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "airbyte-aks.labels" -}}
helm.sh/chart: {{ include "airbyte-aks.chart" . }}
{{ include "airbyte-aks.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "airbyte-aks.selectorLabels" -}}
app.kubernetes.io/name: {{ include "airbyte-aks.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "airbyte-aks.serviceAccountName" -}}
{{- if .Values.security.serviceAccount.create }}
{{- default (include "airbyte-aks.fullname" .) .Values.security.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.security.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Generate Azure-specific annotations for Workload Identity
*/}}
{{- define "airbyte-aks.workloadIdentityAnnotations" -}}
{{- if .Values.azure.workloadIdentity.enabled }}
azure.workload.identity/use: "true"
{{- if .Values.security.serviceAccount.annotations }}
{{- range $key, $value := .Values.security.serviceAccount.annotations }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate node selector for AKS
*/}}
{{- define "airbyte-aks.nodeSelector" -}}
{{- if .Values.aks.nodeSelector }}
{{- toYaml .Values.aks.nodeSelector }}
{{- end }}
{{- end }}

{{/*
Generate resource requirements
*/}}
{{- define "airbyte-aks.resources" -}}
{{- $component := . -}}
{{- if hasKey $.Values.aks.resources $component }}
resources:
{{- toYaml (index $.Values.aks.resources $component) | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate Azure Storage configuration
*/}}
{{- define "airbyte-aks.azureStorage" -}}
{{- if eq .Values.global.storage.type "azure" }}
storage:
  type: azure
  azure:
    storageAccountName: {{ .Values.global.storage.azure.storageAccountName }}
    containerName: {{ .Values.global.storage.azure.containerName }}
{{- if .Values.global.storage.azure.storageAccountKeySecretKey }}
    storageAccountKeySecretKey: {{ .Values.global.storage.azure.storageAccountKeySecretKey }}
{{- end }}
{{- end }}
{{- end }}
