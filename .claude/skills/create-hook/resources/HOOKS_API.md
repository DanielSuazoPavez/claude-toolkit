# Claude Code Hooks API Reference

Source: [Official Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks)

## Contents

1. [Hook Events](#hook-events) - All events with blocking/matcher support
2. [Hook Types](#hook-types) - command, http, prompt, agent
3. [Common Input Fields](#common-input-fields) - Fields available to all hooks
4. [Event-Specific Input Fields](#event-specific-input-fields) - Per-event JSON schemas
5. [Tool-Specific Inputs](#tool-specific-inputs) - Bash, Read, Edit, Write, Task
6. [Output Format](#output-format) - Exit codes, JSON decisions, control flow
7. [settings.json Configuration](#settingsjson-configuration) - Matcher syntax, env vars
8. [Debugging](#debugging) - Logging and troubleshooting

## Hook Events

| Event | When | Can Block? | Matcher? |
|-------|------|------------|----------|
| SessionStart | Session begins/resumes | No | Yes |
| UserPromptSubmit | User sends message | Yes | No |
| **PreToolUse** | Before tool runs | **Yes** | Yes |
| PermissionRequest | Permission dialog shown | Yes | Yes |
| PostToolUse | After tool succeeds | No | Yes |
| PostToolUseFailure | After tool fails | No | Yes |
| SubagentStart | Subagent spawns | No | Yes |
| SubagentStop | Subagent completes | Yes | Yes |
| Stop | Claude finishes responding | Yes | No |
| StopFailure | Turn ends due to API error | No | Yes |
| PreCompact | Before context compaction | No | Yes |
| PostCompact | After context compaction | No | Yes |
| InstructionsLoaded | CLAUDE.md/.claude/rules loaded | No | Yes |
| ConfigChange | Config file changes during session | Yes | Yes |
| TaskCompleted | Task marked completed | No | No |
| TeammateIdle | Agent team teammate going idle | No | No |
| WorktreeCreate | Worktree being created | No | No |
| WorktreeRemove | Worktree being removed | No | No |
| Elicitation | MCP server requests user input | No | Yes |
| ElicitationResult | User responds to MCP elicitation | No | Yes |
| Setup | --init or --maintenance flags | No | Yes |
| SessionEnd | Session terminates | No | Yes |
| Notification | Needs user attention | No | Yes |

## Hook Types

Each hook has a `type` that determines how it runs.

### `command` — Shell command (default)

Runs a shell command. Communicates via stdin (JSON input), stdout (JSON output), stderr (feedback), and exit codes.

```json
{ "type": "command", "command": "bash .claude/hooks/my-hook.sh", "timeout": 30 }
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `command` | yes | — | Shell command to execute |
| `timeout` | no | 600 | Seconds before canceling |
| `statusMessage` | no | — | Custom spinner message while running |

### `http` — POST to URL

Posts event data as JSON to an HTTP endpoint. Response body uses the same JSON format as command hooks.

```json
{
  "type": "http",
  "url": "http://localhost:8080/hooks/tool-use",
  "headers": { "Authorization": "Bearer $MY_TOKEN" },
  "allowedEnvVars": ["MY_TOKEN"]
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `url` | yes | — | Endpoint URL |
| `headers` | no | — | HTTP headers (supports `$VAR` interpolation) |
| `allowedEnvVars` | no | — | Env vars allowed in header interpolation |
| `timeout` | no | 600 | Seconds before canceling |

### `prompt` — Single-turn LLM evaluation

Sends prompt + hook input to a Claude model for a yes/no judgment. No tool access.

```json
{
  "type": "prompt",
  "prompt": "Check if all tasks are complete. $ARGUMENTS",
  "model": "claude-haiku-4-5-20251001",
  "timeout": 30
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `prompt` | yes | — | Prompt text. `$ARGUMENTS` is replaced with hook input JSON |
| `model` | no | haiku | Model for evaluation |
| `timeout` | no | 30 | Seconds before canceling |
| `statusMessage` | no | — | Custom spinner message |

**Response format** — the model returns:
- `{"ok": true}` — action proceeds
- `{"ok": false, "reason": "what remains"}` — action is blocked, reason fed back to Claude

**Example: Anti-rationalization Stop hook**
```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "prompt",
        "prompt": "Review this response for completeness. If Claude declared victory while leaving work undone, respond {\"ok\": false, \"reason\": \"what remains\"}. Response: $ARGUMENTS"
      }]
    }]
  }
}
```

### `agent` — Multi-turn verification with tool access

Spawns a subagent that can read files, search code, and run tools before returning a decision. Same `ok`/`reason` response format as prompt hooks.

```json
{
  "type": "agent",
  "prompt": "Verify all unit tests pass. Run the test suite. $ARGUMENTS",
  "model": "claude-sonnet-4-6",
  "timeout": 60
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `prompt` | yes | — | Task prompt. `$ARGUMENTS` is replaced with hook input JSON |
| `model` | no | haiku | Model for the subagent |
| `timeout` | no | 60 | Seconds before canceling |
| `statusMessage` | no | — | Custom spinner message |

Agent hooks have up to 50 tool-use turns and access to Read, Grep, Glob, and Bash.

**When to use which:** Use `prompt` when hook input alone is enough to decide. Use `agent` when you need to verify against actual codebase state.

## Common Input Fields

All hooks receive these fields via stdin JSON:

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/.claude/projects/.../session.jsonl",
  "cwd": "/path/to/project",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | Unique session identifier |
| `transcript_path` | string | Path to conversation JSON |
| `cwd` | string | Current working directory |
| `permission_mode` | string | `"default"`, `"plan"`, `"acceptEdits"`, `"dontAsk"`, `"bypassPermissions"` |
| `hook_event_name` | string | Event that triggered this hook |

## Event-Specific Input Fields

### SessionStart

```json
{
  "hook_event_name": "SessionStart",
  "source": "startup",
  "model": "claude-sonnet-4-20250514",
  "agent_type": "custom-agent"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `source` | string | `"startup"`, `"resume"`, `"clear"`, `"compact"` |
| `model` | string | Model identifier |
| `agent_type` | string | (Optional) Agent name if started with `--agent` |

**Matchers:** `startup`, `resume`, `clear`, `compact`

### UserPromptSubmit

```json
{
  "hook_event_name": "UserPromptSubmit",
  "prompt": "Write a function to calculate factorial"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `prompt` | string | User's submitted prompt text |

### PreToolUse / PermissionRequest

```json
{
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": { ... },
  "tool_use_id": "toolu_01ABC123..."
}
```

| Field | Type | Description |
|-------|------|-------------|
| `tool_name` | string | Tool being called |
| `tool_input` | object | Tool-specific parameters (see below) |
| `tool_use_id` | string | Unique identifier for this tool call |

### PostToolUse / PostToolUseFailure

```json
{
  "hook_event_name": "PostToolUse",
  "tool_name": "Write",
  "tool_input": { ... },
  "tool_response": { ... },
  "tool_use_id": "toolu_01ABC123..."
}
```

| Field | Type | Description |
|-------|------|-------------|
| `tool_name` | string | Tool that was called |
| `tool_input` | object | Tool-specific parameters |
| `tool_response` | object | Tool execution result |
| `tool_use_id` | string | Unique identifier for this tool call |

### SubagentStart

```json
{
  "hook_event_name": "SubagentStart",
  "agent_id": "agent-abc123",
  "agent_type": "Explore"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `agent_id` | string | Unique subagent identifier |
| `agent_type` | string | Agent name (e.g., `"Bash"`, `"Explore"`, `"Plan"`) |

### SubagentStop

```json
{
  "hook_event_name": "SubagentStop",
  "stop_hook_active": false,
  "agent_id": "def456",
  "agent_transcript_path": "~/.claude/projects/.../subagents/agent-def456.jsonl"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `stop_hook_active` | boolean | True if continuing due to stop hook |
| `agent_id` | string | Unique subagent identifier |
| `agent_transcript_path` | string | Path to subagent's transcript |

### Stop

```json
{
  "hook_event_name": "Stop",
  "stop_hook_active": true,
  "last_assistant_message": "Text of Claude's final response"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `stop_hook_active` | boolean | True if continuing due to stop hook (prevent infinite loops!) |
| `last_assistant_message` | string | Full text of Claude's final response (avoids parsing transcript) |

### PreCompact

```json
{
  "hook_event_name": "PreCompact",
  "trigger": "manual",
  "custom_instructions": ""
}
```

| Field | Type | Description |
|-------|------|-------------|
| `trigger` | string | `"manual"` (from /compact) or `"auto"` |
| `custom_instructions` | string | User instructions (manual only) |

**Matchers:** `manual`, `auto`

### Setup

```json
{
  "hook_event_name": "Setup",
  "trigger": "init"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `trigger` | string | `"init"` (from --init) or `"maintenance"` |

**Matchers:** `init`, `maintenance`

### SessionEnd

```json
{
  "hook_event_name": "SessionEnd",
  "reason": "exit"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `reason` | string | `"clear"`, `"logout"`, `"prompt_input_exit"`, `"other"` |

### Notification

```json
{
  "hook_event_name": "Notification",
  "message": "Claude needs your permission to use Bash",
  "notification_type": "permission_prompt"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `message` | string | Notification message |
| `notification_type` | string | Type of notification |

**Matchers:** `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`

## Tool-Specific Inputs

### Bash

```json
{
  "tool_input": {
    "command": "npm run test",
    "description": "Run tests",
    "timeout": 120000,
    "run_in_background": false
  }
}
```

### Read

```json
{
  "tool_input": {
    "file_path": "/path/to/file.txt",
    "offset": 0,
    "limit": 100
  }
}
```

### Edit

```json
{
  "tool_input": {
    "file_path": "/path/to/file.txt",
    "old_string": "original text",
    "new_string": "replacement text",
    "replace_all": false
  }
}
```

### Write

```json
{
  "tool_input": {
    "file_path": "/path/to/file.txt",
    "content": "file content"
  }
}
```

### Task (Subagent)

```json
{
  "tool_input": {
    "subagent_type": "code-reviewer",
    "prompt": "Review this code",
    "description": "Code review task"
  }
}
```

## Output Format

### Exit Codes

| Code | Meaning | Behavior |
|------|---------|----------|
| 0 | Success | stdout shown in verbose mode; JSON parsed for control |
| 2 | Block | stderr shown to Claude (PreToolUse) or user |
| Other | Error | stderr shown to user, execution continues |

### JSON Output (exit code 0)

#### PreToolUse Decision

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "Auto-approved",
    "updatedInput": { "command": "modified command" },
    "additionalContext": "Extra info for Claude"
  }
}
```

| Decision | Effect |
|----------|--------|
| `"allow"` | Bypass permission, execute tool |
| `"deny"` | Block tool, show reason to Claude |
| `"ask"` | Show permission dialog to user |

#### PermissionRequest Decision

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedInput": { "command": "modified command" }
    }
  }
}
```

| Field | Values | Notes |
|-------|--------|-------|
| `decision.behavior` | `"allow"`, `"deny"` | No `"ask"` option |
| `decision.updatedInput` | object | Optional, allow only |
| `decision.updatedPermissions` | array | Optional, allow only — persists permission rules |
| `decision.message` | string | Optional, deny only |
| `decision.interrupt` | boolean | Optional, deny only |

**Note:** PermissionRequest uses `decision.behavior`, NOT `permissionDecision`. Different structure from PreToolUse.

#### Stop/SubagentStop Decision

```json
{
  "decision": "block",
  "reason": "Tasks not complete, continue working"
}
```

#### UserPromptSubmit

```json
{
  "decision": "block",
  "reason": "Prompt rejected",
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Context added to conversation"
  }
}
```

## settings.json Configuration

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/validate-bash.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/post-edit.sh" }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/on-prompt.sh" }
        ]
      }
    ]
  }
}
```

### Matcher Syntax

- Single tool: `"Bash"`
- Multiple tools: `"Read|Edit|Write"`
- Regex: `"Notebook.*"`
- All tools: `"*"` or `""`
- MCP tools: `"mcp__server__tool"` or `"mcp__memory__.*"`

### Environment Variables

| Variable | Description |
|----------|-------------|
| `CLAUDE_PROJECT_DIR` | Absolute path to project root |
| `CLAUDE_ENV_FILE` | (SessionStart/Setup only) File to persist env vars |
| `CLAUDE_CODE_REMOTE` | `"true"` if running in web environment |

## Debugging

```bash
#!/bin/bash
# Log all hook events
INPUT=$(cat)
mkdir -p ~/.claude/hooks-logs
echo "$(date -Iseconds) $INPUT" >> ~/.claude/hooks-logs/$(date +%Y-%m-%d).jsonl
```

Use `claude --debug` to see hook execution details.
