#!/usr/bin/env python3
"""Minimal LaTeX → PDF compilation service.

POST /compile  { "tex_source": "..." }
  → 200 { "pdf_base64": "...", "error": null }   on success
  → 200 { "pdf_base64": null, "error": "..." }   on compile failure

GET  /health   → 200 { "status": "ok" }
"""
import base64
import json
import os
import subprocess
import tempfile
from http.server import BaseHTTPRequestHandler, HTTPServer


class CompileHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress per-request noise; errors still go to stderr

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"status": "ok"})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/compile":
            self._json(404, {"error": "not found"})
            return

        length = int(self.headers.get("Content-Length", 0))
        if not length:
            self._json(400, {"error": "empty body"})
            return

        try:
            body = json.loads(self.rfile.read(length))
        except json.JSONDecodeError as e:
            self._json(400, {"error": f"invalid JSON: {e}"})
            return

        tex_source = body.get("tex_source", "")
        if not tex_source.strip():
            self._json(400, {"error": "tex_source is required"})
            return

        with tempfile.TemporaryDirectory() as tmpdir:
            tex_path = os.path.join(tmpdir, "resume.tex")
            pdf_path = os.path.join(tmpdir, "resume.pdf")

            with open(tex_path, "w", encoding="utf-8") as f:
                f.write(tex_source)

            cmd = [
                "pdflatex",
                "-interaction=nonstopmode",
                "-halt-on-error",
                "-output-directory", tmpdir,
                tex_path,
            ]

            # Run twice — second pass resolves any cross-references
            subprocess.run(cmd, capture_output=True, timeout=60)
            result = subprocess.run(cmd, capture_output=True, timeout=60)

            if os.path.exists(pdf_path):
                with open(pdf_path, "rb") as f:
                    pdf_b64 = base64.b64encode(f.read()).decode("ascii")
                self._json(200, {"pdf_base64": pdf_b64, "error": None})
            else:
                log = (result.stdout + result.stderr).decode("utf-8", errors="replace")
                lines = log.splitlines()
                errors = [l for l in lines if l.startswith("!") or "Error" in l]
                msg = "\n".join(errors[:15]) if errors else log[-800:]
                self._json(200, {"pdf_base64": None, "error": msg})

    def _json(self, code, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    print(f"LaTeX service listening on :{port}", flush=True)
    HTTPServer(("0.0.0.0", port), CompileHandler).serve_forever()
