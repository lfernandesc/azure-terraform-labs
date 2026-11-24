import json
import os
from pathlib import Path
import subprocess
import sys

outputs = {k: v['value'] for k, v in json.load(sys.stdin).items()}
mode = os.environ['DELIVERY_PROBE_MODE']
probe = str(Path(__file__).with_name('probe.py'))

def run(url, region, expected='healthy', fdid=None):
    args = [sys.executable, probe, '--url', url, '--deployment', outputs['deployment_id'], '--region', region, '--expected', expected, '--deadline', '900', '--consecutive', '5']
    if fdid: args += ['--fdid', fdid]
    subprocess.run(args, check=True)

if mode == 'isolated':
    # Successful edge control before and after network timeouts is essential.
    run(outputs['frontdoor_url'], 'primary')
    for region, url in outputs['gateway_urls'].items():
        run(url, region, 'isolated', outputs['frontdoor_id'])
    run(outputs['frontdoor_url'], 'primary')
else:
    for region, url in outputs['gateway_urls'].items():
        state = 'unhealthy' if mode == 'broken' and region == 'primary' else 'healthy'
        run(url, region, state, outputs['frontdoor_id'])
        if state == 'healthy': run(url, region, 'denied')
    run(outputs['frontdoor_url'], 'secondary' if mode == 'broken' else 'primary')
print(json.dumps(dict(STAGE_RESULT='PASS', stage=mode)))
