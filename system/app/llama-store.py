#!/usr/bin/env python3
import json
import os
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen

from huggingface_hub import HfApi, hf_hub_download, snapshot_download

MODELS_DIR = Path(os.environ.get("MODELS_DIR", "/Vault/llama/models"))
LLAMA_SERVER = os.environ.get("LLAMA_SERVER", "http://127.0.0.1:8080")
PORT = int(os.environ.get("STORE_PORT", "8090"))

api = HfApi()
download_lock = threading.Lock()
SHARD_RE = re.compile(r"^(.*)-(\d+)-of-(\d+)\.gguf$")


def human(n):
    for unit in ["B", "KiB", "MiB", "GiB", "TiB"]:
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} PiB"


def installed():
    if not MODELS_DIR.is_dir():
        return []
    out = []
    for p in sorted(MODELS_DIR.glob("*.gguf")):
        sz = p.stat().st_size
        out.append({"name": p.name, "size": sz, "size_h": human(sz)})
    return out


def search(q, limit=25):
    models = api.list_models(search=q, sort="downloads", limit=limit)
    out = []
    for m in models:
        out.append(
            {
                "id": m.id,
                "downloads": m.downloads or 0,
                "likes": m.likes or 0,
                "task": m.pipeline_tag or "",
                "library": m.library_name or "",
            }
        )
    return out


def repo_files(repo):
    try:
        info = api.model_info(repo, files_metadata=True)
    except Exception as e:
        return {"error": str(e)}
    files = []
    for s in info.siblings:
        if s.rfilename.endswith(".gguf"):
            sz = s.size or 0
            files.append({"path": s.rfilename, "size": sz, "size_h": human(sz)})
    files.sort(key=lambda f: f["path"])
    return {"files": files}


def download(repo, fname):
    with download_lock:
        m = SHARD_RE.match(fname)
        if m:
            base = m.group(1)
            snapshot_download(
                repo_id=repo,
                allow_patterns=[f"{base}-*.gguf"],
                local_dir=str(MODELS_DIR),
            )
        else:
            hf_hub_download(
                repo_id=repo, filename=fname, local_dir=str(MODELS_DIR)
            )
    return {"ok": True, "downloaded": fname}


def remove(name):
    p = MODELS_DIR / name
    if p.is_file() and p.suffix == ".gguf":
        p.unlink()
        return {"ok": True, "removed": name}
    return {"error": "not found"}


def server_status():
    try:
        req = Request(f"{LLAMA_SERVER}/v1/models", headers={"Accept": "application/json"})
        with urlopen(req, timeout=5) as r:
            data = json.load(r)
        ids = [m["id"] for m in data.get("data", [])]
        return {"reachable": True, "models": ids, "count": len(ids)}
    except Exception as e:
        return {"reachable": False, "error": str(e)}


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Model Store</title>
<style>
:root { color-scheme: dark; }
body { font-family: system-ui, sans-serif; background: #121212; color: #e6e6e6; margin: 0; }
header { padding: 16px 24px; background: #1c1c1c; border-bottom: 1px solid #333; display: flex; gap: 16px; align-items: baseline; }
header h1 { margin: 0; font-size: 18px; }
header span { font-size: 13px; color: #aaa; }
main { max-width: 960px; margin: 0 auto; padding: 24px; }
input[type=text] { width: 70%; padding: 8px; background: #222; color: #eee; border: 1px solid #444; border-radius: 6px; }
button { padding: 8px 14px; background: #2c5fa8; color: #fff; border: 0; border-radius: 6px; cursor: pointer; }
button:hover { background: #3a74c9; }
button.danger { background: #a83c3c; }
button.danger:hover { background: #c94a4a; }
table { width: 100%; border-collapse: collapse; margin-top: 12px; }
th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #2a2a2a; font-size: 14px; }
tr.model:hover { background: #1c1c1c; cursor: pointer; }
.muted { color: #999; font-size: 13px; }
.section { margin-top: 28px; }
.progress { display: none; margin-top: 10px; color: #8ec78e; }
</style>
</head>
<body>
<header>
  <h1>Model Store</h1>
  <span id="status">server: checking...</span>
</header>
<main>
  <div class="section">
    <input type="text" id="q" placeholder="Search Hugging Face (e.g. qwen3, llama, gemma)..." />
    <button onclick="doSearch()">Search</button>
  </div>

  <div class="section" id="results" style="display:none">
    <h2>Results <span class="muted" id="result-count"></span></h2>
    <table>
      <thead><tr><th>Model</th><th>Task</th><th>Downloads</th><th>Likes</th></tr></thead>
      <tbody id="model-rows"></tbody>
    </table>
  </div>

  <div class="section" id="files" style="display:none">
    <h2 id="files-title"></h2>
    <div class="progress" id="progress">Downloading... this may take a while for large models.</div>
    <table>
      <thead><tr><th>Quant file</th><th>Size</th><th></th></tr></thead>
      <tbody id="file-rows"></tbody>
    </table>
  </div>

  <div class="section">
    <h2>Installed <span class="muted" id="installed-count"></span></h2>
    <table>
      <thead><tr><th>File</th><th>Size</th><th></th></tr></thead>
      <tbody id="installed-rows"></tbody>
    </table>
  </div>
</main>
<script>
const esc = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

async function api(path, opts) {
  const r = await fetch(path, opts);
  return r.json();
}

async function refreshStatus() {
  const s = await api('/api/status');
  const el = document.getElementById('status');
  el.textContent = s.reachable
    ? `server: online — ${s.count} loaded (${s.models.map(esc).join(', ') || 'none'})`
    : `server: unreachable (${esc(s.error)})`;
}

async function refreshInstalled() {
  const list = await api('/api/installed');
  document.getElementById('installed-count').textContent = `(${list.length})`;
  const tb = document.getElementById('installed-rows');
  tb.innerHTML = '';
  if (!list.length) { tb.innerHTML = '<tr><td colspan="3" class="muted">No models downloaded yet.</td></tr>'; return; }
  for (const m of list) {
    const tr = document.createElement('tr');
    tr.innerHTML = `<td>${esc(m.name)}</td><td>${esc(m.size_h)}</td>` +
      `<td><button class="danger" onclick="removeModel('${esc(m.name).replace(/'/g,"\\'")}')">Remove</button></td>`;
    tb.appendChild(tr);
  }
}

async function doSearch() {
  const q = document.getElementById('q').value.trim();
  if (!q) return;
  const res = await api('/api/search?q=' + encodeURIComponent(q));
  const el = document.getElementById('results');
  el.style.display = 'block';
  document.getElementById('result-count').textContent = `(${res.length})`;
  const tb = document.getElementById('model-rows');
  tb.innerHTML = '';
  for (const m of res) {
    const tr = document.createElement('tr');
    tr.className = 'model';
    tr.innerHTML = `<td>${esc(m.id)}</td><td class="muted">${esc(m.task || '')} ${esc(m.library || '')}</td>` +
      `<td>${Number(m.downloads).toLocaleString()}</td><td>${Number(m.likes).toLocaleString()}</td>`;
    tr.onclick = () => showFiles(m.id);
    tb.appendChild(tr);
  }
}

async function showFiles(repo) {
  document.getElementById('files').style.display = 'block';
  document.getElementById('files-title').textContent = repo;
  const res = await api('/api/files?repo=' + encodeURIComponent(repo));
  const tb = document.getElementById('file-rows');
  tb.innerHTML = '';
  if (res.error) { tb.innerHTML = `<tr><td colspan="3" class="muted">${esc(res.error)}</td></tr>`; return; }
  const files = res.files || [];
  if (!files.length) { tb.innerHTML = '<tr><td colspan="3" class="muted">No .gguf files in this repo.</td></tr>'; return; }
  for (const f of files) {
    const tr = document.createElement('tr');
    tr.innerHTML = `<td>${esc(f.path)}</td><td>${esc(f.size_h)}</td>` +
      `<td><button onclick="startDownload('${esc(repo).replace(/'/g,"\\'")}','${esc(f.path).replace(/'/g,"\\'")}')">Download</button></td>`;
    tb.appendChild(tr);
  }
}

async function startDownload(repo, file) {
  document.getElementById('progress').style.display = 'block';
  try {
    const res = await fetch('/api/download', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({repo, file})
    });
    const data = await res.json();
    if (data.error) alert('Error: ' + data.error);
    else { document.getElementById('progress').textContent = 'Done: ' + data.downloaded; }
  } catch (e) {
    alert('Download failed: ' + e);
  }
  refreshInstalled();
  setTimeout(() => { document.getElementById('progress').style.display = 'none'; document.getElementById('progress').textContent = 'Downloading... this may take a while for large models.'; }, 3000);
}

async function removeModel(name) {
  if (!confirm('Remove ' + name + '?')) return;
  await fetch('/api/remove', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({name}) });
  refreshInstalled();
}

document.getElementById('q').addEventListener('keydown', e => { if (e.key === 'Enter') doSearch(); });
refreshStatus();
refreshInstalled();
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _html(self, body):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        try:
            self._get()
        except Exception as e:
            self._send(500, {"error": f"{type(e).__name__}: {e}"})

    def _get(self):
        path = urlparse(self.path).path
        qs = parse_qs(urlparse(self.path).query)
        if path in ("/", "/models", "/models/"):
            return self._html(PAGE.encode())
        if path == "/api/search":
            q = (qs.get("q") or [""])[0].strip()
            return self._send(200, search(q) if q else [])
        if path == "/api/files":
            repo = (qs.get("repo") or [""])[0].strip()
            if not repo:
                return self._send(400, {"error": "missing repo"})
            return self._send(200, repo_files(repo))
        if path == "/api/installed":
            return self._send(200, installed())
        if path == "/api/status":
            return self._send(200, server_status())
        self._send(404, {"error": "not found"})

    def do_POST(self):
        try:
            self._post()
        except Exception as e:
            self._send(500, {"error": f"{type(e).__name__}: {e}"})

    def _post(self):
        path = urlparse(self.path).path
        try:
            length = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return self._send(400, {"error": "bad request"})
        if path == "/api/download":
            repo = data.get("repo", "").strip()
            file = data.get("file", "").strip()
            if not repo or not file:
                return self._send(400, {"error": "missing repo/file"})
            try:
                return self._send(200, download(repo, file))
            except Exception as e:
                return self._send(500, {"error": str(e)})
        if path == "/api/remove":
            name = data.get("name", "").strip()
            return self._send(200, remove(name))
        self._send(404, {"error": "not found"})


if __name__ == "__main__":
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"llama-store listening on http://127.0.0.1:{PORT}", flush=True)
    server.serve_forever()