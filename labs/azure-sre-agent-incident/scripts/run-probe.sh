#!/usr/bin/env bash
set -euo pipefail
mode="${1:?Usage: bash scripts/run-probe.sh healthy|broken|fixed [samples]}"
[[ "$mode" == healthy || "$mode" == broken || "$mode" == fixed ]] || exit 2
python3 scripts/probe.py --url "$(terraform output -raw api_url)" --expected-mode "$mode" --samples "${2:-5}"
