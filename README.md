# auto-dev-team

Autonomous feature development powered by AI agent teams. Define features, assign engines, and let the agents build your project.

auto-dev-team is a standalone orchestration tool that assembles a system prompt from protocol files and agent definitions, then launches AI CLI tools to autonomously implement features in your target project. A Lead Agent (CTO) coordinates specialist agents (Backend, Frontend, QA), each of which can run on a different AI engine.

## How It Works

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  run.sh     │────▶│ Assemble prompt  │────▶│  Claude Code CLI    │
│  (entry)    │     │ + engine config  │     │  (Lead Agent)       │
└─────────────┘     └──────────────────┘     └─────────┬───────────┘
                                                       │
                                              ┌────────▼────────┐
                                              │   Lead Agent    │
                                              │   (CTO)         │
                                              └──┬─────┬─────┬──┘
                                                 │     │     │
                                  engine:claude  │     │     │  engine:codex
                                        ┌────────┘     │     └────────┐
                                        ▼              ▼              ▼
                                   ┌─────────┐  ┌──────────┐  ┌──────────┐
                                   │ Backend │  │ Frontend │  │    QA    │
                                   │ (Codex) │  │ (Claude) │  │ (Codex)  │
                                   └─────────┘  └──────────┘  └──────────┘
                                        │              │              │
                                        └──────────────┼──────────────┘
                                                       ▼
                                              ┌─────────────────┐
                                              │ Target Project  │
                                              └─────────────────┘
```

## Key Features

- **Multi-engine dispatch** — Each agent role can run on a different AI CLI tool (Claude Code, Codex CLI, etc.)
- **Dependency-aware scheduling** — Features are dispatched in dependency order, independent features run in parallel
- **Automatic retry** — Failed features retry up to `max_attempts` with error context passed to the next attempt
- **PR workflow** — Every feature goes through branch → implement → QA → PR → squash merge
- **Crash recovery** — Resume interrupted sessions without losing progress

## Prerequisites

- **Claude Code CLI**: `npm install -g @anthropic-ai/claude-code`
- **jq**: `brew install jq` (macOS) or `apt install jq` (Linux)
- **git**: Any recent version
- **gh** (GitHub CLI): Required for PR creation and merge

Optional (for multi-engine):
- **Codex CLI**: `npm install -g @openai/codex` (for `engine: "codex"`)

## Quick Start

```bash
# 1. Create a target project (must be a git repo with a remote)
mkdir -p /tmp/my-app && cd /tmp/my-app
git init && git commit --allow-empty -m "chore: init"

# 2. Register the project
cd /path/to/auto-dev-team
./scripts/init-project.sh my-app /tmp/my-app

# 3. Define features
# Edit: projects/my-app/feature_list.json
# Or copy the example: cp examples/todo-app/feature_list.json projects/my-app/

# 4. Run
./scripts/run.sh my-app
```

The Lead Agent will read the feature list, dispatch tasks to specialist agents, run QA, create PRs, and merge — all automatically.

## Example: Todo App

A complete working example is included. It builds a full-stack todo app (Express + vanilla JS) with 4 features:

```bash
# Register
./scripts/init-project.sh todo-demo /tmp/todo-demo

# Copy example features
cp examples/todo-app/feature_list.json projects/todo-demo/

# Run
./scripts/run.sh todo-demo

# After completion, start the app:
cd /tmp/todo-demo && npm start
# Open http://localhost:3000
```

The 4 features built automatically:

| Feature | Category | Description |
|---------|----------|-------------|
| F-001 | backend | Express server with /health endpoint |
| F-002 | backend | CRUD REST API for todos (GET/POST/PUT/DELETE) |
| F-003 | frontend | Todo list UI with add form |
| F-004 | frontend | Toggle completion and delete buttons |

## Project Structure

```
auto-dev-team/
├── agents/
│   ├── lead.md              # CTO — orchestrates, never writes code
│   ├── backend.md           # Server-side specialist
│   ├── frontend.md          # Client-side specialist
│   └── qa.md                # Tester — validates, never fixes
├── protocol.md              # Execution protocol injected into Lead Agent
├── team.json                # Engine definitions + agent-to-engine mapping
├── scripts/
│   ├── run.sh               # Entry point — assembles prompt, launches session
│   ├── init-project.sh      # Register a new target project
│   ├── resume.sh            # Resume after crash
│   ├── check-env.sh         # Validate prerequisites
│   └── filter-prompt.sh     # Filter agent prompts by engine
├── projects/                # Registered project configs + state
│   └── <name>/
│       ├── config.json
│       ├── feature_list.json
│       └── progress.log
├── examples/
│   └── todo-app/            # Example feature list
└── docs/
    └── plans/               # Design documents
```

## Multi-Engine Dispatch

Each agent can run on a different AI CLI tool. Configure this in `team.json`:

```json
{
  "engines": {
    "claude": {
      "command": "claude -p --dangerously-skip-permissions",
      "description": "Best for complex, multi-file, architectural tasks"
    },
    "codex": {
      "command": "codex -q --full-auto",
      "description": "Best for focused implementation, tests, simple CRUD"
    }
  },
  "agents": [
    { "name": "lead",     "engine": "claude", "role": "CTO / Lead Agent" },
    { "name": "backend",  "engine": "codex",  "role": "Backend Specialist" },
    { "name": "frontend", "engine": "claude", "role": "Frontend Specialist" },
    { "name": "qa",       "engine": "codex",  "role": "QA Engineer" }
  ]
}
```

### Engine Resolution

Priority chain: **feature.engine** > **agent.engine** > default `"claude"`

You can override the engine per feature:

```json
{
  "id": "F-005",
  "category": "backend",
  "engine": "claude",
  "title": "Complex auth refactor",
  "description": "This needs Claude for multi-file coordination..."
}
```

### Adding a New Engine

1. Add to `engines` in `team.json`:
   ```json
   "gemini": { "command": "gemini -m gemini-2.5-pro", "description": "..." }
   ```
2. Add `<!-- engine:gemini -->` blocks to agent prompts
3. Assign agents: `"engine": "gemini"`

### Engine-Specific Prompts

Agent prompts use marker blocks for engine-specific instructions:

```markdown
# Backend Specialist

Shared instructions for all engines...

<!-- engine:claude -->
Claude-specific: use Read/Write/Edit tools, multi-step approach...
<!-- /engine:claude -->

<!-- engine:codex -->
Codex-specific: work autonomously, commit and push when done...
<!-- /engine:codex -->

Shared completion criteria...
```

`scripts/filter-prompt.sh` strips non-matching blocks at dispatch time.

## Writing Features

Edit `projects/<name>/feature_list.json`:

```json
{
  "project": "my-app",
  "version": "3.1",
  "features": [
    {
      "id": "F-001",
      "category": "backend",
      "title": "Initialize Express server",
      "description": "Create Express.js server with GET /health on port 3000.",
      "status": "pending",
      "assigned_to": null,
      "depends_on": [],
      "priority": 1,
      "attempts": 0,
      "max_attempts": 3,
      "branch": null,
      "created_at": "2026-02-19",
      "started_at": null,
      "completed_at": null,
      "error_log": [],
      "notes": ""
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier (e.g., `"F-001"`) |
| `category` | string | Agent routing: `"backend"`, `"frontend"`, or custom |
| `engine` | string\|null | Optional engine override (`"claude"`, `"codex"`, `"auto"`) |
| `title` | string | Short feature title |
| `description` | string | Detailed implementation instructions |
| `status` | string | Current state (see Status Lifecycle) |
| `depends_on` | string[] | Feature IDs that must complete first |
| `priority` | number | Dispatch order (lower = higher priority) |
| `max_attempts` | number | Max retries before blocking |

## Status Lifecycle

```
pending → in_progress → testing → merging → completed
              ↓             ↓
           failed         failed
              ↓             ↓
         (retry) → pending   OR   blocked (max attempts)

Terminal states: completed, blocked, cancelled
```

## Agent Roles

| Agent | Role | Engine (default) |
|-------|------|------------------|
| **Lead** | CTO / Orchestrator. Reads protocol, dispatches tasks, updates state. Never writes code. | claude |
| **Backend** | Server-side specialist. API routes, database, business logic. | configurable |
| **Frontend** | Client-side specialist. UI, components, styling, state. | configurable |
| **QA** | Tester. Validates features on branch, reports pass/fail. Does not fix code. | configurable |

## Custom Agents

1. Create a prompt file: `agents/<name>.md`
2. Add the agent to `team.json`:
   ```json
   {
     "name": "devops",
     "role": "DevOps Specialist",
     "engine": "codex",
     "prompt_file": "agents/devops.md",
     "focus": ["CI/CD", "deployment", "infrastructure"]
   }
   ```
3. Use the matching category in features: `"category": "devops"`

## Resuming After a Crash

```bash
./scripts/resume.sh <project-name>
```

Resets orphaned `in_progress`/`testing` tasks to `pending` and re-launches.

## Security Note

auto-dev-team runs Claude Code with `--dangerously-skip-permissions`, which allows the AI to execute arbitrary commands. This is necessary for autonomous operation but means:

- Only run on projects you trust
- `feature_list.json` is treated as trusted input
- Review generated code before deploying to production
- Consider running in a sandboxed environment (container, VM)

## License

MIT
