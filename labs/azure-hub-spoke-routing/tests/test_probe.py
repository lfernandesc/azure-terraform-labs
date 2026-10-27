"""Network fixtures test diagnostic behaviour, not Azure reachability."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FAKE_CURL = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
url = args[-1]
name = 'LOCAL' if '127.0.0.1' in url else 'HUB' if '10.50.0.4' in url else 'REMOTE'
status = os.environ.get(name+'_STATUS', '200')
node = {'LOCAL':'spoke-a', 'HUB':'hub', 'REMOTE':os.environ.get('REMOTE_NODE','spoke-b')}[name]
body = {'node':node, 'client_ip':os.environ.get('OBSERVED_SOURCE','10.51.0.4')}
Path(args[args.index('-o')+1]).write_text(json.dumps(body))
print(status, end='')
sys.exit(7 if status=='000' else 0)
'''

class ProbeTests(unittest.TestCase):
    def probe(self, mode, **values):
        with tempfile.TemporaryDirectory() as folder:
            curl = Path(folder)/'curl'
            curl.write_text(FAKE_CURL); curl.chmod(0o755)
            env = dict(os.environ, PATH=folder+os.pathsep+os.environ['PATH'], **values)
            return subprocess.run(['bash',str(ROOT/'scripts/probe.sh'),'spoke-a','10.51.0.4','spoke-b','10.52.0.4',mode], env=env, capture_output=True, text=True, timeout=10)

    def test_broken_requires_healthy_local_and_hub(self):
        result = self.probe('broken', REMOTE_STATUS='000')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('LAB_RESULT=PASS:', result.stdout)

    def test_fixed_requires_correct_peer_and_untranslated_source(self):
        result = self.probe('fixed', REMOTE_STATUS='200')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('REMOTE_OBSERVED_SOURCE=10.51.0.4', result.stdout)

    def test_local_service_failure_is_not_peering_proof(self):
        result = self.probe('broken', REMOTE_STATUS='000', LOCAL_STATUS='500')
        self.assertEqual(result.returncode, 2)

    def test_failed_hub_path_is_inconclusive(self):
        result = self.probe('broken', REMOTE_STATUS='000', HUB_STATUS='000')
        self.assertEqual(result.returncode, 2)

    def test_wrong_destination_with_http_200_fails(self):
        self.assertNotEqual(self.probe('fixed', REMOTE_STATUS='200', REMOTE_NODE='hub').returncode, 0)

    def test_snat_does_not_silently_pass(self):
        self.assertNotEqual(self.probe('fixed', REMOTE_STATUS='200', OBSERVED_SOURCE='10.50.0.4').returncode, 0)

    def test_http_500_is_not_a_missing_network_path(self):
        self.assertNotEqual(self.probe('broken', REMOTE_STATUS='500').returncode, 0)

    def test_unexpected_connectivity_in_broken_mode_fails(self):
        self.assertNotEqual(self.probe('broken', REMOTE_STATUS='200').returncode, 0)

if __name__=='__main__': unittest.main()
