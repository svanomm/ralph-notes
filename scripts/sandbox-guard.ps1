# Ralph Note - Sandbox Guard (PreToolUse Hook)
# Enforces file access restrictions:
#   - Writes: only to notes/ folder and PROGRESS.md
#   - Terminal: blocked entirely
#   - Reads: allowed within workspace only

$ErrorActionPreference = 'Stop'

try {
    $rawInput = [System.Console]::In.ReadToEnd()
    $hookInput = $rawInput | ConvertFrom-Json
} catch {
    # Can't parse input — deny by default
    @{
        hookSpecificOutput = @{
            hookEventName        = 'PreToolUse'
            permissionDecision   = 'deny'
            permissionDecisionReason = 'SANDBOX: Failed to parse hook input.'
        }
    } | ConvertTo-Json -Depth 5
    exit 0
}

$toolName      = $hookInput.tool_name
$toolInput     = $hookInput.tool_input
$workspaceRoot = $hookInput.cwd

# ---------------------------------------------------------------------------
# Path validation helpers
# ---------------------------------------------------------------------------

function Test-WriteAllowed {
    param([string]$FilePath, [string]$Root)

    # Canonicalize to eliminate .. traversal
    $fp = [System.IO.Path]::GetFullPath($FilePath).ToLower().Replace('/', '\').TrimEnd('\')
    $wr = [System.IO.Path]::GetFullPath($Root).ToLower().Replace('/', '\').TrimEnd('\')

    # Must be inside the workspace
    if (-not $fp.StartsWith("$wr\")) { return $false }

    $relative = $fp.Substring($wr.Length + 1)

    # Allow writes to notes/ directory (any depth)
    if ($relative -eq 'notes' -or $relative.StartsWith('notes\')) { return $true }

    # Allow writes to PROGRESS.md at workspace root
    if ($relative -eq 'progress.md') { return $true }

    return $false
}

function Test-ReadAllowed {
    param([string]$FilePath, [string]$Root)

    # Canonicalize to eliminate .. traversal
    $fp = [System.IO.Path]::GetFullPath($FilePath).ToLower().Replace('/', '\').TrimEnd('\')
    $wr = [System.IO.Path]::GetFullPath($Root).ToLower().Replace('/', '\').TrimEnd('\')

    # Must be inside the workspace
    return $fp.StartsWith("$wr\") -or $fp -eq $wr
}

# ---------------------------------------------------------------------------
# Tool classification
# ---------------------------------------------------------------------------

$writeTools    = @('create_file', 'replace_string_in_file', 'multi_replace_string_in_file')
$terminalTools = @('run_in_terminal')
$readTools     = @('read_file', 'list_dir', 'grep_search', 'file_search', 'semantic_search')

# Tools that are always safe (no file system side-effects)
$allowedTools  = @('runSubagent', 'manage_todo_list', 'ask_questions', 'get_errors', 'tool_search_tool_regex')

# ---------------------------------------------------------------------------
# Build response
# ---------------------------------------------------------------------------

$result = @{
    hookSpecificOutput = @{
        hookEventName = 'PreToolUse'
    }
}

if ($writeTools -contains $toolName) {
    # ------- WRITE TOOLS: enforce notes/ + PROGRESS.md only -------
    $filePaths = @()

    if ($toolName -eq 'multi_replace_string_in_file') {
        if ($toolInput.replacements) {
            foreach ($r in $toolInput.replacements) {
                if ($r.filePath) { $filePaths += $r.filePath }
            }
        }
    } else {
        if ($toolInput.filePath) { $filePaths += $toolInput.filePath }
    }

    if ($filePaths.Count -eq 0) {
        $result.hookSpecificOutput.permissionDecision       = 'deny'
        $result.hookSpecificOutput.permissionDecisionReason = 'SANDBOX: No file path found in tool input.'
    } else {
        $denied = $false
        foreach ($fp in $filePaths) {
            if (-not (Test-WriteAllowed -FilePath $fp -Root $workspaceRoot)) {
                $result.hookSpecificOutput.permissionDecision       = 'deny'
                $result.hookSpecificOutput.permissionDecisionReason = "SANDBOX: Write to '$fp' denied. Only writes to notes/ and PROGRESS.md are allowed."
                $denied = $true
                break
            }
        }
        if (-not $denied) {
            $result.hookSpecificOutput.permissionDecision = 'allow'
        }
    }

} elseif ($terminalTools -contains $toolName) {
    # ------- TERMINAL: blocked entirely -------
    $result.hookSpecificOutput.permissionDecision       = 'deny'
    $result.hookSpecificOutput.permissionDecisionReason = 'SANDBOX: Terminal commands are blocked. Use built-in file tools instead.'

} elseif ($readTools -contains $toolName) {
    # ------- READ TOOLS: must be within workspace -------
    $filePath = $null
    if ($toolInput.filePath) { $filePath = $toolInput.filePath }
    elseif ($toolInput.path)  { $filePath = $toolInput.path }

    if ($filePath -and -not (Test-ReadAllowed -FilePath $filePath -Root $workspaceRoot)) {
        $result.hookSpecificOutput.permissionDecision       = 'deny'
        $result.hookSpecificOutput.permissionDecisionReason = "SANDBOX: Read from '$filePath' denied. Must read from within workspace."
    } else {
        $result.hookSpecificOutput.permissionDecision = 'allow'
    }

} elseif ($allowedTools -contains $toolName) {
    # ------- EXPLICITLY ALLOWED TOOLS (safe, no file-system side-effects) -------
    $result.hookSpecificOutput.permissionDecision = 'allow'

} else {
    # ------- DENY BY DEFAULT: unknown or dangerous tools -------
    $result.hookSpecificOutput.permissionDecision       = 'deny'
    $result.hookSpecificOutput.permissionDecisionReason = "SANDBOX: Tool '$toolName' is not in the allowlist and was denied."
}

$result | ConvertTo-Json -Depth 5
exit 0
