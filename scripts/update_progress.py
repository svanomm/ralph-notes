#!/usr/bin/env python3
"""Safely update PROGRESS.md from one orchestrator iteration event.

The script treats _index.md as the source of truth for open-question and
note counts, then appends a single row to the PROGRESS.md history table.

Usage:
    uv run scripts/update_progress.py \
      --type "asker/doer" \
      --target "Q-20260419-133408-450" \
      --result "Generated 5 questions and created 1 note" \
      --status Active
"""

from __future__ import annotations

import argparse
import re
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

WORKSPACE = Path(__file__).resolve().parent.parent
INDEX_PATH = WORKSPACE / "_index.md"
PROGRESS_PATH = WORKSPACE / "PROGRESS.md"

QUESTION_ROW_RE = re.compile(
    r"^\|\s*\[\[Q-\d{8}-\d{6}-\d{3}\]\]\s*\|\s*(open|answered)\s*\|",
    re.IGNORECASE,
)
NOTE_ROW_RE = re.compile(r"^\|\s*\[\[NOTE-\d{8}-\d{6}-\d{3}\]\]\s*\|")
HISTORY_ROW_RE = re.compile(
    r"^\|\s*(\d+)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|$"
)
TYPE_RE = re.compile(r"^[A-Za-z][A-Za-z0-9/ +_-]{0,39}$")


def _utc_timestamp() -> str:
    now = datetime.now(timezone.utc)
    millis = f"{now.microsecond // 1000:03d}"
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + millis + "Z"


def _find_section(lines: list[str], heading: str) -> tuple[int, int]:
    start = -1
    for i, line in enumerate(lines):
        if line.strip() == heading:
            start = i
            break

    if start == -1:
        raise ValueError(f"Missing section heading: {heading}")

    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("## "):
            end = i
            break

    return start, end


def _find_marker(lines: list[str], marker: str) -> int:
    for i, line in enumerate(lines):
        if line.strip() == marker:
            return i
    raise ValueError(f"Missing marker: {marker}")


def _parse_index_counts(index_text: str) -> tuple[int, int]:
    lines = index_text.splitlines()

    questions_start = _find_marker(lines, "## Questions")
    questions_end = _find_marker(lines, "<!-- END QUESTIONS -->")
    notes_start = _find_marker(lines, "## Notes")
    notes_end = _find_marker(lines, "<!-- END NOTES -->")

    if not (questions_start < questions_end < notes_start < notes_end):
        raise ValueError("_index.md sections are out of expected order")

    open_questions = 0
    for line in lines[questions_start + 1 : questions_end]:
        match = QUESTION_ROW_RE.match(line.strip())
        if match and match.group(1).lower() == "open":
            open_questions += 1

    total_notes = 0
    for line in lines[notes_start + 1 : notes_end]:
        if NOTE_ROW_RE.match(line.strip()):
            total_notes += 1

    return open_questions, total_notes


def _sanitize_cell(value: str, name: str, min_len: int, max_len: int) -> str:
    cleaned = value.strip()
    if len(cleaned) < min_len:
        raise ValueError(f"{name} must be at least {min_len} character(s)")
    if len(cleaned) > max_len:
        raise ValueError(f"{name} must be at most {max_len} character(s)")
    if "|" in cleaned or "\n" in cleaned or "\r" in cleaned:
        raise ValueError(f"{name} cannot contain pipes or newlines")
    return cleaned


def _parse_history(
    lines: list[str], history_start: int, history_end: int
) -> tuple[int, int]:
    header_idx = -1
    for i in range(history_start + 1, history_end):
        if lines[i].strip() == "| # | Type | Target | Result | Timestamp |":
            header_idx = i
            break

    if header_idx == -1:
        raise ValueError("Missing iteration history table header")

    if header_idx + 1 >= history_end:
        raise ValueError("Missing iteration history table separator")

    if not lines[header_idx + 1].strip().startswith("|---|"):
        raise ValueError("Invalid iteration history table separator")

    max_iteration = 0
    insert_idx = header_idx + 2

    while insert_idx < history_end:
        stripped = lines[insert_idx].strip()
        if not stripped:
            break
        if not stripped.startswith("|"):
            break

        match = HISTORY_ROW_RE.match(stripped)
        if not match:
            raise ValueError(
                "Iteration history contains a malformed row; expected five table columns"
            )

        max_iteration = max(max_iteration, int(match.group(1)))
        insert_idx += 1

    return max_iteration + 1, insert_idx


def _replace_state_line(
    lines: list[str], state_start: int, state_end: int, label: str, value: str
) -> None:
    prefix = f"- **{label}**:"
    for i in range(state_start + 1, state_end):
        if lines[i].startswith(prefix):
            lines[i] = f"{prefix} {value}"
            return
    raise ValueError(f"Missing current-state field: {label}")


def _atomic_write(path: Path, text: str) -> None:
    tmp_path = path.with_name(f".{path.name}.tmp-{uuid.uuid4().hex[:8]}")
    tmp_path.write_text(text, encoding="utf-8")
    tmp_path.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Update PROGRESS.md from one iteration event."
    )
    parser.add_argument(
        "--type", required=True, help="Agent type(s), e.g. asker, doer, asker/doer"
    )
    parser.add_argument(
        "--target", required=True, help="Question ID, note ID, or exploration area"
    )
    parser.add_argument(
        "--result", required=True, help="Short summary of iteration outcome"
    )
    parser.add_argument(
        "--status",
        default="Active",
        choices=["Ready", "Active", "Paused"],
        help="Current loop status after this iteration",
    )
    parser.add_argument(
        "--last-action",
        default=None,
        help="Optional override for Current State Last Action",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate and print the computed update without writing PROGRESS.md",
    )
    args = parser.parse_args()

    try:
        activity_type = _sanitize_cell(args.type, "type", 1, 40)
        if not TYPE_RE.fullmatch(activity_type):
            raise ValueError(
                "type must start with a letter and contain only letters, digits, spaces, /, +, _, or -"
            )

        target = _sanitize_cell(args.target, "target", 1, 160)
        result = _sanitize_cell(args.result, "result", 5, 240)

        if args.last_action is None:
            last_action = f"{activity_type} on {target}"
        else:
            last_action = _sanitize_cell(args.last_action, "last-action", 1, 240)

        if not INDEX_PATH.exists():
            raise ValueError(f"Missing file: {INDEX_PATH.name}")
        if not PROGRESS_PATH.exists():
            raise ValueError(f"Missing file: {PROGRESS_PATH.name}")

        open_questions, total_notes = _parse_index_counts(
            INDEX_PATH.read_text(encoding="utf-8")
        )

        progress_text = PROGRESS_PATH.read_text(encoding="utf-8")
        lines = progress_text.splitlines()

        state_start, state_end = _find_section(lines, "## Current State")
        history_start, history_end = _find_section(lines, "## Iteration History")

        next_iteration, insert_idx = _parse_history(lines, history_start, history_end)
        timestamp = _utc_timestamp()

        _replace_state_line(
            lines, state_start, state_end, "Iteration", str(next_iteration)
        )
        _replace_state_line(
            lines, state_start, state_end, "Open Questions", str(open_questions)
        )
        _replace_state_line(
            lines, state_start, state_end, "Total Notes", str(total_notes)
        )
        _replace_state_line(lines, state_start, state_end, "Last Action", last_action)
        _replace_state_line(lines, state_start, state_end, "Status", args.status)

        new_row = f"| {next_iteration} | {activity_type} | {target} | {result} | {timestamp} |"
        lines.insert(insert_idx, new_row)

        updated_text = "\n".join(lines) + "\n"

        if args.dry_run:
            print("Dry run: no files were modified.")
        else:
            _atomic_write(PROGRESS_PATH, updated_text)
            print(f"Updated {PROGRESS_PATH.name}.")

        print(f"Iteration: {next_iteration}")
        print(f"Open Questions: {open_questions}")
        print(f"Total Notes: {total_notes}")
        print(f"Last Action: {last_action}")
        print(f"Status: {args.status}")
        print(f"Timestamp: {timestamp}")
        return 0

    except ValueError as exc:
        print(f"Validation error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
