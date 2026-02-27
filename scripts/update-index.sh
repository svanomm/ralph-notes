#!/usr/bin/env bash
# Ralph Note - Index Updater (PostToolUse Hook)
# Fires after every tool invocation. Only acts on create_file in notes/.
#   - Generates timestamp-based IDs (millisecond precision)
#   - Replaces PLACEHOLDER id and created fields in the new file
#   - Appends entries to _index.md
#   - Marks questions as answered when a note references them

export HOOK_INPUT
HOOK_INPUT=$(cat)

python3 - <<'PYEOF'
import json, sys, os, re
from datetime import datetime, timezone

raw = os.environ.get('HOOK_INPUT', '')

try:
    hook_input = json.loads(raw)
except Exception:
    print('{}')
    sys.exit(0)

# ---- Fast exit: only process create_file events ----
if hook_input.get('toolName') != 'create_file':
    print('{}')
    sys.exit(0)

file_path      = json.loads(hook_input.get('toolArgs') or '{}').get('filePath', '')
workspace_root = hook_input.get('cwd', '')

if not file_path:
    print('{}')
    sys.exit(0)

# ---- Only process .md files inside notes/ ----
fp_norm        = os.path.normpath(file_path).lower()
notes_dir_norm = os.path.normpath(os.path.join(workspace_root, 'notes')).lower()

if not fp_norm.startswith(notes_dir_norm + os.sep):
    print('{}')
    sys.exit(0)

file_name = os.path.basename(file_path)
if not file_name.endswith('.md') or file_name.startswith('_'):
    print('{}')
    sys.exit(0)

# ---- Read the newly created file ----
if not os.path.exists(file_path):
    print('{}')
    sys.exit(0)

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
except Exception:
    print('{}')
    sys.exit(0)

if not content:
    print('{}')
    sys.exit(0)

# ---- Parse YAML frontmatter ----
fm_match = re.search(r'^---\r?\n(.*?)\r?\n---', content, re.DOTALL)
if not fm_match:
    print('{}')
    sys.exit(0)

frontmatter = fm_match.group(1)

# ---- Determine document type ----
type_match = re.search(r'(?m)^type:\s*"?(\w+)"?\s*$', frontmatter)
doc_type   = type_match.group(1).lower() if type_match else None

if doc_type not in ('note', 'question'):
    print('{}')
    sys.exit(0)

# ---- Skip if file already has a real (non-placeholder) ID ----
if re.search(r'(?m)^id:\s*"?(NOTE-\d|Q-\d)', frontmatter):
    print('{}')
    sys.exit(0)

# ---- Generate timestamp-based ID (millisecond precision) ----
now               = datetime.now(timezone.utc)
timestamp         = now.strftime('%Y%m%d-%H%M%S-') + f'{now.microsecond // 1000:03d}'
created_timestamp = now.strftime('%Y-%m-%dT%H:%M:%S.') + f'{now.microsecond // 1000:03d}Z'
id_prefix         = 'NOTE' if doc_type == 'note' else 'Q'
new_id            = f'{id_prefix}-{timestamp}'

# ---- Replace PLACEHOLDERs in the file ----
updated_content = re.sub(
    r'(?m)^(id:\s*)"?PLACEHOLDER"?\s*$',
    lambda m: f'{m.group(1)}{new_id}',
    content
)
updated_content = re.sub(
    r'(?m)^(created:\s*)"?PLACEHOLDER"?\s*$',
    lambda m: f'{m.group(1)}{created_timestamp}',
    updated_content
)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(updated_content)

# ---- Extract metadata for the index ----
title_m    = re.search(r'(?m)^title:\s*"([^"]*)"', frontmatter)
title      = title_m.group(1) if title_m else ''

question_m = re.search(r'(?m)^question:\s*"([^"]*)"', frontmatter)
question   = question_m.group(1) if question_m else ''

answers_m  = re.search(r'(?m)^answers:\s*"?([A-Za-z0-9\-]+)"?\s*$', frontmatter)
answers    = answers_m.group(1) if answers_m else ''

source_m   = re.search(r'(?m)^source:\s*"([^"]*)"', frontmatter)
source     = source_m.group(1) if source_m else ''

parent_m   = re.search(r'(?m)^parent:\s*"?([A-Za-z0-9\-]+)"?\s*$', frontmatter)
parent     = parent_m.group(1) if parent_m else ''

# ---- Ensure _index.md exists ----
index_file = os.path.join(workspace_root, '_index.md')

if not os.path.exists(index_file):
    index_template = (
        "# Research Index\n\n"
        f"Last Updated: {created_timestamp}\n\n"
        "## Questions\n\n"
        "| ID | Status | Question | Source | Answered By |\n"
        "|----|--------|----------|--------|-------------|\n"
        "<!-- END QUESTIONS -->\n\n"
        "## Notes\n\n"
        "| ID | Title | Answers | Source Doc | Created |\n"
        "|----|-------|---------|-----------|---------|\n"
        "<!-- END NOTES -->\n"
    )
    with open(index_file, 'w', encoding='utf-8') as f:
        f.write(index_template)

with open(index_file, 'r', encoding='utf-8') as f:
    index_content = f.read()

# ---- Update "Last Updated" timestamp ----
index_content = re.sub(r'(?m)^Last Updated:.*$', f'Last Updated: {created_timestamp}', index_content)

# ---- Append entry to the correct table ----
context_msg = ''

if doc_type == 'question':
    source_info   = f'followup:{parent}' if parent else 'asker'
    new_row       = f'| {new_id} | open | {question} | {source_info} | |'
    index_content = index_content.replace('<!-- END QUESTIONS -->', f'{new_row}\n<!-- END QUESTIONS -->')
    context_msg   = f'[Ralph Hook] New question indexed as {new_id}. Added to _index.md.'

elif doc_type == 'note':
    new_row       = f'| {new_id} | {title} | {answers} | {source} | {created_timestamp} |'
    index_content = index_content.replace('<!-- END NOTES -->', f'{new_row}\n<!-- END NOTES -->')
    context_msg   = f'[Ralph Hook] Note indexed as {new_id}.'

    # If this note answers a question, mark the question as answered
    if answers:
        escaped_id    = re.escape(answers)
        index_content = re.sub(
            rf'(\| {escaped_id} \| )open( \|)',
            r'\1answered\2',
            index_content
        )
        context_msg += f' Question {answers} marked as answered.'

with open(index_file, 'w', encoding='utf-8') as f:
    f.write(index_content)

# ---- Exit cleanly (PostToolUse output is ignored by the hook runner) ----
print('{}')
sys.exit(0)
PYEOF
