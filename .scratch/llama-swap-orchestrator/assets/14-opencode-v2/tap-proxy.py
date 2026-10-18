#!/usr/bin/env python3
"""Logging reverse proxy: opencode -> this -> llama-swap.

Зачем: доказать, ровно какое тело уходит от клиента и что вернул сервер
(`reasoning_content`, `tool_calls`). opencode не логирует HTTP-body, поэтому
весь трафик пропускается через этот tap, который пишет пару файлов на запрос:

  001-post-v1_chat_completions.req.txt   — метод, заголовки, JSON-тело
  001-post-v1_chat_completions.resp.txt  — строка статуса + сырой поток (SSE)

Ответ отдаётся клиенту по мере поступления (chunked), поэтому streaming не
ломается. Порт и каталог логов — TAP_PORT / TAP_LOG_DIR.
"""

import http.client
import itertools
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = ("127.0.0.1", 8080)
LOG_DIR = os.environ.get("TAP_LOG_DIR", "/tmp/opencode/tap")
PORT = int(os.environ.get("TAP_PORT", "8090"))

HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "content-length",
}

os.makedirs(LOG_DIR, exist_ok=True)
_seq = itertools.count(1)
_lock = threading.Lock()


def next_seq() -> int:
    with _lock:
        return next(_seq)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "tap-proxy"

    def log_message(self, fmt, *args):  # не засорять stderr
        pass

    def _relay(self):
        n = next_seq()
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        slug = (self.path.strip("/") or "root").replace("/", "_").replace("?", "_")
        base = os.path.join(LOG_DIR, f"{n:03d}-{self.command.lower()}-{slug}")

        with open(base + ".req.txt", "w", encoding="utf-8") as f:
            f.write(f"{self.command} {self.path} {self.request_version}\n")
            for k, v in self.headers.items():
                f.write(f"{k}: {v}\n")
            f.write("\n")
            if body:
                try:
                    f.write(
                        json.dumps(
                            json.loads(body.decode("utf-8")),
                            ensure_ascii=False,
                            indent=2,
                        )
                    )
                except Exception:
                    f.write(body.decode("utf-8", "replace"))

        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_BY_HOP}
        headers["Host"] = f"{UPSTREAM[0]}:{UPSTREAM[1]}"
        started = time.time()
        conn = http.client.HTTPConnection(*UPSTREAM, timeout=3600)
        try:
            conn.request(self.command, self.path, body=body or None, headers=headers)
            resp = conn.getresponse()
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                if k.lower() in HOP_BY_HOP:
                    continue
                self.send_header(k, v)
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            with open(base + ".resp.txt", "wb") as f:
                f.write(f"HTTP {resp.status} {resp.reason}\n".encode())
                for k, v in resp.getheaders():
                    f.write(f"{k}: {v}\n".encode())
                f.write(b"\n")
                f.flush()
                while True:
                    chunk = resp.read1(65536)
                    if not chunk:
                        break
                    f.write(chunk)
                    f.flush()
                    self.wfile.write(b"%x\r\n" % len(chunk) + chunk + b"\r\n")
                    self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
            with open(base + ".meta.txt", "w", encoding="utf-8") as f:
                f.write(
                    f"started={started:.3f} finished={time.time():.3f} "
                    f"duration={time.time() - started:.3f}s status={resp.status}\n"
                )
        except Exception as exc:  # noqa: BLE001
            with open(base + ".meta.txt", "w", encoding="utf-8") as f:
                f.write(f"started={started:.3f} error={exc!r}\n")
            try:
                self.wfile.write(
                    b"%x\r\n" % len(str(exc).encode())
                    + str(exc).encode()
                    + b"\r\n0\r\n\r\n"
                )
                self.wfile.flush()
            except Exception:  # noqa: BLE001
                pass
        finally:
            conn.close()

    do_GET = _relay
    do_POST = _relay
    do_PUT = _relay
    do_DELETE = _relay
    do_PATCH = _relay


if __name__ == "__main__":
    print(f"tap -> http://{UPSTREAM[0]}:{UPSTREAM[1]}  listening on :{PORT}  logs: {LOG_DIR}", file=sys.stderr)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
