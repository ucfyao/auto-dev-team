# auto-dev-team: Autonomous AI Development System v3.0

**Date:** 2026-02-19
**Status:** Approved
**Form:** GitHub template repository

## Overview

A GitHub template repo that lets users fork, fill in a `feature_list.json` with 3-5 features, and run a single command to watch a Claude Code Agent Team autonomously build the project — with a Lead Agent orchestrating specialized Backend, Frontend, and QA agents.

## Goals

- Zero external dependencies beyond Claude Code CLI
- Fork → fill features → run → watch agents build code
- Ships with a working TODO app demo (5 pre-filled features)
- Preset roles (Lead, Backend, Frontend, QA) + custom role support

## Repo Structure

```
auto-dev-team/
├── CLAUDE.md                         # Autonomous dev protocol (read on every session)
├── feature_list.json                 # Task queue (state machine core)
├── progress.log                      # Handoff log between sessions
├── team.json                         # Agent Team role configuration
├── .claude/
│   ├── settings.local.json           # Claude Code permission config
│   └── agents/                       # Role system prompts
│       ├── lead.md                   # CTO / Lead Agent
│       ├── backend.md                # Backend specialist
│       ├── frontend.md               # Frontend specialist
│       └── qa.md                     # QA engineer
├── scripts/
│   ├── run.sh                        # One-click start (calls claude CLI)
│   └── init.sh                       # Environment check
├── examples/
│   └── todo-app/                     # Ready-to-run demo
│       ├── feature_list.json         # 5 pre-filled features
│       └── README.md                 # Demo instructions
└── README.md                         # Template usage guide
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
- On failure: Git rollback, `attempts += 1`, back to `pending`

## Agent Team Architecture

### team.json

```json
{
  "team_name": "auto-dev",
  "agents": [
    {
      "name": "lead",
      "role": "CTO / Lead Agent",
      "prompt_file": ".claude/agents/lead.md",
      "capabilities": ["read", "plan", "delegate"],
      "does_not": ["write code directly"]
    },
    {
      "name": "backend",
      "role": "Backend Specialist",
      "prompt_file": ".claude/agents/backend.md",
      "focus": ["API", "database", "server logic"],
      "tools": ["Edit", "Write", "Bash", "Grep", "Glob", "Read"]
    },
    {
      "name": "frontend",
      "role": "Frontend Specialist",
      "prompt_file": ".claude/agents/frontend.md",
      "focus": ["UI", "components", "styling", "client state"],
      "tools": ["Edit", "Write", "Bash", "Grep", "Glob", "Read"]
    },
    {
      "name": "qa",
      "role": "QA Engineer",
      "prompt_file": ".claude/agents/qa.md",
      "focus": ["testing", "validation", "bug reporting"],
      "tools": ["Bash", "Read", "Grep", "Glob"],
      "does_not": ["fix code — reports back to responsible agent"]
    }
  ],
  "custom_agents": []
}
```

### Role Responsibilities

**Lead Agent (CTO):**

1. On startup: read `feature_list.json` + `progress.log`
2. Sort executable tasks by priority and dependency resolution
3. Use `TeamCreate` to initialize the team, `SendMessage` to dispatch tasks
4. Does NOT write code — only reviews and coordinates
5. Updates `feature_list.json` and `progress.log` on task completion

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
- Does NOT fix code. Reports failures via `SendMessage` to the responsible agent
- On pass: updates `passes: true`

**Custom Roles:**

- Users add entries to `custom_agents` in `team.json`
- Create a matching `.md` prompt file in `.claude/agents/`
- Lead Agent routes tasks by matching `category` to agent name

## Success Criteria

- User forks the template repo
- Fills in 3-5 features in `feature_list.json` (or uses the TODO app example)
- Runs `./scripts/run.sh`
- Observes Agent Team: Lead dispatches tasks → Backend/Frontend build code → QA validates
- All features reach `status: completed` with generated, working code

## Non-Goals

- No Web UI / dashboard (out of scope for v1)
- No multi-provider support (Claude Code CLI only)
- No cost tracking or token monitoring
- No CI/CD integration
