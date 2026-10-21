"""Where Hermes keeps its state, and how its scripts read it.

Two of the scripts beside this file (usage-digest.py and replay-task.py) each
opened state.db themselves and each decided independently what a failed tool
result looks like - and the two answers had drifted. The digest matched
"error:" and ignored case; the replay harness compared four substrings with SQL
LIKE and so never counted an "error:" result at all. Both scripts report on the
same sessions, so the two reports were quietly measuring different things. One
definition lives here instead.

peak_price.py and deepseek_budget.py take only the home directory from here:
they write their own small state files and never open the DB.

This file lands in $HERMES_HOME/scripts beside the scripts that import it
(users/snowyrenard/hermes/home.nix declares it - remove that line and the next
rebuild leaves `import hermes_state` failing at runtime). No PYTHONPATH is
involved: python puts the running script's own directory on sys.path, which is
also why the dashboard plugin has to add this directory itself before it loads
deepseek_budget.py from disk.
"""

from __future__ import annotations

import os
import sqlite3
from pathlib import Path

#: HERMES_HOME as the agent itself resolves it: the env var when the wrapper set
#: it, ~/.hermes otherwise. Not Path.home()/".hermes" directly, which would
#: ignore an agent pointed at another home (a second profile, a test run).
HERMES_HOME = Path(os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes"))
DB_PATH = HERMES_HOME / "state.db"

#: What a failed tool result looks like inside a stored message body. Kept as a
#: list because one consumer counts them in SQL (replay-task) and the other
#: scans message bodies it has already fetched (the digest); both read this.
TOOL_ERROR_MARKERS = (
    '"success": false',
    "Traceback (most recent call last)",
    "command not found",
    "no such file",
    "error:",
)


def connect(path: Path | str | None = None) -> sqlite3.Connection:
    """A read-only connection with columns addressable by name.

    Every script here only ever reads: the agent owns state.db and writes it
    while a session runs, so a report must not be able to lock it or leave a
    journal behind.
    """
    con = sqlite3.connect(f"file:{path or DB_PATH}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    return con


def is_tool_error(content: str | None) -> bool:
    """True when a tool message body carries one of the failure markers."""
    text = (content or "").lower()
    return any(marker in text for marker in TOOL_ERROR_MARKERS)


def error_match_sql(column: str = "content") -> tuple[str, list[str]]:
    """(WHERE fragment, LIKE parameters) counting the same markers in SQL.

    The replay harness scores finished sessions straight out of the DB rather
    than loading every tool message into memory, so it needs the markers as SQL.
    Built from TOOL_ERROR_MARKERS so the two cannot drift again.
    """
    clause = " or ".join(f"lower({column}) like ?" for _ in TOOL_ERROR_MARKERS)
    return f"({clause})", [f"%{marker.lower()}%" for marker in TOOL_ERROR_MARKERS]


def human(n: float) -> str:
    """Token counts as 1.20M / 34.50K / 900, so a column stays narrow."""
    for unit, div in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if abs(n) >= div:
            return f"{n / div:.2f}{unit}"
    return f"{int(n)}"


def money(amount) -> str:
    """Dollars at a precision that never rounds a real charge away to $0."""
    value = float(amount)
    if value == 0:
        return "$0"
    if value < 0.01:
        return f"${value:.6f}"
    return f"${value:.4f}"
