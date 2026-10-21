#!/usr/bin/env python3
"""Collect a Hermes usage/spend digest from the agent's own state DB.

Run by the "Hermes usage & spend digest" cron job (see users/snowyrenard/hermes/home.nix,
which installs this file into $HERMES_HOME/scripts/).  stdout is injected into the
job's prompt, and the agent writes the prose - so this script only has to be
accurate, not readable.

Every figure comes from one of two places, and the report says which:

  * state.db - what Hermes recorded while doing the work (tokens, calls, and the
    cost it estimated with the rate card in force at the time);
  * Hermes' own cost engine (``agent.usage_pricing``), re-run over the window's
    token mix - the same engine behind /usage and /insights.

Nothing here invents a price.  A model whose rates cannot be resolved is printed
as unpriced rather than guessed at.  (Local models used to be priced at $0 by
that rule; there are none left, since the agent runs on DeepSeek alone.)
"""
from __future__ import annotations

import os
import re
import sqlite3
import statistics
import sys
import time
from collections import defaultdict
from datetime import datetime

# Where state.db lives, what a failed tool result looks like, and the two
# formatters: all four had a copy in each script and the copies had drifted.
from hermes_state import DB_PATH, connect, human, is_tool_error, money

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


# ── cost per task ─────────────────────────────────────────────────────────────
#
# The price tables above answer "what does a million tokens cost". This section
# answers the question that decides a model: what does one task cost, after the
# tokens that model actually needed. A task is a top-level session; subagent
# sessions roll into the session that spawned them, because the work was done
# for that task. Tokens per task is input + output + cache reads - the same sum
# the cost is built from - so a model with cheaper rates but more turns cannot
# look artificially good.

CORRECTION_RE = re.compile(
    r"^(?:no\b|nope\b|wrong\b|incorrect\b|stop\b|undo\b|revert\b|again\b|"
    r"that'?s not\b|not what\b|actually\b|still (?:broke|fails|failing|broken)\b|"
    r"why did\b|you didn'?t\b|it (?:broke|fails|failed)\b)",
    re.I,
)
MAX_CORRECTION_CHARS = 240  # a long user message is new instructions, not a correction


def root_of(parent_of: dict[str, str | None], sid: str) -> str:
    seen: set[str] = set()
    while True:
        parent = parent_of.get(sid)
        if not parent or sid in seen:
            return sid
        seen.add(sid)
        sid = parent


def task_panel(con: sqlite3.Connection, rows: list[sqlite3.Row]) -> None:
    sessions = {
        r["id"]: r
        for r in con.execute("select id, parent_session_id, title from sessions")
    }
    parent_of = {sid: (r["parent_session_id"] or None) for sid, r in sessions.items()}

    # Spend per session from the window's usage rows, then rolled up the tree:
    # a subagent's tokens are part of the task it was dispatched for.
    tasks: dict[str, dict] = defaultdict(lambda: defaultdict(float))
    model_calls: dict[tuple[str, str], float] = defaultdict(float)
    for r in rows:
        root = root_of(parent_of, r["session_id"])
        agg = tasks[root]
        agg["cost"] += r["estimated_cost_usd"] or 0.0
        agg["calls"] += r["api_call_count"] or 0
        agg["input"] += r["input_tokens"] or 0
        agg["output"] += r["output_tokens"] or 0
        agg["cache"] += r["cache_read_tokens"] or 0
        model_calls[(root, r["model"] or "?")] += r["api_call_count"] or 0

    # Turns, corrections and tool failures, mapped onto the same tree. User
    # turns count only in the root session: a subagent's prompt is not a turn
    # the operator took.
    sid_root = {sid: root_of(parent_of, sid) for sid in sessions}
    msg: dict[str, dict] = defaultdict(lambda: defaultdict(float))
    last_role: dict[str, str] = {}
    for r in con.execute("select session_id, role, content from messages order by timestamp"):
        root = sid_root.get(r["session_id"])
        if root is None:
            continue
        content = r["content"] or ""
        if r["session_id"] == root and r["role"] == "user":
            msg[root]["user"] += 1
            if msg[root]["user"] > 1 and len(content) <= MAX_CORRECTION_CHARS and CORRECTION_RE.match(content.strip()):
                msg[root]["corr"] += 1
        elif r["role"] == "tool":
            msg[root]["tools"] += 1
            if is_tool_error(content):
                msg[root]["errs"] += 1
        if r["session_id"] == root:
            last_role[root] = r["role"]

    def title(root: str) -> str:
        row = sessions.get(root)
        name = (row["title"] if row else "") or root
        return name[:40]

    print("\n## cost per task (a task is a session; subagent sessions roll into it)")
    print("  task                                      cost   calls  tok/task  cache%  corr  err%  deliv")
    for root, t in sorted(tasks.items(), key=lambda kv: -kv[1]["cost"])[:8]:
        tok = t["input"] + t["output"] + t["cache"]
        cache_pct = 100 * t["cache"] / tok if tok else 0.0
        m = msg[root]
        err = 100 * m["errs"] / m["tools"] if m["tools"] else 0.0
        delivered = "yes" if last_role.get(root) == "assistant" else "no"
        print(
            f"  {title(root):<40} {money(t['cost']):>8} {int(t['calls']):>6} {human(tok):>8} "
            f"{cache_pct:5.0f}% {int(m['corr']):>5} {err:4.0f}%  {delivered}"
        )

    paid = sorted(v["cost"] for v in tasks.values() if v["cost"] > 0)
    if paid:
        def pct(q: float) -> float:
            return paid[min(len(paid) - 1, int(len(paid) * q))]

        top5_share = 100 * sum(sorted(paid, reverse=True)[:5]) / sum(paid)
        calls = [v["calls"] for v in tasks.values() if v["calls"]]
        toks = [(v["input"] + v["output"] + v["cache"]) for v in tasks.values() if v["calls"]]
        print(
            f"\n  {len(paid)} tasks spent tokens; median {money(pct(0.5))}, p75 {money(pct(0.75))}, "
            f"p90 {money(pct(0.9))}, max {money(paid[-1])}"
        )
        print(
            f"  top 5 tasks = {top5_share:.0f}% of spend; median calls/task {int(statistics.median(calls))}, "
            f"tokens/task {human(statistics.median(toks))}"
        )

    # One row per model: the A/B instrument. A task lands on the model that
    # served most of its calls, so a task that escalated mid-way is not counted
    # twice and does not distort either arm.
    dominant: dict[str, tuple[float, str]] = {}
    for (root, model), calls in model_calls.items():
        if calls > dominant.get(root, (0.0, ""))[0]:
            dominant[root] = (calls, model)
    per_model: dict[str, dict] = defaultdict(lambda: defaultdict(float))
    for root, t in tasks.items():
        model = dominant.get(root, (0.0, "?"))[1]
        agg = per_model[model]
        m = msg[root]
        delivered = last_role.get(root) == "assistant"
        accepted = delivered and m["corr"] == 0
        agg["tasks"] += 1
        agg["calls"] += t["calls"]
        agg["tok"] += t["input"] + t["output"] + t["cache"]
        agg["cache"] += t["cache"]
        agg["cost"] += t["cost"]
        agg["corr"] += m["corr"]
        agg["tools"] += m["tools"]
        agg["errs"] += m["errs"]
        agg["accepted"] += 1 if accepted else 0
        agg["accepted_cost"] += t["cost"] if accepted else 0.0

    print("\n## cost per accepted task, by model (a task counts once, on its busiest model)")
    print("  model                        tasks  calls/task  tok/task  cache%   $/task  corr/task  err%  accepted  $/accepted")
    for model, a in sorted(per_model.items(), key=lambda kv: -kv[1]["cost"]):
        n = max(int(a["tasks"]), 1)
        cache_pct = 100 * a["cache"] / a["tok"] if a["tok"] else 0.0
        err = 100 * a["errs"] / a["tools"] if a["tools"] else 0.0
        per_accepted = money(a["accepted_cost"] / a["accepted"]) if a["accepted"] else "n/a"
        print(
            f"  {model[:28]:<28} {n:>5} {a['calls'] / n:>11.1f} {human(a['tok'] / n):>9} "
            f"{cache_pct:5.0f}% {money(a['cost'] / n):>8} {a['corr'] / n:>10.2f} {err:4.0f}% "
            f"{int(a['accepted']):>9}  {per_accepted:>10}"
        )
    print(
        "\n  accepted = the session ended on the agent's own message and no short user turn read as a\n"
        "  correction. It is a heuristic, not a verdict: it cannot tell a session that finished from\n"
        "  one that was abandoned quietly. corrections match short turns only - a long user message is\n"
        "  new instructions. tokens/task is input + output + cache reads, the same sum the cost uses."
    )


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

    # ── per-task detail ────────────────────────────────────────────────────────
    task_panel(con, rows)

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
