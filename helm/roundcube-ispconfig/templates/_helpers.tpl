{{/*
Expand the name of the chart.
*/}}
{{- define "roundcube.name" -}}
{{- $ctx := . -}}
{{- if .context -}}
{{- $ctx = .context -}}
{{- end -}}
{{- default $ctx.Chart.Name $ctx.Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "roundcube.fullname" -}}
{{- $ctx := . -}}
{{- if .context -}}
{{- $ctx = .context -}}
{{- end -}}
{{- if $ctx.Values.fullnameOverride -}}
{{- $ctx.Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default $ctx.Chart.Name $ctx.Values.nameOverride -}}
{{- if contains $name $ctx.Release.Name -}}
{{- $ctx.Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" $ctx.Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "roundcube.chart" -}}
{{- $ctx := . -}}
{{- if .context -}}
{{- $ctx = .context -}}
{{- end -}}
{{- printf "%s-%s" $ctx.Chart.Name $ctx.Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels (replaces common.labels.standard)
Usage: {{ include "roundcube.labels.standard" . }}
   or: {{ include "roundcube.labels.standard" (dict "context" $ "customLabels" .Values.commonLabels) }}
*/}}
{{- define "roundcube.labels.standard" -}}
{{- $ctx := . -}}
{{- if .context -}}
{{- $ctx = .context -}}
{{- end -}}
helm.sh/chart: {{ include "roundcube.chart" $ctx }}
{{ include "roundcube.labels.matchLabels" $ctx }}
{{- if $ctx.Chart.AppVersion }}
app.kubernetes.io/version: {{ $ctx.Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ $ctx.Release.Service }}
{{- if .customLabels }}
{{ include "roundcube.tplvalues.render" (dict "value" .customLabels "context" $ctx) }}
{{- end -}}
{{- end -}}

{{/*
Selector labels (replaces common.labels.matchLabels)
*/}}
{{- define "roundcube.labels.matchLabels" -}}
{{- $ctx := . -}}
{{- if .context -}}
{{- $ctx = .context -}}
{{- end -}}
app.kubernetes.io/name: {{ include "roundcube.name" $ctx }}
app.kubernetes.io/instance: {{ $ctx.Release.Name }}
{{- end -}}

{{/*
Render a value that may contain template (replaces common.tplvalues.render)
Usage:
{{ include "roundcube.tplvalues.render" ( dict "value" .Values.path.to.the.Value "context" $) }}
*/}}
{{- define "roundcube.tplvalues.render" -}}
{{- if .value -}}
{{- if typeIs "string" .value -}}
{{- tpl .value .context -}}
{{- else -}}
{{- tpl (.value | toYaml) .context -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Merge a list of values (replaces common.tplvalues.merge)
Usage:
{{ include "roundcube.tplvalues.merge" ( dict "values" (list .Values.first .Values.second) "context" .) }}
*/}}
{{- define "roundcube.tplvalues.merge" -}}
{{- $dst := dict -}}
{{- range .values -}}
{{- if . -}}
{{- $dst = mergeOverwrite $dst (fromYaml (include "roundcube.tplvalues.render" (dict "value" . "context" $.context))) -}}
{{- end -}}
{{- end -}}
{{- $dst | toYaml -}}
{{- end -}}

{{/*
Return a soft podAffinity/podAntiAffinity definition (replaces common.affinities.pods.soft)
*/}}
{{- define "roundcube.affinities.pods.soft" -}}
preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 1
    podAffinityTerm:
      labelSelector:
        matchLabels: {{- include "roundcube.labels.matchLabels" (dict "context" .context) | nindent 10 }}
      topologyKey: kubernetes.io/hostname
{{- end -}}

{{/*
Return a hard podAffinity/podAntiAffinity definition (replaces common.affinities.pods.hard)
*/}}
{{- define "roundcube.affinities.pods.hard" -}}
requiredDuringSchedulingIgnoredDuringExecution:
  - labelSelector:
      matchLabels: {{- include "roundcube.labels.matchLabels" (dict "context" .context) | nindent 8 }}
    topologyKey: kubernetes.io/hostname
{{- end -}}

{{/*
Return a podAffinity/podAntiAffinity definition (replaces common.affinities.pods)
Usage:
{{ include "roundcube.affinities.pods" (dict "type" "soft" "context" $) }}
*/}}
{{- define "roundcube.affinities.pods" -}}
{{- if eq .type "soft" -}}
{{- include "roundcube.affinities.pods.soft" . -}}
{{- else if eq .type "hard" -}}
{{- include "roundcube.affinities.pods.hard" . -}}
{{- end -}}
{{- end -}}

{{/*
Return the proper Storage Class (replaces common.storage.class)
Usage:
{{ include "roundcube.storage.class" (dict "persistence" .Values.persistence "global" .Values.global) }}
*/}}
{{- define "roundcube.storage.class" -}}
{{- $storageClass := "" -}}
{{- if .global -}}
{{- if .global.storageClass -}}
{{- $storageClass = .global.storageClass -}}
{{- end -}}
{{- end -}}
{{- if .persistence.storageClass -}}
{{- if eq "-" .persistence.storageClass -}}
{{- $storageClass = "" -}}
{{- else -}}
{{- $storageClass = .persistence.storageClass -}}
{{- end -}}
{{- end -}}
{{- if $storageClass -}}
storageClassName: {{ $storageClass | quote }}
{{- end -}}
{{- end -}}

{{/*
===== ROUNDCUBE SPECIFIC HELPERS =====
*/}}

{{- define "roundcube.encryption" -}}
{{- if not (has . (list "none" "starttls" "ssltls")) -}}
{{ required (printf "invalid value for encryption: %s" .) nil -}}
{{- else if eq . "starttls" -}}
tls://
{{- else if eq . "ssltls" -}}
ssl://
{{- end -}}
{{- end -}}

{{- define "roundcube.desKey" -}}
{{- $ctx := . -}}
{{- if .context -}}
{{- $ctx = .context -}}
{{- end -}}
{{- if $ctx.Values.config.desKey }}
{{- $ctx.Values.config.desKey -}}
{{- else -}}
{{- $lookupResult := (lookup "v1" "Secret" $ctx.Release.Namespace (include "roundcube.fullname" $ctx )).data -}}
{{- if $lookupResult -}}
{{- (index $lookupResult "desKey" | b64dec) | default (randAlphaNum 64) -}}
{{- else -}}
{{- randAlphaNum 64 -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "roundcube.plugins.list" -}}
{{- $pluginList := list -}}
{{- range $plugin, $settings := .Values.config.plugins -}}
{{- if $settings }}
{{- if $settings.enabled -}}
{{- $pluginList = append $pluginList $plugin -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $pluginList | join "," -}}
{{- end -}}

{{- define "roundcube.skins.requirements" -}}
{{- $skinList := list -}}
{{- range $skin, $settings := .Values.config.skins -}}
{{- if $settings -}}
{{- if $settings.enabled -}}
{{- $composerPackage := printf "roundcube/%s" $skin -}}
{{- $composerVersion := $.Chart.AppVersion -}}
{{- if $settings.composerPackage -}}
{{- if $settings.composerPackage.name -}}
{{- $composerPackage = $settings.composerPackage.name -}}
{{- end -}}
{{- if $settings.composerPackage.version -}}
{{- $composerVersion = $settings.composerPackage.version -}}
{{- end -}}
{{- end -}}
{{- $skinRequirement := printf "%s:%s" $composerPackage $composerVersion -}}
{{- $skinList = append $skinList $skinRequirement -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $skinList | join " " -}}
{{- end -}}

{{- define "roundcube.plugins.requirements" -}}
{{- $pluginList := list -}}
{{- range $plugin, $settings := .Values.config.plugins -}}
{{- if $settings }}
{{- if and $settings.enabled $settings.composerPackage -}}
{{- $pluginRequirement := "" -}}
{{- if $settings.composerPackage.version -}}
{{- $pluginRequirement = printf "%s:%s" $settings.composerPackage.name $settings.composerPackage.version -}}
{{- else -}}
{{- $pluginRequirement = $settings.composerPackage.name -}}
{{- end -}}
{{- $pluginList = append $pluginList $pluginRequirement -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $pluginList | join " " -}}
{{- end -}}

{{- define "roundcube.deployment.command" -}}
(cd /usr/src/roundcubemail && composer require roundcube/plugin-installer>=0.3.5) &&
{{- if (include "roundcube.plugins.requirements" .) -}}
(cd /usr/src/roundcubemail && composer require {{ include "roundcube.plugins.requirements" . }}) &&
{{- end -}}
{{- if (include "roundcube.skins.requirements" .) -}}
(cd /usr/src/roundcubemail && composer require {{ include "roundcube.skins.requirements" . }}) &&
{{- end -}}
/docker-entrypoint.sh php-fpm
{{- end -}}

{{- define "roundcube.helm2php" -}}
{{- $kind := kindOf . -}}
{{- if has $kind (list "slice" "map") -}}
json_decode({{- . | toJson | quote -}}, true)
{{- else if has $kind (list "string") -}}
{{- . | quote -}}
{{- else -}}
{{- . -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "roundcube.serviceAccountName" -}}
{{- $ctx := . -}}
{{- if .context -}}
{{- $ctx = .context -}}
{{- end -}}
{{- if $ctx.Values.serviceAccount.create -}}
{{ default (include "roundcube.fullname" $ctx) $ctx.Values.serviceAccount.name }}
{{- else -}}
{{ default "default" $ctx.Values.serviceAccount.name }}
{{- end -}}
{{- end -}}
