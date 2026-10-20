"""Backend for the peak-price desktop plugin.

Serves the DeepSeek account credit (and burn rate) to the hover card. The
numbers come from ~/.hermes/scripts/deepseek_budget.py — the same script the
cron job runs — so the card and the alerts can never disagree.

Routes mount under /api/plugins/peak-price/.
"""

import importlib.util
import threading
import time
from pathlib import Path

from fastapi import APIRouter

router = APIRouter()

SCRIPT = Path.home() / ".hermes/scripts/deepseek_budget.py"
CACHE_SECONDS = 120

_lock = threading.Lock()
_cache = {"at": 0.0, "data": None, "error": None}


def _budget_module():
    spec = importlib.util.spec_from_file_location("deepseek_budget", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {SCRIPT}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _refresh():
    """Refresh at most once per CACHE_SECONDS; reuse the last good answer on failure."""
    now = time.monotonic()
    with _lock:
        fresh = _cache["data"] is not None and now - _cache["at"] < CACHE_SECONDS
        if fresh:
            return _cache["data"]
        try:
            data = _budget_module().snapshot()
            _cache.update(at=now, data=data, error=None)
            return data
        except Exception as e:  # network down, no key, malformed response
            _cache["error"] = str(e)
            if _cache["data"] is not None:
                # Serve the last known balance, flagged as stale.
                stale = dict(_cache["data"])
                stale["stale"] = True
                stale["error"] = str(e)
                return stale
            raise


@router.get("/balance")
def balance():
    try:
        data = _refresh()
    except Exception as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True, **data}
