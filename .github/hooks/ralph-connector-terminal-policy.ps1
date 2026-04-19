# Agent-scoped PreToolUse hook for the ralph-connector agent.
$ErrorActionPreference = 'Stop'

$AgentName = 'ralph-connector'
$AllowedScripts = @(
    'scripts/assign_note_batch.py'
)

function Write-DenyResponse {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    @{
        hookSpecificOutput = @{
            hookEventName = 'PreToolUse'
            permissionDecision = 'deny'
            permissionDecisionReason = $Reason
        }
    } | ConvertTo-Json -Depth 6 -Compress | Write-Output
    exit 0
}

function Normalize-Token {
    param([string]$Text)

    if ($null -eq $Text) {
        return ''
    }

    $value = $Text.Trim()
    if ($value.Length -ge 2) {
        $isSingleQuoted = $value.StartsWith("'") -and $value.EndsWith("'")
        $isDoubleQuoted = $value.StartsWith('"') -and $value.EndsWith('"')
        if ($isSingleQuoted -or $isDoubleQuoted) {
            $value = $value.Substring(1, $value.Length - 2)
        }
    }

    return $value
}

function Normalize-ScriptPath {
    param([string]$PathText)

    $pathValue = Normalize-Token $PathText
    $pathValue = $pathValue.Replace('\', '/')

    while ($pathValue.StartsWith('./')) {
        $pathValue = $pathValue.Substring(2)
    }

    return $pathValue.ToLowerInvariant()
}

$inputText = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($inputText)) {
    exit 0
}

try {
    $hookInput = $inputText | ConvertFrom-Json
} catch {
    Write-DenyResponse 'Hook input was invalid JSON.'
}

$toolNameRaw = [string]$hookInput.tool_name
if ([string]::IsNullOrWhiteSpace($toolNameRaw)) {
    exit 0
}

$toolName = $toolNameRaw.ToLowerInvariant()
$collapsedToolName = ($toolName -replace '[/._-]', '')

$blockedTools = @(
    'sendtoterminal'
    'executesendtoterminal'
    'executionsubagent'
    'executeexecutionsubagent'
)

if ($blockedTools -contains $collapsedToolName) {
    Write-DenyResponse "Tool '$toolNameRaw' is not permitted for $AgentName."
}

$runTerminalTools = @(
    'runinterminal'
    'executeruninterminal'
)

if ($runTerminalTools -notcontains $collapsedToolName) {
    exit 0
}

$commandText = [string]$hookInput.tool_input.command
if ([string]::IsNullOrWhiteSpace($commandText)) {
    Write-DenyResponse 'Terminal command is missing.'
}

$tokens = @()
$parseErrors = @()
$ast = [System.Management.Automation.Language.Parser]::ParseInput(
    $commandText,
    [ref]$tokens,
    [ref]$parseErrors
)

if ($parseErrors.Count -gt 0) {
    Write-DenyResponse "Only direct 'uv run <allowed script>' commands are permitted."
}

$statements = @($ast.EndBlock.Statements)
if ($statements.Count -ne 1) {
    Write-DenyResponse 'Command chaining is not permitted.'
}

$statement = $statements[0]
if ($statement -isnot [System.Management.Automation.Language.PipelineAst]) {
    Write-DenyResponse 'Only a single direct command is permitted.'
}

if ($statement.PipelineElements.Count -ne 1) {
    Write-DenyResponse 'Pipelines are not permitted.'
}

$commandAst = $statement.PipelineElements[0]
if ($commandAst -isnot [System.Management.Automation.Language.CommandAst]) {
    Write-DenyResponse 'Only direct command invocations are permitted.'
}

$elements = @($commandAst.CommandElements)
if ($elements.Count -lt 3) {
    Write-DenyResponse "Command not permitted for $AgentName."
}

$executable = (Normalize-Token $elements[0].Extent.Text).ToLowerInvariant()
$verb = (Normalize-Token $elements[1].Extent.Text).ToLowerInvariant()
$scriptPath = Normalize-ScriptPath $elements[2].Extent.Text

if ($executable -ne 'uv' -or $verb -ne 'run') {
    Write-DenyResponse "Only 'uv run <allowed script>' commands are permitted."
}

if ($AllowedScripts -notcontains $scriptPath) {
    $allowedList = ($AllowedScripts | ForEach-Object { "uv run $_" }) -join '; '
    Write-DenyResponse "Command not permitted for $AgentName. Allowed commands: $allowedList"
}

exit 0