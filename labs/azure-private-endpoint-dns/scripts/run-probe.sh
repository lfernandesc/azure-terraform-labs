#!/usr/bin/env bash
# Run from the lab root. The payload explicitly starts Bash even if the agent uses /bin/sh.
set -euo pipefail
mode="${1:?Usage: bash scripts/run-probe.sh broken|fixed}"
[[ "$mode" == broken || "$mode" == fixed ]] || exit 2
account="$(terraform output -raw storage_account)"
private_ip="$(terraform output -raw private_ip)"
[[ "$account" =~ ^[a-z0-9]{3,24}$ ]] || exit 2
[[ "$private_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || exit 2
report="$(mktemp)"
payload="$(mktemp)"
trap 'rm -f "$report" "$payload"' EXIT
{
  printf "bash -s -- '%s' '%s' '%s' <<'LAB_PROBE_SCRIPT'\n" "$account" "$private_ip" "$mode"
  cat scripts/probe.sh
  printf '\nLAB_PROBE_SCRIPT\n'
} > "$payload"
az vm run-command invoke \
  --resource-group "$(terraform output -raw resource_group)" \
  --name "$(terraform output -raw vm_name)" \
  --command-id RunShellScript \
  --scripts @"$payload" \
  --query 'value[].message' --output tsv | tee "$report"
# A successful Run Command API response does not imply that the guest test passed.
grep -q 'LAB_RESULT=PASS:' "$report"
