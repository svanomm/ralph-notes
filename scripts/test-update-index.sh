#!/bin/bash
set -e

# Test suite for scripts/update-index.sh
# Verifies the PostToolUse hook correctly updates _index.md and replaces PLACEHOLDERs.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/update-index.sh"
PASS=0
FAIL=0

# --- Helpers ---

setup_workspace() {
  TMPDIR=$(mktemp -d)
  mkdir -p "${TMPDIR}/notes"
  cat > "${TMPDIR}/_index.md" <<'EOF'
# Research Index

Last Updated: 

## Questions

| ID | Status | Question | Source | Answered By |
|----|--------|----------|--------|-------------|
<!-- END QUESTIONS -->

## Notes

| ID | Title | Answers | Source Doc | Created |
|----|-------|---------|-----------|---------|
<!-- END NOTES -->
EOF
}

teardown_workspace() {
  rm -rf "$TMPDIR"
}

make_hook_input() {
  local tool_name="$1"
  local file_path="$2"
  local result_type="${3:-success}"
  local content="${4:-}"
  # Build the toolArgs JSON
  local tool_args
  tool_args=$(jq -n --arg fp "$file_path" --arg c "$content" '{filePath: $fp, content: $c}')
  # Build the full hook input
  jq -n \
    --arg tn "$tool_name" \
    --arg ta "$tool_args" \
    --arg rt "$result_type" \
    --arg cwd "$TMPDIR" \
    '{
      timestamp: 1704614700000,
      cwd: $cwd,
      toolName: $tn,
      toolArgs: $ta,
      toolResult: { resultType: $rt, textResultForLlm: "File created" }
    }'
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local description="$3"
  if grep -q "$pattern" "$file"; then
    PASS=$((PASS + 1))
    echo "  PASS: ${description}"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: ${description}"
    echo "    Expected pattern: ${pattern}"
    echo "    File contents:"
    sed 's/^/    /' "$file"
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local description="$3"
  if ! grep -q "$pattern" "$file"; then
    PASS=$((PASS + 1))
    echo "  PASS: ${description}"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: ${description}"
    echo "    Pattern should NOT appear: ${pattern}"
    echo "    File contents:"
    sed 's/^/    /' "$file"
  fi
}

assert_file_contains() {
  assert_contains "$@"
}

# --- Test Cases ---

test_question_creation() {
  echo "TEST: Question file creation"
  setup_workspace

  # Create a question file with PLACEHOLDERs
  cat > "${TMPDIR}/notes/q-how-does-x-work.md" <<'EOF'
---
type: question
id: PLACEHOLDER
question: "How does X work?"
source: "asker"
status: open
created: PLACEHOLDER
---
EOF

  # Run the hook
  make_hook_input "create_file" "${TMPDIR}/notes/q-how-does-x-work.md" | bash "$HOOK_SCRIPT"

  # Verify PLACEHOLDER replaced in file
  assert_not_contains "${TMPDIR}/notes/q-how-does-x-work.md" "^id: PLACEHOLDER$" \
    "id PLACEHOLDER replaced in question file"
  assert_not_contains "${TMPDIR}/notes/q-how-does-x-work.md" "^created: PLACEHOLDER$" \
    "created PLACEHOLDER replaced in question file"
  assert_contains "${TMPDIR}/notes/q-how-does-x-work.md" "^id: Q-" \
    "Question ID has Q- prefix"
  assert_contains "${TMPDIR}/notes/q-how-does-x-work.md" "^created: [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T" \
    "Created has ISO timestamp format"

  # Verify index updated
  assert_contains "${TMPDIR}/_index.md" "| Q-.*| open | How does X work? | asker | |" \
    "Question added to index"
  assert_contains "${TMPDIR}/_index.md" "^Last Updated: [0-9]\{4\}-" \
    "Last Updated timestamp set"

  teardown_workspace
}

test_note_creation() {
  echo "TEST: Note file creation"
  setup_workspace

  # Create a note file with PLACEHOLDERs
  cat > "${TMPDIR}/notes/binary-search-sorted.md" <<'EOF'
---
type: note
id: PLACEHOLDER
title: "Binary search requires sorted input"
answers: "Q-20260225-143022-731"
source: "docs/algorithms.md"
tags: [algorithms, binary-search]
created: PLACEHOLDER
---

Binary search requires sorted input to function correctly.
EOF

  # Run the hook
  make_hook_input "create_file" "${TMPDIR}/notes/binary-search-sorted.md" | bash "$HOOK_SCRIPT"

  # Verify PLACEHOLDER replaced
  assert_not_contains "${TMPDIR}/notes/binary-search-sorted.md" "^id: PLACEHOLDER$" \
    "id PLACEHOLDER replaced in note file"
  assert_not_contains "${TMPDIR}/notes/binary-search-sorted.md" "^created: PLACEHOLDER$" \
    "created PLACEHOLDER replaced in note file"
  assert_contains "${TMPDIR}/notes/binary-search-sorted.md" "^id: NOTE-" \
    "Note ID has NOTE- prefix"

  # Verify index updated
  assert_contains "${TMPDIR}/_index.md" "| NOTE-.*| Binary search requires sorted input |" \
    "Note added to index"

  teardown_workspace
}

test_note_answers_question() {
  echo "TEST: Note answering an existing question"
  setup_workspace

  # Pre-populate index with an open question
  sed -i '/<!-- END QUESTIONS -->/i | Q-20260225-143022-731 | open | How does auth work? | asker | |' "${TMPDIR}/_index.md"

  # Create a note that answers this question
  cat > "${TMPDIR}/notes/auth-uses-jwt.md" <<'EOF'
---
type: note
id: PLACEHOLDER
title: "Auth uses JWT tokens"
answers: "Q-20260225-143022-731"
source: "docs/auth.md"
tags: [auth, jwt]
created: PLACEHOLDER
---

The authentication system uses JWT tokens.
EOF

  # Run the hook
  make_hook_input "create_file" "${TMPDIR}/notes/auth-uses-jwt.md" | bash "$HOOK_SCRIPT"

  # Verify question marked as answered
  assert_contains "${TMPDIR}/_index.md" "| Q-20260225-143022-731 | answered |" \
    "Question status changed to answered"
  assert_contains "${TMPDIR}/_index.md" "| NOTE-.*|$" \
    "Note ID added to Answered By column"
  assert_not_contains "${TMPDIR}/_index.md" "| Q-20260225-143022-731 | open |" \
    "Question no longer shows as open"

  teardown_workspace
}

test_ignores_non_notes_path() {
  echo "TEST: Ignores files outside notes/"
  setup_workspace

  # Create a file outside notes/
  mkdir -p "${TMPDIR}/docs"
  cat > "${TMPDIR}/docs/something.md" <<'EOF'
---
type: note
id: PLACEHOLDER
title: "Should be ignored"
source: "docs/test.md"
tags: [test]
created: PLACEHOLDER
---
EOF

  # Run the hook
  make_hook_input "create_file" "${TMPDIR}/docs/something.md" | bash "$HOOK_SCRIPT"

  # Verify file was NOT modified
  assert_contains "${TMPDIR}/docs/something.md" "^id: PLACEHOLDER$" \
    "PLACEHOLDER not replaced for non-notes file"

  # Verify index was NOT modified
  assert_not_contains "${TMPDIR}/_index.md" "Should be ignored" \
    "Non-notes file not added to index"

  teardown_workspace
}

test_ignores_non_create_tool() {
  echo "TEST: Ignores non-create_file tool events"
  setup_workspace

  cat > "${TMPDIR}/notes/test-note.md" <<'EOF'
---
type: note
id: PLACEHOLDER
title: "Test note"
source: "docs/test.md"
tags: [test]
created: PLACEHOLDER
---
EOF

  # Send an edit event instead of create_file
  make_hook_input "replace_string_in_file" "${TMPDIR}/notes/test-note.md" | bash "$HOOK_SCRIPT"

  # Verify file was NOT modified
  assert_contains "${TMPDIR}/notes/test-note.md" "^id: PLACEHOLDER$" \
    "PLACEHOLDER not replaced for non-create event"

  teardown_workspace
}

test_ignores_failed_tool_result() {
  echo "TEST: Ignores failed tool results"
  setup_workspace

  cat > "${TMPDIR}/notes/test-note.md" <<'EOF'
---
type: note
id: PLACEHOLDER
title: "Test note"
source: "docs/test.md"
tags: [test]
created: PLACEHOLDER
---
EOF

  # Send a failure result
  make_hook_input "create_file" "${TMPDIR}/notes/test-note.md" "failure" | bash "$HOOK_SCRIPT"

  # Verify file was NOT modified
  assert_contains "${TMPDIR}/notes/test-note.md" "^id: PLACEHOLDER$" \
    "PLACEHOLDER not replaced for failed result"

  teardown_workspace
}

test_ignores_bad_frontmatter() {
  echo "TEST: Ignores files without valid frontmatter"
  setup_workspace

  # Create a file without frontmatter
  echo "Just some text, no frontmatter." > "${TMPDIR}/notes/no-frontmatter.md"

  # Run the hook
  make_hook_input "create_file" "${TMPDIR}/notes/no-frontmatter.md" | bash "$HOOK_SCRIPT"

  # Verify index was NOT modified
  assert_not_contains "${TMPDIR}/_index.md" "no-frontmatter" \
    "File without frontmatter not added to index"

  teardown_workspace
}

test_ignores_unknown_type() {
  echo "TEST: Ignores files with unknown type"
  setup_workspace

  cat > "${TMPDIR}/notes/unknown-type.md" <<'EOF'
---
type: summary
id: PLACEHOLDER
title: "Unknown type"
created: PLACEHOLDER
---
EOF

  # Run the hook
  make_hook_input "create_file" "${TMPDIR}/notes/unknown-type.md" | bash "$HOOK_SCRIPT"

  # Verify PLACEHOLDER not replaced
  assert_contains "${TMPDIR}/notes/unknown-type.md" "^id: PLACEHOLDER$" \
    "PLACEHOLDER not replaced for unknown type"

  teardown_workspace
}

test_question_with_parent() {
  echo "TEST: Question with parent field"
  setup_workspace

  cat > "${TMPDIR}/notes/q-followup.md" <<'EOF'
---
type: question
id: PLACEHOLDER
question: "What hashing algorithm is used?"
parent: "Q-20260225-143022-731"
source: "asker"
status: open
created: PLACEHOLDER
---
EOF

  # Run the hook
  make_hook_input "create_file" "${TMPDIR}/notes/q-followup.md" | bash "$HOOK_SCRIPT"

  # Verify PLACEHOLDER replaced
  assert_contains "${TMPDIR}/notes/q-followup.md" "^id: Q-" \
    "Follow-up question gets Q- prefix"
  assert_contains "${TMPDIR}/_index.md" "What hashing algorithm is used?" \
    "Follow-up question added to index"

  teardown_workspace
}

test_create_tool_name_variant() {
  echo "TEST: Handles 'create' tool name (GitHub coding agent variant)"
  setup_workspace

  cat > "${TMPDIR}/notes/q-variant.md" <<'EOF'
---
type: question
id: PLACEHOLDER
question: "Does create tool name work?"
source: "asker"
status: open
created: PLACEHOLDER
---
EOF

  # Use "create" instead of "create_file"
  make_hook_input "create" "${TMPDIR}/notes/q-variant.md" | bash "$HOOK_SCRIPT"

  # Verify it still processed
  assert_contains "${TMPDIR}/notes/q-variant.md" "^id: Q-" \
    "'create' tool name handled correctly"

  teardown_workspace
}

test_multiple_questions_only_target_answered() {
  echo "TEST: Only the target question is marked answered"
  setup_workspace

  # Pre-populate with two open questions
  sed -i '/<!-- END QUESTIONS -->/i | Q-20260225-143022-001 | open | First question? | asker | |' "${TMPDIR}/_index.md"
  sed -i '/<!-- END QUESTIONS -->/i | Q-20260225-143022-002 | open | Second question? | asker | |' "${TMPDIR}/_index.md"

  # Create a note answering only the first question
  cat > "${TMPDIR}/notes/answer-first.md" <<'EOF'
---
type: note
id: PLACEHOLDER
title: "Answer to first question"
answers: "Q-20260225-143022-001"
source: "docs/test.md"
tags: [test]
created: PLACEHOLDER
---

This answers the first question.
EOF

  make_hook_input "create_file" "${TMPDIR}/notes/answer-first.md" | bash "$HOOK_SCRIPT"

  # First question answered
  assert_contains "${TMPDIR}/_index.md" "| Q-20260225-143022-001 | answered |" \
    "First question marked as answered"
  # Second question still open
  assert_contains "${TMPDIR}/_index.md" "| Q-20260225-143022-002 | open |" \
    "Second question still open"

  teardown_workspace
}

# --- Run all tests ---

echo "============================================"
echo "  update-index.sh test suite"
echo "============================================"
echo ""

test_question_creation
echo ""
test_note_creation
echo ""
test_note_answers_question
echo ""
test_ignores_non_notes_path
echo ""
test_ignores_non_create_tool
echo ""
test_ignores_failed_tool_result
echo ""
test_ignores_bad_frontmatter
echo ""
test_ignores_unknown_type
echo ""
test_question_with_parent
echo ""
test_create_tool_name_variant
echo ""
test_multiple_questions_only_target_answered
echo ""

echo "============================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
