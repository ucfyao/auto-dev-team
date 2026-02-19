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

# Check CLI tools for all configured engines
ENGINES_JSON="$TOOL_DIR/team.json"
if [ -f "$ENGINES_JSON" ]; then
    # Extract unique engine commands used by agents
    USED_ENGINES=$(jq -r '[.agents[].engine] | unique[]' "$ENGINES_JSON")

    for eng in $USED_ENGINES; do
        CLI_CMD=$(jq -r --arg e "$eng" '.engines[$e].command' "$ENGINES_JSON" | awk '{print $1}')
        if [ -z "$CLI_CMD" ] || [ "$CLI_CMD" = "null" ]; then
            echo "WARNING: Engine '$eng' referenced by agents but not defined in team.json engines."
            continue
        fi
        if ! command -v "$CLI_CMD" &> /dev/null; then
            echo "ERROR: CLI tool '$CLI_CMD' not found (required by engine '$eng')."
            echo "Install it before running auto-dev-team."
            exit 1
        fi
        echo "  Engine '$eng': $CLI_CMD ✓"
    done
fi

# Check filter-prompt.sh
if [ ! -x "$TOOL_DIR/scripts/filter-prompt.sh" ]; then
    echo "ERROR: scripts/filter-prompt.sh not found or not executable."
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

# Validate: no circular dependencies
# Build dependency graph and check for cycles using jq + topological sort
CYCLE_CHECK=$(jq -r '
  .features as $feats |
  [.features[] | {id, deps: .depends_on}] |
  # Simple cycle detection: for each feature, follow depends_on chain
  # If we revisit a node, there is a cycle
  map(.id) as $ids |
  [.[] | select(.deps | length > 0) | .deps[] as $dep |
    select([$feats[] | select(.id == $dep) | .depends_on[] | select(. == .id)] | length > 0)
  ] | length
' "$FEATURES" 2>/dev/null || echo "0")

# Check target is a git repo
if ! git -C "$TARGET" rev-parse --git-dir &> /dev/null; then
    echo "ERROR: Target project is not a git repo."
    echo "Initialize it first: git -C $TARGET init"
    exit 1
fi

# Check target git status — require clean working tree
if [ -n "$(git -C "$TARGET" status --porcelain)" ]; then
    echo "ERROR: Target project has uncommitted changes."
    echo "Please commit or stash changes before running auto-dev-team."
    echo "  cd $TARGET && git stash   (to stash)"
    echo "  cd $TARGET && git add . && git commit -m 'wip'   (to commit)"
    exit 1
fi

echo "=== Environment OK ==="
echo "  Tool dir:    $TOOL_DIR"
echo "  Project:     $PROJECT_NAME"
echo "  Target:      $TARGET"
echo "  Features:    $FEATURE_COUNT"
