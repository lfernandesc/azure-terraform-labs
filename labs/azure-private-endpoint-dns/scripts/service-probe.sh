#!/usr/bin/env bash
# Guest diagnostic for the SECOND account. Never used to test the private account.
set -euo pipefail
account="${1:?Storage account required}"
mode="${2:?Expected mode: allowed or denied}"
[[ "$account" =~ ^[a-z0-9]{3,24}$ ]] || exit 2
[[ "$mode" == allowed || "$mode" == denied ]] || exit 2
host="${account}.blob.core.windows.net"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
resolved="$(getent ahostsv4 "$host" | awk '{print $1}' | sort -u)"
printf 'SERVICE_DNS=%s\n' "$(tr '\n' ',' <<< "$resolved" | sed 's/,$//')"
# This account has NO PE. Public DNS is expected, not a DNS fault.
if ! python3 - "$resolved" <<'PY'
import ipaddress,sys
addresses=sys.argv[1].split()
sys.exit(0 if addresses and all(ipaddress.ip_address(ip).version==4 and ipaddress.ip_address(ip).is_global for ip in addresses) else 1)
PY
then
  echo 'LAB_SERVICE_RESULT=INCONCLUSIVE: expected global IPv4 answers for the service-only account.'
  exit 2
fi
token="$(curl --noproxy '*' -fsS --connect-timeout 5 --max-time 30 \
  -H 'Metadata: true' \
  'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')"
printf 'Authorization: Bearer %s\nx-ms-version: 2023-11-03\n' "$token" > "$work/auth"
unset token
status="$(curl --noproxy '*' -sS --connect-timeout 5 --max-time 30 \
  -H @"$work/auth" -D "$work/headers" -o "$work/body" -w '%{http_code}' \
  "https://${host}/?comp=list")" || status="000"
printf 'SERVICE_HTTP=%s\n' "$status"
grep -i '^x-ms-error-code:' "$work/headers" 2>/dev/null | tr -d '\r' || true
if [[ "$mode" == allowed && "$status" == 200 ]]; then
  echo 'LAB_SERVICE_RESULT=PASS: public DNS and authenticated operation succeed; verify effective service endpoint route separately.'
elif [[ "$mode" == denied && "$status" == 403 ]]; then
  echo 'LAB_SERVICE_RESULT=OBSERVED_DENY: 403 observed; compare with a prior allowed=200 and unchanged identity, operation and RBAC.'
else
  echo 'LAB_SERVICE_RESULT=INCONCLUSIVE: unexpected HTTP result; inspect RBAC propagation, network rules and error code.'
  exit 2
fi
