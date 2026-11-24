from contextlib import contextmanager, redirect_stdout
from http.server import ThreadingHTTPServer
import importlib.util
import io
import json
from pathlib import Path
import threading
import unittest
from urllib.request import Request, urlopen
ROOT = Path(__file__).resolve().parents[1]

def load(name, path):
    s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
server=load('delivery_server',ROOT/'app/server.py');probe=load('delivery_probe',ROOT/'scripts/probe.py')

@contextmanager
def serve():
    h=ThreadingHTTPServer(('127.0.0.1',0),server.handler_for('primary','deployment','correct-fdid'))
    t=threading.Thread(target=lambda:h.serve_forever(poll_interval=.01),daemon=True);t.start()
    try:yield 'http://127.0.0.1:'+str(h.server_port)
    finally:h.shutdown();h.server_close();t.join(2)

class HttpTests(unittest.TestCase):
    def test_get_and_head_health(self):
        with redirect_stdout(io.StringIO()),serve() as base:
            for method in ('GET','HEAD'):
                with urlopen(Request(base+'/health',method=method)) as r:self.assertEqual(r.status,200)
    def test_unknown_health_path_fails(self):
        with redirect_stdout(io.StringIO()),serve() as base:
            self.assertEqual(probe.request(base+'/missing',{})[0],404)
    def test_valid_fdid_real_http_correlates_request(self):
        with redirect_stdout(io.StringIO()),serve() as base:
            status,raw=probe.request(base+'/checkout?nonce=fresh',{'X-Azure-FDID':'correct-fdid','X-Lab-Request-Id':'fresh'})
            probe.check(status,raw,'healthy','deployment','fresh','primary')
    def test_missing_or_wrong_fdid_is_rejected(self):
        with redirect_stdout(io.StringIO()),serve() as base:
            for headers in ({},{'X-Azure-FDID':'other-profile'}):
                status,raw=probe.request(base+'/checkout',{**headers,'X-Lab-Request-Id':'id'})
                probe.check(status,raw,'denied','deployment','id','primary')
    def test_redirect_does_not_count_as_success(self):
        self.assertIsNone(probe.NoRedirect().redirect_request(None,None,302,'',{},'http://elsewhere/'))

class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.body=dict(service='delivery-lab',region='primary',deployment_id='deployment',request_id='fresh',result='checkout_ok')
    def check(self,body=None,status=200,expected='healthy'):
        probe.check(status,json.dumps(body or self.body),expected,'deployment','fresh','primary')
    def test_valid_body(self):self.check()
    def test_wrong_service(self):
        with self.assertRaises(ValueError):self.check({**self.body,'service':'wrong'})
    def test_wrong_region(self):
        with self.assertRaises(ValueError):self.check({**self.body,'region':'secondary'})
    def test_wrong_deployment(self):
        with self.assertRaises(ValueError):self.check({**self.body,'deployment_id':'old'})
    def test_stale_response(self):
        with self.assertRaises(ValueError):self.check({**self.body,'request_id':'old'})
    def test_generic_error_not_gateway_failure(self):
        with self.assertRaises(ValueError):self.check(status=503,expected='unhealthy')
    def test_gateway_502_is_expected_fault(self):self.check(status=502,expected='unhealthy')
    def test_html_200_not_functional_success(self):
        with self.assertRaises(ValueError):probe.check(200,'<html>ok</html>','healthy','deployment','fresh','primary')

if __name__=='__main__':unittest.main()
