# auto-dev-team: Autonomous AI Development System v3.0

**Date:** 2026-02-19
**Status:** Approved
**Form:** Standalone tool (GitHub repo, works on any project)

## Overview

A standalone CLI tool that orchestrates a Claude Code Agent Team to autonomously build features for any target project. Users clone the tool once, register target projects, fill in a `feature_list.json`, and run a single command — the tool handles everything else.

The tool lives separately from target projects. Zero file pollution.

## Goals

- Zero external dependencies beyond Claude Code CLI and jq
- Clone once → register project → fill features → run
- Works on any target project regardless of tech stack
- Ships with a working TODO app demo (5 pre-filled features)
- Preset roles (Lead, Backend, Frontend, QA) + custom role support
- Target project stays 100% clean — no auto-dev files injected

## Repo Structure

```
auto-dev-team/
├── agents/                         # Agent system prompts
│   ├── lead.md                     # CTO / Lead Agent
│   ├── backend.md                  # Backend specialist
│   ├── frontend.md                 # Frontend specialist
│   └── qa.md                       # QA engineer
├── protocol.md                     # Master autonomous dev protocol
├── team.json                       # Default team config
├── projects/                       # Per-project state directories
│   └── <project-name>/
│       ├── config.json             # { "target": "/absolute/path/to/project" }
│       ├── feature_list.json       # Task queue for this project
│       └── progress.log            # Handoff log for this project
├── scripts/
│   ├── run.sh                      # Main entry: ./scripts/run.sh <project-name>
│   ├── init-project.sh             # Setup: ./scripts/init-project.sh <name> <path>
│   └── check-env.sh               # Environment check
├── examples/
│   └── todo-app/
│       ├── feature_list.json       # 5 pre-filled features
│       └── README.md               # Demo instructions
├── README.md
└── .gitignore
```

## Workflow

```bash
# 1. Clone (one-time setup)
git clone https://github.com/you/auto-dev-team ~/tools/auto-dev-team
cd ~/tools/auto-dev-team

# 2. Register a target project
./scripts/init-project.sh my-app /Users/me/code/my-app

# 3. Fill in features
vim projects/my-app/feature_list.json

# 4. Run
./scripts/run.sh my-app
```

## How run.sh Works

```
./scripts/run.sh my-app

  1. Read projects/my-app/config.json → get target project path
  2. Read projects/my-app/feature_list.json → get tasks
  3. Read protocol.md + agents/lead.md → assemble mega-prompt
  4. Run check-env.sh against target project
  5. cd into target project directory
  6. Launch: claude --dangerously-skip-permissions -p "<assembled prompt>"
  7. Lead Agent uses TeamCreate + Task to spawn specialists
  8. Agents work in target project, state files accessed via absolute paths
  9. On completion: feature_list.json and progress.log updated in projects/my-app/
```

## Core State Machine: feature_list.json

### Schema

```json
{
  "project": "my-project",
  "version": "3.0",
  "features": [
    {
      "id": "F-001",
      "category": "backend",
      "title": "User registration API",
      "description": "Implement POST /api/auth/register with email + password",
      "status": "pending",
      "assigned_to": null,
      "depends_on": [],
      "priority": 1,
      "passes": false,
      "attempts": 0,
      "max_attempts": 3,
      "created_at": "2026-02-19",
      "completed_at": null,
      "notes": ""
    }
  ]
}
```

### Status Flow

```
pending → in_progress → testing → completed
              ↓             ↓
            failed ←←←←← failed
              ↓
    (attempts < max_attempts ? retry : blocked)
```

### Field Definitions

| Field                       | Purpose                                                           |
| --------------------------- | ----------------------------------------------------------------- |
| `category`                  | Maps to the responsible agent (backend/frontend/qa/custom)        |
| `assigned_to`               | Which agent claimed this task                                     |
| `depends_on`                | Feature IDs that must be `completed` before this task is eligible |
| `priority`                  | Lower number = higher priority                                    |
| `attempts` / `max_attempts` | Retry mechanism; exceeding max marks task as `blocked`            |
| `passes`                    | Set to `true` by QA Agent after successful validation             |

### Rules

- Lead Agent sorts by `priority` + `depends_on` to determine next executable task
- Agent claims task: sets `status: in_progress` + `assigned_to`
- On completion: `status: testing`, QA Agent validates, then `passes: true` + `status: completed`
- On failure: Git rollback in target project, `attempts += 1`, back to `pending`

## Agent Team Architecture

### team.json

```json
{
  "team_name": "auto-dev",
  "agents": [
    {
      "name": "lead",
      "role": "CTO / Lead Agent",
      "prompt_file": "agents/lead.md",
      "capabilities": ["read", "plan", "delegate"],
      "does_not": ["write code directly"]
    },
    {
      "name": "backend",
      "role": "Backend Specialist",
      "prompt_file": "agents/backend.md",
      "focus": ["API", "database", "server logic"],
      "tools": ["Edit", "Write", "Bash", "Grep", "Glob", "Read"]
    },
    {
      "name": "frontend",
      "role": "Frontend Specialist",
      "prompt_file": "agents/frontend.md",
      "focus": ["UI", "components", "styling", "client state"],
      "tools": ["Edit", "Write", "Bash", "Grep", "Glob", "Read"]
    },
    {
      "name": "qa",
      "role": "QA Engineer",
      "prompt_file": "agents/qa.md",
      "focus": ["testing", "validation", "bug reporting"],
      "tools": ["Bash", "Read", "Grep", "Glob"],
      "does_not": ["fix code — reports failures back to responsible agent"]
    }
  ],
  "custom_agents": []
}
```

### Role Responsibilities

**Lead Agent (CTO):**

1. Receives the assembled prompt with protocol + features + state paths
2. Sorts executable tasks by priority and dependency resolution
3. Uses TeamCreate to initialize the team, Task tool to spawn specialists
4. Does NOT write code — only reviews and coordinates
5. Updates feature_list.json and progress.log via absolute paths

**Backend Agent:**

- Receives backend-category tasks from Lead
- Focuses exclusively on server-side code (APIs, database, business logic)
- Notifies Lead on completion, status transitions to `testing`

**Frontend Agent:**

- Receives frontend-category tasks from Lead
- Focuses exclusively on client-side code (components, styling, state)
- Notifies Lead on completion, status transitions to `testing`

**QA Agent:**

- Picks up tasks with `status: testing`
- Runs test commands (unit tests, E2E, curl validation)
- Does NOT fix code. Reports failures to the responsible agent
- On pass: updates `passes: true`

**Custom Roles:**

- Users add entries to `custom_agents` in `team.json`
- Create matching `.md` prompt files in `agents/`
- Lead Agent routes tasks by matching `category` to agent name

## Key Design Decisions

1. **Separate from target project** — auto-dev-team never writes files into the target project's config. All orchestration state lives in `projects/<name>/`.
2. **Absolute paths for state** — run.sh resolves all paths to absolute before injecting into the prompt, so agents can read/write state files regardless of CWD.
3. **Prompt injection over file injection** — protocol and agent prompts are assembled into the mega-prompt by run.sh, not copied into the target project.
4. **Per-project isolation** — each registered project has its own state directory. You can manage multiple projects concurrently.

## Success Criteria

- User clones auto-dev-team
- Runs `./scripts/init-project.sh todo-demo /tmp/todo-demo` (or any target path)
- Copies the example feature list: `cp examples/todo-app/feature_list.json projects/todo-demo/`
- Runs `./scripts/run.sh todo-demo`
- Observes Agent Team: Lead dispatches tasks → Backend/Frontend build code → QA validates
- All features reach `status: completed` with generated, working code in the target project

## Non-Goals

- No Web UI / dashboard (out of scope for v1)
- No multi-provider support (Claude Code CLI only)
- No cost tracking or token monitoring
- No CI/CD integration
