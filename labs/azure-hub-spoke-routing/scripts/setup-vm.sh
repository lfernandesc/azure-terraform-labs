#!/usr/bin/env bash
# Runs as root ONLY in disposable lab VMs through Custom Script Extension.
# Do not execute on a workstation or an existing production router.
set -euo pipefail
node="${1:?node name required}"
router="${2:?router flag required}"
[[ "$node" =~ ^(hub|spoke-a|spoke-b)$ ]] || exit 2
[[ "$router" == true || "$router" == false ]] || exit 2
command -v python3 >/dev/null
install -d -m 0755 /opt/hub-spoke-lab
printf 'NODE_NAME=%s\n' "$node" > /etc/default/hub-spoke-lab
cat > /opt/hub-spoke-lab/server.py <<'PY'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/health':
            self.send_error(404)
            return
        body = json.dumps({'node': os.environ['NODE_NAME'], 'client_ip': self.client_address[0]}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

ThreadingHTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
PY
cat > /etc/systemd/system/lab-http.service <<'UNIT'
[Unit]
Description=Private lab health endpoint (no sensitive data)
After=network-online.target
Wants=network-online.target
[Service]
EnvironmentFile=/etc/default/hub-spoke-lab
ExecStart=/usr/bin/python3 /opt/hub-spoke-lab/server.py
User=nobody
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
if [[ "$router" == true ]]; then
  command -v iptables >/dev/null
  cat > /usr/local/sbin/lab-forwarding <<'ROUTER'
#!/usr/bin/env bash
set -euo pipefail
sysctl -w net.ipv4.ip_forward=1
# Azure routes control the return path; avoid reverse-path filtering dropping forwarded packets.
for setting in /proc/sys/net/ipv4/conf/*/rp_filter; do echo 0 > "$setting"; done
iptables -P FORWARD DROP
iptables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
for pair in '10.51.0.0/16 10.52.0.0/16' '10.52.0.0/16 10.51.0.0/16'; do
  read -r source destination <<< "$pair"
  iptables -C FORWARD -s "$source" -d "$destination" -p tcp --dport 8080 -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -s "$source" -d "$destination" -p tcp --dport 8080 -m conntrack --ctstate NEW -j ACCEPT
done
# Intentionally no SNAT/MASQUERADE: the destination must observe the real spoke source IP.
ROUTER
  chmod 0755 /usr/local/sbin/lab-forwarding
  cat > /etc/sysctl.d/60-hub-spoke-lab.conf <<'SYSCTL'
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
SYSCTL
  cat > /etc/systemd/system/lab-forwarding.service <<'UNIT'
[Unit]
Description=Disposable hub-spoke lab forwarding rules
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lab-forwarding
RemainAfterExit=true
[Install]
WantedBy=multi-user.target
UNIT
fi
systemctl daemon-reload
if [[ "$router" == true ]]; then systemctl enable --now lab-forwarding.service; fi
systemctl enable lab-http.service
systemctl restart lab-http.service
systemctl is-active --quiet lab-http.service
printf 'SETUP_READY=%s\n' "$node"
