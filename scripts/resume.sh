#!/bin/bash
set -e

TOOL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$1"

if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: $0 <project-name>"
    echo "Resets orphaned in_progress/testing tasks and re-runs."
    exit 1
fi

PROJECT_DIR="$TOOL_DIR/projects/$PROJECT_NAME"
FEATURE_LIST="$PROJECT_DIR/feature_list.json"

if [ ! -f "$FEATURE_LIST" ]; then
    echo "ERROR: Feature list not found: $FEATURE_LIST"
    exit 1
fi

# Count orphaned tasks
ORPHANED=$(jq '[.features[] | select(.status == "in_progress" or .status == "testing" or .status == "merging")] | length' "$FEATURE_LIST")

if [ "$ORPHANED" = "0" ]; then
    echo "No orphaned tasks found. Running normally..."
else
    echo "Found $ORPHANED orphaned task(s). Resetting to pending..."

    # Reset orphaned tasks: status → pending, clear assigned_to
    jq '(.features[] | select(.status == "in_progress" or .status == "testing" or .status == "merging")) |=
      (.status = "pending" | .assigned_to = null)' "$FEATURE_LIST" > "${FEATURE_LIST}.tmp" \
      && mv "${FEATURE_LIST}.tmp" "$FEATURE_LIST"

    echo "Reset complete."
fi

# Log resume event
PROGRESS_LOG="$PROJECT_DIR/progress.log"
echo "{\"ts\":\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\",\"event\":\"resumed\",\"orphaned_reset\":$ORPHANED}" >> "$PROGRESS_LOG"

# Clean orphaned git worktrees
CONFIG="$PROJECT_DIR/config.json"
TARGET=$(jq -r '.target' "$CONFIG")
echo "Checking for orphaned worktrees..."
git -C "$TARGET" worktree prune 2>/dev/null || true
git -C "$TARGET" worktree list --porcelain 2>/dev/null | grep "^worktree /tmp/auto-dev-${PROJECT_NAME}-" | \
    sed 's/^worktree //' | while read WT; do
    echo "  Removing orphaned worktree: $WT"
    git -C "$TARGET" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
done

# Run normally
exec "$TOOL_DIR/scripts/run.sh" "$PROJECT_NAME"
