#!/usr/bin/env python3
"""One-time migration: rename note files to {ID}.md and move questions to notes/questions/.

This reads YAML frontmatter from each file in notes/, extracts the ID,
and renames the file accordingly. Question files (type: question) are
moved to notes/questions/{Q-ID}.md.

Usage:
    python scripts/migrate_filenames.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

WORKSPACE = Path(__file__).resolve().parent.parent
NOTES_DIR = WORKSPACE / "notes"
QUESTIONS_DIR = NOTES_DIR / "questions"


def parse_frontmatter(text: str) -> dict | None:
    match = re.match(r"^---\n(.+?)\n---", text, re.DOTALL)
    if not match:
        return None
    raw = yaml.safe_load(match.group(1))
    return raw if isinstance(raw, dict) else None


def main() -> int:
    QUESTIONS_DIR.mkdir(parents=True, exist_ok=True)

    files = sorted(NOTES_DIR.glob("*.md"))
    moved = 0
    renamed = 0
    errors = 0

    for fpath in files:
        text = fpath.read_text(encoding="utf-8")
        fm = parse_frontmatter(text)
        if fm is None:
            print(f"SKIP (no frontmatter): {fpath.name}")
            continue

        entry_id = fm.get("id")
        entry_type = fm.get("type")
        if not entry_id or entry_id == "PLACEHOLDER":
            print(f"SKIP (no ID): {fpath.name}")
            errors += 1
            continue

        expected_name = f"{entry_id}.md"

        if entry_type == "question":
            new_path = QUESTIONS_DIR / expected_name
            if fpath.name == expected_name and fpath.parent == QUESTIONS_DIR:
                continue  # already correct
            if new_path.exists():
                print(f"ERROR: target exists: {new_path.relative_to(WORKSPACE)}")
                errors += 1
                continue
            fpath.rename(new_path)
            action = "moved to questions" if fpath.name != expected_name else "moved"
            print(f"{action}: {fpath.name} -> {new_path.relative_to(WORKSPACE)}")
            moved += 1
        else:
            new_path = NOTES_DIR / expected_name
            if fpath.name == expected_name:
                continue  # already correct
            if new_path.exists():
                print(f"ERROR: target exists: {new_path.relative_to(WORKSPACE)}")
                errors += 1
                continue
            fpath.rename(new_path)
            print(f"renamed: {fpath.name} -> {expected_name}")
            renamed += 1

    print(f"\nDone: {renamed} renamed, {moved} moved to questions/, {errors} errors")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
