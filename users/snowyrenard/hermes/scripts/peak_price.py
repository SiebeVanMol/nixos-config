#!/usr/bin/env python3
"""Print a message only when DeepSeek peak/off-peak pricing changes.

Peak (2x price): Mon-Fri 01:00-04:00 and 06:00-10:00 UTC.
Everything else is off-peak (half price), including all weekend.
Run from cron every few minutes: silent unless the state flipped.
"""
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

STATE = Path.home() / ".hermes" / "state" / "peak-price.json"
WINDOWS = [(1, 4), (6, 10)]  # UTC hours, half-open


def is_peak(dt):
    dt = dt.astimezone(timezone.utc)
    if dt.weekday() >= 5:  # Sat/Sun
        return False
    h = dt.hour + dt.minute / 60.0
    return any(a <= h < b for a, b in WINDOWS)


def next_flip(start):
    """First minute after start where the state differs."""
    cur = is_peak(start)
    t = start.replace(second=0, microsecond=0) + timedelta(minutes=1)
    for _ in range(60 * 24 * 8):
        if is_peak(t) != cur:
            return t
        t += timedelta(minutes=1)
    return None


def local(dt):
    return dt.astimezone().strftime("%a %H:%M")


def human(delta):
    mins = int(delta.total_seconds() // 60)
    h, m = divmod(mins, 60)
    return f"{h}h {m:02d}m" if h else f"{m}m"


def main():
    now = datetime.now(timezone.utc)
    peak = is_peak(now)
    state = "peak" if peak else "offpeak"

    prev = None
    try:
        prev = json.loads(STATE.read_text()).get("state")
    except Exception:
        pass

    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps({"state": state, "at": now.isoformat()}))

    flip = next_flip(now)
    when = f"{local(flip)} (in {human(flip - now)})" if flip else "?"

    if prev == state:
        return 0  # nothing changed, stay quiet

    if state == "peak":
        print(
            f"💸 Peak pricing is ON — deepseek-flash bills 2x "
            f"($0.30 in / $1.20 out per 1M tokens). "
            f"Back to half price {when}."
        )
    else:
        print(
            f"✅ Off-peak pricing — deepseek-flash at half rate "
            f"($0.15 in / $0.60 out per 1M tokens). "
            f"Peak starts {when}."
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
