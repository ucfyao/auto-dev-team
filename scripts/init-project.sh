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

# Validate project name (alphanumeric, hyphens, underscores only)
if ! echo "$PROJECT_NAME" | grep -qE '^[a-zA-Z0-9_-]+$'; then
    echo "ERROR: Project name must contain only letters, numbers, hyphens, and underscores."
    exit 1
fi

# Require target directory to exist and resolve to absolute path
if [ ! -d "$TARGET_PATH" ]; then
    echo "ERROR: Target directory does not exist: $TARGET_PATH"
    echo "Create it first, then re-run this command."
    exit 1
fi
TARGET_PATH="$(cd "$TARGET_PATH" && pwd -P)"

# Verify target does not point to the auto-dev-team directory itself
TOOL_DIR_REAL=$(cd "$TOOL_DIR" && pwd -P)
if [[ "$TARGET_PATH" == "$TOOL_DIR_REAL"* ]]; then
    echo "ERROR: Target directory cannot be inside auto-dev-team directory."
    exit 1
fi

PROJECT_DIR="$TOOL_DIR/projects/$PROJECT_NAME"

if [ -d "$PROJECT_DIR" ]; then
    echo "ERROR: Project '$PROJECT_NAME' already exists at $PROJECT_DIR"
    exit 1
fi

echo "Initializing project: $PROJECT_NAME"
echo "  Target: $TARGET_PATH"

mkdir -p "$PROJECT_DIR"

# Create config.json using jq for safe JSON generation
jq -n \
  --arg target "$TARGET_PATH" \
  --arg name "$PROJECT_NAME" \
  --arg created "$(date '+%Y-%m-%d')" \
  '{target: $target, name: $name, created_at: $created, max_parallel: 3}' \
  > "$PROJECT_DIR/config.json"

# Create empty feature list using jq
jq -n \
  --arg project "$PROJECT_NAME" \
  '{project: $project, version: "3.0", features: []}' \
  > "$PROJECT_DIR/feature_list.json"

# Create progress log (JSONL format)
echo "{\"ts\":\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\",\"event\":\"initialized\",\"target\":\"$TARGET_PATH\"}" > "$PROJECT_DIR/progress.log"

echo ""
echo "Project '$PROJECT_NAME' initialized."
echo ""
echo "Next steps:"
echo "  1. Edit: projects/$PROJECT_NAME/feature_list.json"
echo "     Add your features to the 'features' array."
echo "  2. Run:  ./scripts/run.sh $PROJECT_NAME"
