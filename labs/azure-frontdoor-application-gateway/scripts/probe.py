#!/usr/bin/env python3
"""Bounded, identity-aware functional observations; no cloud provisioning."""
import argparse
import json
import time
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener, HTTPRedirectHandler, ProxyHandler
from uuid import uuid4


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_):
        return None


def request(url, headers, timeout=10):
    try:
        with build_opener(ProxyHandler({}), NoRedirect()).open(Request(url, headers=headers), timeout=timeout) as r:
            return r.status, r.read().decode()
    except HTTPError as e:
        return e.code, e.read().decode()


def check(status, raw, expected, deployment, rid, region):
    if expected == 'unhealthy':
        if status != 502:
            raise ValueError('Regional gateway must return 502, not an arbitrary failure')
        return
    body = json.loads(raw)
    result = 'wrong_frontdoor' if expected == 'denied' else 'checkout_ok'
    expected_status = 403 if expected == 'denied' else 200
    if status != expected_status or body.get('result') != result:
        raise ValueError('Unexpected status/result')
    if body.get('service') != 'delivery-lab' or body.get('deployment_id') != deployment:
        raise ValueError('Wrong service or deployment')
    if body.get('request_id') != rid or body.get('region') != region:
        raise ValueError('Wrong request correlation or region')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--url', required=True)
    p.add_argument('--deployment', required=True)
    p.add_argument('--region', choices=['primary', 'secondary'], required=True)
    p.add_argument('--fdid')
    p.add_argument('--expected', choices=['healthy', 'denied', 'unhealthy', 'isolated'], default='healthy')
    p.add_argument('--deadline', type=int, default=120)
    p.add_argument('--consecutive', type=int, default=3)
    args = p.parse_args()
    if not 1 <= args.deadline <= 1200 or not 1 <= args.consecutive <= 20:
        p.error('deadline 1..1200 seconds; consecutive 1..20')
    if not args.url.startswith(('http://', 'https://')):
        p.error('URL must use HTTP or HTTPS')
    started, streak, observations = time.monotonic(), 0, []
    while True:
        rid = str(uuid4())
        headers = {'X-Lab-Request-Id': rid, 'Cache-Control': 'no-cache'}
        if args.fdid:
            headers['X-Azure-FDID'] = args.fdid
        sample = dict(request_id=rid, utc=datetime.now(timezone.utc).isoformat(), elapsed_seconds=round(time.monotonic()-started, 2))
        try:
            status, raw = request(args.url.rstrip('/')+'/checkout?nonce='+rid, headers)
            sample['status'] = status
            if args.expected == 'isolated':
                raise ValueError('Origin still responds over HTTP; network isolation not observed')
            check(status, raw, args.expected, args.deployment, rid, args.region)
            sample['passed'] = True
        except (URLError, TimeoutError, ConnectionError) as e:
            # DNS failure is not proof of a network restriction. Require an IP-level timeout.
            reason = getattr(e, 'reason', e)
            sample['passed'] = args.expected == 'isolated' and isinstance(reason, TimeoutError)
            sample['error'] = type(reason).__name__
        except (ValueError, KeyError) as e:
            sample.update(passed=False, error=str(e))
        observations.append(sample)
        streak = streak+1 if sample['passed'] else 0
        if streak >= args.consecutive:
            print(json.dumps(dict(LAB_RESULT='PASS', expected=args.expected, region=args.region, observations=observations), indent=2))
            return 0
        if time.monotonic()-started >= args.deadline:
            print(json.dumps(dict(LAB_RESULT='FAIL', expected=args.expected, observations=observations), indent=2))
            return 1
        time.sleep(5)


if __name__ == '__main__':
    raise SystemExit(main())
