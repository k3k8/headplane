{{- define "headplane.cookieSecret" -}}
{{- if .Values.headplane.config.cookieSecret.value -}}
{{- .Values.headplane.config.cookieSecret.value -}}
{{- else -}}
{{- randAlphaNum 32 -}}
{{- end -}}
{{- end -}}

{{/*
The headscale configuration file.

Rendered twice with different arguments:

  includeReloadable=true   the ConfigMap, i.e. the real file headscale reads
  includeReloadable=false  the StatefulSet's checksum annotation

headscale reloads the `dns` section and the `oidc.allowed_*` lists on its own
when the file changes, so those must not contribute to the annotation —
otherwise every DNS edit would restart the pod and take the embedded DERP
server down with it. Everything else still needs a restart to take effect, and
is hashed so that it gets one.

Keep any key that headscale cannot reload outside the includeReloadable
guards, or changing it will silently do nothing.

Arguments: a dict with `Values` and `includeReloadable`.
*/}}
{{- define "headplane.headscaleConfig" -}}
server_url: {{ .Values.headscale.config.url }}
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 0.0.0.0:9090
grpc_listen_addr: 0.0.0.0:50443
grpc_allow_insecure: false
noise:
  private_key_path: /etc/headscale/noise_private.key
prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48
  allocation: sequential
derp:
  server:
    enabled: {{ .Values.headscale.config.derp.server.enabled }}
    {{- if .Values.headscale.config.derp.server.enabled }}
    region_id: {{ .Values.headscale.config.derp.server.regionId }}
    region_code: {{ .Values.headscale.config.derp.server.regionCode | quote }}
    region_name: {{ .Values.headscale.config.derp.server.regionName | quote }}
    stun_listen_addr: "0.0.0.0:{{ .Values.stun.port }}"
    private_key_path: {{ .Values.headscale.config.derp.server.privateKeyPath }}
    automatically_add_embedded_derp_region: {{ .Values.headscale.config.derp.server.automaticallyAddEmbeddedDerpRegion }}
    {{- end }}
  {{- if and (not .Values.headscale.config.derp.server.enabled) .Values.headscale.config.derp.urls }}
  urls:
    {{- toYaml .Values.headscale.config.derp.urls | nindent 4 }}
  {{- else if .Values.headscale.config.derp.server.enabled }}
  urls: []
  {{- end }}
  {{- if .Values.headscale.config.derp.paths }}
  paths:
    {{- toYaml .Values.headscale.config.derp.paths | nindent 4 }}
  {{- else }}
  paths: []
  {{- end }}
  auto_update_enabled: true
  update_frequency: 24h
disable_check_updates: true
node:
  expiry: {{ .Values.headscale.config.nodeExpiry }}
  ephemeral:
    inactivity_timeout: {{ .Values.headscale.config.ephemeralNodeInactivityTimeout }}
database:
  type: {{ .Values.headscale.config.database.type }}
  {{- if eq .Values.headscale.config.database.type "sqlite" }}
  sqlite:
    path: /etc/headscale/db.sqlite
    write_ahead_log: true
    wal_autocheckpoint: 1000
  {{- else if eq .Values.headscale.config.database.type "postgres" }}
  postgres:
    host: {{ .Values.headscale.config.database.postgres.host }}
    port: {{ .Values.headscale.config.database.postgres.port }}
    name: {{ .Values.headscale.config.database.postgres.name }}
    user: {{ .Values.headscale.config.database.postgres.user }}
    # Password injected via HEADSCALE_DATABASE_POSTGRES_PASS env var
    pass: ""
    ssl: {{ ne .Values.headscale.config.database.postgres.sslMode "disable" }}
  {{- end }}
  gorm:
    prepare_stmt: true
    parameterized_queries: true
    skip_err_record_not_found: true
    slow_threshold: 1000
log:
  format: text
  level: info
policy:
  mode: database
{{- if .includeReloadable }}
dns:
  magic_dns: {{ .Values.headscale.config.dns.magicDns }}
  base_domain: {{ .Values.headscale.config.dns.baseDomain }}
  {{- if .Values.headscale.config.dns.nameservers }}
  nameservers:
    {{- if .Values.headscale.config.dns.nameservers.global }}
    global:
      {{- toYaml .Values.headscale.config.dns.nameservers.global | nindent 6 }}
    {{- end }}
    {{- if .Values.headscale.config.dns.nameservers.split }}
    split:
      {{- toYaml .Values.headscale.config.dns.nameservers.split | nindent 6 }}
    {{- end }}
  {{- end }}
  override_local_dns: {{ .Values.headscale.config.dns.overrideLocalDns }}
  # Managed by Headplane, on the writable volume rather than in this ConfigMap.
  # headscale watches this file and applies changes without a restart.
  extra_records_path: {{ .Values.headscale.config.dns.extraRecordsPath }}
{{- else }}
# dns is reloaded by headscale without a restart and is deliberately excluded
# from the checksum, but base_domain is not reloadable: it is baked into every
# node's FQDN, so headscale pins it and a change needs a restart to apply.
dns:
  base_domain: {{ .Values.headscale.config.dns.baseDomain }}
  extra_records_path: {{ .Values.headscale.config.dns.extraRecordsPath }}
{{- end }}
unix_socket: /etc/headscale/headscale.sock
unix_socket_permission: "0770"
{{- if .Values.headscale.config.oidc.enabled }}
oidc:
  only_start_if_oidc_is_available: {{ .Values.headscale.config.oidc.startupCheck }}
  issuer: {{ .Values.headscale.config.oidc.issuerUrl }}
  client_id: {{ .Values.headscale.config.oidc.clientId }}
  # Secret injected via HEADSCALE_OIDC_CLIENT_SECRET env var
  client_secret: ""
  pkce:
    enabled: {{ .Values.headscale.config.oidc.pkceEnabled }}
    method: S256
  {{- if .includeReloadable }}
  {{- if .Values.headscale.config.oidc.allowedDomains }}
  allowed_domains:
    {{- toYaml .Values.headscale.config.oidc.allowedDomains | nindent 4 }}
  {{- end }}
  {{- if .Values.headscale.config.oidc.allowedUsers }}
  allowed_users:
    {{- toYaml .Values.headscale.config.oidc.allowedUsers | nindent 4 }}
  {{- end }}
  {{- end }}
{{- end }}
logtail:
  enabled: false
randomize_client_port: {{ .Values.headscale.config.randomizeClientPort }}
{{- end -}}
