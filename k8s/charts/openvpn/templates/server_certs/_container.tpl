{{/*
Create helm partial for generating server certs
*/}}
{{- define "server_certs" }}
- name: server_certs
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  securityContext:
    privileged: true
  ports:
  - containerPort: {{ .Values.service.apiSecurePort }}
  env:
  - name: SCRIPT
    value: &generateCerts |-
    SERVER_CERT="{{ .Values.CERT_DIR }}/pki/issued/server.crt"
    if [ -e "$SERVER_CERT" ]
    then
      echo "found existing certs - reusing"
    else
      cp -R /usr/share/easy-rsa/* {{ .Values.CERT_DIR }}C
      cd {{ .Values.CERT_DIR }}
      ./easyrsa init-pki
      echo "ca\n" | ./easyrsa build-ca nopass
      ./easyrsa build-server-full server nopass
      ./easyrsa gen-dh
    fi
         
  command: ["/bin/sh"]
  args: ['-cx', *generateCerts]
  resources:
{{ toYaml .Values.resources.apache | indent 10 }}
  volumeMounts:
  - mountPath: /etc/openvpn/setup
    name: openvpn
    readOnly: false
  - mountPath: {{ .Values.CERT_DIR }}
    name: certs
    readOnly: false
{{- end }}
