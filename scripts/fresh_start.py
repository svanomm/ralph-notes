"""Archive current Ralph Note state and reset for a fresh start."""

import shutil
import zipfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTES_DIR = ROOT / "notes"
QUESTIONS_DIR = NOTES_DIR / "questions"
ARCHIVES_DIR = ROOT / "archives"

FILES_TO_ARCHIVE = [
    ROOT / "_index.md",
    ROOT / "PROGRESS.md",
    ROOT / "research-questions.md",
]

FRESH_INDEX = """\
# Research Index

Last Updated: —

## Questions

| ID | Status | Question | Source | Answered By |
|----|--------|----------|--------|-------------|
<!-- END QUESTIONS -->

## Notes

| ID | Title | Answers | Source Doc | Created |
|----|-------|---------|-----------|---------|
<!-- END NOTES -->
"""

FRESH_PROGRESS = """\
# Ralph Loop Progress

## Current State

- **Iteration**: 0
- **Open Questions**: 0
- **Total Notes**: 0
- **Last Action**: —
- **Status**: Ready

## Iteration History

| # | Type | Target | Result | Timestamp |
|---|------|--------|--------|-----------|
"""

FRESH_RESEARCH_QUESTIONS = """\
# Research Objectives

Define your research goals here. The Ralph orchestrator and its asker subagents will use these objectives to generate specific, answerable research questions.

## Primary Questions

## Areas of Interest

## Scope Boundaries

- **In scope**: All Markdown documents in `docs/`
"""


def build_archive() -> Path:
    """Create a zip archive of the current notes, index, progress, and questions."""
    now = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    zip_name = f"ralph_notes_archive_{now}.zip"
    zip_path = ROOT / zip_name

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        # Archive top-level files
        for fp in FILES_TO_ARCHIVE:
            if fp.exists():
                zf.write(fp, fp.relative_to(ROOT))

        # Archive all files in notes/ (including questions/)
        if NOTES_DIR.exists():
            for child in sorted(NOTES_DIR.rglob("*")):
                if child.is_file():
                    zf.write(child, child.relative_to(ROOT))

    return zip_path


def move_to_archives(zip_path: Path) -> Path:
    """Move the zip file into the archives directory."""
    ARCHIVES_DIR.mkdir(parents=True, exist_ok=True)
    dest = ARCHIVES_DIR / zip_path.name
    shutil.move(str(zip_path), str(dest))
    return dest


def clear_notes():
    """Delete all files in notes/ and notes/questions/, preserving the directories."""
    if QUESTIONS_DIR.exists():
        for f in QUESTIONS_DIR.iterdir():
            if f.is_file():
                f.unlink()

    if NOTES_DIR.exists():
        for f in NOTES_DIR.iterdir():
            if f.is_file():
                f.unlink()


def reset_files():
    """Reset _index.md, PROGRESS.md, and research-questions.md to fresh templates."""
    (ROOT / "_index.md").write_text(FRESH_INDEX, encoding="utf-8")
    (ROOT / "PROGRESS.md").write_text(FRESH_PROGRESS, encoding="utf-8")
    (ROOT / "research-questions.md").write_text(FRESH_RESEARCH_QUESTIONS, encoding="utf-8")


def main():
    print("Archiving current state...")
    zip_path = build_archive()

    print(f"Moving archive to {ARCHIVES_DIR / zip_path.name}")
    dest = move_to_archives(zip_path)

    print("Clearing notes...")
    clear_notes()

    print("Resetting files to fresh state...")
    reset_files()

    print(f"Done. Archive saved to: {dest.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
