#!/usr/bin/env bash
# Guest-side proof. Called from both spokes; no DNS, public service, token or SSH involved.
set -euo pipefail
node="${1:?source node required}"
source_ip="${2:?source private IP required}"
peer="${3:?destination node required}"
peer_ip="${4:?destination private IP required}"
mode="${5:?broken or fixed required}"
[[ "$node" =~ ^spoke-[ab]$ && "$peer" =~ ^spoke-[ab]$ && "$node" != "$peer" ]] || exit 2
[[ "$source_ip" =~ ^10\.5[12]\.0\.4$ && "$peer_ip" =~ ^10\.5[12]\.0\.4$ ]] || exit 2
[[ "$mode" == broken || "$mode" == fixed ]] || exit 2
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
request() {
  local name="$1" ip="$2" status
  status="$(curl --noproxy '*' -sS --connect-timeout 5 --max-time 10 \
    -o "$work/$name.json" -w '%{http_code}' "http://${ip}:8080/health")" || status=000
  printf '%s\n' "$status"
}
field() {
  python3 - "$work/$1.json" "$2" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as file:
        print(json.load(file).get(sys.argv[2], 'INVALID'))
except (OSError, ValueError):
    print('INVALID')
PY
}
local_status="$(request local 127.0.0.1)"
hub_status="$(request hub 10.50.0.4)"
remote_status="$(request remote "$peer_ip")"
printf 'SOURCE=%s\nLOCAL_HTTP=%s\nHUB_HTTP=%s\nREMOTE_HTTP=%s\n' "$node" "$local_status" "$hub_status" "$remote_status"
if [[ "$local_status" != 200 || "$(field local node)" != "$node" || "$hub_status" != 200 || "$(field hub node)" != hub ]]; then
  echo 'LAB_RESULT=INCONCLUSIVE: local service or direct hub path is unhealthy.'
  exit 2
fi
if [[ "$mode" == broken && "$remote_status" == 000 ]]; then
  echo 'LAB_RESULT=PASS: local and hub checks pass; no HTTP connection to the other spoke.'
elif [[ "$mode" == fixed && "$remote_status" == 200 && "$(field remote node)" == "$peer" && "$(field remote client_ip)" == "$source_ip" ]]; then
  printf 'REMOTE_NODE=%s\nREMOTE_OBSERVED_SOURCE=%s\n' "$(field remote node)" "$(field remote client_ip)"
  echo 'LAB_RESULT=PASS: peer service reached and original source address preserved.'
else
  echo 'LAB_RESULT=FAIL: unexpected HTTP result, destination identity or source address.'
  exit 1
fi
