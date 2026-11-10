#!/usr/bin/env python3
"""Functional checks, not an Azure SRE Agent evaluation or a production SLO measurement."""
import argparse
import json
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from uuid import uuid4


def request(url, request_id):
    req = Request(url, headers={"X-Lab-Request-Id": request_id, "Cache-Control": "no-cache"})
    try:
        with urlopen(req, timeout=10) as response:
            return response.status, json.load(response)
    except HTTPError as exc:
        return exc.code, json.load(exc)


def check(health, checkout, request_id, mode):
    hs, hb = health
    cs, cb = checkout
    if hs != 200 or hb.get("service") != "checkout-api" or hb.get("result") != "alive":
        raise ValueError("Health endpoint does not identify the expected running API")
    if hb.get("request_id") != request_id or cb.get("request_id") != request_id:
        raise ValueError("Missing or mismatched request correlation")
    if cb.get("service") != "checkout-api":
        raise ValueError("Unexpected checkout service")
    if mode == "broken":
        if cs != 503 or cb.get("result") != "dependency_timeout" or cb.get("timeout_ms") != 100:
            raise ValueError("Not the intended dependency-timeout fault")
    else:
        backend = cb.get("backend", {})
        if cs != 200 or cb.get("result") != "checkout_ok" or cb.get("timeout_ms") != 2000:
            raise ValueError("Functional checkout is not healthy with the restored timeout")
        if backend.get("service") != "slow-backend" or backend.get("request_id") != request_id or backend.get("delay_ms") != 350:
            raise ValueError("Expected backend response is missing")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True)
    p.add_argument("--expected-mode", choices=["healthy", "broken", "fixed"], required=True)
    p.add_argument("--samples", type=int, default=5)
    args = p.parse_args()
    if not 1 <= args.samples <= 30 or not args.url.startswith(("https://", "http://")):
        p.error("Use a valid URL and 1..30 bounded samples")
    records = []
    try:
        for _ in range(args.samples):
            rid, started = str(uuid4()), time.monotonic()
            health = request(args.url.rstrip("/") + "/health", rid)
            checkout = request(args.url.rstrip("/") + "/checkout", rid)
            check(health, checkout, rid, args.expected_mode)
            records.append({"request_id": rid, "health_status": health[0], "checkout_status": checkout[0],
                            "result": checkout[1]["result"], "timeout_ms": checkout[1]["timeout_ms"],
                            "revision": checkout[1].get("revision"),
                            "round_trip_ms": round((time.monotonic() - started) * 1000, 2)})
    except Exception as exc:
        print(json.dumps({"LAB_RESULT": "FAIL", "reason": str(exc), "completed": len(records)}))
        return 1
    print(json.dumps({"LAB_RESULT": "PASS", "mode": args.expected_mode, "samples": records}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
