{{/*
Create helm partial for the openvpn containers
*/}}
{{- define "server_certs" }}
- name: openvpn_server
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  command: ["/etc/openvpn/setup/configure.sh"]
  ports:
  - containerPort: {{ .Values.service.internalPort }}
    name: openvpn
  securityContext:
  capabilities:
    add:
      - NET_ADMIN
  resources:
    requests:
      cpu: "{{ .Values.resources.requests.cpu }}"
      memory: "{{ .Values.resources.requests.memory }}"
    limits:
      cpu: "{{ .Values.resources.limits.cpu }}"
      memory: "{{ .Values.resources.limits.memory }}"
  volumeMounts:
    - mountPath: /etc/openvpn/setup
      name: openvpn
      readOnly: false
    - mountPath: /etc/openvpn/certs
      name: certs
      readOnly: false
{{- end }}