#!/usr/bin/env python3
"""Collect a Hermes usage/spend digest from the agent's own state DB.

Run by the "Hermes usage & spend digest" cron job (see users/snowyrenard/hermes.nix,
which installs this file into $HERMES_HOME/scripts/).  stdout is injected into the
job's prompt, and the agent writes the prose - so this script only has to be
accurate, not readable.

Every figure comes from one of two places, and the report says which:

  * state.db - what Hermes recorded while doing the work (tokens, calls, and the
    cost it estimated with the rate card in force at the time);
  * Hermes' own cost engine (``agent.usage_pricing``), re-run over the window's
    token mix - the same engine behind /usage and /insights.

Nothing here invents a price.  A model whose rates cannot be resolved is printed
as unpriced rather than guessed at, and that includes the local llama-server
models, which are reported as $0 because they are - the hardware is already paid
for.
"""
from __future__ import annotations

import os
import sqlite3
import sys
import time
from collections import defaultdict
from datetime import datetime

HERMES_HOME = os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes")
DB_PATH = os.path.join(HERMES_HOME, "state.db")
DAYS = 7
BUDGET_S = 25.0  # the scheduler hard-interrupts a run at 3 minutes; stay well inside

#: Providers to price against the week's real token mix.  Discovered through
#: models.dev, so this list can stay short without going stale: only models the
#: catalog actually has cost data for are reported.
PROVIDER_SCAN = ("deepseek", "google", "openai", "anthropic", "mistral", "moonshotai")

#: A candidate has to be able to do this agent's work at all before its price is
#: worth quoting: tool calls, a window big enough for a long session, and cost data.
MIN_CONTEXT = 200_000

try:  # only importable under Hermes' own interpreter; the report still works without
    import agent.models_dev as models_dev
    import agent.usage_pricing as pricing
except Exception as exc:  # pragma: no cover - depends on the interpreter
    models_dev = pricing = None
    IMPORT_ERROR = f"{type(exc).__name__}: {exc}"
    # Hermes' own interpreter carries the pricing engine and a bare one does not.
    # Re-exec under it once so the comparison table survives, instead of silently
    # dropping the section. The `hermes` wrapper exports HERMES_PYTHON, and the
    # guard variable makes a failed re-exec fall through to the degraded report
    # rather than looping.
    _hermes_python = os.environ.get("HERMES_PYTHON") or ""
    # Asked through all() rather than a multi-line `and` chain: flake8 as the
    # writers invoke it rejects an operator that starts a line. `or ""` keeps the
    # variable a str, so nothing below has to re-check it for None.
    _another_python = all(
        [
            bool(_hermes_python),
            os.path.exists(_hermes_python),
            os.path.realpath(_hermes_python) != os.path.realpath(sys.executable),
        ]
    )
    if _another_python and not os.environ.get("HERMES_DIGEST_REEXEC"):
        os.environ["HERMES_DIGEST_REEXEC"] = "1"
        try:
            os.execv(_hermes_python, [_hermes_python, os.path.abspath(__file__), *sys.argv[1:]])
        except Exception:
            pass
else:
    IMPORT_ERROR = None


def human(n: int | float) -> str:
    for unit, div in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if abs(n) >= div:
            return f"{n / div:.2f}{unit}"
    return f"{int(n)}"


def money(amount) -> str:
    value = float(amount)
    if value == 0:
        return "$0"
    if value < 0.01:
        return f"${value:.6f}"
    return f"${value:.4f}"


def connect() -> sqlite3.Connection:
    con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    return con


def window_rows(con: sqlite3.Connection, start: float, end: float) -> list[sqlite3.Row]:
    """Per-model/task usage rows whose last activity falls inside [start, end)."""
    return list(
        con.execute(
            """select session_id, model, billing_provider, billing_base_url, task,
                      api_call_count, input_tokens, output_tokens, cache_read_tokens,
                      cache_write_tokens, reasoning_tokens, estimated_cost_usd,
                      actual_cost_usd, first_seen, last_seen
                 from session_model_usage
                where last_seen >= ? and last_seen < ?""",
            (start, end),
        )
    )


def totals(rows: list[sqlite3.Row]) -> dict:
    out = defaultdict(float)
    sessions = set()
    for r in rows:
        out["calls"] += r["api_call_count"] or 0
        out["input"] += r["input_tokens"] or 0
        out["output"] += r["output_tokens"] or 0
        out["cache_read"] += r["cache_read_tokens"] or 0
        out["cache_write"] += r["cache_write_tokens"] or 0
        out["reasoning"] += r["reasoning_tokens"] or 0
        out["cost"] += r["estimated_cost_usd"] or 0.0
        # Kept because a provider that reports its own charge would make the
        # estimate a floor rather than the figure; the report prints the two side
        # by side when this is non-zero.
        out["actual_cost"] += r["actual_cost_usd"] or 0.0
        sessions.add(r["session_id"])
    out["sessions"] = len(sessions)
    return out


def is_local(row: sqlite3.Row) -> bool:
    base = (row["billing_base_url"] or "").lower()
    return "127.0.0.1" in base or "localhost" in base


def rates_for(model: str, provider: str | None, base_url: str | None):
    """PricingEntry for a route, or None. Never guesses."""
    if pricing is None:
        return None
    try:
        return pricing.get_pricing_entry(model, provider=provider, base_url=base_url)
    except Exception:
        return None


def cost_of_mix(model: str, provider: str | None, mix, base_url: str | None = None):
    if pricing is None:
        return None
    try:
        return pricing.estimate_usage_cost(model, mix, provider=provider, base_url=base_url)
    except Exception:
        return None


def component_split(model: str, provider: str | None, t: dict) -> dict | None:
    """What each token class cost, using the rate card in force for the real model."""
    entry = rates_for(model, provider, None)
    if entry is None:
        return None
    fresh = float(t["input"]) * float(entry.input_cost_per_million or 0) / 1e6
    out = float(t["output"]) * float(entry.output_cost_per_million or 0) / 1e6
    cached = float(t["cache_read"]) * float(entry.cache_read_cost_per_million or 0) / 1e6
    return {"input": fresh, "output": out, "cache_read": cached, "total": fresh + out + cached}


def candidate_prices(mix, deadline: float, current_model: str) -> tuple[list[dict], list[str]]:
    """Price the week's exact mix on every eligible catalog model. Facts, not opinions."""
    priced: list[dict] = []
    unpriced: list[str] = []
    if models_dev is None or pricing is None:
        return priced, unpriced
    seen: set[str] = set()
    for provider in PROVIDER_SCAN:
        if time.monotonic() > deadline:
            unpriced.append(f"(scan budget reached before {provider})")
            break
        try:
            models = models_dev.list_agentic_models(provider) or []
        except Exception:
            continue
        for model in models:
            if time.monotonic() > deadline:
                break
            key = f"{provider}/{model}"
            if key in seen:
                continue
            seen.add(key)
            try:
                info = models_dev.get_model_info(provider, model)
            except Exception:
                continue
            if info is None or not info.has_cost_data():
                continue
            if not getattr(info, "tool_call", False):
                continue
            if (getattr(info, "context_window", 0) or 0) < MIN_CONTEXT:
                continue
            result = cost_of_mix(model, provider, mix)
            if result is None or result.amount_usd is None:
                continue
            entry = rates_for(model, provider, None)
            priced.append(
                {
                    "route": key,
                    "model": model,
                    "provider": provider,
                    "cost": float(result.amount_usd),
                    "cache_read": None
                    if entry is None or entry.cache_read_cost_per_million is None
                    else float(entry.cache_read_cost_per_million),
                    "window": getattr(info, "context_window", None),
                    "source": result.source,
                    "current": model == current_model,
                }
            )
    priced.sort(key=lambda item: item["cost"])
    return priced, unpriced


def main() -> int:
    if not os.path.exists(DB_PATH):
        print(f"no state DB at {DB_PATH} - nothing to report")
        return 0
    con = connect()
    now = time.time()
    start, prev_start = now - DAYS * 86400, now - 2 * DAYS * 86400

    rows = window_rows(con, start, now)
    prev_rows = window_rows(con, prev_start, start)
    t, p = totals(rows), totals(prev_rows)

    stamp = datetime.fromtimestamp
    print(f"# Hermes usage report - {DAYS} days")
    print(
        f"window: {stamp(start).strftime('%Y-%m-%d %H:%M')} .. {stamp(now).strftime('%Y-%m-%d %H:%M')} "
        f"(previous window starts {stamp(prev_start).strftime('%Y-%m-%d')})"
    )
    print(f"db: {DB_PATH}")
    print(f"pricing engine: {'available' if pricing else 'UNAVAILABLE - ' + str(IMPORT_ERROR)}")
    if not rows:
        print("\nNo usage recorded in this window (nothing ran, or the DB was reset).")
        return 0

    print("\n## this window vs previous")
    print(f"  sessions           {int(t['sessions']):>6}   (prev {int(p['sessions'])})")
    print(f"  API calls          {int(t['calls']):>6}   (prev {int(p['calls'])})")
    print(f"  fresh input tokens {human(t['input']):>8}   (prev {human(p['input'])})")
    print(f"  output tokens      {human(t['output']):>8}   (prev {human(p['output'])})")
    print(f"  cache read tokens  {human(t['cache_read']):>8}   (prev {human(p['cache_read'])})")
    print(f"  estimated cost     {money(t['cost']):>10}   (prev {money(p['cost'])})")
    if t["actual_cost"]:
        print(
            f"  provider-reported  {money(t['actual_cost']):>10}   "
            f"(estimated {money(t['cost'])}, difference {money(t['actual_cost'] - t['cost'])})"
        )
    if p["cost"]:
        change = 100 * (t["cost"] - p["cost"]) / p["cost"]
        print(f"  cost change        {change:+.0f}%")
    else:
        print("  cost change        n/a (no earlier data in the DB)")

    total_in = t["input"] + t["cache_read"]
    # The two figures need different inputs, so they get different guards: the
    # cache-hit rate needs only prompt volume, which a week of calls always has,
    # while the reasoning share needs output tokens.
    if total_in:
        print(f"\n  cache-hit rate     {100 * t['cache_read'] / total_in:.1f}% of prompt volume")
    if t["output"]:
        print(f"  reasoning share    {100 * t['reasoning'] / t['output']:.0f}% of output tokens")

    # ── where it went ──────────────────────────────────────────────────────────
    by_model: dict[tuple, dict] = defaultdict(lambda: defaultdict(float))
    by_task: dict[str, dict] = defaultdict(lambda: defaultdict(float))
    for r in rows:
        mkey = (r["model"], "local" if is_local(r) else (r["billing_provider"] or "?"))
        by_model[mkey]["calls"] += r["api_call_count"] or 0
        by_model[mkey]["output"] += r["output_tokens"] or 0
        by_model[mkey]["cost"] += r["estimated_cost_usd"] or 0.0
        task = r["task"] or "main agent"
        by_task[task]["calls"] += r["api_call_count"] or 0
        by_task[task]["cost"] += r["estimated_cost_usd"] or 0.0

    print("\n## by model")
    for (model, provider), agg in sorted(by_model.items(), key=lambda kv: -kv[1]["cost"]):
        print(
            f"  {provider}/{model}: calls={int(agg['calls'])} out={human(agg['output'])} "
            f"cost={money(agg['cost'])}"
        )

    print("\n## by task (aux slots listed separately from the main agent)")
    for task, agg in sorted(by_task.items(), key=lambda kv: -kv[1]["cost"]):
        print(f"  {task}: calls={int(agg['calls'])} cost={money(agg['cost'])}")

    # ── per-session detail ─────────────────────────────────────────────────────
    session_cost = defaultdict(float)
    session_calls = defaultdict(int)
    for r in rows:
        session_cost[r["session_id"]] += r["estimated_cost_usd"] or 0.0
        session_calls[r["session_id"]] += r["api_call_count"] or 0
    print("\n## most expensive sessions")
    for sid, cost in sorted(session_cost.items(), key=lambda kv: -kv[1])[:5]:
        meta = con.execute(
            "select title, model, message_count, tool_call_count, started_at from sessions where id=?",
            (sid,),
        ).fetchone()
        title = (meta["title"] if meta and meta["title"] else sid[:14] + "...")
        when = stamp(meta["started_at"]).strftime("%m-%d %H:%M") if meta and meta["started_at"] else "?"
        extra = f"msgs={meta['message_count']} tools={meta['tool_call_count']}" if meta else "session row gone"
        print(f"  {money(cost):>10}  calls={session_calls[sid]:<4} {when}  {title[:60]}  ({extra})")

    # ── component split, priced with the rate card of the real model ───────────
    cloud = [(k, v) for k, v in by_model.items() if k[1] != "local"]
    if cloud and pricing:
        model, provider = max(cloud, key=lambda kv: kv[1]["cost"])[0]
        split = component_split(model, provider, t)
        if split:
            print(f"\n## where the money went (rates for {provider}/{model}, window totals)")
            for label, key in (("fresh input", "input"), ("output (incl. reasoning)", "output"), ("cache reads", "cache_read")):
                share = 100 * split[key] / split["total"] if split["total"] else 0
                print(f"  {label:<24} {money(split[key]):>10}  {share:5.1f}%")
        recomputed = cost_of_mix(model, provider, pricing.CanonicalUsage(
            input_tokens=t["input"], output_tokens=t["output"], cache_read_tokens=t["cache_read"],
            cache_write_tokens=t["cache_write"], reasoning_tokens=t["reasoning"], request_count=t["calls"]))
        if recomputed:
            print(
                f"  (recorded {money(t['cost'])} vs engine {money(recomputed.amount_usd)} "
                f"on the same tokens, {recomputed.source})"
            )

    # ── what the same work would cost elsewhere ────────────────────────────────
    if models_dev and pricing:
        mix = pricing.CanonicalUsage(
            input_tokens=t["input"], output_tokens=t["output"], cache_read_tokens=t["cache_read"],
            cache_write_tokens=t["cache_write"], reasoning_tokens=t["reasoning"], request_count=t["calls"])
        current_model = max(cloud, key=lambda kv: kv[1]["cost"])[0][0] if cloud else "deepseek-flash"
        priced, unpriced = candidate_prices(mix, time.monotonic() + BUDGET_S, current_model)
        print(f"\n## the same tokens priced elsewhere (candidates: tool-capable, >={human(MIN_CONTEXT)} window)")
        print("  model                              cost      vs now   cache-read rate")
        for item in priced[:12]:
            ratio = item["cost"] / t["cost"] if t["cost"] else 0
            mark = " <- current" if item["current"] else ""
            cache = "none published" if item["cache_read"] is None else f"${item['cache_read']}/M"
            print(f"  {item['route'][:32]:<32} {money(item['cost']):>9}  {ratio:5.2f}x   {cache}{mark}")
        if unpriced:
            print("  unpriced: " + "; ".join(unpriced[:3]))
        print(
            "\n  Note: a candidate with no cache-read rate was priced per its own published\n"
            "  rates, so its number is only comparable if the provider also caches. Quality\n"
            "  is not priced here - a cheaper model is not automatically a better setup."
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
