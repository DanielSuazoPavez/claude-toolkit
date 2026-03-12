"""Tests for scripts/insights.py — Claude Code transcript analytics."""

from __future__ import annotations

import scripts.insights


def test_import_succeeds():
    """Smoke test: module imports without error."""
    assert hasattr(scripts.insights, "main")
