#!/usr/bin/env bash
# Run from the lab root, after the comparison stage has been applied.
set -euo pipefail
mode="${1:?Usage: bash scripts/run-service-probe.sh allowed|denied}"
[[ "$mode" == allowed || "$mode" == denied ]] || exit 2
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
terraform output -json service_endpoint_comparison > "$work/outputs"
mapfile -t config < <(python3 - "$work/outputs" <<'PY'
import json,sys
with open(sys.argv[1]) as f: c=json.load(f)
if not isinstance(c,dict): sys.exit('Enable enable_service_endpoint_comparison and apply first')
for key in ('account','id','subnet_id'): print(c[key])
PY
)
[[ "${#config[@]}" == 3 && "${config[0]}" =~ ^[a-z0-9]{3,24}$ ]] || { echo 'Comparison output unavailable' >&2; exit 2; }
account="${config[0]}"
az rest --method get --url "https://management.azure.com${config[1]}?api-version=2023-05-01" --output json > "$work/storage"
az network vnet subnet show --ids "${config[2]}" --output json > "$work/subnet"
python3 scripts/check-service-config.py "$work/storage" "$work/subnet" "${config[2]}" "$mode"
{
  printf "bash -s -- '%s' '%s' <<'LAB_SERVICE_SCRIPT'\n" "$account" "$mode"
  cat scripts/service-probe.sh
  printf '\nLAB_SERVICE_SCRIPT\n'
} > "$work/payload"
az vm run-command invoke \
  --resource-group "$(terraform output -raw resource_group)" \
  --name "$(terraform output -raw vm_name)" \
  --command-id RunShellScript --scripts @"$work/payload" \
  --query 'value[].message' --output tsv | tee "$work/report"
if [[ "$mode" == allowed ]]; then
  grep -q '^LAB_SERVICE_RESULT=PASS:' "$work/report"
else
  grep -q '^LAB_SERVICE_RESULT=OBSERVED_DENY:' "$work/report"
fi

az network nic show-effective-route-table \
  --resource-group "$(terraform output -raw resource_group)" \
  --name "$(terraform output -raw probe_nic_name)" --output json > "$work/routes"
python3 scripts/check-service-route.py "$work/routes" "$work/report"
if [[ "$mode" == allowed ]]; then
  echo 'SERVICE_COMPARISON=PASS: ARM controls, public DNS, service endpoint route and authenticated HTTP 200 verified.'
else
  echo 'SERVICE_COMPARISON=OBSERVED_DENY: ARM deny rule and service route verified; interpret 403 against prior allowed success.'
fi
