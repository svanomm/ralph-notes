---
name: research-planner
description: "Populate research-questions.md with an initial research plan. Use when: setting up research goals, defining research questions, planning what to investigate, filling in research objectives, starting a new Ralph Note session, or when research-questions.md is empty or needs to be written. Conducts an inquisitive interview from general to specific, then writes a comprehensive research plan into research-questions.md."
argument-hint: "Optional topic hint (e.g. 'antitrust DiD analysis')"
---

# Research Planner

Conduct a progressive interview with the user to understand their research goals, then write a comprehensive `research-questions.md`.

## When to Use
- `research-questions.md` is blank or under-populated
- User wants to define or refocus their research agenda
- Starting a new Ralph Note investigation session
- User says "plan my research", "set up research questions", "what should I study"

## Procedure

### Step 1 — Scan Available Documents
Read `docs/` to understand what material is available. List the documents briefly so the user knows what the corpus covers.

### Step 2 — Interview: General Questions (ask these first)
Ask **one or two questions at a time** — never a long list. Wait for answers before proceeding.

**Round 1 — Purpose & Context**
- What is the broad topic or problem you are trying to understand?
- What is the context for this research? (e.g., academic paper, litigation support, policy analysis, internal report)

**Round 2 — Goals & Outputs**
- What would a successful outcome look like? What should you be able to say or do after this research?
- Who is the intended audience, and what decisions might they make based on your findings?

**Round 3 — Scope & Constraints**
- Are there specific papers, authors, methods, or time periods you know you want to focus on?
- Are there topics, methods, or papers that are explicitly out of scope?

**Round 4 — Specific Hypotheses & Questions (optional, based on earlier answers)**
- Do you have specific hypotheses or relationships you want to test or verify?
- Are there methodological debates or open questions in this domain you want to resolve?

### Step 3 — Synthesize & Confirm
Summarize back to the user what you've understood:
- Their primary research goal in one sentence
- 3–5 candidate primary questions you plan to write
- Key thematic areas you plan to list under Areas of Interest
- Any scope boundaries to add

Ask: *"Does this capture what you're looking for, or should I adjust anything?"*

### Step 4 — Write `research-questions.md`
Once confirmed, overwrite `research-questions.md` using the template below. Be specific and actionable — primary questions should be answerable by reading the documents in `docs/`.

```markdown
# Research Objectives

<1–2 sentence summary of the research goal and context>

## Primary Questions

1. <Specific, answerable question drawn directly from the user's goals>
2. <...>
3. <...>
(aim for 4–8 primary questions)

## Areas of Interest

- **<Theme 1>**: <brief description>
- **<Theme 2>**: <brief description>
(aim for 4–6 thematic areas)

## Scope Boundaries

- **In scope**: All Markdown documents in `docs/`
- **In scope**: <any specific papers, methods, or concepts the user named>
- **Out of scope**: <any explicit exclusions the user named>
```

### Step 5 — Suggest Next Steps
After writing the file, tell the user:
- What the Ralph Orchestrator will use these questions for
- Suggest running the orchestrator: *"You can now run the Ralph Orchestrator to start building notes from these questions."*

## Quality Criteria
- Primary questions are **specific and answerable** from the docs, not vague ("What is DiD?" not "What are econometrics?")
- At least 4 primary questions written
- Areas of Interest map onto actual themes in `docs/`
- Scope Boundaries are concrete, not just the default placeholder
- The written file is valid Markdown with no broken formatting
