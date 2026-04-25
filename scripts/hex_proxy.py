#!/usr/bin/env python3
"""Local HTTP proxy that forwards to https://repo.hex.pm.

Workaround for the sandbox egress proxy that rejects Erlang :httpc but
accepts Python urllib (which uses Python's TLS stack).

Usage:
    python3 hex_proxy.py &
    export HEX_MIRROR_URL=http://127.0.0.1:8789
    mix deps.get
"""

import http.server
import urllib.request
import urllib.error
import socketserver
import sys

UPSTREAM = "https://repo.hex.pm"
PORT = 8789


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = UPSTREAM + self.path
        try:
            req = urllib.request.Request(url, method="GET")
            with urllib.request.urlopen(req, timeout=60) as r:
                body = r.read()
                self.send_response(r.status)
                for k in ("content-type", "content-length", "etag", "last-modified", "cache-control"):
                    v = r.headers.get(k)
                    if v:
                        self.send_header(k, v)
                if not r.headers.get("content-length"):
                    self.send_header("content-length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        except urllib.error.HTTPError as e:
            body = e.read()
            self.send_response(e.code)
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception as e:
            self.send_error(502, str(e))

    def log_message(self, fmt, *args):
        sys.stderr.write("[hex_proxy] %s\n" % (fmt % args))


class ReuseServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    srv = ReuseServer(("127.0.0.1", PORT), Handler)
    print(f"[hex_proxy] forwarding http://127.0.0.1:{PORT} -> {UPSTREAM}", flush=True)
    srv.serve_forever()
