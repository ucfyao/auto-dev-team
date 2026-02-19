# auto-dev-team Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a standalone tool that orchestrates a Claude Code Agent Team to autonomously develop features in any target project.

**Architecture:** Standalone repo with shell scripts that assemble protocol + features into a mega-prompt, cd into the target project, and launch Claude Code. State files live in the tool's `projects/` directory, accessed via absolute paths.

**Tech Stack:** Claude Code CLI, Bash, jq, JSON

---

### Task 1: Project scaffolding

**Files:**

- Create: `.gitignore`
- Create: `projects/.gitkeep`

**Step 1: Create .gitignore**

```gitignore
node_modules/
.env
.env.local
.DS_Store

# Keep project state directories but ignore generated logs
# (progress.log is tracked per-project)
```

**Step 2: Create projects directory placeholder**

```bash
mkdir -p projects
touch projects/.gitkeep
```

**Step 3: Commit**

```bash
git add .gitignore projects/.gitkeep
git commit -m "chore: initial project scaffolding"
```

---

### Task 2: Default team config — team.json

**Files:**

- Create: `team.json`

**Step 1: Create team.json**

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

**Step 2: Commit**

```bash
git add team.json
git commit -m "feat: add default team configuration"
```

---

### Task 3: Master protocol — protocol.md

**Files:**

- Create: `protocol.md`

**Step 1: Write protocol.md**

This is the core autonomous development protocol that gets injected into the Lead Agent's prompt by run.sh. It must contain:

1. **Role Definition** — You are the Lead Agent (CTO). You orchestrate, you do not code.
2. **State Files** — Absolute paths to feature_list.json and progress.log (injected by run.sh as `{{FEATURE_LIST_PATH}}` and `{{PROGRESS_LOG_PATH}}` placeholders).
3. **Task Dispatch Rules**:
   - Read feature_list.json
   - Filter: `status === "pending"` AND all `depends_on` IDs are `completed`
   - Sort by `priority` ascending
   - Match `category` to agent name
   - One task per agent at a time
4. **Agent Spawning** — Use `TeamCreate` to create team, then `Task` tool with `subagent_type: "general-purpose"` for each specialist. Include the specialist's prompt from `agents/*.md` content (injected by run.sh).
5. **Status Transitions**:
   - Lead assigns → `status: "in_progress"`, `assigned_to: "<agent>"`
   - Agent completes → `status: "testing"`
   - QA passes → `passes: true`, `status: "completed"`, `completed_at: "<date>"`
   - QA fails → `status: "failed"`, send error to responsible agent
   - Retry logic: `attempts += 1`, if < max_attempts reset to `pending`, else `blocked`
6. **Git Safety**:
   - Branch per feature: `git checkout -b feature/F-XXX`
   - Commit format: `feat(F-XXX): <title>`
   - On failure: `git checkout main && git branch -D feature/F-XXX`
   - Never force push or rewrite history
7. **Progress Logging** — After each task completion/failure, append a line to progress.log with timestamp, feature ID, and outcome.
8. **Completion** — When all features are `completed` or `blocked`, write a summary to progress.log and stop.

The file should be ~100-120 lines. Use `{{PLACEHOLDER}}` syntax for values that run.sh will substitute at runtime:

- `{{FEATURE_LIST_PATH}}` — absolute path to feature_list.json
- `{{PROGRESS_LOG_PATH}}` — absolute path to progress.log
- `{{TARGET_PROJECT_PATH}}` — absolute path to target project
- `{{AGENT_PROMPTS}}` — assembled agent prompt content

**Step 2: Commit**

```bash
git add protocol.md
git commit -m "feat: add master autonomous development protocol"
```

---

### Task 4: Lead Agent prompt — agents/lead.md

**Files:**

- Create: `agents/lead.md`

**Step 1: Write agents/lead.md**

This prompt wraps protocol.md with the Lead Agent's specific persona and instructions. It should be short (~30 lines) since the bulk of logic is in protocol.md which gets injected alongside it.

Key content:

- You are the CTO of this project
- Your job: read the protocol, dispatch tasks, review results, update state
- You NEVER write implementation code directly
- You use TeamCreate + Task tool to spawn specialists
- After spawning, monitor progress and update feature_list.json
- Coordinate between agents when tasks have cross-cutting concerns

**Step 2: Commit**

```bash
git add agents/lead.md
git commit -m "feat: add lead agent system prompt"
```

---

### Task 5: Backend Agent prompt — agents/backend.md

**Files:**

- Create: `agents/backend.md`

**Step 1: Write agents/backend.md**

~40-50 lines. Key behaviors:

- You are a Backend Specialist
- You receive a task with: feature ID, title, description, target project path
- Create a feature branch: `git checkout -b feature/F-XXX`
- Focus exclusively on server-side code: API routes, database, business logic, server config
- Do NOT touch client-side files (HTML, CSS, React components, etc.)
- Write clean, well-structured code following the target project's existing patterns
- Run any available test commands after implementation
- Commit with format: `feat(F-XXX): <title>`
- Report completion or errors clearly — never silently fail

**Step 2: Commit**

```bash
git add agents/backend.md
git commit -m "feat: add backend specialist agent prompt"
```

---

### Task 6: Frontend Agent prompt — agents/frontend.md

**Files:**

- Create: `agents/frontend.md`

**Step 1: Write agents/frontend.md**

~40-50 lines. Same structure as backend.md but:

- Focus on client-side: UI components, styling, state management, API consumption
- Do NOT touch server-side files (API routes, database, server config)
- Match existing UI patterns and styling conventions in the target project

**Step 2: Commit**

```bash
git add agents/frontend.md
git commit -m "feat: add frontend specialist agent prompt"
```

---

### Task 7: QA Agent prompt — agents/qa.md

**Files:**

- Create: `agents/qa.md`

**Step 1: Write agents/qa.md**

~40-50 lines. Key behaviors:

- You are a QA Engineer
- You receive tasks with `status: testing` from the Lead
- Run validation: unit tests, integration tests, curl commands, E2E tests — whatever is appropriate
- You do NOT modify source code. You only read code and run tests.
- If tests pass: report success to Lead with details
- If tests fail: send detailed error report (command, expected, actual, stack trace) to the responsible agent. Do NOT attempt to fix it yourself.
- Be specific in error reports — include file paths, line numbers, exact error messages

**Step 2: Commit**

```bash
git add agents/qa.md
git commit -m "feat: add QA engineer agent prompt"
```

---

### Task 8: Environment check script — check-env.sh

**Files:**

- Create: `scripts/check-env.sh`

**Step 1: Write scripts/check-env.sh**

```bash
#!/bin/bash
set -e

TOOL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$1"

echo "=== Auto-Dev-Team Environment Check ==="

# Check dependencies
if ! command -v claude &> /dev/null; then
    echo "ERROR: Claude Code CLI not found."
    echo "Install: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "ERROR: jq not found."
    echo "Install: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "ERROR: git not found."
    exit 1
fi

# Check project config exists
if [ -z "$PROJECT_NAME" ]; then
    echo "ERROR: No project name provided."
    echo "Usage: $0 <project-name>"
    exit 1
fi

PROJECT_DIR="$TOOL_DIR/projects/$PROJECT_NAME"
if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: Project '$PROJECT_NAME' not found in projects/"
    echo "Run: ./scripts/init-project.sh $PROJECT_NAME /path/to/project"
    exit 1
fi

# Check config.json
CONFIG="$PROJECT_DIR/config.json"
if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Missing $CONFIG"
    exit 1
fi

TARGET=$(jq -r '.target' "$CONFIG")
if [ ! -d "$TARGET" ]; then
    echo "ERROR: Target project directory not found: $TARGET"
    exit 1
fi

# Check feature_list.json
FEATURES="$PROJECT_DIR/feature_list.json"
if [ ! -f "$FEATURES" ]; then
    echo "ERROR: Missing $FEATURES"
    echo "Create it or copy from examples/todo-app/feature_list.json"
    exit 1
fi

FEATURE_COUNT=$(jq '.features | length' "$FEATURES")
if [ "$FEATURE_COUNT" = "0" ]; then
    echo "ERROR: feature_list.json has no features. Add features before running."
    exit 1
fi

# Check target is a git repo
if ! git -C "$TARGET" rev-parse --git-dir &> /dev/null; then
    echo "WARNING: Target project is not a git repo. Initializing..."
    git -C "$TARGET" init
fi

# Check target git status
if [ -n "$(git -C "$TARGET" status --porcelain)" ]; then
    echo "WARNING: Target project has uncommitted changes. Stashing..."
    git -C "$TARGET" stash
fi

echo "=== Environment OK ==="
echo "  Tool dir:    $TOOL_DIR"
echo "  Project:     $PROJECT_NAME"
echo "  Target:      $TARGET"
echo "  Features:    $FEATURE_COUNT"
```

**Step 2: Make executable**

```bash
chmod +x scripts/check-env.sh
```

**Step 3: Commit**

```bash
git add scripts/check-env.sh
git commit -m "feat: add environment check script"
```

---

### Task 9: Project init script — init-project.sh

**Files:**

- Create: `scripts/init-project.sh`

**Step 1: Write scripts/init-project.sh**

```bash
#!/bin/bash
set -e

TOOL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$1"
TARGET_PATH="$2"

if [ -z "$PROJECT_NAME" ] || [ -z "$TARGET_PATH" ]; then
    echo "Usage: $0 <project-name> <target-project-path>"
    echo ""
    echo "Example:"
    echo "  $0 my-app /Users/me/code/my-app"
    exit 1
fi

# Resolve to absolute path
TARGET_PATH="$(cd "$TARGET_PATH" 2>/dev/null && pwd || echo "$TARGET_PATH")"

PROJECT_DIR="$TOOL_DIR/projects/$PROJECT_NAME"

if [ -d "$PROJECT_DIR" ]; then
    echo "ERROR: Project '$PROJECT_NAME' already exists at $PROJECT_DIR"
    exit 1
fi

echo "Initializing project: $PROJECT_NAME"
echo "  Target: $TARGET_PATH"

mkdir -p "$PROJECT_DIR"

# Create config.json
cat > "$PROJECT_DIR/config.json" << EOF
{
  "target": "$TARGET_PATH",
  "name": "$PROJECT_NAME",
  "created_at": "$(date '+%Y-%m-%d')"
}
EOF

# Create empty feature list
cat > "$PROJECT_DIR/feature_list.json" << 'EOF'
{
  "project": "PROJECT_NAME_PLACEHOLDER",
  "version": "3.0",
  "features": []
}
EOF
sed -i '' "s/PROJECT_NAME_PLACEHOLDER/$PROJECT_NAME/" "$PROJECT_DIR/feature_list.json" 2>/dev/null || \
sed -i "s/PROJECT_NAME_PLACEHOLDER/$PROJECT_NAME/" "$PROJECT_DIR/feature_list.json"

# Create progress log
echo "# Progress Log: $PROJECT_NAME" > "$PROJECT_DIR/progress.log"
echo "# Target: $TARGET_PATH" >> "$PROJECT_DIR/progress.log"
echo "$(date '+%Y-%m-%d %H:%M:%S'): Project initialized" >> "$PROJECT_DIR/progress.log"

echo ""
echo "Project '$PROJECT_NAME' initialized."
echo ""
echo "Next steps:"
echo "  1. Edit: projects/$PROJECT_NAME/feature_list.json"
echo "     Add your features to the 'features' array."
echo "  2. Run:  ./scripts/run.sh $PROJECT_NAME"
```

**Step 2: Make executable**

```bash
chmod +x scripts/init-project.sh
```

**Step 3: Commit**

```bash
git add scripts/init-project.sh
git commit -m "feat: add project initialization script"
```

---

### Task 10: Main entry script — run.sh

**Files:**

- Create: `scripts/run.sh`

**Step 1: Write scripts/run.sh**

This is the core orchestration script. It:

1. Runs check-env.sh
2. Reads config, features, protocol, and agent prompts
3. Substitutes placeholders in protocol.md
4. Assembles a mega-prompt
5. cd into target project
6. Launches Claude Code with the mega-prompt

```bash
#!/bin/bash
set -e

TOOL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$1"

# Environment check
source "$TOOL_DIR/scripts/check-env.sh" "$PROJECT_NAME"

# Read paths
PROJECT_DIR="$TOOL_DIR/projects/$PROJECT_NAME"
CONFIG="$PROJECT_DIR/config.json"
TARGET=$(jq -r '.target' "$CONFIG")
FEATURE_LIST="$PROJECT_DIR/feature_list.json"
PROGRESS_LOG="$PROJECT_DIR/progress.log"

# Read protocol and agent prompts
PROTOCOL=$(cat "$TOOL_DIR/protocol.md")
LEAD_PROMPT=$(cat "$TOOL_DIR/agents/lead.md")
BACKEND_PROMPT=$(cat "$TOOL_DIR/agents/backend.md")
FRONTEND_PROMPT=$(cat "$TOOL_DIR/agents/frontend.md")
QA_PROMPT=$(cat "$TOOL_DIR/agents/qa.md")
TEAM_CONFIG=$(cat "$TOOL_DIR/team.json")

# Read current features
FEATURES=$(cat "$FEATURE_LIST")

# Substitute placeholders in protocol
PROTOCOL="${PROTOCOL//\{\{FEATURE_LIST_PATH\}\}/$FEATURE_LIST}"
PROTOCOL="${PROTOCOL//\{\{PROGRESS_LOG_PATH\}\}/$PROGRESS_LOG}"
PROTOCOL="${PROTOCOL//\{\{TARGET_PROJECT_PATH\}\}/$TARGET}"

# Assemble mega-prompt
MEGA_PROMPT="$LEAD_PROMPT

---

## Protocol

$PROTOCOL

---

## Current Feature List

\`\`\`json
$FEATURES
\`\`\`

Feature list file (read/write): $FEATURE_LIST
Progress log file (append): $PROGRESS_LOG
Target project directory: $TARGET

---

## Team Configuration

\`\`\`json
$TEAM_CONFIG
\`\`\`

---

## Agent Prompts (use when spawning specialists)

### Backend Agent Prompt
$BACKEND_PROMPT

### Frontend Agent Prompt
$FRONTEND_PROMPT

### QA Agent Prompt
$QA_PROMPT

---

Begin execution now. Follow the protocol exactly."

# Log session start
echo "$(date '+%Y-%m-%d %H:%M:%S'): Session started" >> "$PROGRESS_LOG"

echo ""
echo "Starting Auto-Dev-Team v3.0..."
echo "  Project: $PROJECT_NAME"
echo "  Target:  $TARGET"
echo ""

# Launch Claude Code in target project directory
cd "$TARGET"
claude --dangerously-skip-permissions -p "$MEGA_PROMPT"
```

**Step 2: Make executable**

```bash
chmod +x scripts/run.sh
```

**Step 3: Commit**

```bash
git add scripts/run.sh
git commit -m "feat: add main entry run script"
```

---

### Task 11: Example — TODO app feature list

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
      "description": "Create a basic Express.js server with GET /health endpoint on port 3000. Run npm init -y and install express. Create src/index.js as entry point.",
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
      "description": "Create public/index.html with a form (text input + submit button) to add todos and an unordered list to display them. Use vanilla JS fetch to call GET /api/todos on load and POST /api/todos on submit. Configure Express to serve static files from public/.",
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
      "description": "Add a checkbox per todo item to toggle completion (calls PUT /api/todos/:id). Add a delete button per item (calls DELETE /api/todos/:id). Refresh the list after each action. Style completed todos with line-through text decoration.",
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
      "description": "Start the server, then verify all CRUD operations via curl: 1) GET /health returns 200, 2) POST /api/todos creates a todo, 3) GET /api/todos returns the created todo, 4) PUT /api/todos/:id toggles completion, 5) DELETE /api/todos/:id removes it, 6) GET /api/todos returns empty array. Stop the server after tests.",
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

### Task 12: Example — TODO app README

**Files:**

- Create: `examples/todo-app/README.md`

**Step 1: Write example README**

Content (~30 lines):

- What this example builds (a simple Express + vanilla JS TODO app)
- How to run it:
  1. `mkdir -p /tmp/todo-demo && cd /tmp/todo-demo && git init`
  2. `cd /path/to/auto-dev-team`
  3. `./scripts/init-project.sh todo-demo /tmp/todo-demo`
  4. `cp examples/todo-app/feature_list.json projects/todo-demo/feature_list.json`
  5. `./scripts/run.sh todo-demo`
- What to expect (5 features built sequentially, QA validation at the end)

**Step 2: Commit**

```bash
git add examples/todo-app/README.md
git commit -m "docs: add todo-app example instructions"
```

---

### Task 13: Project README

**Files:**

- Create: `README.md`

**Step 1: Write README.md**

Sections (~120 lines):

1. **auto-dev-team** — one-line tagline + one-paragraph description
2. **How It Works** — diagram: run.sh → assemble prompt → Claude Code → Agent Team → target project
3. **Prerequisites** — Claude Code CLI, jq, git
4. **Quick Start** — 4 commands to get running
5. **Registering a Project** — init-project.sh usage
6. **Writing Features** — feature_list.json schema with field reference table
7. **Agent Roles** — Lead, Backend, Frontend, QA descriptions
8. **Custom Agents** — how to add to team.json + create prompt file
9. **Examples** — link to examples/todo-app/
10. **Configuration** — team.json reference

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add project README"
```

---

### Task 14: Final verification

**Step 1: Verify all files present**

```bash
ls -la agents/
ls -la scripts/
ls -la examples/todo-app/
cat team.json | jq .
cat protocol.md | head -5
```

**Step 2: Test init-project.sh**

```bash
mkdir -p /tmp/auto-dev-test && git -C /tmp/auto-dev-test init
./scripts/init-project.sh test-project /tmp/auto-dev-test
ls -la projects/test-project/
cat projects/test-project/config.json | jq .
```

**Step 3: Test check-env.sh with example features**

```bash
cp examples/todo-app/feature_list.json projects/test-project/feature_list.json
./scripts/check-env.sh test-project
```

Expected output: "Environment OK" with 5 features loaded.

**Step 4: Clean up test project**

```bash
rm -rf projects/test-project /tmp/auto-dev-test
```

**Step 5: Final commit if any cleanup needed**

```bash
git status
```
