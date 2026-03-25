"""Shared terminal formatting utilities for CLI scripts."""

from __future__ import annotations

import os
import sys

COLORS = {
    "bold": "\033[1m",
    "dim": "\033[2m",
    "cyan": "\033[36m",
    "green": "\033[32m",
    "yellow": "\033[33m",
    "red": "\033[31m",
    "reset": "\033[0m",
}
NO_COLORS = {k: "" for k in COLORS}


def _c() -> dict[str, str]:
    """Return color dict, respecting NO_COLOR env and non-TTY."""
    if os.environ.get("NO_COLOR") or not sys.stdout.isatty():
        return NO_COLORS
    return COLORS


def _fmt_tokens(n: int) -> str:
    """Format token count with K/M suffix."""
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)
