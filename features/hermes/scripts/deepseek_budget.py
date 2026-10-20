#!/usr/bin/env python3
"""DeepSeek credit tracker.

Polls https://api.deepseek.com/user/balance, keeps a history in
~/.hermes/state/deepseek-budget.json, and prints only when something needs
attention (low balance, fast burn, money ran out). Silent otherwise, so it is
safe to run from cron.

The desktop plugin reads the same numbers through `snapshot()`, imported by
~/.hermes/plugins/peak-price/dashboard/plugin_api.py.

    deepseek_budget.py            # silent unless an alert fires
    deepseek_budget.py --report   # always print the full picture
"""

import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

STATE = Path.home() / ".hermes/state/deepseek-budget.json"
ENV_FILES = [Path.home() / ".hermes/.env", Path.home() / ".config/hermes/env"]

LOW_BALANCE = 1.00      # dollars — warn when the credit drops below this
FAST_BURN = 1.00        # dollars in 24h — warn when a day costs more than this


def api_key():
    key = os.environ.get("DEEPSEEK_API_KEY")
    if key:
        return key.strip()
    for path in ENV_FILES:
        if not path.exists():
            continue
        for line in path.read_text().splitlines():
            m = re.match(r"\s*(?:export\s+)?DEEPSEEK_API_KEY\s*=\s*(.+)", line)
            if m:
                return m.group(1).strip().strip('"').strip("'")
    return None


def fetch():
    """Return (usd_total, currency) or raise."""
    key = api_key()
    if not key:
        raise RuntimeError("no DEEPSEEK_API_KEY found")
    req = urllib.request.Request(
        "https://api.deepseek.com/user/balance",
        headers={"Authorization": f"Bearer {key}", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=25) as r:
        data = json.loads(r.read().decode())
    infos = data.get("balance_infos") or []
    usd = next((b for b in infos if b.get("currency") == "USD"), infos[0] if infos else None)
    if not usd:
        raise RuntimeError("no balance info in response")
    return float(usd["total_balance"]), usd["currency"]


def load():
    if STATE.exists():
        try:
            return json.loads(STATE.read_text())
        except Exception:
            pass
    return {"history": [], "alerts": {}}


def save(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    cut = (datetime.now(timezone.utc) - timedelta(days=90)).isoformat()
    state["history"] = [h for h in state["history"] if h[0] >= cut][-4000:]
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=1))
    tmp.replace(STATE)


def spent_since(history, hours):
    """Dollars spent in the last N hours, from the oldest sample inside the window."""
    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
    window = [(datetime.fromisoformat(t), v) for t, v in history if datetime.fromisoformat(t) >= cutoff]
    if len(window) < 2:
        return None
    return round(window[0][1] - window[-1][1], 4)


def snapshot():
    """Poll the balance, record it, and return the current picture.

    Raises when the API cannot be reached; callers decide how to degrade.
    """
    state = load()
    balance, currency = fetch()
    now = datetime.now(timezone.utc)
    state["history"].append([now.isoformat(), balance])

    d1 = spent_since(state["history"], 24)
    d7 = spent_since(state["history"], 168)
    burn = None
    if d7 is not None and d7 > 0:
        burn = round(d7 / 7, 4)
    elif d1 is not None and d1 > 0:
        burn = d1
    days_left = round(balance / burn, 1) if burn and burn > 0 else None

    snap = {
        "usd": round(balance, 4),
        "currency": currency,
        "spent_24h": d1,
        "spent_7d": d7,
        "burn_per_day": burn,
        "days_left": days_left,
        "updated_at": now.isoformat(),
        "alerts": [],
    }

    alerts_state = state.setdefault("alerts", {})
    alerts = snap["alerts"]

    if balance < LOW_BALANCE and not alerts_state.get("low"):
        alerts_state["low"] = True
        alerts.append(f"⚠️ DeepSeek credit low: ${balance:.2f}. Top up before the next run fails.")
    elif balance >= LOW_BALANCE:
        alerts_state["low"] = False

    if balance <= 0 and not alerts_state.get("empty"):
        alerts_state["empty"] = True
        alerts.append("⛔ DeepSeek credit is exhausted — requests will fail until you top up.")
    elif balance > 0:
        alerts_state["empty"] = False

    day_key = now.strftime("%Y-%m-%d")
    if d1 is not None and d1 >= FAST_BURN and alerts_state.get("burn") != day_key:
        alerts_state["burn"] = day_key
        alerts.append(f"📉 Spent ${d1:.2f} on DeepSeek in the last 24 h. Balance now ${balance:.2f}.")

    save(state)
    return snap


def main():
    report = "--report" in sys.argv
    try:
        snap = snapshot()
    except Exception as e:
        print(f"deepseek budget: could not read balance ({e})")
        return 0

    if report:
        bits = [f"balance: ${snap['usd']:.2f} {snap['currency']}"]
        if snap["spent_24h"] is not None:
            bits.append(f"last 24h: ${snap['spent_24h']:.2f}")
        if snap["spent_7d"] is not None:
            bits.append(f"last 7d: ${snap['spent_7d']:.2f}")
        if snap["burn_per_day"]:
            bits.append(f"burn ≈ ${snap['burn_per_day']:.2f}/day")
        if snap["days_left"] is not None:
            bits.append(f"≈ {snap['days_left']} days left")
        print(" · ".join(bits))
        for a in snap["alerts"]:
            print(a)
    elif snap["alerts"]:
        print("\n".join(snap["alerts"]))

    return 0


if __name__ == "__main__":
    sys.exit(main())
