#!/usr/bin/env python3
"""ApexFlow Remote Panel — servidor local (só stdlib).

O app no jogo NÃO tem HTTP: ele escreve
  Documents/Assetto Corsa/RaceFlow_webui_status.json   (a cada 0.5s)
e lê
  Documents/Assetto Corsa/RaceFlow_webui_cmd.json      (comandos).

Este servidor faz a ponte para o navegador:
  http://localhost:8080/panel.html   -> painel remoto (este PC)
  http://<seu-ip>:8080/panel.html    -> celular na mesma rede / OBS

Uso:
  python panel_server.py [--port 8080] [--docs "C:/.../Documents/Assetto Corsa"]

Requisitos no jogo: app ApexFlow com Web UI ativada + sessão iniciada.
Token: o mesmo configurado no app (Ajustes > Web remota). Se vazio, sem auth.
"""

import argparse
import functools
import http.server
import json
import os
import socket
import sys
import time
from pathlib import Path

STATUS_FILE = "RaceFlow_webui_status.json"
CMD_FILE = "RaceFlow_webui_cmd.json"


def find_docs(cli_docs=None):
    if cli_docs:
        return Path(cli_docs)
    env = os.environ.get("APEXFLOW_DOCS")
    if env:
        return Path(env)
    home = Path.home()
    for cand in (
        home / "Documents" / "Assetto Corsa",
        home / "OneDrive" / "Documentos" / "Assetto Corsa",
        home / "OneDrive" / "Documents" / "Assetto Corsa",
    ):
        if cand.is_dir():
            return cand
    return home / "Documents" / "Assetto Corsa"


def read_status(docs):
    p = docs / STATUS_FILE
    if not p.is_file():
        return {"_waiting": True, "_hint": "Ligue a Web UI no app e entre em pista."}
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
        data["_waiting"] = False
        data["_serverTime"] = int(time.time())
        return data
    except Exception as exc:  # noqa: BLE001 - mostra erro no painel, nunca quebra
        return {"_waiting": True, "_hint": f"status ilegível: {exc}"}


def post_command(docs, action, params, token):
    p = docs / CMD_FILE
    try:
        current = json.loads(p.read_text(encoding="utf-8")) if p.is_file() else {}
    except Exception:  # noqa: BLE001 - arquivo corrompido: recomeça
        current = {}
    commands = current.get("commands")
    if not isinstance(commands, list):
        commands = []
    cmd_id = int(time.time() * 1000)
    commands.append({"id": cmd_id, "action": action, "params": params or {}, "token": token or ""})
    # O app limpa o arquivo após processar; mantemos no máx. 20 pendentes.
    p.write_text(json.dumps({"commands": commands[-20:]}), encoding="utf-8")
    return {"ok": True, "id": cmd_id}


class Handler(http.server.SimpleHTTPRequestHandler):
    docs = None

    def log_message(self, *args):  # log enxuto
        sys.stdout.write("[panel] %s\n" % (args[1] if len(args) > 1 else args[0]))

    def _json(self, payload, code=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/status":
            return self._json(read_status(self.docs))
        return super().do_GET()

    def do_POST(self):
        if self.path != "/api/cmd":
            return self._json({"ok": False, "error": "unknown endpoint"}, 404)
        try:
            length = int(self.headers.get("Content-Length") or 0)
            payload = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
        except Exception as exc:  # noqa: BLE001
            return self._json({"ok": False, "error": f"json inválido: {exc}"}, 400)
        action = str(payload.get("action") or "")
        if not action:
            return self._json({"ok": False, "error": "sem action"}, 400)
        try:
            result = post_command(self.docs, action, payload.get("params") or {}, payload.get("token") or "")
        except Exception as exc:  # noqa: BLE001
            return self._json({"ok": False, "error": str(exc)}, 500)
        return self._json(result)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()


def lan_ip():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def main():
    ap = argparse.ArgumentParser(description="ApexFlow Remote Panel")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--docs", default=None, help="Pasta Documents/Assetto Corsa")
    ap.add_argument("--host", default="0.0.0.0", help="Interface de escuta")
    args = ap.parse_args()

    docs = find_docs(args.docs)
    webdir = Path(__file__).resolve().parent
    Handler.docs = docs
    handler = functools.partial(Handler, directory=str(webdir))

    with http.server.ThreadingHTTPServer((args.host, args.port), handler) as srv:
        print(f"[panel] Docs AC : {docs}")
        print(f"[panel] Este PC : http://localhost:{args.port}/panel.html")
        print(f"[panel] Rede     : http://{lan_ip()}:{args.port}/panel.html")
        print("[panel] Ctrl+C para parar.")
        try:
            srv.serve_forever()
        except KeyboardInterrupt:
            print("\n[panel] até logo!")


if __name__ == "__main__":
    main()
