#!/usr/bin/env python3
"""Assign a random batch of registered notes for a connector agent.

Scans notes/ for files matching the registered NOTE-ID pattern,
randomly selects a batch, and prints their relative filepaths.

Usage:
    python scripts/assign_note_batch.py          # default batch of 3
    python scripts/assign_note_batch.py --size 5  # custom batch size
"""

from __future__ import annotations

import argparse
import random
import re
import sys
from pathlib import Path

WORKSPACE = Path(__file__).resolve().parent.parent
NOTES_DIR = WORKSPACE / "notes"
_NOTE_ID_RE = re.compile(r"^NOTE-\d{8}-\d{6}-\d{3}\.md$")


def find_registered_notes() -> list[Path]:
    """Return all registered note files (matching NOTE-ID pattern) in notes/."""
    if not NOTES_DIR.exists():
        return []
    return sorted(
        f for f in NOTES_DIR.iterdir()
        if f.is_file() and _NOTE_ID_RE.match(f.name)
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Assign a random batch of notes.")
    parser.add_argument(
        "--size", type=int, default=3,
        help="Number of notes to select (default: 3)",
    )
    args = parser.parse_args()

    notes = find_registered_notes()
    if not notes:
        print("No registered notes found.", file=sys.stderr)
        return 1

    batch_size = min(args.size, len(notes))
    batch = random.sample(notes, batch_size)

    for note_path in batch:
        print(note_path.relative_to(WORKSPACE))

    return 0


if __name__ == "__main__":
    sys.exit(main())
