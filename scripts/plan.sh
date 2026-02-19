#!/bin/bash
set -e

TOOL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$1"
REQUIREMENT="$2"
AUTO_RUN=false

# Parse flags
for arg in "$@"; do
    case "$arg" in
        --run) AUTO_RUN=true ;;
    esac
done

if [ -z "$PROJECT_NAME" ] || [ -z "$REQUIREMENT" ]; then
    echo "Usage: $0 <project-name> \"<requirement>\" [--run]"
    echo ""
    echo "Examples:"
    echo "  $0 my-app \"Build a todo app with Express backend and vanilla JS frontend\""
    echo "  $0 my-app \"Add user authentication with JWT\" --run"
    echo ""
    echo "Options:"
    echo "  --run    Automatically start execution after planning"
    exit 1
fi

# Check project exists
PROJECT_DIR="$TOOL_DIR/projects/$PROJECT_NAME"
if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: Project '$PROJECT_NAME' not found."
    echo "Register it first: auto-dev init $PROJECT_NAME /path/to/project"
    exit 1
fi

CONFIG="$PROJECT_DIR/config.json"
TARGET=$(jq -r '.target' "$CONFIG")
FEATURE_LIST="$PROJECT_DIR/feature_list.json"

# Check if feature list already has features
EXISTING_COUNT=$(jq '.features | length' "$FEATURE_LIST")
if [ "$EXISTING_COUNT" != "0" ]; then
    echo "WARNING: feature_list.json already has $EXISTING_COUNT feature(s)."
    echo ""
    read -p "Overwrite? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""
echo "Planning features for: $PROJECT_NAME"
echo "  Target:      $TARGET"
echo "  Requirement: $REQUIREMENT"
echo ""

# Build planner prompt
PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/auto-dev-plan-prompt.XXXXXX")

cat > "$PROMPT_FILE" << PLAN_PROMPT
You are a project planner for auto-dev-team. Your job is to decompose a high-level requirement into a structured feature list.

## Target Project

- Path: $TARGET
- Name: $PROJECT_NAME

## Requirement

$REQUIREMENT

## Your Job

1. First, explore the target project directory to understand what already exists (files, package.json, tech stack, etc.)
2. Decompose the requirement into 3-8 concrete, implementable features
3. Each feature should be small enough for one agent to complete in a single session
4. Assign appropriate categories: "backend", "frontend", or other specialist categories
5. Set dependencies correctly — features that need other features to be done first
6. Set priorities (lower number = higher priority, typically matching dependency order)
7. Write clear, detailed descriptions — the implementing agent needs to know exactly what to build

## Output

Write the feature list to: $FEATURE_LIST

The file must be valid JSON with this exact structure:

\`\`\`json
{
  "project": "$PROJECT_NAME",
  "version": "3.1",
  "features": [
    {
      "id": "F-001",
      "category": "backend",
      "title": "Short title",
      "description": "Detailed implementation instructions. Be specific about files, endpoints, data structures, behavior.",
      "status": "pending",
      "assigned_to": null,
      "depends_on": [],
      "priority": 1,
      "attempts": 0,
      "max_attempts": 3,
      "branch": null,
      "created_at": "$(date '+%Y-%m-%d')",
      "started_at": null,
      "completed_at": null,
      "error_log": [],
      "notes": ""
    }
  ]
}
\`\`\`

## Rules

- IDs must be sequential: F-001, F-002, F-003, ...
- Backend features first, then frontend (frontend usually depends on backend APIs)
- Each description must be detailed enough that an AI agent can implement it without asking questions
- Include specific file paths, function signatures, data structures, and expected behavior
- Do NOT over-scope. 3-8 features is the sweet spot. YAGNI.
- After writing the file, validate it with: jq . $FEATURE_LIST
- Then print a summary table of all features (ID, category, title, depends_on)
PLAN_PROMPT

# Cleanup on exit
cleanup() {
    rm -f "$PROMPT_FILE"
}
trap cleanup EXIT

echo "Launching planner..."
echo ""

# Launch Claude Code for planning
cd "$TARGET"
cat "$PROMPT_FILE" | claude --dangerously-skip-permissions -p -

# Validate output
if [ ! -f "$FEATURE_LIST" ]; then
    echo ""
    echo "ERROR: Planner did not create feature_list.json"
    exit 1
fi

FEATURE_COUNT=$(jq '.features | length' "$FEATURE_LIST" 2>/dev/null || echo "0")
if [ "$FEATURE_COUNT" = "0" ]; then
    echo ""
    echo "ERROR: feature_list.json has no features"
    exit 1
fi

echo ""
echo "Planning complete: $FEATURE_COUNT features generated"
echo ""
jq -r '.features[] | "  \(.id) [\(.category)] \(.title) (depends: \(.depends_on | join(", ") // "none"))"' "$FEATURE_LIST"
echo ""

if [ "$AUTO_RUN" = true ]; then
    echo "Starting execution (--run flag)..."
    echo ""
    exec "$TOOL_DIR/scripts/run.sh" "$PROJECT_NAME"
else
    echo "Review the features: projects/$PROJECT_NAME/feature_list.json"
    echo "Then run: auto-dev run $PROJECT_NAME"
fi
