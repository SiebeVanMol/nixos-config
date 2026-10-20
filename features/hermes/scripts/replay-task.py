#!/usr/bin/env python3
"""Run one task on several models and measure what it cost to finish.

The digest answers what a week cost. This answers the narrower question a model
switch depends on: for the same task, from the same starting state, how many
calls and how many minutes did each model need, and what did it finally return?

One arm is one fresh clone of the source repo, so neither model sees the other's
edits. Everything is measured from the outside - wall clock around the process,
the session row in state.db for calls and tokens, git for the size of the change,
and an optional verification command run inside the clone - so the numbers do
not depend on the model reporting on itself.

  replay-task.py --task add-flag --prompt-file task.md \
      --source ~/nixos-config \
      --arm deepseek:deepseek-flash --arm deepseek:deepseek-v4-pro \
      --verify "./test.sh" --max-turns 60 --run-budget 900

Results are appended to $HERMES_HOME/replay/runs.jsonl and the previous runs of
the same task are printed beside the new ones: runtime is the thing that drifts,
and it only drifts visibly if it is kept.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import uuid
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path

HERMES_HOME = Path(os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes"))
DB_PATH = HERMES_HOME / "state.db"
RESULTS_DIR = HERMES_HOME / "replay"
SCRATCH = Path(os.environ.get("BH_AGENT_WORKSPACE") or tempfile.gettempdir())

#: A session is created with a fresh id per run, but the id is also printed by
#: --pass-session-id; the DB path is the fallback for a run that died early.
JSONL_LINE = re.compile(r'^\{.*"session_id".*\}$')


@dataclass
class Arm:
    name: str
    provider: str
    model: str


@dataclass
class Run:
    task: str
    arm: str
    provider: str
    model: str
    started: str
    wall_s: float = 0.0
    llm_s: float = 0.0
    tool_s: float = 0.0
    status: str = "unknown"
    calls: int = 0
    tokens_in: int = 0
    tokens_out: int = 0
    cache_read: int = 0
    reasoning: int = 0
    cost_usd: float = 0.0
    tool_calls: int = 0
    tool_errors: int = 0
    user_turns: int = 0
    diff_files: int = 0
    diff_added: int = 0
    diff_removed: int = 0
    untracked: int = 0
    verify_ok: bool | None = None
    verify_s: float = 0.0
    verify_tail: str = ""
    session_id: str = ""
    patch_path: str = ""
    prompt_path: str = ""
    note: str = ""
    extra: dict = field(default_factory=dict)


def sh(cmd: list[str], cwd: Path | None = None, timeout: float | None = None, env: dict | None = None):
    return subprocess.run(
        cmd, cwd=str(cwd) if cwd else None, capture_output=True, text=True, timeout=timeout, env=env
    )


def clone(src: Path, dest: Path) -> None:
    """A shallow local clone: one arm per clone so neither sees the other."""
    res = sh(["git", "clone", "--quiet", "--depth", "1", "--no-hardlinks", str(src), str(dest)])
    if res.returncode != 0:
        raise SystemExit(f"git clone failed: {res.stderr.strip()}")


def diff_stats(clone_dir: Path, base: str) -> tuple[int, int, int, int, str, int]:
    """Everything the arm changed, whether it left it in the tree or committed it.

    Diffing against the starting commit rather than HEAD matters: an agent that
    commits its own work shows an empty `git diff` and would otherwise be scored
    as having done nothing.
    """
    numstat = sh(["git", "-C", str(clone_dir), "diff", "--numstat", base]).stdout
    files = added = removed = 0
    for line in numstat.splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        files += 1
        try:
            added += int(parts[0])
            removed += int(parts[1])
        except ValueError:  # binary
            pass
    noise = ("__pycache__", ".pyc", "node_modules/", "result")
    untracked = len(
        [
            p
            for p in sh(["git", "-C", str(clone_dir), "status", "--porcelain"]).stdout.splitlines()
            if p.startswith("??") and not any(n in p for n in noise)
        ]
    )
    commits = int(sh(["git", "-C", str(clone_dir), "rev-list", "--count", f"{base}..HEAD"]).stdout.strip() or 0)
    patch = sh(["git", "-C", str(clone_dir), "diff", base]).stdout
    if untracked:
        patch += "\n# untracked files present, not in this patch\n"
    return files, added, removed, untracked, patch, commits


def session_metrics(session_id: str | None, cwd: Path, since: float) -> tuple[dict, str]:
    """Calls, tokens and cost from state.db: the model's own account is not used."""
    if not DB_PATH.exists():
        return {}, session_id or ""
    con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    sid = session_id
    if sid:
        row = con.execute("select id from sessions where id=?", (sid,)).fetchone()
        if not row:
            sid = None
    if not sid:
        row = con.execute(
            "select id from sessions where cwd=? and started_at>=? order by started_at desc limit 1",
            (str(cwd), since - 5),
        ).fetchone()
        sid = row["id"] if row else None
    out: dict = {}
    if sid:
        r = con.execute(
            """select api_call_count, input_tokens, output_tokens, cache_read_tokens,
                      reasoning_tokens, estimated_cost_usd, started_at, ended_at, title
                 from sessions where id=?""",
            (sid,),
        ).fetchone()
        if r:
            out = dict(r)
        counts = con.execute(
            """select role, count(*) as n, min(timestamp) as first, max(timestamp) as last
                 from messages where session_id=? group by role""",
            (sid,),
        ).fetchall()
        by_role = {c["role"]: c for c in counts}
        if by_role:
            out["first_msg_at"] = min(c["first"] for c in by_role.values() if c["first"])
            out["last_msg_at"] = max(c["last"] for c in by_role.values() if c["last"])
        out["user_turns"] = by_role["user"]["n"] if "user" in by_role else 0
        out["tool_calls"] = sum(c["n"] for role, c in by_role.items() if role == "tool")
        errs = con.execute(
            """select count(*) from messages where session_id=? and role='tool'
                 and (content like '%"success": false%' or content like '%Traceback%'
                      or content like '%command not found%' or content like '%No such file%')""",
            (sid,),
        ).fetchone()
        out["tool_errors"] = errs[0] if errs else 0
    con.close()
    return out, sid or ""


def run_arm(arm: Arm, task: str, prompt_text: str, source: Path, verify: str | None,
            max_turns: int | None, run_budget: int, keep: bool, workroot: Path) -> Run:
    started = datetime.now().isoformat(timespec="seconds")
    work = workroot / arm.name
    res = Run(task=task, arm=arm.name, provider=arm.provider, model=arm.model, started=started)
    t0 = time.time()
    try:
        clone(source, work)
        head = sh(["git", "-C", str(work), "rev-parse", "HEAD"]).stdout.strip()[:12]
        res.extra["start_head"] = head

        # Hermes' tools do not inherit the launcher's cwd: the terminal tool and
        # the code kernel start in the home directory, and a model that searches
        # relative paths finds nothing and reports the task impossible. The first
        # measured run failed exactly that way, on the environment rather than on
        # the model. Every arm therefore gets the same explicit working directory
        # in its prompt, and the prompt it actually saw is kept beside the patch.
        effective = prompt_text.replace("{work}", str(work)) + (
            f"\n\n---\nYour working directory for this task is {work}\n"
            "Every file you need is under that directory. Use absolute paths under it.\n"
        )
        prompt_path = workroot / f"{arm.name}.prompt.txt"
        prompt_path.write_text(effective)
        res.extra["prompt"] = effective
        res.prompt_path = str(RESULTS_DIR / f"{task}-{arm.name}-{started.replace(':', '')}.prompt.txt")

        cmd = [
            "hermes", "chat",
            "--query-file", str(prompt_path),
            "--oneshot", "--quiet", "--yolo", "--pass-session-id",
            "--provider", arm.provider, "--model", arm.model,
            # --in anchors the session's recorded directory; --no-restore-cwd
            # keeps a previous session's directory from winning instead.
            "--in", str(work), "--no-restore-cwd",
            # Same ceiling for every arm: the comparison is "what it takes inside
            # one budget", not "how long a patient model would eventually need".
            "--run-budget", str(run_budget),
        ]
        if max_turns:
            cmd += ["--max-turns", str(max_turns)]
        env = dict(os.environ)
        env["HERMES_HOME"] = str(HERMES_HOME)
        began = time.time()
        try:
            proc = sh(cmd, cwd=work, timeout=run_budget + 180, env=env)
            res.status = "completed" if proc.returncode == 0 else f"exit {proc.returncode}"
            res.extra["stdout_tail"] = proc.stdout.strip()[-1200:]
            res.extra["stderr_tail"] = proc.stderr.strip()[-800:]
        except subprocess.TimeoutExpired:
            res.status = "killed by harness timeout"
        res.wall_s = time.time() - began
        # The session id is printed last by --pass-session-id; a JSON line if
        # --format stream-json was used, otherwise a bare id.
        for line in reversed(res.extra.get("stdout_tail", "").splitlines()):
            line = line.strip()
            if JSONL_LINE.match(line):
                try:
                    res.session_id = json.loads(line).get("session_id", "")
                except json.JSONDecodeError:
                    pass
            elif re.fullmatch(r"[0-9a-f]{16,64}", line):
                res.session_id = line
            if res.session_id:
                break

        metrics, sid = session_metrics(res.session_id or None, work, began)
        res.session_id = sid
        res.calls = int(metrics.get("api_call_count") or 0)
        res.tokens_in = int(metrics.get("input_tokens") or 0)
        res.tokens_out = int(metrics.get("output_tokens") or 0)
        res.cache_read = int(metrics.get("cache_read_tokens") or 0)
        res.reasoning = int(metrics.get("reasoning_tokens") or 0)
        res.cost_usd = float(metrics.get("estimated_cost_usd") or 0.0)
        res.tool_calls = int(metrics.get("tool_calls") or 0)
        res.tool_errors = int(metrics.get("tool_errors") or 0)
        res.user_turns = int(metrics.get("user_turns") or 0)
        # LLM time is the span between the first and last recorded message: the
        # rest of the wall clock is process start-up and tool execution.
        if metrics.get("first_msg_at") and metrics.get("last_msg_at"):
            res.llm_s = max(0.0, float(metrics["last_msg_at"]) - float(metrics["first_msg_at"]))
            res.tool_s = max(0.0, res.wall_s - res.llm_s)

        base = str(res.extra.get("start_head") or "HEAD")
        files, added, removed, untracked, patch, commits = diff_stats(work, base)
        res.diff_files, res.diff_added, res.diff_removed, res.untracked = files, added, removed, untracked
        res.extra["commits"] = commits
        RESULTS_DIR.mkdir(parents=True, exist_ok=True)
        patch_path = RESULTS_DIR / f"{task}-{arm.name}-{started.replace(':', '')}.patch"
        patch_path.write_text(patch)
        res.patch_path = str(patch_path)
        if res.prompt_path:
            Path(res.prompt_path).write_text(str(res.extra.get("prompt", "")))

        if verify:
            v0 = time.time()
            v = sh(["bash", "-lc", verify], cwd=work, timeout=run_budget + 180)
            res.verify_s = time.time() - v0
            res.verify_ok = v.returncode == 0
            tail = (v.stdout + v.stderr).strip().splitlines()[-6:]
            res.verify_tail = " | ".join(tail)[-400:]
        if not res.calls:
            res.note = "no session found in state.db - metrics missing"
    finally:
        if not keep:
            shutil.rmtree(work, ignore_errors=True)
        res.extra["total_s"] = time.time() - t0
    return res


def human_tokens(n: int) -> str:
    for unit, div in (("M", 1_000_000), ("K", 1_000)):
        if n >= div:
            return f"{n / div:.1f}{unit}"
    return str(n)


def clock(seconds: float) -> str:
    m, s = divmod(int(seconds), 60)
    return f"{m}:{s:02d}"


def append_history(runs: list[Run], history_path: Path) -> list[dict]:
    """Write every arm of this run, and return the earlier runs of the same task."""
    history_path.parent.mkdir(parents=True, exist_ok=True)
    task = runs[0].task if runs else ""
    previous: list[dict] = []
    if history_path.exists():
        for line in history_path.read_text().splitlines():
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get("task") == task:
                previous.append(rec)
    with history_path.open("a") as fh:
        for run in runs:
            fh.write(json.dumps(asdict(run), sort_keys=True) + "\n")
    return previous


def report(runs: list[Run], previous: list[dict]) -> None:
    print("\n## replay: one task, one clone per arm, same budget")
    print("  arm        model                     status      wall  llm  calls  calls/min  tok/task  cache%      $  diff     verify")
    for r in runs:
        tok = r.tokens_in + r.tokens_out + r.cache_read
        cache_pct = 100 * r.cache_read / tok if tok else 0.0
        rate = r.calls / (r.wall_s / 60) if r.wall_s else 0.0
        verify = "n/a" if r.verify_ok is None else ("pass" if r.verify_ok else "FAIL")
        print(
            f"  {r.arm:<10} {r.model[:25]:<25} {r.status[:10]:<10} {clock(r.wall_s):>5} {clock(r.llm_s):>4} "
            f"{r.calls:>6} {rate:>10.1f} {human_tokens(tok):>9} {cache_pct:5.0f}% {r.cost_usd:>7.3f} "
            f"+{r.diff_added}/-{r.diff_removed:<4} {verify}"
        )
    print("\n  wall = process lifetime; llm = first to last recorded message; the difference is start-up and tools.")
    print("  cost is the session's own recorded cost; a local arm records 0 because there is no invoice.")
    if previous:
        print(f"\n## previous runs of '{runs[0].task}' (runtime is the number that drifts)")
        print("  when                 arm        model                     wall  calls      $  verify")
        for rec in previous[-10:]:
            verify = "n/a" if rec.get("verify_ok") is None else ("pass" if rec["verify_ok"] else "FAIL")
            print(
                f"  {rec.get('started', '?')[:19]:<19} {rec.get('arm', '?'):<10} {rec.get('model', '?')[:25]:<25} "
                f"{clock(rec.get('wall_s') or 0):>5} {rec.get('calls', 0):>6} {rec.get('cost_usd') or 0:>6.3f}  {verify}"
            )


def main() -> int:
    ap = argparse.ArgumentParser(description="Measure one task on several models, one clone each.")
    ap.add_argument("--task", required=True, help="name for this task, used to keep history together")
    ap.add_argument("--prompt-file", required=True, help="file holding the exact prompt every arm receives")
    ap.add_argument("--source", required=True, help="git repo to clone for each arm")
    ap.add_argument("--arm", action="append", required=True, help="provider:model, repeatable")
    ap.add_argument("--verify", help="command run inside each clone after the arm finishes")
    ap.add_argument("--max-turns", type=int, default=60, help="same turn ceiling for every arm (0 = none)")
    ap.add_argument("--run-budget", type=int, default=900, help="seconds of agent time per arm")
    ap.add_argument("--keep", action="store_true", help="keep the clones for inspection")
    args = ap.parse_args()

    arms = []
    for spec in args.arm:
        provider, _, model = spec.partition(":")
        if not model:
            raise SystemExit(f"--arm wants provider:model, got {spec!r}")
        arms.append(Arm(name=re.sub(r"[^a-z0-9]+", "-", model.lower())[:12], provider=provider, model=model))

    prompt_file = Path(args.prompt_file).resolve()
    source = Path(args.source).expanduser().resolve()
    if not prompt_file.exists():
        raise SystemExit(f"no such prompt file: {prompt_file}")
    if not (source / ".git").exists():
        raise SystemExit(f"not a git repository: {source}")
    prompt_text = prompt_file.read_text()

    workroot = SCRATCH / f"replay-{args.task}-{uuid.uuid4().hex[:6]}"
    workroot.mkdir(parents=True, exist_ok=True)
    history_path = RESULTS_DIR / "runs.jsonl"
    runs: list[Run] = []
    try:
        for arm in arms:
            print(f"[{arm.name}] {arm.provider}/{arm.model} ...", file=sys.stderr, flush=True)
            runs.append(
                run_arm(
                    arm, args.task, prompt_text, source, args.verify,
                    args.max_turns or None, args.run_budget, args.keep, workroot,
                )
            )
    finally:
        if not args.keep:
            shutil.rmtree(workroot, ignore_errors=True)
    previous = append_history(runs, history_path) if runs else []
    report(runs, previous)
    return 0 if all(r.status == "completed" for r in runs) else 1


if __name__ == "__main__":
    sys.exit(main())
