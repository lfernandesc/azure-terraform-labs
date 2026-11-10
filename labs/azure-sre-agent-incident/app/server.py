"""Disposable teaching workload. Not a production HTTP server."""
from dataclasses import dataclass
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import re
import socket
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import uuid4


@dataclass(frozen=True)
class Config:
    role: str
    backend_url: str = ""
    timeout_ms: int = 2000
    delay_ms: int = 350
    revision: str = "local"

    @classmethod
    def from_env(cls):
        role = os.environ.get("APP_ROLE", "api")
        timeout = int(os.environ.get("DEPENDENCY_TIMEOUT_MS", "2000"))
        delay = int(os.environ.get("BACKEND_DELAY_MS", "350"))
        backend = os.environ.get("BACKEND_URL", "").rstrip("/")
        if role not in {"api", "backend"} or not 1 <= timeout <= 5000 or not 1 <= delay <= 2000:
            raise ValueError("Invalid bounded lab configuration")
        if role == "api" and not backend.startswith(("http://", "https://")):
            raise ValueError("API requires an explicit BACKEND_URL")
        return cls(role, backend, timeout, delay, os.environ.get("CONTAINER_APP_REVISION", "local"))


def handler_for(config):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # Only bounded structured application events are written.

        def respond(self, status, payload):
            body = json.dumps(payload).encode()
            try:
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass  # Expected when the API timed out before this backend finished.

        def do_GET(self):
            service = "checkout-api" if config.role == "api" else "slow-backend"
            raw_id = self.headers.get("X-Lab-Request-Id", "")
            request_id = raw_id if re.fullmatch(r"[a-zA-Z0-9-]{1,64}", raw_id) else str(uuid4())
            base = {"service": service, "request_id": request_id, "revision": config.revision}
            if self.path == "/health":
                self.respond(200, {**base, "result": "alive"})
                return
            started = time.monotonic()
            status, event, extra = 404, "not_found", {}
            if config.role == "backend" and self.path == "/work":
                time.sleep(config.delay_ms / 1000)
                status, event, extra = 200, "backend_ok", {"delay_ms": config.delay_ms}
            elif config.role == "api" and self.path == "/checkout":
                try:
                    request = Request(config.backend_url + "/work", headers={"X-Lab-Request-Id": request_id})
                    with urlopen(request, timeout=config.timeout_ms / 1000) as response:
                        backend = json.load(response)
                    if backend.get("service") != "slow-backend" or backend.get("request_id") != request_id or backend.get("result") != "backend_ok":
                        raise ValueError("Backend identity or correlation mismatch")
                    status, event, extra = 200, "checkout_ok", {"backend": backend}
                except (TimeoutError, socket.timeout):
                    status, event = 503, "dependency_timeout"
                except HTTPError:
                    status, event = 502, "upstream_invalid"
                except URLError as exc:
                    status = 503
                    event = "dependency_timeout" if isinstance(exc.reason, (TimeoutError, socket.timeout)) else "upstream_unavailable"
                except ValueError:
                    status, event = 502, "upstream_invalid"
                extra["timeout_ms"] = config.timeout_ms
            payload = {**base, "result": event, **extra}
            print(json.dumps({**payload, "event": event, "status": status,
                              "elapsed_ms": round((time.monotonic() - started) * 1000, 2),
                              "timestamp": datetime.now(timezone.utc).isoformat()}), flush=True)
            self.respond(status, payload)
    return Handler


if __name__ == "__main__":
    config = Config.from_env()
    print(json.dumps({"event": "startup", "role": config.role,
                      "timeout_ms": config.timeout_ms, "revision": config.revision}), flush=True)
    ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), handler_for(config)).serve_forever()
