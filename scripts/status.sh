#!/bin/bash
set -e

TOOL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$1"

if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: $0 <project-name>"
    exit 1
fi

PROJECT_DIR="$TOOL_DIR/projects/$PROJECT_NAME"
FEATURE_LIST="$PROJECT_DIR/feature_list.json"

if [ ! -f "$FEATURE_LIST" ]; then
    echo "ERROR: Project '$PROJECT_NAME' not found or has no feature list."
    exit 1
fi

CONFIG="$PROJECT_DIR/config.json"
TARGET=$(jq -r '.target' "$CONFIG")

echo ""
echo "Project: $PROJECT_NAME"
echo "Target:  $TARGET"
echo ""

# Count by status
TOTAL=$(jq '.features | length' "$FEATURE_LIST")
COMPLETED=$(jq '[.features[] | select(.status == "completed")] | length' "$FEATURE_LIST")
IN_PROGRESS=$(jq '[.features[] | select(.status == "in_progress")] | length' "$FEATURE_LIST")
TESTING=$(jq '[.features[] | select(.status == "testing")] | length' "$FEATURE_LIST")
PENDING=$(jq '[.features[] | select(.status == "pending")] | length' "$FEATURE_LIST")
FAILED=$(jq '[.features[] | select(.status == "failed")] | length' "$FEATURE_LIST")
BLOCKED=$(jq '[.features[] | select(.status == "blocked")] | length' "$FEATURE_LIST")

echo "Progress: $COMPLETED/$TOTAL completed"
echo ""

# Status bar
if [ "$TOTAL" -gt 0 ]; then
    PCT=$((COMPLETED * 100 / TOTAL))
    BAR_LEN=30
    FILLED=$((PCT * BAR_LEN / 100))
    EMPTY=$((BAR_LEN - FILLED))
    printf "  ["
    printf '%0.s#' $(seq 1 $FILLED 2>/dev/null) || true
    printf '%0.s-' $(seq 1 $EMPTY 2>/dev/null) || true
    printf "] %d%%\n" "$PCT"
fi

echo ""

# Summary counts
[ "$COMPLETED" -gt 0 ]   && echo "  completed:   $COMPLETED"
[ "$IN_PROGRESS" -gt 0 ] && echo "  in_progress: $IN_PROGRESS"
[ "$TESTING" -gt 0 ]     && echo "  testing:     $TESTING"
[ "$PENDING" -gt 0 ]     && echo "  pending:     $PENDING"
[ "$FAILED" -gt 0 ]      && echo "  failed:      $FAILED"
[ "$BLOCKED" -gt 0 ]     && echo "  blocked:     $BLOCKED"

echo ""
echo "Features:"
echo ""

# Feature table
jq -r '.features[] | "  \(.id)  \(.status | if length < 11 then . + " " * (11 - length) else . end)  \(.title)"' "$FEATURE_LIST"

echo ""
