# Ralph Note - Index Updater (PostToolUse Hook)
# Fires after every tool invocation. Only acts on create_file in notes/.
#   - Generates timestamp-based IDs (millisecond precision)
#   - Replaces PLACEHOLDER id and created fields in the new file
#   - Appends entries to _index.md
#   - Marks questions as answered when a note references them

$ErrorActionPreference = 'Stop'

try {
    $rawInput  = [System.Console]::In.ReadToEnd()
    $hookInput = $rawInput | ConvertFrom-Json
} catch {
    Write-Output '{}'
    exit 0
}

# ---- Fast exit: only process create_file events ----
if ($hookInput.toolName -ne 'create_file') {
    Write-Output '{}'
    exit 0
}

$toolArgs      = try { $hookInput.toolArgs | ConvertFrom-Json } catch { @{} }
$filePath      = $toolArgs.filePath
$workspaceRoot = $hookInput.cwd

if (-not $filePath) {
    Write-Output '{}'
    exit 0
}

# ---- Only process .md files inside notes/ ----
$fpNorm   = $filePath.Replace('/', '\').TrimEnd('\').ToLower()
$notesDirNorm = (Join-Path $workspaceRoot 'notes').ToLower()

if (-not $fpNorm.StartsWith("$notesDirNorm\")) {
    Write-Output '{}'
    exit 0
}

$fileName = [System.IO.Path]::GetFileName($filePath)
if (-not $fileName.EndsWith('.md') -or $fileName.StartsWith('_')) {
    Write-Output '{}'
    exit 0
}

# ---- Read the newly created file ----
if (-not (Test-Path $filePath)) {
    Write-Output '{}'
    exit 0
}

$content = Get-Content $filePath -Raw -ErrorAction SilentlyContinue
if (-not $content) {
    Write-Output '{}'
    exit 0
}

# ---- Parse YAML frontmatter ----
if ($content -notmatch '(?s)^---\r?\n(.*?)\r?\n---') {
    Write-Output '{}'
    exit 0
}
$frontmatter = $Matches[1]

# ---- Determine document type ----
$type = $null
if ($frontmatter -match '(?m)^type:\s*"?(\w+)"?\s*$') {
    $type = $Matches[1].ToLower()
}

if ($type -ne 'note' -and $type -ne 'question') {
    Write-Output '{}'
    exit 0
}

# ---- Skip if file already has a real (non-placeholder) ID ----
if ($frontmatter -match '(?m)^id:\s*"?(NOTE-\d|Q-\d)') {
    Write-Output '{}'
    exit 0
}

# ---- Generate timestamp-based ID (millisecond precision) ----
$now              = [DateTime]::UtcNow
$timestamp        = $now.ToString('yyyyMMdd-HHmmss-fff')
$createdTimestamp  = $now.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$idPrefix         = if ($type -eq 'note') { 'NOTE' } else { 'Q' }
$newId            = "$idPrefix-$timestamp"

# ---- Replace PLACEHOLDERs in the file ----
$updatedContent = $content -replace '(?m)^(id:\s*)"?PLACEHOLDER"?\s*$',      "`${1}$newId"
$updatedContent = $updatedContent -replace '(?m)^(created:\s*)"?PLACEHOLDER"?\s*$', "`${1}$createdTimestamp"

Set-Content -Path $filePath -Value $updatedContent -NoNewline -Encoding UTF8

# ---- Extract metadata for the index ----
$title    = ''
if ($frontmatter -match '(?m)^title:\s*"([^"]*)"')                     { $title    = $Matches[1] }
$question = ''
if ($frontmatter -match '(?m)^question:\s*"([^"]*)"')                  { $question = $Matches[1] }
$answers  = ''
if ($frontmatter -match '(?m)^answers:\s*"?([A-Za-z0-9\-]+)"?\s*$')   { $answers  = $Matches[1] }
$source   = ''
if ($frontmatter -match '(?m)^source:\s*"([^"]*)"')                    { $source   = $Matches[1] }
$parent   = ''
if ($frontmatter -match '(?m)^parent:\s*"?([A-Za-z0-9\-]+)"?\s*$')    { $parent   = $Matches[1] }

# ---- Ensure _index.md exists ----
$indexFile = Join-Path $workspaceRoot '_index.md'

if (-not (Test-Path $indexFile)) {
    $indexTemplate = @"
# Research Index

Last Updated: $createdTimestamp

## Questions

| ID | Status | Question | Source | Answered By |
|----|--------|----------|--------|-------------|
<!-- END QUESTIONS -->

## Notes

| ID | Title | Answers | Source Doc | Created |
|----|-------|---------|-----------|---------|
<!-- END NOTES -->
"@
    Set-Content -Path $indexFile -Value $indexTemplate -Encoding UTF8
}

$indexContent = Get-Content $indexFile -Raw

# ---- Update "Last Updated" timestamp ----
$indexContent = $indexContent -replace '(?m)^Last Updated:.*$', "Last Updated: $createdTimestamp"

# ---- Append entry to the correct table ----
$contextMsg = ''

if ($type -eq 'question') {
    $sourceInfo = if ($parent) { "followup:$parent" } else { 'asker' }
    $newRow     = "| $newId | open | $question | $sourceInfo | |"
    $indexContent = $indexContent -replace '<!-- END QUESTIONS -->', "$newRow`n<!-- END QUESTIONS -->"
    $contextMsg   = "[Ralph Hook] New question indexed as $newId. Added to _index.md."
}
elseif ($type -eq 'note') {
    $newRow     = "| $newId | $title | $answers | $source | $createdTimestamp |"
    $indexContent = $indexContent -replace '<!-- END NOTES -->', "$newRow`n<!-- END NOTES -->"
    $contextMsg   = "[Ralph Hook] Note indexed as $newId."

    # If this note answers a question, mark the question as answered
    if ($answers) {
        $escapedId  = [regex]::Escape($answers)
        $pattern    = "(\| $escapedId \| )open( \|)"
        $replacement = '${1}answered${2}'
        $indexContent = $indexContent -replace $pattern, $replacement
        $contextMsg  += " Question $answers marked as answered."
    }
}

Set-Content -Path $indexFile -Value $indexContent -NoNewline -Encoding UTF8

# ---- Exit cleanly (PostToolUse output is ignored by the hook runner) ----
Write-Output '{}'
exit 0
