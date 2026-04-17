#!/usr/bin/env python3
"""Create a new note file in notes/ and immediately register it in _index.md.

Usage:
    uv run scripts/create_note.py --title "..." --answers "Q-..." --source "docs/..." --tags "tag1,tag2" --body "..."

Options:
    --title       Brief title (max 10 words)
    --answers     Question ID this note answers (Q-YYYYMMDD-HHMMSS-mmm)
    --source      Source document path (must start with docs/)
    --tags        Comma-separated list of tags
    --body        Note body text (1–3 paragraphs)
    --related     Related note with optional description, repeatable:
                  --related "NOTE-ID" or --related "NOTE-ID: description"

The script writes the note, assigns a real ID and timestamp, renames the file to
its ID, and updates _index.md — all in one step.
"""

from __future__ import annotations

import argparse
import sys
import uuid
from pathlib import Path

from pydantic import ValidationError

sys.path.insert(0, str(Path(__file__).parent))
from models import NoteFrontmatter  # noqa: E402
from update_index import process_file  # noqa: E402

WORKSPACE = Path(__file__).resolve().parent.parent


def build_frontmatter(title: str, answers: str, source: str, tags: list[str]) -> str:
    tags_inline = "[" + ", ".join(tags) + "]"
    return (
        "---\n"
        "type: note\n"
        "id: PLACEHOLDER\n"
        f'title: "{title}"\n'
        f'answers: "{answers}"\n'
        f'source: "{source}"\n'
        f"tags: {tags_inline}\n"
        "created: PLACEHOLDER\n"
        "---"
    )


def build_related_section(related: list[str]) -> str:
    if not related:
        return ""
    lines = ["", "## Related"]
    for item in related:
        item = item.strip()
        if ":" in item:
            note_id, _, desc = item.partition(":")
            note_id = note_id.strip()
            desc = desc.strip()
            lines.append(f"- [[{note_id}]] - {desc}")
        else:
            lines.append(f"- [[{item}]]")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a note file in notes/")
    parser.add_argument("--title", required=True, help="Brief title (max 10 words)")
    parser.add_argument("--answers", required=True, help="Question ID this note answers")
    parser.add_argument("--source", required=True, help="Source document path (docs/...)")
    parser.add_argument("--tags", required=True, help="Comma-separated tags")
    parser.add_argument("--body", required=True, help="Note body text")
    parser.add_argument(
        "--related",
        action="append",
        default=[],
        metavar="NOTE-ID[:description]",
        help="Related note ID with optional description (repeatable)",
    )
    args = parser.parse_args()

    tags = [t.strip() for t in args.tags.split(",") if t.strip()]

    try:
        NoteFrontmatter(
            type="note",
            id="PLACEHOLDER",
            title=args.title,
            answers=args.answers,
            source=args.source,
            tags=tags,
            created="PLACEHOLDER",
        )
    except ValidationError as exc:
        print(f"Validation error:\n{exc}", file=sys.stderr)
        return 1

    frontmatter = build_frontmatter(args.title, args.answers, args.source, tags)
    related_section = build_related_section(args.related)
    body = args.body.strip()

    content = f"{frontmatter}\n\n{body}{related_section}\n"

    notes_dir = WORKSPACE / "notes"
    notes_dir.mkdir(parents=True, exist_ok=True)
    file_path = notes_dir / f"temp-{uuid.uuid4().hex[:8]}.md"
    file_path.write_text(content, encoding="utf-8")

    result = process_file(file_path)
    if result is None:
        return 1
    entry_id, new_path, timestamp = result
    return 0


if __name__ == "__main__":
    sys.exit(main())
