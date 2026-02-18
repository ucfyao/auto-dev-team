# auto-dev-team Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a GitHub template repo where users fork, fill `feature_list.json`, and run one command to watch a Claude Code Agent Team autonomously build their project.

**Architecture:** Pure Claude Code Native — zero external dependencies beyond Claude Code CLI. File-based state machine (`feature_list.json`) drives task dispatch. `.claude/agents/*.md` defines specialized roles. Shell scripts handle startup and environment checks.

**Tech Stack:** Claude Code CLI, Bash, JSON

---

### Task 1: Project scaffolding — .gitignore and empty progress.log

**Files:**

- Create: `.gitignore`
- Create: `progress.log`

**Step 1: Create .gitignore**

```gitignore
node_modules/
.env
.env.local
*.log
!progress.log
.DS_Store
```

**Step 2: Create empty progress.log**

```
# Auto-Dev-Team Progress Log
# Each session appends entries here for cross-session context handoff.
```

**Step 3: Commit**

```bash
git add .gitignore progress.log
git commit -m "chore: add gitignore and progress log"
```

---

### Task 2: Core state machine — feature_list.json template

**Files:**

- Create: `feature_list.json`

**Step 1: Create the empty template feature list**

```json
{
  "project": "my-project",
  "version": "3.0",
  "features": []
}
```

This is the user-facing template. Empty `features` array — users fill this in after forking.

**Step 2: Commit**

```bash
git add feature_list.json
git commit -m "feat: add feature_list.json state machine template"
```

---

### Task 3: Agent Team config — team.json

**Files:**

- Create: `team.json`

**Step 1: Create team.json with preset roles + custom slot**

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
      "does_not": ["fix code — reports failures back to responsible agent"]
    }
  ],
  "custom_agents": []
}
```

**Step 2: Commit**

```bash
git add team.json
git commit -m "feat: add team.json agent team configuration"
```

---

### Task 4: Lead Agent system prompt

**Files:**

- Create: `.claude/agents/lead.md`

**Step 1: Write lead.md**

This is the CTO prompt. It must instruct the Lead Agent on the full startup sequence, task dispatch logic, and completion protocol. Reference the design doc section "CLAUDE.md Protocol" for the exact rules.

Key behaviors to encode:

- Read `feature_list.json`, `progress.log`, `team.json` on startup
- Sort tasks by priority, resolve dependency chains
- Use `TeamCreate` to spawn the team
- Use `Task` tool (subagent_type: `general-purpose`) to spawn specialists with their `.claude/agents/*.md` prompt as system instructions
- Dispatch one task at a time per agent
- Update `feature_list.json` status fields after each task
- On failure: rollback git, increment attempts, log to progress.log
- On all features completed: write summary to progress.log

The prompt should be ~80-120 lines of clear, imperative instructions.

**Step 2: Commit**

```bash
git add .claude/agents/lead.md
git commit -m "feat: add lead agent (CTO) system prompt"
```

---

### Task 5: Backend Agent system prompt

**Files:**

- Create: `.claude/agents/backend.md`

**Step 1: Write backend.md**

Key behaviors:

- Receives task from Lead with feature ID, title, description
- Works only on server-side code (API routes, database, business logic)
- Creates a feature branch: `git checkout -b feature/F-XXX`
- Writes implementation code
- Runs any available test commands
- Commits with format: `feat(F-XXX): <title>`
- Notifies Lead on completion via SendMessage
- On error: does NOT silently continue — reports the error clearly

The prompt should be ~40-60 lines.

**Step 2: Commit**

```bash
git add .claude/agents/backend.md
git commit -m "feat: add backend specialist agent prompt"
```

---

### Task 6: Frontend Agent system prompt

**Files:**

- Create: `.claude/agents/frontend.md`

**Step 1: Write frontend.md**

Key behaviors:

- Same structure as backend.md but focused on client-side code
- Components, styling, state management, API consumption
- Same branch/commit/notify conventions
- Does NOT touch server-side files

The prompt should be ~40-60 lines.

**Step 2: Commit**

```bash
git add .claude/agents/frontend.md
git commit -m "feat: add frontend specialist agent prompt"
```

---

### Task 7: QA Agent system prompt

**Files:**

- Create: `.claude/agents/qa.md`

**Step 1: Write qa.md**

Key behaviors:

- Picks up tasks with `status: testing`
- Runs test/validation commands (unit tests, curl, E2E)
- Has read-only + bash access — cannot Edit or Write code files
- If tests pass: reports success to Lead
- If tests fail: sends detailed error report to the responsible agent (backend or frontend) via SendMessage — does NOT attempt to fix code
- Updates `passes` field

The prompt should be ~40-60 lines.

**Step 2: Commit**

```bash
git add .claude/agents/qa.md
git commit -m "feat: add QA engineer agent prompt"
```

---

### Task 8: Claude Code settings

**Files:**

- Create: `.claude/settings.local.json`

**Step 1: Write settings.local.json**

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(npm *)",
      "Bash(npx *)",
      "Bash(node *)",
      "Bash(curl *)",
      "Bash(source *)",
      "Bash(chmod *)",
      "Bash(cat *)",
      "Bash(ls *)",
      "Bash(mkdir *)"
    ]
  }
}
```

**Step 2: Commit**

```bash
git add .claude/settings.local.json
git commit -m "chore: add Claude Code permission settings"
```

---

### Task 9: Environment check script — init.sh

**Files:**

- Create: `scripts/init.sh`

**Step 1: Write init.sh**

```bash
#!/bin/bash
set -e

echo "=== Auto-Dev-Team Environment Check ==="

# Check Claude Code CLI
if ! command -v claude &> /dev/null; then
    echo "ERROR: Claude Code CLI not found."
    echo "Install: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

# Check Git
if ! git rev-parse --git-dir &> /dev/null; then
    echo "ERROR: Not a git repository. Run 'git init' first."
    exit 1
fi

# Check required files
missing=0
for f in feature_list.json team.json progress.log; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Missing required file: $f"
        missing=1
    fi
done
if [ $missing -eq 1 ]; then
    exit 1
fi

# Check feature_list has features
feature_count=$(node -e "const f=require('./feature_list.json'); console.log(f.features.length)" 2>/dev/null || echo "0")
if [ "$feature_count" = "0" ]; then
    echo "WARNING: feature_list.json has no features. Add features before running."
    exit 1
fi

# Check git status
if [ -n "$(git status --porcelain)" ]; then
    echo "WARNING: Uncommitted changes detected. Stashing..."
    git stash
fi

echo "=== Environment OK ($feature_count features loaded) ==="
```

**Step 2: Make executable**

```bash
chmod +x scripts/init.sh
```

**Step 3: Commit**

```bash
git add scripts/init.sh
git commit -m "feat: add environment check script"
```

---

### Task 10: One-click start script — run.sh

**Files:**

- Create: `scripts/run.sh`

**Step 1: Write run.sh**

```bash
#!/bin/bash
set -e

# Run environment check
source "$(dirname "$0")/init.sh" || exit 1

echo ""
echo "Starting Auto-Dev-Team v3.0..."
echo "$(date '+%Y-%m-%d %H:%M:%S'): Session started" >> progress.log

claude --dangerously-skip-permissions \
  -p "You are the Lead Agent of the Auto-Dev-Team system. Execute the startup sequence defined in CLAUDE.md exactly. Read feature_list.json, progress.log, and team.json, then initialize the Agent Team and begin dispatching tasks."
```

**Step 2: Make executable**

```bash
chmod +x scripts/run.sh
```

**Step 3: Commit**

```bash
git add scripts/run.sh
git commit -m "feat: add one-click start script"
```

---

### Task 11: CLAUDE.md — Autonomous dev protocol

**Files:**

- Create: `CLAUDE.md`

**Step 1: Write CLAUDE.md**

This is the master protocol file that Claude Code reads on every session. It must contain:

1. **Startup Sequence** — exact ordered steps (run init.sh, read state files, init team, dispatch)
2. **Task Dispatch Rules** — priority sorting, dependency resolution, category-to-agent matching
3. **Completion Protocol** — status transitions, QA handoff, failure handling
4. **Git Safety Rules** — branch-per-feature, commit format, rollback on failure
5. **State Update Rules** — how to read/write feature_list.json atomically
6. **Progress Logging** — what to log and when

Reference the design doc for exact content. The file should be ~100-150 lines of clear, imperative protocol.

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "feat: add CLAUDE.md autonomous development protocol"
```

---

### Task 12: Example demo — TODO app feature list

**Files:**

- Create: `examples/todo-app/feature_list.json`

**Step 1: Write the pre-filled feature list**

```json
{
  "project": "todo-app",
  "version": "3.0",
  "features": [
    {
      "id": "F-001",
      "category": "backend",
      "title": "Initialize Express server",
      "description": "Create a basic Express.js server with GET /health endpoint on port 3000. Install express as dependency. Create src/index.js as entry point.",
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
    },
    {
      "id": "F-002",
      "category": "backend",
      "title": "CRUD API for todos",
      "description": "Implement REST endpoints: GET /api/todos (list all), POST /api/todos (create), PUT /api/todos/:id (update), DELETE /api/todos/:id (delete). Use in-memory array storage. Each todo has: id (uuid), title (string), completed (boolean).",
      "status": "pending",
      "assigned_to": null,
      "depends_on": ["F-001"],
      "priority": 2,
      "passes": false,
      "attempts": 0,
      "max_attempts": 3,
      "created_at": "2026-02-19",
      "completed_at": null,
      "notes": ""
    },
    {
      "id": "F-003",
      "category": "frontend",
      "title": "Todo list UI",
      "description": "Create public/index.html with a form (text input + submit button) to add todos and an unordered list to display them. Use vanilla JS fetch to call GET /api/todos on load and POST /api/todos on submit. Serve static files from Express.",
      "status": "pending",
      "assigned_to": null,
      "depends_on": ["F-002"],
      "priority": 3,
      "passes": false,
      "attempts": 0,
      "max_attempts": 3,
      "created_at": "2026-02-19",
      "completed_at": null,
      "notes": ""
    },
    {
      "id": "F-004",
      "category": "frontend",
      "title": "Toggle and delete UI",
      "description": "Add a checkbox per todo item to toggle completion (calls PUT /api/todos/:id). Add a delete button per item (calls DELETE /api/todos/:id). Refresh the list after each action. Style completed todos with line-through.",
      "status": "pending",
      "assigned_to": null,
      "depends_on": ["F-003"],
      "priority": 4,
      "passes": false,
      "attempts": 0,
      "max_attempts": 3,
      "created_at": "2026-02-19",
      "completed_at": null,
      "notes": ""
    },
    {
      "id": "F-005",
      "category": "qa",
      "title": "End-to-end validation",
      "description": "Verify all CRUD operations work via curl commands: 1) GET /health returns 200, 2) POST /api/todos creates a todo, 3) GET /api/todos returns the created todo, 4) PUT /api/todos/:id toggles completion, 5) DELETE /api/todos/:id removes it, 6) GET /api/todos returns empty array.",
      "status": "pending",
      "assigned_to": null,
      "depends_on": ["F-004"],
      "priority": 5,
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

**Step 2: Commit**

```bash
git add examples/todo-app/feature_list.json
git commit -m "feat: add todo-app example with 5 pre-filled features"
```

---

### Task 13: Example demo — README

**Files:**

- Create: `examples/todo-app/README.md`

**Step 1: Write example README**

Short instructions: copy feature_list.json to root, run `./scripts/run.sh`, what to expect. ~30 lines.

**Step 2: Commit**

```bash
git add examples/todo-app/README.md
git commit -m "docs: add todo-app example readme"
```

---

### Task 14: Project README

**Files:**

- Create: `README.md`

**Step 1: Write README.md**

Sections:

1. **What is this** — one-paragraph overview
2. **Prerequisites** — Claude Code CLI installed
3. **Quick Start** — fork → fill features → run
4. **How It Works** — state machine diagram, agent roles
5. **Configuration** — team.json, custom agents
6. **Example** — link to examples/todo-app
7. **Feature List Schema** — field reference table

~100-150 lines.

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add project README"
```

---

### Task 15: Final verification

**Step 1: Run init.sh against the example**

```bash
cp examples/todo-app/feature_list.json feature_list.json
source scripts/init.sh
```

Expected: "Environment OK (5 features loaded)"

**Step 2: Restore template feature_list.json**

```bash
git checkout feature_list.json
```

**Step 3: Verify all files present**

```bash
ls -la CLAUDE.md feature_list.json progress.log team.json
ls -la .claude/agents/
ls -la .claude/settings.local.json
ls -la scripts/
ls -la examples/todo-app/
```

**Step 4: Final commit if any cleanup needed**

```bash
git status
# If clean, done. If not, commit remaining changes.
```
