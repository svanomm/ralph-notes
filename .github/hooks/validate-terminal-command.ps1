# validate-terminal-command.ps1
# PreToolUse hook that restricts terminal commands for Ralph Note agents.
# Each agent passes its name via the RALPH_AGENT environment variable.
# The script reads JSON from stdin, checks the tool_name and tool_input,
# and denies any terminal command not in the agent's allow-list.

$ErrorActionPreference = 'Stop'

# ── Read hook input from stdin ────────────────────────────────────────
$jsonInput = [Console]::In.ReadToEnd()
$hookInput = $jsonInput | ConvertFrom-Json

$toolName = $hookInput.tool_name

# ── Block tools that should never be used by these agents ─────────────
$blockedTools = @('send_to_terminal', 'execution_subagent')
if ($toolName -in $blockedTools) {
    @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = "Tool '$toolName' is not permitted for Ralph Note agents."
        }
    } | ConvertTo-Json -Depth 3 -Compress | Write-Output
    exit 0
}

# ── Only validate run_in_terminal; allow everything else ──────────────
if ($toolName -ne 'run_in_terminal') {
    exit 0
}

# ── Allowed command patterns per agent ────────────────────────────────
$allowedPatterns = @{
    asker     = @(
        '^\s*uv\s+run\s+\.?/?scripts/create_question\.py\b'
        '^\s*uv\s+run\s+\.?/?scripts/update_index\.py\b'
    )
    doer      = @(
        '^\s*uv\s+run\s+\.?/?scripts/create_note\.py\b'
        '^\s*uv\s+run\s+\.?/?scripts/update_index\.py\b'
    )
    connector = @(
        '^\s*uv\s+run\s+\.?/?scripts/assign_note_batch\.py\b'
    )
}

# ── Resolve agent name from environment ───────────────────────────────
$agent = $env:RALPH_AGENT
if (-not $agent -or -not $allowedPatterns.ContainsKey($agent)) {
    @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = "Unknown agent '$agent' — all terminal commands denied."
        }
    } | ConvertTo-Json -Depth 3 -Compress | Write-Output
    exit 0
}

# ── Extract the command string from tool input ────────────────────────
$command = ''
if ($hookInput.tool_input.PSObject.Properties['command']) {
    $command = $hookInput.tool_input.command
}

# ── Block command chaining / shell metacharacters ─────────────────────
# Catches ;  &&  ||  |  newlines  $()  backtick-escapes and & (call operator mid-command)
$chainPattern = ';|&&|\|\||(?<!\A)\||\r|\n|`|\$\(|&\s'
if ($command -match $chainPattern) {
    @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = "Chained or compound commands are not permitted. Submit a single allowed command."
        }
    } | ConvertTo-Json -Depth 3 -Compress | Write-Output
    exit 0
}

# ── Match against allowed patterns ────────────────────────────────────
$patterns  = $allowedPatterns[$agent]
$isAllowed = $false
foreach ($p in $patterns) {
    if ($command -match $p) {
        $isAllowed = $true
        break
    }
}

if ($isAllowed) {
    exit 0
}

$readable = ($patterns -join '  |  ')
@{
    hookSpecificOutput = @{
        hookEventName            = 'PreToolUse'
        permissionDecision       = 'deny'
        permissionDecisionReason = "Command not permitted for the '$agent' agent. Allowed: $readable"
    }
} | ConvertTo-Json -Depth 3 -Compress | Write-Output
exit 0
