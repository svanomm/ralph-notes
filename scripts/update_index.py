#!/usr/bin/env python3
"""Register new notes and questions in the Ralph Note index.

Scans notes/ and notes/questions/ for files that haven't been registered
(i.e. filenames that don't match the ID format), validates frontmatter,
generates unique IDs and timestamps, and updates _index.md.

Usage:
    python scripts/update_index.py
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


def rename_to_id(file_path: Path, entry_id: str, entry_type: str) -> Path:
    """Rename file to {entry_id}.md in the appropriate directory.

    Notes stay in notes/, questions go to notes/questions/.
    Returns the new file path.
    """
    if entry_type == "question":
        dest_dir = WORKSPACE / "notes" / "questions"
    else:
        dest_dir = WORKSPACE / "notes"
    dest_dir.mkdir(parents=True, exist_ok=True)
    new_path = dest_dir / f"{entry_id}.md"
    if file_path.resolve() != new_path.resolve():
        file_path.rename(new_path)
    return new_path


def update_index(
    index_path: Path,
    entry_type: str,
    entry_id: str,
    timestamp: str,
    data: dict,
) -> None:
    """Append an entry to the correct table in _index.md, using wikilinks for IDs."""
    content = index_path.read_text(encoding="utf-8")

    if entry_type == "question":
        row = f'| [[{entry_id}]] | open | {data["question"]} | {data["source"]} | |'
        content = content.replace(
            "<!-- END QUESTIONS -->", f"{row}\n<!-- END QUESTIONS -->"
        )
    else:
        answers_link = f'[[{data.get("answers", "")}]]' if data.get("answers") else ""
        row = (
            f'| [[{entry_id}]] | {data["title"]} | {answers_link}'
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
                    lines[i] = re.sub(r"\|\s*\|$", f"| [[{entry_id}]] |", lines[i])
            content = "\n".join(lines)

    content = re.sub(
        r"^Last Updated:.*$",
        f"Last Updated: {timestamp}",
        content,
        flags=re.MULTILINE,
    )
    index_path.write_text(content, encoding="utf-8")


# ── Scanner ──────────────────────────────────────────────────────────

_NOTE_ID_RE = re.compile(r"^NOTE-\d{8}-\d{6}-\d{3}\.md$")
_QUESTION_ID_RE = re.compile(r"^Q-\d{8}-\d{6}-\d{3}\.md$")


def find_unregistered_files() -> list[Path]:
    """Return .md files in notes/ and notes/questions/ that don't match the ID format."""
    notes_dir = WORKSPACE / "notes"
    questions_dir = WORKSPACE / "notes" / "questions"
    unregistered: list[Path] = []

    # Scan top-level notes/ (non-recursive, skip questions/ subdir)
    if notes_dir.exists():
        for f in notes_dir.iterdir():
            if f.is_file() and f.suffix == ".md" and not _NOTE_ID_RE.match(f.name):
                unregistered.append(f)

    # Scan notes/questions/
    if questions_dir.exists():
        for f in questions_dir.iterdir():
            if f.is_file() and f.suffix == ".md" and not _QUESTION_ID_RE.match(f.name):
                unregistered.append(f)

    return sorted(unregistered)


# ── CLI ──────────────────────────────────────────────────────────────


def process_file(file_path: Path) -> tuple[str, Path, str] | None:
    """Validate, assign ID, rename, and return (entry_id, new_path, timestamp) or None on error."""
    text = file_path.read_text(encoding="utf-8")

    try:
        raw = parse_frontmatter(text)
    except ValueError as exc:
        print(f"Error in {file_path.name}: {exc}", file=sys.stderr)
        return None

    try:
        entry = _validate(raw)
    except Exception as exc:
        print(f"Validation error in {file_path.name}:\n{exc}", file=sys.stderr)
        return None

    entry_id, timestamp = generate_id_and_timestamp(entry.type)

    updated = replace_placeholders(text, entry_id, timestamp)
    file_path.write_text(updated, encoding="utf-8")

    new_path = rename_to_id(file_path, entry_id, entry.type)

    index_path = WORKSPACE / "_index.md"
    if index_path.exists():
        update_index(index_path, entry.type, entry_id, timestamp, raw)
        print(f"Registered {entry_id} in _index.md")
    else:
        print("Warning: _index.md not found, skipping index update", file=sys.stderr)

    print(f"ID: {entry_id}")
    print(f"File: {new_path.relative_to(WORKSPACE)}")
    print(f"Created: {timestamp}")
    return entry_id, new_path, timestamp


def main() -> int:
    files = find_unregistered_files()
    if not files:
        print("No unregistered notes found.")
        return 0

    print(f"Found {len(files)} unregistered file(s).")
    errors = 0
    for file_path in files:
        result = process_file(file_path)
        if result is None:
            errors += 1

    registered = len(files) - errors
    print(f"\nDone: {registered} registered, {errors} error(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
