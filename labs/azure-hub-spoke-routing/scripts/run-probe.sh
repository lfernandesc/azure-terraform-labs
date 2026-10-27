#!/usr/bin/env bash
# Execute from the lab root. Both directions must pass before LAB_SUITE=PASS.
set -euo pipefail
mode="${1:?Usage: bash scripts/run-probe.sh broken|fixed}"
[[ "$mode" == broken || "$mode" == fixed ]] || exit 2
group="$(terraform output -raw resource_group)"
vm_names="$(terraform output -json vm_names)"
ips="$(terraform output -json node_ips)"
report="$(mktemp)"
payload="$(mktemp)"
trap 'rm -f "$report" "$payload"' EXIT
lookup() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
for node in spoke-a spoke-b; do
  if [[ "$node" == spoke-a ]]; then peer=spoke-b; else peer=spoke-a; fi
  vm="$(lookup "$node" <<< "$vm_names")"
  source_ip="$(lookup "$node" <<< "$ips")"
  peer_ip="$(lookup "$peer" <<< "$ips")"
  [[ "$source_ip" =~ ^10\.5[12]\.0\.4$ && "$peer_ip" =~ ^10\.5[12]\.0\.4$ ]] || exit 2
  {
    printf "bash -s -- '%s' '%s' '%s' '%s' '%s' <<'LAB_PROBE_SCRIPT'\n" "$node" "$source_ip" "$peer" "$peer_ip" "$mode"
    cat scripts/probe.sh
    printf '\nLAB_PROBE_SCRIPT\n'
  } > "$payload"
  az vm run-command invoke --resource-group "$group" --name "$vm" \
    --command-id RunShellScript --scripts @"$payload" \
    --query 'value[].message' --output tsv | tee "$report"
  # API success is not guest test success.
  grep -q 'LAB_RESULT=PASS:' "$report"
done
echo 'LAB_SUITE=PASS: both spoke directions matched the expected scenario.'
