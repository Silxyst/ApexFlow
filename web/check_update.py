#!/usr/bin/env python3
"""ApexFlow Update Check — consulta releases no GitHub (só stdlib).

O jogo (CSP) não expõe HTTP para o Lua (sem ac.webRequest), então este
script faz a consulta pelo app e grava o resultado em:
  Documents/Assetto Corsa/ApexFlow_update.json   (lido pelo app no jogo)

Uso:
  python check_update.py [--repo Silxyst/ApexFlow] [--docs "C:/.../Documents/Assetto Corsa"]

O panel_server.py já chama isso sozinho a cada 30 min — use este script
apenas se quiser checar manualmente sem abrir o painel.
"""

import argparse
import json
import os
import time
import urllib.request
from pathlib import Path

UPDATE_FILE = "ApexFlow_update.json"


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


def check(repo, docs):
    url = f"https://api.github.com/repos/{repo}/releases/latest"
    req = urllib.request.Request(url, headers={"User-Agent": "ApexFlow-AC-App"})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception as exc:  # noqa: BLE001 - sem internet? só avisa
        print(f"[update] falha ao consultar GitHub: {exc}")
        return False
    tag = str(data.get("tag_name") or data.get("name") or "")
    payload = {
        "repo": repo,
        "tag": tag,
        "version": tag.lstrip("v"),
        "changelog": data.get("body") or "",
        "html_url": data.get("html_url") or "",
        "published_at": data.get("published_at") or "",
        "checked_at": int(time.time()),
    }
    try:
        docs.mkdir(parents=True, exist_ok=True)
        tmp = docs / (UPDATE_FILE + ".tmp")
        tmp.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        tmp.replace(docs / UPDATE_FILE)
    except Exception as exc:  # noqa: BLE001
        print(f"[update] falha ao gravar: {exc}")
        return False
    print(f"[update] {repo} latest = {tag} (gravado em {UPDATE_FILE})")
    return True


def main():
    ap = argparse.ArgumentParser(description="ApexFlow Update Check")
    ap.add_argument("--repo", default="Silxyst/ApexFlow")
    ap.add_argument("--docs", default=None, help="Pasta Documents/Assetto Corsa")
    args = ap.parse_args()
    raise SystemExit(0 if check(args.repo, find_docs(args.docs)) else 1)


if __name__ == "__main__":
    main()
