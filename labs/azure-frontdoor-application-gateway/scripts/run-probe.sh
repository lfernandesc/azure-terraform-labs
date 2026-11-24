#!/usr/bin/env bash
set -euo pipefail
# Run from this lab directory. No dependencies besides Terraform and Python 3.
mode="${1:?Usage: bash scripts/run-probe.sh baseline|broken|recovered|isolated}"
case "$mode" in baseline|broken|recovered|isolated) ;; *) exit 2 ;; esac
export DELIVERY_PROBE_MODE="$mode"
terraform output -json | python3 scripts/run-stage.py
