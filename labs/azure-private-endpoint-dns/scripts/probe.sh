#!/usr/bin/env bash
# Executed inside the VM via Run Command. No token is printed or passed to Azure CLI.
set -euo pipefail
account="${1:?Storage account name required}"
private_ip="${2:?Private Endpoint IP required}"
mode="${3:?Expected mode: broken or fixed}"
[[ "$account" =~ ^[a-z0-9]{3,24}$ ]] || exit 2
[[ "$private_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || exit 2
[[ "$mode" == broken || "$mode" == fixed ]] || exit 2
host="${account}.blob.core.windows.net"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

resolved="$(getent ahostsv4 "$host" | awk '{print $1}' | sort -u)"
printf 'DNS=%s\nEXPECTED_PRIVATE_IP=%s\n' "$resolved" "$private_ip"
# A fresh token for this VM's system-assigned identity, not the deployer's identity.
token="$(curl --noproxy '*' -fsS --connect-timeout 5 --max-time 30 \
  -H 'Metadata: true' \
  'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')"
# Header file keeps the token out of curl's process arguments.
printf 'Authorization: Bearer %s\nx-ms-version: 2023-11-03\n' "$token" > "$work/auth"
unset token

request() {
  local label="$1"
  shift
  local status
  status="$(curl --noproxy '*' -sS --connect-timeout 5 --max-time 30 \
    -H @"$work/auth" -D "$work/$label.headers" -o "$work/$label.body" \
    -w '%{http_code}' "$@" "https://${host}/?comp=list")" || status="000"
  printf '%s\n' "$status"
}
normal="$(request normal)"
# Diagnostic only: preserve the public FQDN, TLS SNI and certificate validation.
forced="$(request forced --resolve "${host}:443:${private_ip}")"
printf 'HTTP_NORMAL=%s\nHTTP_FORCED_PRIVATE=%s\n' "$normal" "$forced"
for label in normal forced; do
  printf '%s ' "$label"
  grep -i '^x-ms-error-code:' "$work/$label.headers" 2>/dev/null | tr -d '\r' || true
done

if [[ "$forced" != 200 ]]; then
  echo 'LAB_RESULT=INCONCLUSIVE: private request failed; check RBAC propagation, identity, PE approval and network.'
  exit 2
fi
if [[ "$mode" == broken ]] && ! grep -Fxq "$private_ip" <<< "$resolved" && [[ "$normal" == 403 ]]; then
  echo 'LAB_RESULT=PASS: DNS fault reproduced; the same identity succeeds over the private path.'
elif [[ "$mode" == fixed ]] && grep -Fxq "$private_ip" <<< "$resolved" && [[ "$normal" == 200 ]]; then
  echo 'LAB_RESULT=PASS: DNS returns the PE address and the normal HTTPS request succeeds.'
else
  echo 'LAB_RESULT=FAIL: observations do not match the expected mode.'
  exit 1
fi
