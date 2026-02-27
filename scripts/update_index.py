#!/usr/bin/env python3
"""Register a new note or question in the Ralph Note index.

Called by agents after creating a file in notes/. Validates frontmatter,
generates a unique ID and timestamp, and updates _index.md.

Usage:
    python scripts/update_index.py <file_path>
"""

from __future__ import annotations

import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated, Literal, Union

import yaml
from pydantic import BaseModel, Field, TypeAdapter, field_validator

WORKSPACE = Path(__file__).resolve().parent.parent


# ── Frontmatter models ──────────────────────────────────────────────


class NoteFrontmatter(BaseModel):
    type: Literal["note"]
    id: Literal["PLACEHOLDER"]
    title: str = Field(min_length=1, max_length=80)
    answers: str
    source: str = Field(min_length=1)
    tags: list[str] = Field(min_length=1)
    created: Literal["PLACEHOLDER"]

    @field_validator("title")
    @classmethod
    def title_max_words(cls, v: str) -> str:
        if len(v.split()) > 10:
            raise ValueError("title must be 10 words or fewer")
        return v

    @field_validator("source")
    @classmethod
    def source_in_docs(cls, v: str) -> str:
        if not v.startswith("docs/"):
            raise ValueError("source must reference a file in docs/")
        return v

    @field_validator("answers")
    @classmethod
    def answers_format(cls, v: str) -> str:
        if not re.match(r"^Q-\d{8}-\d{6}-\d{3}$", v):
            raise ValueError(
                f"answers must be a valid question ID (Q-YYYYMMDD-HHMMSS-mmm), got '{v}'"
            )
        return v


class QuestionFrontmatter(BaseModel):
    type: Literal["question"]
    id: Literal["PLACEHOLDER"]
    question: str = Field(min_length=1)
    parent: str | None = None
    source: Literal["asker"]
    status: Literal["open"]
    created: Literal["PLACEHOLDER"]

    @field_validator("parent")
    @classmethod
    def parent_format(cls, v: str | None) -> str | None:
        if v is not None and not re.match(r"^Q-\d{8}-\d{6}-\d{3}$", v):
            raise ValueError(
                f"parent must be a valid question ID (Q-YYYYMMDD-HHMMSS-mmm), got '{v}'"
            )
        return v


Frontmatter = Annotated[
    Union[NoteFrontmatter, QuestionFrontmatter],
    Field(discriminator="type"),
]
_validate = TypeAdapter(Frontmatter).validate_python


# ── Helpers ──────────────────────────────────────────────────────────


def parse_frontmatter(text: str) -> dict:
    """Extract and parse YAML frontmatter from a Markdown file."""
    match = re.match(r"^---\n(.+?)\n---", text, re.DOTALL)
    if not match:
        raise ValueError("No valid YAML frontmatter (expected --- delimiters)")
    raw = yaml.safe_load(match.group(1))
    if not isinstance(raw, dict):
        raise ValueError("Frontmatter must be a YAML mapping")
    return raw


def generate_id_and_timestamp(entry_type: str) -> tuple[str, str]:
    """Return (entry_id, iso_timestamp) with millisecond precision."""
    now = datetime.now(timezone.utc)
    datestamp = now.strftime("%Y%m%d-%H%M%S")
    millis = f"{now.microsecond // 1000:03d}"
    iso = now.strftime("%Y-%m-%dT%H:%M:%S.") + millis + "Z"
    prefix = "NOTE" if entry_type == "note" else "Q"
    return f"{prefix}-{datestamp}-{millis}", iso


def replace_placeholders(text: str, entry_id: str, timestamp: str) -> str:
    """Replace id: PLACEHOLDER and created: PLACEHOLDER in frontmatter."""
    text = re.sub(
        r"^id: PLACEHOLDER$", f"id: {entry_id}", text, count=1, flags=re.MULTILINE
    )
    text = re.sub(
        r"^created: PLACEHOLDER$",
        f"created: {timestamp}",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    return text


def update_index(
    index_path: Path,
    entry_type: str,
    entry_id: str,
    timestamp: str,
    data: dict,
) -> None:
    """Append an entry to the correct table in _index.md."""
    content = index_path.read_text(encoding="utf-8")

    if entry_type == "question":
        row = f'| {entry_id} | open | {data["question"]} | {data["source"]} | |'
        content = content.replace(
            "<!-- END QUESTIONS -->", f"{row}\n<!-- END QUESTIONS -->"
        )
    else:
        row = (
            f'| {entry_id} | {data["title"]} | {data.get("answers", "")}'
            f' | {data["source"]} | {timestamp} |'
        )
        content = content.replace(
            "<!-- END NOTES -->", f"{row}\n<!-- END NOTES -->"
        )
        # Mark the referenced question as answered
        answers = data.get("answers")
        if answers:
            lines = content.split("\n")
            for i, line in enumerate(lines):
                if answers in line:
                    lines[i] = line.replace("| open |", "| answered |")
                    lines[i] = re.sub(r"\|\s*\|$", f"| {entry_id} |", lines[i])
            content = "\n".join(lines)

    content = re.sub(
        r"^Last Updated:.*$",
        f"Last Updated: {timestamp}",
        content,
        flags=re.MULTILINE,
    )
    index_path.write_text(content, encoding="utf-8")


# ── CLI ──────────────────────────────────────────────────────────────


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]

    if len(args) != 1:
        print("Usage: uv python scripts/update_index.py <file_path>", file=sys.stderr)
        return 1

    file_path = Path(args[0])
    if not file_path.is_absolute():
        file_path = WORKSPACE / file_path

    if not file_path.exists():
        print(f"Error: file not found: {file_path}", file=sys.stderr)
        return 1

    # Guard: file must be inside notes/
    notes_dir = WORKSPACE / "notes"
    try:
        file_path.resolve().relative_to(notes_dir.resolve())
    except ValueError:
        print(f"Error: file must be inside notes/: {file_path}", file=sys.stderr)
        return 1

    text = file_path.read_text(encoding="utf-8")

    try:
        raw = parse_frontmatter(text)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    try:
        entry = _validate(raw)
    except Exception as exc:
        print(f"Validation error:\n{exc}", file=sys.stderr)
        return 1

    entry_id, timestamp = generate_id_and_timestamp(entry.type)

    updated = replace_placeholders(text, entry_id, timestamp)
    file_path.write_text(updated, encoding="utf-8")

    index_path = WORKSPACE / "_index.md"
    if index_path.exists():
        update_index(index_path, entry.type, entry_id, timestamp, raw)
        print(f"Registered {entry_id} in _index.md")
    else:
        print("Warning: _index.md not found, skipping index update", file=sys.stderr)

    print(f"ID: {entry_id}")
    print(f"Created: {timestamp}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
