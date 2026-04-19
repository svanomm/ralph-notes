#!/usr/bin/env python3
"""Create a new question file in notes/questions/ with correct frontmatter structure.

Usage:
    uv run scripts/create_question.py --question "..." [--parent "Q-..."]

Options:
    --question    The specific, answerable research question
    --parent      Parent question ID (Q-YYYYMMDD-HHMMSS-mmm) — omit for top-level questions
"""

from __future__ import annotations

import argparse
import sys
import uuid
from pathlib import Path

from pydantic import ValidationError

sys.path.insert(0, str(Path(__file__).parent))
from models import QuestionFrontmatter  # noqa: E402

WORKSPACE = Path(__file__).resolve().parent.parent


def build_frontmatter(question: str, parent: str | None) -> str:
    lines = [
        "---",
        "type: question",
        "id: PLACEHOLDER",
        f'question: "{question}"',
    ]
    if parent:
        lines.append(f'parent: "{parent}"')
    lines += [
        "source: asker",
        "status: open",
        "created: PLACEHOLDER",
        "---",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create a question file in notes/questions/"
    )
    parser.add_argument("--question", required=True, help="The research question")
    parser.add_argument(
        "--parent",
        default=None,
        help="Parent question ID (Q-YYYYMMDD-HHMMSS-mmm)",
    )
    args = parser.parse_args()

    try:
        QuestionFrontmatter(
            type="question",
            id="PLACEHOLDER",
            question=args.question,
            parent=args.parent,
            source="asker",
            status="open",
            created="PLACEHOLDER",
        )
    except ValidationError as exc:
        print(f"Validation error:\n{exc}", file=sys.stderr)
        return 1

    frontmatter = build_frontmatter(args.question, args.parent)
    content = f"{frontmatter}\n"

    questions_dir = WORKSPACE / "notes" / "questions"
    questions_dir.mkdir(parents=True, exist_ok=True)
    file_path = questions_dir / f"temp-{uuid.uuid4().hex[:8]}.md"
    file_path.write_text(content, encoding="utf-8")

    print(str(file_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
