"""Tests for .github/scripts/format-raiz-changelog.py.

Covers sidecar loading, single-version rendering, range rendering, HTML escaping,
override flags, auto-override, output modes, and edge cases.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / ".github" / "scripts" / "format-raiz-changelog.py"


# === Fixture helpers ===


def _write_sidecar(root: Path, version: str, *, skip: bool = False, headline: str = "",
                   date: str = "2026-04-01", sections: list[dict] | None = None) -> Path:
    d = root / "dist" / "raiz" / "changelog"
    d.mkdir(parents=True, exist_ok=True)
    data = {
        "version": version,
        "date": date,
        "headline": headline,
        "skip": skip,
        "sections": sections or [],
    }
    p = d / f"{version}.json"
    p.write_text(json.dumps(data, indent=2))
    return p


@pytest.fixture
def fixture_root(tmp_path: Path) -> Path:
    """tmp project root with VERSION + several sidecars."""
    (tmp_path / "VERSION").write_text("1.3.0\n")

    _write_sidecar(
        tmp_path, "1.3.0",
        headline="Alpha skill & hook improvements",
        date="2026-04-01",
        sections=[
            {"kind": "skills", "bullets": ["`/alpha-skill` — new brainstorm mode"]},
            {"kind": "hooks", "bullets": ["`gamma-hook` now validates JSON input"]},
        ],
    )
    _write_sidecar(
        tmp_path, "1.2.0",
        headline="Agent upgrades",
        date="2026-03-15",
        sections=[
            {"kind": "agents", "bullets": ["`beta-agent` — phased investigation protocol"]},
        ],
    )
    _write_sidecar(
        tmp_path, "1.1.0",
        headline="Entity & edge cases",
        date="2026-03-01",
        sections=[
            {"kind": "skills", "bullets": ["`/alpha-skill` supports `--hierarchical` for nested <tree> output"]},
            {"kind": "agents", "bullets": ["`beta-agent` handles R&D queries with <context> tags"]},
        ],
    )
    # Skipped version
    _write_sidecar(tmp_path, "1.0.5", skip=True, headline="", date="2026-02-15", sections=[])
    return tmp_path


def run_fmt(root: Path, *args: str, expect_zero: bool = True) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env["FORMAT_RAIZ_PROJECT_ROOT"] = str(root)
    result = subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        env=env,
        capture_output=True,
        text=True,
    )
    if expect_zero and result.returncode != 0:
        raise AssertionError(
            f"Expected exit 0, got {result.returncode}\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
    return result


# === Sidecar loading ===


class TestSidecarLoading:
    def test_valid_sidecar_loads(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--raw")
        assert "## [1.3.0]" in r.stdout

    def test_missing_sidecar_logs_skipping(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "9.9.9", "--raw")
        assert "Skipping v9.9.9: no raiz-relevant changes" in r.stderr

    def test_bad_schema_errors(self, fixture_root: Path) -> None:
        bad = fixture_root / "dist" / "raiz" / "changelog" / "5.0.0.json"
        bad.write_text('{"version": "5.0.0", "date": "not-a-date", "headline": "x", "skip": false}')
        r = run_fmt(fixture_root, "5.0.0", "--raw", expect_zero=False)
        assert r.returncode != 0
        assert "date must match" in r.stderr

    def test_skip_sidecar_produces_minimal_message(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.0.5", "--html")
        assert "v1.0.5" in r.stdout
        assert "no raiz-relevant changes" in r.stdout


# === Single-version rendering ===


class TestSingleVersionRendering:
    def test_raw_has_header(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--raw")
        assert "## [1.3.0] - 2026-04-01 - Alpha skill & hook improvements" in r.stdout

    def test_raw_has_matching_content(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--raw")
        assert "alpha-skill" in r.stdout
        assert "gamma-hook" in r.stdout

    def test_middle_version_extracted(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.2.0", "--raw")
        assert "## [1.2.0]" in r.stdout
        assert "beta-agent" in r.stdout

    def test_last_version_extracted(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.1.0", "--raw")
        assert "## [1.1.0]" in r.stdout

    def test_v_prefix_stripped(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "v1.3.0", "--raw")
        assert "## [1.3.0]" in r.stdout

    def test_latest_resolves_from_version_file(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "latest", "--raw")
        assert "## [1.3.0]" in r.stdout

    def test_html_emoji_header(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--html")
        assert "🔄 <b>claude-toolkit-raiz</b> v1.3.0" in r.stdout

    def test_html_date_headline_italics(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--html")
        assert "<i>2026-04-01 — Alpha skill &amp; hook improvements</i>" in r.stdout

    def test_html_section_header_bold(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--html")
        assert "<b>Skills</b>" in r.stdout
        assert "<b>Hooks</b>" in r.stdout

    def test_html_bullet_dot_prefix_and_code(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--html")
        assert "• <code>/alpha-skill</code>" in r.stdout

    def test_html_has_code_tag(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--html")
        assert "<code>" in r.stdout

    def test_html_date_line(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--html")
        assert "<i>2026-04-01" in r.stdout

    def test_html_bullet_dot_for_hook(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--html")
        assert "• " in r.stdout


# === Range rendering ===


class TestRangeRendering:
    def test_range_includes_to(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--from", "1.1.0", "--raw")
        assert "## [1.3.0]" in r.stdout

    def test_range_includes_middle(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--from", "1.1.0", "--raw")
        assert "## [1.2.0]" in r.stdout

    def test_range_excludes_from(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--from", "1.1.0", "--raw")
        assert "## [1.1.0]" not in r.stdout

    def test_range_newest_first_order(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--from", "1.1.0", "--raw")
        pos_130 = r.stdout.find("## [1.3.0]")
        pos_120 = r.stdout.find("## [1.2.0]")
        assert 0 <= pos_130 < pos_120

    def test_same_version_range_empty(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.2.0", "--from", "1.2.0", "--raw")
        assert r.returncode == 0
        assert "no versions found" in r.stderr

    def test_single_version_no_from(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.2.0", "--raw")
        assert "## [1.2.0]" in r.stdout
        assert "## [1.3.0]" not in r.stdout
        assert "## [1.1.0]" not in r.stdout

    def test_range_header_format_html(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--from", "1.1.0", "--html")
        assert "v1.1.0 →" in r.stdout
        assert "→ v1.3.0" in r.stdout

    def test_range_no_date_italic(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--from", "1.1.0", "--html")
        assert "<i>" not in r.stdout

    def test_range_cross_version_merge(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--from", "1.1.0", "--html")
        assert "alpha-skill" in r.stdout
        assert "beta-agent" in r.stdout
        assert "<b>Agents</b>" in r.stdout

    def test_range_no_per_version_emoji_header(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--from", "1.1.0", "--html")
        assert "claude-toolkit-raiz</b> v1.2.0" not in r.stdout

    def test_range_skips_no_match_version(self, fixture_root: Path) -> None:
        # 1.0.5 is skip=true — range (0.9.0, 1.1.0] should include only 1.1.0 content
        r = run_fmt(fixture_root, "1.1.0", "--from", "0.9.0", "--raw")
        assert "## [1.1.0]" in r.stdout
        assert "## [1.0.5]" not in r.stdout
        assert "Skipping v1.0.5: no raiz-relevant changes" in r.stderr

    def test_range_dedupes_bullets(self, tmp_path: Path) -> None:
        (tmp_path / "VERSION").write_text("2.0.0\n")
        _write_sidecar(
            tmp_path, "2.0.0",
            headline="v2 headline",
            sections=[{"kind": "skills", "bullets": ["dup bullet"]}],
        )
        _write_sidecar(
            tmp_path, "1.9.0",
            headline="v1.9 headline",
            sections=[{"kind": "skills", "bullets": ["dup bullet"]}],
        )
        r = run_fmt(tmp_path, "2.0.0", "--from", "1.8.0", "--html")
        assert r.stdout.count("• dup bullet") == 1


# === HTML escaping ===


class TestHtmlEscaping:
    def test_angle_brackets_escaped(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.1.0", "--html")
        assert "&lt;tree&gt;" in r.stdout
        assert "&lt;context&gt;" in r.stdout

    def test_ampersand_escaped(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.1.0", "--html")
        assert "R&amp;D" in r.stdout

    def test_backtick_to_code(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--html")
        assert "<code>/alpha-skill</code>" in r.stdout

    def test_headline_escaped(self, tmp_path: Path) -> None:
        (tmp_path / "VERSION").write_text("1.0.0\n")
        _write_sidecar(
            tmp_path, "1.0.0",
            headline="A & B < C > D",
            sections=[{"kind": "other", "bullets": ["x"]}],
        )
        r = run_fmt(tmp_path, "1.0.0", "--html")
        assert "A &amp; B &lt; C &gt; D" in r.stdout


# === Override flags ===


class TestOverride:
    def test_manual_override_flag(self, fixture_root: Path, tmp_path: Path) -> None:
        override = tmp_path / "manual-override.html"
        override.write_text("<b>Manual msg</b>")
        r = run_fmt(fixture_root, "1.3.0", "--override", str(override))
        assert "<b>Manual msg</b>" in r.stdout

    def test_override_missing_file_errors(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--override", "/nonexistent", expect_zero=False)
        assert r.returncode != 0
        assert "override file not found" in r.stderr

    def test_auto_override_replaces_html(self, fixture_root: Path) -> None:
        (fixture_root / "dist" / "raiz" / "changelog" / "1.2.0.html").write_text(
            "<b>Custom override</b> for v1.2.0"
        )
        r = run_fmt(fixture_root, "1.2.0", "--html")
        assert "Custom override" in r.stdout

    def test_auto_override_raw_still_rendered(self, fixture_root: Path) -> None:
        (fixture_root / "dist" / "raiz" / "changelog" / "1.2.0.html").write_text(
            "<b>Custom override</b>"
        )
        r = run_fmt(fixture_root, "1.2.0", "--raw")
        assert "## [1.2.0]" in r.stdout
        assert "beta-agent" in r.stdout


# === Output modes ===


class TestOutputModes:
    def test_raw_no_html_tags(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--raw")
        assert "<b>" not in r.stdout
        assert "<i>" not in r.stdout

    def test_html_no_markdown_headers(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--html")
        assert "## [" not in r.stdout
        assert "### " not in r.stdout

    def test_out_writes_to_file(self, fixture_root: Path, tmp_path: Path) -> None:
        out = tmp_path / "out.html"
        run_fmt(fixture_root, "1.3.0", "--html", "--out", str(out))
        assert out.is_file()
        assert "v1.3.0" in out.read_text()

    def test_default_mode_has_stats(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0")
        assert "=== Stats ===" in r.stdout
        assert "bullet lines" in r.stdout
        assert "Message length" in r.stdout


# === Minimal messages ===


class TestMinimalMessages:
    def test_all_skipped_minimal_raw(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.0.5", "--raw")
        assert r.returncode == 0
        assert "no raiz-relevant changes" in r.stdout
        assert "Skipping v1.0.5" in r.stderr

    def test_single_no_match_html(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.0.5", "--html")
        assert r.returncode == 0
        assert "claude-toolkit-raiz" in r.stdout
        assert "v1.0.5" in r.stdout
        assert "no raiz-relevant changes" in r.stdout

    def test_missing_version_raw_minimal(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "9.9.9", "--raw")
        assert r.returncode == 0
        assert "no raiz-relevant changes" in r.stdout


# === Edge cases ===


class TestEdgeCases:
    def test_no_args_shows_usage(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, expect_zero=False)
        assert r.returncode != 0
        assert "Usage:" in r.stderr

    def test_unknown_flag_errors(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--bogus", expect_zero=False)
        assert r.returncode != 0
        assert "Unknown flag" in r.stderr

    def test_trailing_whitespace_stripped(self, fixture_root: Path) -> None:
        r = run_fmt(fixture_root, "1.3.0", "--raw")
        last_line = r.stdout.rstrip("\n").splitlines()[-1]
        assert last_line.strip() != ""

    def test_no_changelog_dir(self, tmp_path: Path) -> None:
        (tmp_path / "VERSION").write_text("1.0.0\n")
        r = run_fmt(tmp_path, "1.0.0", "--raw")
        assert r.returncode == 0
        assert "no raiz-relevant changes" in r.stdout
