"""Disposable HTTP teaching backend. No real data or authentication tokens."""
import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


def handler_for(region, deployment_id, frontdoor_id):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_HEAD(self):
            self.respond(head=True)

        def do_GET(self):
            self.respond()

        def respond(self, head=False):
            path = urlsplit(self.path).path
            rid = self.headers.get('X-Lab-Request-Id', '')
            rid = rid if re.fullmatch(r'[a-zA-Z0-9-]{1,64}', rid) else ''
            status, result = 404, 'not_found'
            if path == '/health':
                status, result = 200, 'ready'
            elif path == '/checkout':
                status, result = (200, 'checkout_ok') if self.headers.get('X-Azure-FDID') == frontdoor_id else (403, 'wrong_frontdoor')
            payload = dict(service='delivery-lab', region=region, deployment_id=deployment_id, request_id=rid, result=result)
            body = json.dumps(payload).encode()
            self.send_response(status)
            for k, v in [('Content-Type', 'application/json'), ('Cache-Control', 'no-store'), ('X-Origin-Region', region), ('Content-Length', str(len(body)))]:
                self.send_header(k, v)
            self.end_headers()
            if not head:
                self.wfile.write(body)
            print(json.dumps(dict(event=result, status=status, **payload)), flush=True)
    return Handler


if __name__ == '__main__':
    ThreadingHTTPServer(('0.0.0.0', 8080), handler_for(os.environ['LAB_REGION'], os.environ['DEPLOYMENT_ID'], os.environ['FRONTDOOR_ID'])).serve_forever()
