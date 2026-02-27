#!/usr/bin/env python3
"""Validate all wikilink references in Ralph Note files.

Scans every note and question file in notes/ (and notes/questions/),
builds an ID-to-filename mapping from YAML frontmatter, and reports
any [[ID]] wikilinks that don't resolve to an existing file.

Also validates that each file is named using its frontmatter ID
(i.e. the filename should be {id}.md).

Usage:
    python scripts/validate_references.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

WORKSPACE = Path(__file__).resolve().parent.parent
NOTES_DIR = WORKSPACE / "notes"

# Matches wikilinks like [[NOTE-20260227-054343-855]] or [[Q-20260227-051858-705]]
WIKILINK_RE = re.compile(r"\[\[((?:NOTE|Q)-\d{8}-\d{6}-\d{3})\]\]")

# Expected filename pattern: {ID}.md
NOTE_ID_RE = re.compile(r"^(NOTE-\d{8}-\d{6}-\d{3})\.md$")
QUESTION_ID_RE = re.compile(r"^(Q-\d{8}-\d{6}-\d{3})\.md$")


def parse_frontmatter(text: str) -> dict | None:
    """Extract YAML frontmatter from a Markdown file."""
    match = re.match(r"^---\n(.+?)\n---", text, re.DOTALL)
    if not match:
        return None
    raw = yaml.safe_load(match.group(1))
    return raw if isinstance(raw, dict) else None


def collect_files() -> list[Path]:
    """Collect all .md files under notes/ recursively."""
    return sorted(NOTES_DIR.rglob("*.md"))


def main() -> int:
    files = collect_files()
    if not files:
        print("No note files found in notes/")
        return 0

    # Build ID → filepath mapping
    id_to_file: dict[str, Path] = {}
    file_to_id: dict[Path, str] = {}
    errors: list[str] = []

    for fpath in files:
        text = fpath.read_text(encoding="utf-8")
        fm = parse_frontmatter(text)
        if fm is None:
            errors.append(f"  {fpath.relative_to(WORKSPACE)}: missing or invalid frontmatter")
            continue

        entry_id = fm.get("id")
        if not entry_id or entry_id == "PLACEHOLDER":
            errors.append(
                f"  {fpath.relative_to(WORKSPACE)}: id is missing or still PLACEHOLDER"
            )
            continue

        if entry_id in id_to_file:
            errors.append(
                f"  {fpath.relative_to(WORKSPACE)}: duplicate ID {entry_id} "
                f"(also in {id_to_file[entry_id].relative_to(WORKSPACE)})"
            )
        id_to_file[entry_id] = fpath
        file_to_id[fpath] = entry_id

    # Validate filenames match IDs
    filename_errors: list[str] = []
    for fpath, entry_id in file_to_id.items():
        expected_name = f"{entry_id}.md"
        if fpath.name != expected_name:
            filename_errors.append(
                f"  {fpath.relative_to(WORKSPACE)}: "
                f"filename should be {expected_name} (id: {entry_id})"
            )

    # Validate wikilink references
    ref_errors: list[str] = []
    for fpath in files:
        text = fpath.read_text(encoding="utf-8")
        for match in WIKILINK_RE.finditer(text):
            ref_id = match.group(1)
            if ref_id not in id_to_file:
                ref_errors.append(
                    f"  {fpath.relative_to(WORKSPACE)}: "
                    f"broken reference [[{ref_id}]] — no file with this ID"
                )

    # Report
    has_errors = False

    if errors:
        has_errors = True
        print(f"Frontmatter errors ({len(errors)}):")
        for e in errors:
            print(e)
        print()

    if filename_errors:
        has_errors = True
        print(f"Filename errors ({len(filename_errors)}):")
        for e in filename_errors:
            print(e)
        print()

    if ref_errors:
        has_errors = True
        print(f"Broken references ({len(ref_errors)}):")
        for e in ref_errors:
            print(e)
        print()

    if not has_errors:
        print(f"All clear: {len(id_to_file)} files validated, "
              f"all filenames match IDs, all references resolve.")
        return 0

    total = len(errors) + len(filename_errors) + len(ref_errors)
    print(f"Total issues: {total}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
