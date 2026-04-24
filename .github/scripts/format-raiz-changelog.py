#!/usr/bin/env python3
"""Format a raiz Telegram notification from per-version JSON sidecars.

Reads `dist/raiz/changelog/<version>.json` sidecars (schema described in
CLAUDE.md) and renders trimmed markdown + Telegram HTML.

Usage:
    format-raiz-changelog.py <version|latest> [--raw|--html] [--out <file>]
                             [--from <version>] [--override <file>]
"""

from __future__ import annotations

import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_PROJECT_ROOT = SCRIPT_DIR.parent.parent
PROJECT_ROOT = Path(os.environ.get("FORMAT_RAIZ_PROJECT_ROOT") or DEFAULT_PROJECT_ROOT)

ALLOWED_KINDS = {"skills", "agents", "hooks", "docs", "scripts", "templates", "other"}
KIND_ORDER = ["skills", "agents", "hooks", "docs", "scripts", "templates", "other"]
KIND_LABELS = {
    "skills": "Skills",
    "agents": "Agents",
    "hooks": "Hooks",
    "docs": "Docs",
    "scripts": "Scripts",
    "templates": "Templates",
    "other": "Other",
}


# === Data ===


@dataclass
class Section:
    kind: str
    bullets: list[str]


@dataclass
class Sidecar:
    version: str
    date: str
    headline: str
    skip: bool
    sections: list[Section] = field(default_factory=list)


class SidecarError(Exception):
    pass


# === Loading / validation ===


def _require(cond: bool, path: Path, msg: str) -> None:
    if not cond:
        raise SidecarError(f"{path}: {msg}")


def load_sidecar(path: Path) -> Sidecar:
    if not path.is_file():
        raise SidecarError(f"{path}: sidecar not found")
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        raise SidecarError(f"{path}: invalid JSON — {e}") from e

    _require(isinstance(data, dict), path, "top-level must be an object")
    for key in ("version", "date", "headline", "skip"):
        _require(key in data, path, f"missing required key: {key}")

    version = data["version"]
    date = data["date"]
    headline = data["headline"]
    skip = data["skip"]

    _require(isinstance(version, str) and version.strip(), path, "version must be non-empty string")
    _require(
        isinstance(date, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", date) is not None,
        path,
        "date must match YYYY-MM-DD",
    )
    _require(isinstance(headline, str), path, "headline must be string")
    _require(isinstance(skip, bool), path, "skip must be boolean")

    sections: list[Section] = []
    raw_sections = data.get("sections", [])
    _require(isinstance(raw_sections, list), path, "sections must be a list")

    if not skip:
        _require(headline.strip() != "", path, "headline must be non-empty when skip=false")
        _require(len(raw_sections) > 0, path, "sections must be non-empty when skip=false")

    for idx, raw in enumerate(raw_sections):
        _require(isinstance(raw, dict), path, f"sections[{idx}] must be an object")
        _require("kind" in raw and "bullets" in raw, path, f"sections[{idx}] missing kind/bullets")
        kind = raw["kind"]
        bullets = raw["bullets"]
        _require(
            isinstance(kind, str) and kind in ALLOWED_KINDS,
            path,
            f"sections[{idx}].kind must be one of {sorted(ALLOWED_KINDS)}",
        )
        _require(isinstance(bullets, list), path, f"sections[{idx}].bullets must be a list")
        if not skip:
            _require(len(bullets) > 0, path, f"sections[{idx}].bullets must be non-empty")
        for bidx, b in enumerate(bullets):
            _require(
                isinstance(b, str) and b.strip() != "",
                path,
                f"sections[{idx}].bullets[{bidx}] must be a non-empty string",
            )
        sections.append(Section(kind=kind, bullets=list(bullets)))

    return Sidecar(version=version, date=date, headline=headline, skip=skip, sections=sections)


def sidecar_path(version: str, project_root: Path) -> Path:
    return project_root / "dist" / "raiz" / "changelog" / f"{version}.json"


def override_html_path(version: str, project_root: Path) -> Path:
    return project_root / "dist" / "raiz" / "changelog" / f"{version}.html"


# === Version listing ===


_SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def _semver_tuple(v: str) -> tuple[int, int, int]:
    m = _SEMVER.match(v)
    if not m:
        raise ValueError(f"not a semver: {v}")
    return int(m.group(1)), int(m.group(2)), int(m.group(3))


def list_versions_in_range(from_v: str, to_v: str, project_root: Path) -> list[str]:
    """Return all sidecar versions in (from_v, to_v], descending."""
    if from_v == to_v:
        return []

    changelog_dir = project_root / "dist" / "raiz" / "changelog"
    if not changelog_dir.is_dir():
        return [to_v]

    try:
        from_tuple = _semver_tuple(from_v)
        to_tuple = _semver_tuple(to_v)
    except ValueError:
        return [to_v]

    found: set[str] = set()
    for p in changelog_dir.glob("*.json"):
        stem = p.stem
        try:
            t = _semver_tuple(stem)
        except ValueError:
            continue
        if from_tuple < t <= to_tuple:
            found.add(stem)

    found.add(to_v)
    return sorted(found, key=_semver_tuple, reverse=True)


# === Rendering: raw markdown ===


def _raw_header(sc: Sidecar) -> str:
    return f"## [{sc.version}] - {sc.date} - {sc.headline}"


def render_raw_single(sc: Sidecar) -> str:
    """Render a single sidecar as trimmed markdown (header + ### sections)."""
    lines: list[str] = [_raw_header(sc)]
    if sc.skip or not sc.sections:
        return lines[0]

    # Merge bullets across same-kind sections (within a single sidecar, preserve order)
    ordered: list[tuple[str, list[str]]] = []
    for kind in KIND_ORDER:
        merged: list[str] = []
        for sect in sc.sections:
            if sect.kind == kind:
                merged.extend(sect.bullets)
        if merged:
            ordered.append((kind, merged))

    for kind, bullets in ordered:
        lines.append("")
        lines.append(f"### {KIND_LABELS[kind]}")
        for b in bullets:
            lines.append(f"- {b}")

    return "\n".join(lines)


def render_raw(sidecars: list[Sidecar]) -> str:
    """Concatenate per-version raw renderings, newest first, separated by blank lines."""
    chunks = [render_raw_single(sc) for sc in sidecars]
    return "\n\n".join(chunks).rstrip()


# === Rendering: Telegram HTML ===


def _html_escape(s: str) -> str:
    # Order matters: ampersand first to avoid double-escaping.
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


_BACKTICK_RE = re.compile(r"`([^`]*)`")


def _render_bullet_html(bullet: str) -> str:
    escaped = _html_escape(bullet)
    return _BACKTICK_RE.sub(r"<code>\1</code>", escaped)


def _merge_bullets_by_kind(sidecars: list[Sidecar]) -> dict[str, list[str]]:
    """Concatenate bullets across all sidecars, grouped by kind, dedup preserving first seen."""
    grouped: dict[str, list[str]] = {k: [] for k in KIND_ORDER}
    seen: dict[str, set[str]] = {k: set() for k in KIND_ORDER}
    for sc in sidecars:
        if sc.skip:
            continue
        for sect in sc.sections:
            for b in sect.bullets:
                if b in seen[sect.kind]:
                    continue
                seen[sect.kind].add(b)
                grouped[sect.kind].append(b)
    return grouped


def render_html(sidecars: list[Sidecar], target_version: str, from_version: str | None) -> str:
    """Render the Telegram HTML message.

    `target_version` and `from_version` drive the header; `sidecars` supplies the body.
    """
    # Header
    if from_version:
        header = f"🔄 <b>claude-toolkit-raiz</b> v{from_version} → v{target_version}"
    else:
        header = f"🔄 <b>claude-toolkit-raiz</b> v{target_version}"
        # Single-version mode: append date/headline italics if we have the target sidecar.
        target_sc = next((sc for sc in sidecars if sc.version == target_version and not sc.skip), None)
        if target_sc is not None:
            italic_body = f"{target_sc.date} — {_html_escape(target_sc.headline)}"
            header += f"\n<i>{italic_body}</i>"

    grouped = _merge_bullets_by_kind(sidecars)
    has_content = any(bullets for bullets in grouped.values())

    if not has_content:
        # Minimal "no raiz-relevant changes" message.
        if from_version:
            return f"🔄 <b>claude-toolkit-raiz</b> v{from_version} → v{target_version}\n<i>no raiz-relevant changes</i>"
        target_sc = next((sc for sc in sidecars if sc.version == target_version), None)
        base = f"🔄 <b>claude-toolkit-raiz</b> v{target_version}"
        if target_sc is not None:
            return f"{base}\n<i>{target_sc.date} — no raiz-relevant changes</i>"
        return f"{base}\n<i>no raiz-relevant changes</i>"

    body_lines: list[str] = []
    first = True
    for kind in KIND_ORDER:
        bullets = grouped[kind]
        if not bullets:
            continue
        if not first:
            body_lines.append("")
        first = False
        body_lines.append(f"<b>{KIND_LABELS[kind]}</b>")
        for b in bullets:
            body_lines.append(f"• {_render_bullet_html(b)}")

    return header + "\n\n" + "\n".join(body_lines)


# === CLI ===


def _usage_error(msg: str = "") -> int:
    if msg:
        print(msg, file=sys.stderr)
    print(
        "Usage: format-raiz-changelog.py <version|latest> [--raw|--html] "
        "[--out <file>] [--from <version>] [--override <file>]",
        file=sys.stderr,
    )
    return 1


def _strip_v(s: str) -> str:
    return s[1:] if s.startswith("v") else s


def _parse_args(argv: list[str]) -> tuple[str | None, str | None, str, str | None, str | None] | int:
    version: str | None = None
    from_version: str | None = None
    mode = "both"  # "both" | "--raw" | "--html"
    out_file: str | None = None
    override_file: str | None = None

    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("--raw", "--html"):
            mode = arg
            i += 1
        elif arg == "--out":
            if i + 1 >= len(argv):
                return _usage_error("--out requires a value")
            out_file = argv[i + 1]
            i += 2
        elif arg == "--override":
            if i + 1 >= len(argv):
                return _usage_error("--override requires a value")
            override_file = argv[i + 1]
            i += 2
        elif arg == "--from":
            if i + 1 >= len(argv):
                return _usage_error("--from requires a value")
            from_version = _strip_v(argv[i + 1])
            i += 2
        elif arg.startswith("-"):
            return _usage_error(f"Unknown flag: {arg}")
        else:
            version = arg
            i += 1

    if version is None:
        return _usage_error()

    return version, from_version, mode, out_file, override_file


def _emit(text: str, out_file: str | None) -> None:
    if out_file:
        Path(out_file).write_text(text + ("\n" if not text.endswith("\n") else ""))
        print(f"Wrote {len(text)} chars to {out_file}", file=sys.stderr)
    else:
        print(text)


def _resolve_target_version(version: str, project_root: Path) -> str:
    version = _strip_v(version)
    if version == "latest":
        version_file = project_root / "VERSION"
        if not version_file.is_file():
            raise SidecarError(f"VERSION file not found: {version_file}")
        version = version_file.read_text().strip()
    return version


def _load_version_sidecar(version: str, project_root: Path) -> Sidecar | None:
    """Load a sidecar, or None if missing. Logs skip to stderr for both missing & skip=true."""
    path = sidecar_path(version, project_root)
    if not path.is_file():
        print(f"Skipping v{version}: no raiz-relevant changes", file=sys.stderr)
        return None
    sc = load_sidecar(path)
    if sc.version != version:
        raise SidecarError(f"{path}: version mismatch (file says {sc.version}, expected {version})")
    if sc.skip:
        print(f"Skipping v{version}: no raiz-relevant changes", file=sys.stderr)
        return sc
    return sc


def main(argv: list[str]) -> int:
    parsed = _parse_args(argv)
    if isinstance(parsed, int):
        return parsed
    version, from_version, mode, out_file, override_file = parsed

    project_root = PROJECT_ROOT

    # Manual override: emit file as-is, early exit.
    if override_file:
        p = Path(override_file)
        if not p.is_file():
            print(f"Error: override file not found: {override_file}", file=sys.stderr)
            return 1
        _emit(p.read_text().rstrip("\n"), out_file)
        return 0

    try:
        target_version = _resolve_target_version(version, project_root)
    except SidecarError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    # Empty range shortcut
    if from_version is not None and from_version == target_version:
        print(f"(no versions found between {from_version} and {target_version})", file=sys.stderr)
        return 0

    # Build version list
    if from_version is not None:
        versions = list_versions_in_range(from_version, target_version, project_root)
    else:
        versions = [target_version]

    # Load sidecars (skips contribute nothing; missing ones already logged)
    loaded: list[Sidecar] = []
    try:
        for v in versions:
            sc = _load_version_sidecar(v, project_root)
            if sc is not None and not sc.skip:
                loaded.append(sc)
    except SidecarError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    # Auto-override HTML
    auto_override_html: str | None = None
    auto_path = override_html_path(target_version, project_root)
    if auto_path.is_file():
        print(f"Using override for v{target_version}: {auto_path}", file=sys.stderr)
        auto_override_html = auto_path.read_text().rstrip("\n")

    # Render raw
    if loaded:
        raw_text = render_raw(loaded)
    else:
        raw_text = "(no raiz-relevant changes)"

    # Render HTML
    if auto_override_html is not None:
        html_text = auto_override_html
    else:
        html_text = render_html(loaded, target_version, from_version)

    if mode == "--raw":
        _emit(raw_text, out_file)
        return 0
    if mode == "--html":
        _emit(html_text, out_file)
        return 0

    # Default "both" mode — stats included. Ignores --out.
    full_bullets = 0
    kept_bullets = 0
    for sc in loaded:
        for sect in sc.sections:
            full_bullets += len(sect.bullets)
            kept_bullets += len(sect.bullets)

    print("=== Trimmed Markdown ===")
    print(raw_text)
    print()
    print("=== Telegram HTML ===")
    print(html_text)
    print()
    print("=== Stats ===")
    versions_label = " ".join(versions)
    print(f"Versions: {len(versions)} ({versions_label})")
    print(f"Full entry: {full_bullets} bullet lines")
    print(f"After trim: {kept_bullets} bullet lines")
    print(f"Message length: {len(html_text)} chars (limit: 4096)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
