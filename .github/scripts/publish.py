#!/usr/bin/env python3
"""Build a distribution from toolkit resources.

Reads a distribution MANIFEST, copies matching resources, and trims
cross-references to anything not in the subset.

Usage:
    uv run scripts/publish.py <dist_name> [output_dir]
    Example: uv run scripts/publish.py raiz
    Default output: dist-output/<dist_name>/
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

TOOLKIT_DIR = Path(__file__).resolve().parent.parent.parent
CLAUDE_DIR = TOOLKIT_DIR / ".claude"

# Colors
GREEN = "\033[0;32m"
RED = "\033[0;31m"
NC = "\033[0m"


# === MANIFEST parsing ===


def resolve_source_file(target_path: str, claude_dir: Path, dist_dir: Path) -> Path:
    """Resolve a target path to its source file location.

    docs/*       → repo root (outside .claude/)
    templates/*  → dist-specific override if exists, else dist/base/templates/
    everything else → claude_dir/{target_path}
    """
    if target_path.startswith("docs/"):
        return claude_dir.parent / target_path
    if target_path.startswith("templates/"):
        basename = target_path.removeprefix("templates/")
        override = dist_dir / "templates" / basename
        if override.is_file():
            return override
        return claude_dir.parent / "dist" / "base" / "templates" / basename
    return claude_dir / target_path


def resolve_source_dir(target_path: str, claude_dir: Path, dist_dir: Path) -> Path:
    """Resolve a target directory path to its source directory.

    docs/*       → repo root (outside .claude/)
    templates/*  → always from dist/base/ (dist only has file-level overrides)
    everything else → claude_dir/{target_path}
    """
    clean = target_path.rstrip("/")
    if clean.startswith("docs/"):
        return claude_dir.parent / clean
    if clean.startswith("templates/"):
        return claude_dir.parent / "dist" / "base" / clean
    return claude_dir / clean


def resolve_manifest(manifest_path: Path, claude_dir: Path, dist_dir: Path) -> list[str]:
    """Parse MANIFEST and return expanded list of target paths."""
    targets: list[str] = []
    for raw_line in manifest_path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if line.endswith("/"):
            # Directory entry — expand to individual files
            source_dir = resolve_source_dir(line, claude_dir, dist_dir)
            if source_dir.is_dir():
                for f in sorted(source_dir.rglob("*")):
                    if f.is_file():
                        targets.append(line + str(f.relative_to(source_dir)))
            else:
                print(f"Warning: directory not found: {line} (source: {source_dir})", file=sys.stderr)
        else:
            source_file = resolve_source_file(line, claude_dir, dist_dir)
            if source_file.is_file():
                targets.append(line)
            else:
                print(f"Warning: file not found: {line} (source: {source_file})", file=sys.stderr)
    return targets


# === Resource list building ===


def build_resource_lists(manifest_path: Path) -> dict[str, list[str]]:
    """Parse MANIFEST and return resource names by category."""
    resources: dict[str, list[str]] = {
        "skills": [],
        "agents": [],
        "hooks": [],
        "memories": [],
    }
    for raw_line in manifest_path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if line.startswith("skills/"):
            # skills/brainstorm-idea/ → brainstorm-idea
            name = line.removeprefix("skills/").rstrip("/")
            resources["skills"].append(name)
        elif line.startswith("agents/"):
            # agents/code-debugger.md → code-debugger
            name = line.removeprefix("agents/").removesuffix(".md")
            resources["agents"].append(name)
        elif line.startswith("hooks/"):
            # hooks/block-config-edits.sh → block-config-edits.sh (keep extension)
            resources["hooks"].append(line.removeprefix("hooks/"))
        elif line.startswith("memories/"):
            # memories/essential-conventions-code_style.md → essential-conventions-code_style
            name = line.removeprefix("memories/").removesuffix(".md")
            resources["memories"].append(name)
    return resources


# === Trimming ===


def should_keep_ref(ref: str, resources: dict[str, list[str]]) -> bool:
    """Check if a single ref string references a resource in the distribution."""
    # Skill ref: `/skill-name`
    m = re.search(r"`/([a-z][-a-z0-9]*)`", ref)
    if m:
        return m.group(1) in resources["skills"]

    # Agent ref: `agent-name` agent
    m = re.search(r"`([a-z][-a-z0-9]*)`\s+agent", ref)
    if m:
        return m.group(1) in resources["agents"]

    # Memory ref: `memory-name` (for|memory|—)
    m = re.search(r"`([a-z][-a-z_0-9]*)`\s+(for|memory|—)", ref)
    if m:
        return m.group(1) in resources["memories"]

    # Unknown ref type — keep it
    return True


def trim_bullet_line(line: str, resources: dict[str, list[str]]) -> str | None:
    """Check if a bullet line references an excluded resource. Returns None to remove."""
    # Skill bullet: - `/skill-name` ...
    m = re.match(r"^\s*-\s+`/([a-z][-a-z0-9]*)`", line)
    if m and m.group(1) not in resources["skills"]:
        return None

    # Agent bullet: - `agent-name` agent ...
    m = re.match(r"^\s*-\s+`([a-z][-a-z0-9]*)`\s+agent", line)
    if m and m.group(1) not in resources["agents"]:
        return None

    # Memory bullet: - `memory-name` memory ...
    m = re.match(r"^\s*-\s+`([a-z][-a-z_0-9]*)`\s+memory", line)
    if m and m.group(1) not in resources["memories"]:
        return None

    return line


def trim_see_also_line(line: str, resources: dict[str, list[str]]) -> str | None:
    """Trim a See also: line, keeping only refs in the distribution. Returns None if all removed."""
    m = re.match(r"^(\*\*See also:\*\*\s*|See also:\s*)", line)
    if not m:
        return line

    prefix = m.group(1)
    refs_part = line[len(prefix):]

    # Split on comma-before-backtick: ", `" → split just before the backtick
    refs = re.split(r",\s*(?=`)", refs_part)
    kept = [ref for ref in refs if ref.strip() and should_keep_ref(ref, resources)]

    if not kept:
        return None

    return prefix + ", ".join(kept)


def trim_markdown(content: str, resources: dict[str, list[str]]) -> str:
    """Trim cross-references to excluded resources from markdown content."""
    lines = content.splitlines()
    result: list[str] = []

    for line in lines:
        # Check See also lines first (they have their own logic)
        if re.match(r"^(\*\*See also:\*\*|See also:)", line):
            trimmed = trim_see_also_line(line, resources)
            if trimmed is not None:
                result.append(trimmed)
            continue

        # Check bullet lines
        if re.match(r"^\s*-\s+`", line):
            trimmed = trim_bullet_line(line, resources)
            if trimmed is not None:
                result.append(trimmed)
            continue

        result.append(line)

    # Post-pass: remove orphaned ## See Also headers (next non-empty line is not a bullet)
    final: list[str] = []
    i = 0
    while i < len(result):
        if re.match(r"^##\s+See\s+Also\s*$", result[i]):
            # Look ahead for content under this header
            j = i + 1
            while j < len(result) and result[j].strip() == "":
                j += 1
            if j >= len(result) or not re.match(r"^\s*-\s+", result[j]):
                # No bullet content follows — skip header and trailing blank lines
                i = j
                continue
        final.append(result[i])
        i += 1

    result_text = "\n".join(final)
    # Preserve trailing newline if original had one
    if content.endswith("\n") and not result_text.endswith("\n"):
        result_text += "\n"
    return result_text


def trim_settings_json(content: str, hooks: list[str]) -> str:
    """Filter settings.template.json to only include distribution hooks, remove statusLine."""
    data = json.loads(content)

    # Build regex pattern for matching hook commands
    hook_pattern = "|".join(re.escape(h) for h in hooks)

    # Filter hooks
    if "hooks" in data:
        new_hooks = {}
        for event, entries in data["hooks"].items():
            new_entries = []
            for entry in entries:
                if "hooks" in entry:
                    filtered = [
                        h for h in entry["hooks"]
                        if re.search(hook_pattern, h.get("command", ""))
                    ]
                    if filtered:
                        new_entry = dict(entry)
                        new_entry["hooks"] = filtered
                        new_entries.append(new_entry)
                else:
                    new_entries.append(entry)
            if new_entries:
                new_hooks[event] = new_entries
        data["hooks"] = new_hooks

    # Remove statusLine
    data.pop("statusLine", None)

    return json.dumps(data, indent=2) + "\n"


# === Main ===


def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <dist_name> [output_dir]", file=sys.stderr)
        sys.exit(1)

    dist_name = sys.argv[1]
    dist_dir = TOOLKIT_DIR / "dist" / dist_name
    manifest_path = dist_dir / "MANIFEST"

    if not manifest_path.is_file():
        print(f"{RED}MANIFEST not found: {manifest_path}{NC}", file=sys.stderr)
        sys.exit(1)

    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else TOOLKIT_DIR / "dist-output" / dist_name
    claude_output = output_dir / ".claude"

    print(f"Building {dist_name} distribution...")
    print(f"  Source: {CLAUDE_DIR}")
    print(f"  Output: {output_dir}")
    print()

    # Clean output
    if output_dir.exists():
        shutil.rmtree(output_dir)
    claude_output.mkdir(parents=True)

    # Build resource lists for trimming
    resources = build_resource_lists(manifest_path)
    print(
        f"Resources: {len(resources['skills'])} skills, "
        f"{len(resources['agents'])} agents, "
        f"{len(resources['hooks'])} hooks, "
        f"{len(resources['memories'])} memories"
    )
    print()

    # Resolve and copy files
    targets = resolve_manifest(manifest_path, CLAUDE_DIR, dist_dir)
    for target_path in targets:
        source = resolve_source_file(target_path, CLAUDE_DIR, dist_dir)
        # docs/ files go to output root, everything else to .claude/
        if target_path.startswith("docs/"):
            dest = output_dir / target_path
        else:
            dest = claude_output / target_path
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)

    print(f"Copied {len(targets)} files")

    # Trim cross-references in markdown files
    print("Trimming cross-references...")
    for md_file in output_dir.rglob("*.md"):
        content = md_file.read_text()
        trimmed = trim_markdown(content, resources)
        md_file.write_text(trimmed)

    # Trim settings template
    settings_file = claude_output / "templates" / "settings.template.json"
    if settings_file.is_file():
        print("Trimming settings.template.json...")
        content = settings_file.read_text()
        trimmed = trim_settings_json(content, resources["hooks"])
        settings_file.write_text(trimmed)

    print()
    print(f"{GREEN}{dist_name.capitalize()} distribution built at: {output_dir}{NC}")
    print()

    # Summary
    print("Contents:")
    for category in ("skills", "agents", "hooks", "memories", "templates"):
        cat_dir = claude_output / category
        if cat_dir.is_dir():
            count = sum(1 for f in cat_dir.rglob("*") if f.is_file())
            print(f"  {category}: {count} files")
    # Root-level directories (docs/, etc.)
    for category in ("docs",):
        cat_dir = output_dir / category
        if cat_dir.is_dir():
            count = sum(1 for f in cat_dir.rglob("*") if f.is_file())
            print(f"  {category}: {count} files")


if __name__ == "__main__":
    main()
