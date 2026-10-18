#!/usr/bin/env python3
"""Фиктивный OpenAI-совместимый backend для offline-проверок router-конфига.

Возвращает name/port и полное тело запроса — так видно и маршрутизацию, и
результат `useModelName`/`stripParams`.

    python3 router-smoke-backend.py llama.cpp 19011
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
            parsed = json.loads(body) if body else None
        except json.JSONDecodeError:
            parsed = "<unparsable>"
        out = json.dumps(
            {"backend": name, "port": port, "body": parsed}, sort_keys=True
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
