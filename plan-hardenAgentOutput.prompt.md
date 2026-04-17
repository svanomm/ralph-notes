# Plan: Harden Agent Output with Python File Generators

Replace agents' manual Markdown file creation with two Python CLI commands — `create_note.py` and `create_question.py` — that accept structured arguments and produce guaranteed-valid files. This eliminates frontmatter formatting errors, inconsistent YAML, wrong field names, missing PLACEHOLDERs, and body structure drift. Agent instructions get updated to call these commands instead of hand-writing files.

## Problem Analysis

Current brittleness vectors:
1. **YAML formatting** — agents produce inconsistent quoting, indentation, key ordering, or missing fields
2. **PLACEHOLDER discipline** — agents sometimes invent IDs/timestamps instead of using `PLACEHOLDER`
3. **Body structure** — inconsistent paragraph formatting, missing `## Related` sections, wrong heading levels
4. **Tag formatting** — tags as strings, quoted lists, or inconsistent formats
5. **Field names** — typos in frontmatter keys (`answer:` vs `answers:`)
6. **File placement** — notes created in wrong directories

## Steps

### Phase 1 — Create file generator scripts

1. **Create `scripts/create_note.py`** — CLI (argparse) accepting `--title`, `--answers`, `--source`, `--tags` (comma-separated), `--body`, and optional `--related` (comma-separated `NOTE-ID: description` pairs). Validates all inputs using the existing Pydantic models, generates the complete Markdown file with correct YAML frontmatter (`id: PLACEHOLDER`, `created: PLACEHOLDER`), writes to `notes/temp-{uuid}.md`, prints the filepath to stdout. Exits non-zero with clear error on validation failure.

2. **Create `scripts/create_question.py`** — CLI accepting `--question` and optional `--parent`. Same pattern: validates, generates, writes to `notes/questions/temp-{uuid}.md`, prints filepath.

### Phase 2 — Extract shared models (parallel with Phase 1)

3. **Create `scripts/models.py`** — Extract `NoteFrontmatter`, `QuestionFrontmatter`, `parse_frontmatter()`, and the `Frontmatter` TypeAdapter from `scripts/update_index.py` into this shared module. Update `update_index.py` to import from `models.py`. Both creation scripts also import from `models.py`. Single source of truth for validation.

### Phase 3 — Update agent instructions (depends on Phase 1)

4. **Update `.github/agents/ralph-doer.agent.md`** — Replace "create files manually" instructions with CLI usage: `uv run scripts/create_note.py --title "..." --answers "Q-..." --source "docs/..." --tags "tag1,tag2" --body "..."`. Remove the YAML template section (the script enforces it). Keep the example note as "expected output" reference.

5. **Update `.github/agents/ralph-asker.agent.md`** — Replace manual file creation with: `uv run scripts/create_question.py --question "..." [--parent "Q-..."]`. Remove the YAML template section.

6. **Update `.github/copilot-instructions.md`** — Document the new scripts in the directory table and security rules. (parallel with steps 4-5)

7. **No changes needed** to `ralph-connector.agent.md` (only edits existing note bodies) or `ralph-orchestrator.agent.md` (only dispatches subagents).

## Relevant Files

| File | Action |
|------|--------|
| `scripts/create_note.py` | **Create** — note generator CLI |
| `scripts/create_question.py` | **Create** — question generator CLI |
| `scripts/models.py` | **Create** — shared Pydantic models |
| `scripts/update_index.py` | **Modify** — import models from `models.py` |
| `.github/agents/ralph-doer.agent.md` | **Modify** — use CLI instead of manual files |
| `.github/agents/ralph-asker.agent.md` | **Modify** — use CLI instead of manual files |
| `.github/copilot-instructions.md` | **Modify** — document new scripts |

## Verification

1. Run `uv run scripts/create_note.py --title "Test note" --answers "Q-20260225-143022-001" --source "docs/test.md" --tags "test,verification" --body "Test body."` → confirm valid file in `notes/`
2. Run `uv run scripts/create_question.py --question "What is the test?"` → confirm valid file in `notes/questions/`
3. Run `uv run scripts/create_question.py --question "Follow up?" --parent "Q-20260225-143022-001"` → confirm parent field works
4. Run `uv run scripts/update_index.py` on generated files → confirm they pass validation and register
5. Test error cases: missing fields, title >10 words, invalid question ID, bad source prefix → all exit non-zero with clear messages
6. Confirm `update_index.py` still works after the models extraction refactor

## Decisions

- **Body via `--body` flag**: agent passes full text as a single argument. Simpler than stdin/file approaches
- **`--related` is optional**: `## Related` section only added when provided, avoiding empty sections
- **Two-step flow preserved**: creation scripts produce PLACEHOLDER files, `update_index.py` still does registration separately
- **Shared models in `scripts/models.py`**: single source of truth for validation

## Further Considerations

1. **Body text quoting** — long multi-paragraph bodies can be awkward as CLI args. Could add `--body-file <path>` if agents struggle with shell quoting. Recommendation: start with `--body`, add `--body-file` only if needed.
