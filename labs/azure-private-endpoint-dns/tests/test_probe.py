"""Offline behavioural tests: Azure/network responses are fixtures, not live execution."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

PROBE = Path(__file__).resolve().parents[1] / "scripts/probe.sh"
FAKE_CURL = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
if any('169.254.169.254' in arg for arg in args):
    print(json.dumps({'access_token': 'DO_NOT_LOG_THIS_TOKEN'}))
    sys.exit(0)
status = os.environ['FORCED_STATUS' if '--resolve' in args else 'NORMAL_STATUS']
if '-D' in args:
    Path(args[args.index('-D')+1]).write_text('HTTP/1.1 '+status+'\r\nx-ms-error-code: TestFixture\r\n')
if '-o' in args:
    Path(args[args.index('-o')+1]).write_text('<EnumerationResults/>')
print(status, end='')
sys.exit(7 if status == '000' else 0)
'''

class ProbeTests(unittest.TestCase):
    def run_probe(self, mode, dns, normal, forced):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            for name, body in [('curl', FAKE_CURL), ('getent', '#!/bin/sh\nprintf "%s STREAM fixture\\n" "$DNS_IP"\n')]:
                file = folder / name
                file.write_text(body)
                file.chmod(0o755)
            env = dict(os.environ, PATH=directory+os.pathsep+os.environ['PATH'], DNS_IP=dns,
                       NORMAL_STATUS=normal, FORCED_STATUS=forced)
            result = subprocess.run(['bash', str(PROBE), 'stpednsabcd1234', '10.42.2.4', mode],
                                    env=env, text=True, capture_output=True, timeout=10)
            self.assertNotIn('DO_NOT_LOG_THIS_TOKEN', result.stdout+result.stderr)
            return result

    def test_reproduces_dns_failure_only_when_private_request_succeeds(self):
        result = self.run_probe('broken', '203.0.113.10', '403', '200')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('LAB_RESULT=PASS:', result.stdout)

    def test_confirms_fixed_resolution_and_authenticated_request(self):
        result = self.run_probe('fixed', '10.42.2.4', '200', '200')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_does_not_misdiagnose_rbac_failure_as_dns_success(self):
        result = self.run_probe('broken', '203.0.113.10', '403', '403')
        self.assertEqual(result.returncode, 2)
        self.assertIn('LAB_RESULT=INCONCLUSIVE:', result.stdout)

    def test_http_200_alone_does_not_prove_private_dns(self):
        result = self.run_probe('fixed', '203.0.113.10', '200', '200')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('LAB_RESULT=FAIL:', result.stdout)

    def test_private_dns_with_public_failure_is_not_the_missing_link_scenario(self):
        result = self.run_probe('broken', '10.42.2.4', '403', '200')
        self.assertNotEqual(result.returncode, 0)

    def test_private_network_timeout_is_inconclusive(self):
        result = self.run_probe('broken', '203.0.113.10', '403', '000')
        self.assertEqual(result.returncode, 2)
        self.assertIn('LAB_RESULT=INCONCLUSIVE:', result.stdout)

if __name__ == '__main__':
    unittest.main()
