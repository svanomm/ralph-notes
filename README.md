# Ralph Note

An iterative knowledge extraction system powered by VS Code Copilot agents. Ralph Note explores Markdown documents and builds a database of atomic [Zettelkasten](https://zettelkasten.de/overview/)-style notes — automatically, loop after loop. Related notes are linked together to build a knowledge graph.

Inspired by the [Ralph Wiggum loop technique](https://ghuntley.com/ralph/): an AI orchestrator dispatches disposable subagents to explore source material, generate research questions, and distill findings into atomic notes. Each subagent starts with a fresh context window, avoiding the bloat that kills long-running AI sessions.

**Warning**: Please use this tool at your own risk. We use agent-scoped hooks to prevent agents from running arbitrary code in the temrinal, but I highly recommend implementing an agent sandbox for additional protection. I personally use [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/agents/copilot/) to ensure agents cannot interact with files outside of the repo.

## How It Works

```
┌─────────────────────────────────────────────────────┐
│                 Ralph Orchestrator                  │
│                                                     │
│  1. Check PAUSE.md (stop if exists)                 │
│  2. Read state (_index.md, PROGRESS.md)             │
│  3. Decide: Asker, Doer, and/or Connector?          │
│  4. Dispatch subagents via runSubagent              │
│  5. Verify results, update PROGRESS.md              │
│  6. Repeat                                          │
└──────┬──────────────┬──────────────┬────────────────┘
       │              │              │
┌──────▼──────┐ ┌─────▼──────┐ ┌────▼─────────┐
│    Asker    │ │    Doer    │ │  Connector   │
│             │ │            │ │              │
│ Reads docs/ │ │ Reads docs/│ │ Reads notes/ │
│ Generates   │ │ Answers a  │ │ Adds inline  │
│ research    │ │ question   │ │ [[wikilinks]]│
│ questions   │ │ with notes │ │ between notes│
└──────┬──────┘ └─────┬──────┘ └──────┬───────┘
       │              │               │
       ▼              ▼               │
   notes/q-*.md   notes/*.md     edits notes/
       │              │
┌──────▼──────────────▼──────┐
│   scripts/update_index.py  │
│  • Validates frontmatter   │
│  • Generates unique ID     │
│  • Sets created timestamp  │
│  • Updates _index.md       │
│  • Marks questions answered│
└────────────────────────────┘
```

**Three subagent types work together:**

- **Askers** survey the documents and research objectives, then generate specific, answerable research questions
- **Doers** pick up an open question, read the source documents, and produce atomic notes that answer it
- **Connectors** read a random batch of existing notes, find conceptual relationships, and weave inline `[[wikilinks]]` to create a densely connected knowledge graph

All subagent types are able to run as parallel fleets of subagents, allowing for generation of large note databases.

After creating each file, Askers and Doers call `scripts/update_index.py` to handle all bookkeeping deterministically — frontmatter validation, ID generation, timestamps, index updates, and question status tracking. Connectors only edit existing notes and do not create new files.

The orchestrator updates `PROGRESS.md` programmatically by running `scripts/update_progress.py`, which computes state counts from `_index.md` and appends one validated iteration row.

## Requirements

- **VS Code** with GitHub Copilot Chat (agent mode)
- **Python 3.12+** (for the index update script)
- **[uv](https://docs.astral.sh/uv/)** (for environment management)

## Quick Start

### 1. Clone or download this repository

```
git clone <repo-url> ralph-notes
cd ralph-notes
```

### 2. Add your source documents

Place Markdown files in the `docs/` folder. NOTE: future versions will convert other filetypes to Markdown for you.

```
docs/
├── architecture-overview.md
├── api-reference.md
└── design-decisions.md
```

### 3. Define your research objectives

You can define your research objectives in two ways:

**Option A — Use the create-plan prompt (recommended)**

Open GitHub Copilot Chat and type:

```
/create-plan
```

Copilot will then interview you — starting with broad questions about purpose and context, then narrowing to specific hypotheses and scope boundaries. After a short back-and-forth, it writes a complete `research-questions.md` tailored to your goals and the documents in `docs/`.

**Option B — Edit `research-questions.md` directly**

Open `research-questions.md` and fill in your questions manually:

```markdown
## Primary Questions

1. How does the authentication system work?
2. What are the main architectural trade-offs?
3. How is data validation handled across services?

## Areas of Interest

- Security model
- Error handling patterns
- Performance considerations
```

### 4. Set up the Python environment

```
uv venv --python 3.12
uv pip install -r requirements.txt
```

### 5. Launch the orchestrator

Open GitHub Copilot Chat (`Ctrl+Shift+I`) and type:

```
@ralph-orchestrator Begin the research loop.
```

The orchestrator will start iterating — generating questions, reading documents, and producing notes.

NOTE: to avoid abusing GitHub Copilot premium requests, the current system stops after each iteration, i.e. 1 premium request equals 1 iteration. You could remove this restriction and have the orchestrator keep iterating forever, but you may get rate-limited (or worse).

### 6. Stop the loop

Create a file called `PAUSE.md` in the workspace root:

```
echo. > PAUSE.md
```

The orchestrator checks for this file at the start of every iteration and will stop gracefully. Delete it to resume.

### 7. Start fresh

To archive all current notes, questions, and state, then reset the workspace for a new research session:

```
uv run scripts/fresh_start.py
```

This creates a timestamped zip archive in `archives/`, clears all files from `notes/`, and resets `_index.md`, `PROGRESS.md`, and `research-questions.md` to blank templates. Your source documents in `docs/` are never touched.

## Project Structure

```
ralph-notes/
├── .github/
│   ├── agents/
│   │   ├── ralph-asker.agent.md           # Asker subagent — generates research questions
│   │   ├── ralph-connector.agent.md       # Connector subagent — adds wikilinks between notes
│   │   ├── ralph-doer.agent.md            # Doer subagent — creates atomic notes
│   │   └── ralph-orchestrator.agent.md    # Orchestrator — dispatches subagents
│   └── copilot-instructions.md           # Project-wide AI instructions
├── docs/                                 # Source documents (READ ONLY)
├── notes/                                # Generated notes & questions (WRITE)
├── scripts/
│   ├── update_index.py                   # Frontmatter validation, ID generation & index updates
│   ├── update_progress.py                # Deterministic PROGRESS.md updater for orchestrator iterations
│   └── fresh_start.py                    # Archive current state and reset for a new session
├── .venv/                                # Python virtual environment (uv)
├── requirements.txt                      # Python dependencies (pydantic, pyyaml)
├── _index.md                             # Auto-maintained research index
├── PROGRESS.md                           # Loop state & iteration history
└── research-questions.md                 # Human-provided research objectives
```

### File Access Rules

| Path | Access | Description |
|------|--------|-------------|
| `docs/` | Read only | Source documents — agents read but never modify |
| `notes/` | Write | Where all generated notes and questions are created |
| `_index.md` | Auto-managed | Updated by `scripts/update_index.py` — never edited directly |
| `PROGRESS.md` | Orchestrator only | Loop state tracking, written by the orchestrator |
| `research-questions.md` | Human only | You define the research goals before starting |
| `scripts/` | Do not modify | Index update script and utilities |

## Note Format

All files in `notes/` use YAML frontmatter. Two types are supported:

### Research Notes (`type: note`)

```yaml
---
type: note
id: PLACEHOLDER
title: "Brief descriptive title (max 10 words)"
answers: "Q-20260225-143022-731"
source: "docs/filename.md"
tags: [tag1, tag2, tag3]
created: PLACEHOLDER
---
```

One to three paragraphs expressing a single atomic insight, grounded in the source document.

Optionally end with a `## Related` section linking to other note IDs.

### Research Questions (`type: question`)

```yaml
---
type: question
id: PLACEHOLDER
question: "Specific, answerable research question"
parent: "Q-20260225-143022-731"
source: "asker"
status: open
created: PLACEHOLDER
---
```

## Research Index

`_index.md` is the central registry maintained automatically by the hook. It contains two tables:

**Questions table** — tracks every generated question and its status:

| ID | Status | Question | Source | Answered By |
|----|--------|----------|--------|-------------|
| Q-20260225-143022-731 | answered | How does auth work? | asker | NOTE-20260225-150102-331 |
| Q-20260225-143055-412 | open | What hashing algorithm is used? | followup:Q-20260225-143022-731 | |

**Notes table** — tracks every created note:

| ID | Title | Answers | Source Doc | Created |
|----|-------|---------|-----------|---------|
| NOTE-20260225-150102-331 | Auth uses JWT tokens | Q-20260225-143022-731 | docs/auth.md | 2026-02-25T15:01:02.331Z |

## Progress Tracking

`PROGRESS.md` records the orchestrator's loop state, updated after every iteration via:

```
uv run scripts/update_progress.py --type "..." --target "..." --result "..."
```

The script computes open-question and total-note counts from `_index.md`, updates the Current State fields, and appends exactly one row to Iteration History.

```markdown
## Current State

- **Iteration**: 7
- **Open Questions**: 4
- **Total Notes**: 12
- **Last Action**: Doer answered Q-20260225-143055-412
- **Status**: Running

## Iteration History

| # | Type | Target | Result | Timestamp |
|---|------|--------|--------|-----------|
| 1 | asker | initial survey | Generated 5 questions | 2026-02-25T14:30:00Z |
| 2 | doer | Q-20260225-143022-731 | Created 2 notes | 2026-02-25T14:35:00Z |
```

## Fresh Start

When you want to begin a new research session from scratch — with different documents or objectives — run:

```
uv run scripts/fresh_start.py
```

The script:

1. **Archives** the current `_index.md`, `PROGRESS.md`, `research-questions.md`, and everything in `notes/` into a timestamped zip file
2. **Moves** the archive into the `archives/` directory
3. **Clears** all files from `notes/` and `notes/questions/` (preserving the directories)
4. **Resets** `_index.md`, `PROGRESS.md`, and `research-questions.md` to empty templates

Previous archives are kept in `archives/` (e.g., `archives/ralph_notes_archive_20260228_150000.zip`) so you can always recover earlier work.

## Tips

- **Start small**: Begin with a few focused documents and 2–3 primary questions. The asker subagents will naturally expand the question pool over time.
- **Check the index**: Open `_index.md` at any time to see the current state of research — which questions are open, which are answered, and all notes created.
- **Quality over quantity**: The orchestrator prioritizes depth. It generates 3–5 questions per asker session and creates one note per atomic insight.
- **Resume anytime**: The loop state is fully captured in `_index.md` and `PROGRESS.md`. Delete `PAUSE.md` and re-invoke the orchestrator to continue where you left off.
- **Add documents mid-run**: You can add new files to `docs/` while the loop is running. The next asker iteration will discover them.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Agent not appearing | Check that `.github/agents/ralph-orchestrator.agent.md` (and `ralph-asker.agent.md`, `ralph-doer.agent.md`, `ralph-connector.agent.md`) exist and VS Code has reloaded. |
| `PLACEHOLDER` not replaced | The agent must call `scripts/update_index.py` after creating the file. Check the agent instructions. |
| Validation error from script | Read the error output — Pydantic reports exactly which field failed and why. Fix the frontmatter and re-run the script. |
| `ModuleNotFoundError` | Run `uv pip install -r requirements.txt` from the workspace root to install dependencies into `.venv/`. |
| Script can't find file | Ensure the path is relative to the workspace root (e.g., `./notes/my-note.md`), not an absolute path. |

## License

MIT license. Be careful about using this; I make no attempt to confirm whether it adheres to AI provider terms of use.
