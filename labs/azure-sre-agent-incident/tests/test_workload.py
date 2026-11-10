"""Real localhost HTTP tests plus evidence-classifier tests. No Azure or SRE Agent calls."""
from contextlib import contextmanager, redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
from threading import Thread
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module

server = load('sre_workload', ROOT/'app/server.py')
probe = load('sre_probe', ROOT/'scripts/probe.py')

@contextmanager
def serve(config):
    http = ThreadingHTTPServer(('127.0.0.1', 0), server.handler_for(config))
    thread = Thread(target=lambda: http.serve_forever(poll_interval=0.01), daemon=True)
    thread.start()
    try: yield 'http://127.0.0.1:'+str(http.server_port)
    finally:
        http.shutdown(); http.server_close(); thread.join(2)

class WorkloadTests(unittest.TestCase):
    def test_health_stays_green_while_real_backend_request_times_out(self):
        with redirect_stdout(io.StringIO()), serve(server.Config('backend', delay_ms=350)) as backend:
            with serve(server.Config('api', backend_url=backend, timeout_ms=100)) as api:
                rid = 'broken-test'
                health = probe.request(api+'/healthz', rid)
                checkout = probe.request(api+'/checkout', rid)
                probe.check(health, checkout, rid, 'broken')
                self.assertEqual(checkout[0], 503)
                self.assertEqual(health[0], 200)
    def test_raising_only_timeout_restores_real_end_to_end_request(self):
        with redirect_stdout(io.StringIO()), serve(server.Config('backend', delay_ms=350)) as backend:
            with serve(server.Config('api', backend_url=backend, timeout_ms=2000)) as api:
                rid = 'fixed-test'
                probe.check(probe.request(api+'/healthz',rid),probe.request(api+'/checkout',rid),rid,'fixed')
    def test_unknown_backend_path_is_not_the_intended_timeout(self):
        with redirect_stdout(io.StringIO()), serve(server.Config('backend')) as backend:
            status, body = probe.request(backend+'/unknown', 'unknown-path')
            self.assertEqual(status,404);self.assertEqual(body['result'],'not_found')
    def test_full_probe_cli_checks_multiple_real_requests(self):
        with redirect_stdout(io.StringIO()), serve(server.Config('backend')) as backend:
            with serve(server.Config('api', backend_url=backend)) as api:
                result=subprocess.run([sys.executable,str(ROOT/'scripts/probe.py'),'--url',api,'--expected-mode','healthy','--samples','2'],capture_output=True,text=True,timeout=10)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertEqual(len(json.loads(result.stdout)['samples']),2)

class ClassifierTests(unittest.TestCase):
    def setUp(self):
        self.rid='fixture'
        self.health=(200,{'service':'checkout-api','result':'alive','request_id':self.rid})
        self.broken=(503,{'service':'checkout-api','result':'dependency_timeout','timeout_ms':100,'request_id':self.rid})
    def test_arbitrary_503_is_not_a_reproduction(self):
        status,body=self.broken;body={**body,'result':'upstream_unavailable'}
        with self.assertRaises(ValueError):probe.check(self.health,(status,body),self.rid,'broken')
    def test_healthy_probe_does_not_mask_checkout_failure(self):
        with self.assertRaises(ValueError):probe.check(self.health,self.broken,self.rid,'healthy')
    def test_wrong_service_cannot_pass(self):
        status,body=self.broken;body={**body,'service':'proxy'}
        with self.assertRaises(ValueError):probe.check(self.health,(status,body),self.rid,'broken')
    def test_old_cached_response_cannot_pass(self):
        status,body=self.broken;body={**body,'request_id':'old'}
        with self.assertRaises(ValueError):probe.check(self.health,(status,body),self.rid,'broken')
    def test_backend_identity_is_required_for_fixed_success(self):
        body={'service':'checkout-api','result':'checkout_ok','timeout_ms':2000,'request_id':self.rid,'backend':{'service':'other','request_id':self.rid,'delay_ms':350}}
        with self.assertRaises(ValueError):probe.check(self.health,(200,body),self.rid,'fixed')

if __name__=='__main__':unittest.main()
