#!/usr/bin/env python3
"""Фиктивный OpenAI-совместимый backend для проверок llama-swap.

Возвращает, кто получил запрос и с каким `model` в теле — так видно и
маршрутизацию, и результат `useModelName`.

    python3 fake_backend.py llama.cpp 19001
"""
import http.server
import json
import sys

name = sys.argv[1]
port = int(sys.argv[2])


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode() if n else ""
        try:
            req_model = json.loads(body).get("model") if body else None
        except json.JSONDecodeError:
            req_model = "<unparsable>"
        out = json.dumps(
            {"backend": name, "port": port, "received_model": req_model}
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def do_GET(self):
        out = b'{"status":"ok"}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
