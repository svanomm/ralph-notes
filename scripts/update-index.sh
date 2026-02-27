#!/bin/bash
set -e

# PostToolUse hook — updates _index.md after file creation in notes/
# Reads JSON from stdin describing the completed tool call.
# Only acts on successful create_file events targeting notes/.

# --- Dependency check ---
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed" >&2
  exit 1
fi

# --- Read JSON input from stdin ---
INPUT=$(cat)

# --- Guard: only act on create_file / create events ---
TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName')
if [ "$TOOL_NAME" != "create_file" ] && [ "$TOOL_NAME" != "create" ]; then
  exit 0
fi

# --- Guard: tool must have succeeded ---
RESULT_TYPE=$(echo "$INPUT" | jq -r '.toolResult.resultType // empty')
if [ "$RESULT_TYPE" != "success" ]; then
  exit 0
fi

# --- Extract file path from toolArgs ---
TOOL_ARGS=$(echo "$INPUT" | jq -r '.toolArgs')
FILE_PATH=$(echo "$TOOL_ARGS" | jq -r '.filePath // .path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# --- Guard: only act on files in notes/ ---
if [[ "$FILE_PATH" != */notes/* ]] && [[ "$FILE_PATH" != notes/* ]]; then
  exit 0
fi

# --- Guard: file must exist on disk ---
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# --- Extract frontmatter from the file ---
# Frontmatter is everything between the first and second '---' lines
FRONTMATTER=$(sed -n '/^---$/,/^---$/{/^---$/d;p;}' "$FILE_PATH")

if [ -z "$FRONTMATTER" ]; then
  exit 0
fi

# Helper: extract a YAML scalar value by key (strips quotes and whitespace)
get_field() {
  echo "$FRONTMATTER" | grep -m1 "^${1}:" | sed "s/^${1}: *//; s/\r//; s/^ *//; s/ *$//; s/^\"//; s/\"$//; s/^'//; s/'$//"
}

TYPE=$(get_field "type")

# --- Guard: must be a note or question ---
if [ "$TYPE" != "note" ] && [ "$TYPE" != "question" ]; then
  exit 0
fi

# --- Generate unique ID and ISO timestamp ---
DATESTAMP=$(date -u +"%Y%m%d-%H%M%S")
MILLIS=$(date -u +"%3N" 2>/dev/null)
if [ "$MILLIS" = "%3N" ] || [ -z "$MILLIS" ]; then
  MILLIS=$(printf "%03d" $((RANDOM % 1000)))
fi
ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.${MILLIS}Z")

if [ "$TYPE" = "note" ]; then
  ID="NOTE-${DATESTAMP}-${MILLIS}"
else
  ID="Q-${DATESTAMP}-${MILLIS}"
fi

# --- Replace PLACEHOLDERs in the created file ---
sed -i "s/^id: PLACEHOLDER$/id: ${ID}/" "$FILE_PATH"
sed -i "s/^created: PLACEHOLDER$/created: ${ISO_TIMESTAMP}/" "$FILE_PATH"

# --- Locate _index.md ---
CWD=$(echo "$INPUT" | jq -r '.cwd')
INDEX_FILE="${CWD%/}/_index.md"

if [ ! -f "$INDEX_FILE" ]; then
  exit 0
fi

# --- Append entry to the appropriate table in _index.md ---
if [ "$TYPE" = "question" ]; then
  QUESTION=$(get_field "question")
  SOURCE=$(get_field "source")

  export ROW="| ${ID} | open | ${QUESTION} | ${SOURCE} | |"
  awk '/<!-- END QUESTIONS -->/ { print ENVIRON["ROW"] } { print }' \
    "$INDEX_FILE" > "${INDEX_FILE}.tmp" && mv "${INDEX_FILE}.tmp" "$INDEX_FILE"

elif [ "$TYPE" = "note" ]; then
  TITLE=$(get_field "title")
  ANSWERS=$(get_field "answers")
  SOURCE=$(get_field "source")

  export ROW="| ${ID} | ${TITLE} | ${ANSWERS} | ${SOURCE} | ${ISO_TIMESTAMP} |"
  awk '/<!-- END NOTES -->/ { print ENVIRON["ROW"] } { print }' \
    "$INDEX_FILE" > "${INDEX_FILE}.tmp" && mv "${INDEX_FILE}.tmp" "$INDEX_FILE"

  # If this note answers a question, mark that question as answered
  if [ -n "$ANSWERS" ]; then
    sed -i "/${ANSWERS}/ s/| open |/| answered |/" "$INDEX_FILE"
    sed -i "/${ANSWERS}/ s/| *|$/| ${ID} |/" "$INDEX_FILE"
  fi
fi

# --- Update the "Last Updated" timestamp ---
sed -i "s/^Last Updated:.*$/Last Updated: ${ISO_TIMESTAMP}/" "$INDEX_FILE"

exit 0
