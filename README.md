# auto-dev-team

Autonomous feature development powered by a Claude Code Agent Team. Point it at any project, define features, and let the agents build them.

auto-dev-team is a standalone orchestration tool that assembles a system prompt from protocol files and agent definitions, then launches Claude Code to autonomously implement features in your target project. A Lead Agent coordinates specialist agents (Backend, Frontend, QA) that are spawned as sub-agents via the Task tool.

## How It Works

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  run.sh     │────▶│ Assemble prompt  │────▶│  Claude Code CLI    │
│  (entry)    │     │ to temp file     │     │  (stdin pipe)       │
└─────────────┘     └──────────────────┘     └─────────┬───────────┘
                                                       │
                                              ┌────────▼────────┐
                                              │   Lead Agent    │
                                              │   (CTO)         │
                                              └──┬─────┬─────┬──┘
                                                 │     │     │
                                        ┌────────┘     │     └────────┐
                                        ▼              ▼              ▼
                                   ┌─────────┐  ┌──────────┐  ┌──────────┐
                                   │ Backend │  │ Frontend │  │    QA    │
                                   │  Agent  │  │  Agent   │  │  Agent   │
                                   └─────────┘  └──────────┘  └──────────┘
                                        │              │              │
                                        └──────────────┼──────────────┘
                                                       ▼
                                              ┌─────────────────┐
                                              │ Target Project  │
                                              └─────────────────┘
```

## Prerequisites

- **Claude Code CLI**: `npm install -g @anthropic-ai/claude-code`
- **jq**: `brew install jq` (macOS) or `apt install jq` (Linux)
- **git**: Any recent version

## Quick Start

```bash
# 1. Create a target project
mkdir -p /tmp/my-app && cd /tmp/my-app && git init

# 2. Initialize the project in auto-dev-team
cd /path/to/auto-dev-team
./scripts/init-project.sh my-app /tmp/my-app

# 3. Edit the feature list
# Add your features to: projects/my-app/feature_list.json

# 4. Run
./scripts/run.sh my-app
```

## Registering a Project

```bash
./scripts/init-project.sh <project-name> <target-project-path>
```

This creates a project directory under `projects/<name>/` with:

- `config.json` — project configuration (target path, name, creation date)
- `feature_list.json` — empty feature list to populate
- `progress.log` — JSONL event log

## Writing Features

Edit `projects/<name>/feature_list.json` to define your features. Each feature has:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier (e.g., `"F-001"`) |
| `category` | string | Agent routing: `"backend"`, `"frontend"`, or custom |
| `title` | string | Short feature title |
| `description` | string | Detailed implementation instructions |
| `status` | string | Current state (see Status Lifecycle) |
| `assigned_to` | string\|null | Agent currently working on this |
| `depends_on` | string[] | Feature IDs that must complete first |
| `priority` | number | Dispatch order (lower = higher priority) |
| `attempts` | number | Number of implementation attempts |
| `max_attempts` | number | Max retries before blocking |
| `branch` | string\|null | Git branch name for this feature |
| `created_at` | string | Creation date |
| `started_at` | string\|null | ISO timestamp when work began |
| `completed_at` | string\|null | Completion date |
| `error_log` | string[] | Error messages from failed attempts |
| `notes` | string | Optional notes |

## Status Lifecycle

```
pending → in_progress → testing → merging → completed
              ↓             ↓
           failed         failed
              ↓             ↓
         (retry) → pending   OR   blocked (max attempts)

Terminal states: completed, blocked, cancelled
```

- **pending**: Ready to be assigned (or waiting for dependencies)
- **in_progress**: An agent is implementing the feature
- **testing**: QA agent is validating the implementation
- **merging**: Feature branch is being merged to main
- **completed**: Merged to main, all tests pass
- **failed**: Implementation or tests failed (will retry)
- **blocked**: Max attempts reached or dependency is blocked
- **cancelled**: Manually cancelled

## Agent Roles

| Agent | Role | Spawned Via |
|-------|------|-------------|
| **Lead** | CTO / Orchestrator. Reads protocol, dispatches tasks, updates state. Never writes code. | Runs as the main Claude Code session |
| **Backend** | Server-side specialist. API routes, database, business logic. | `Task` tool with `subagent_type: "general-purpose"` |
| **Frontend** | Client-side specialist. UI, components, styling, state. | `Task` tool with `subagent_type: "general-purpose"` |
| **QA** | Tester. Validates features on branch, reports pass/fail. Does not fix code. | `Task` tool with `subagent_type: "general-purpose"` |

## Custom Agents

To add a custom specialist:

1. Create a prompt file: `agents/<name>.md`
2. Add the agent to `team.json` under `custom_agents`:
   ```json
   {
     "name": "devops",
     "role": "DevOps Specialist",
     "prompt_file": "agents/devops.md",
     "focus": ["CI/CD", "deployment", "infrastructure"]
   }
   ```
3. Use the matching category name in your features: `"category": "devops"`

## Resuming After a Crash

If a session crashes, tasks may be stuck in `in_progress` or `testing`:

```bash
./scripts/resume.sh <project-name>
```

This resets orphaned tasks to `pending` and re-launches the session.

## Examples

See [`examples/todo-app/`](examples/todo-app/) for a complete example that builds a simple Express + vanilla JS todo application.

## Configuration

`team.json` defines the agent team structure. This file is **informational context** — it is injected into the Lead Agent's prompt so it knows which agents are available and their capabilities. It is NOT consumed by Claude Code's native team system.

## Security Note

auto-dev-team runs Claude Code with `--dangerously-skip-permissions`, which allows the AI to execute arbitrary commands in the target project directory without confirmation prompts. This is necessary for autonomous operation but means:

- Only run on projects you trust
- `feature_list.json` is treated as trusted input — do not accept feature definitions from untrusted sources
- Review generated code before deploying to production
- Consider running in a sandboxed environment (container, VM) for additional safety
