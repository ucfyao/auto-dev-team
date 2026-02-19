#!/bin/bash
set -e

TOOL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$1"

if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: $0 <project-name>"
    exit 1
fi

# Environment check — run as subprocess (NOT source)
"$TOOL_DIR/scripts/check-env.sh" "$PROJECT_NAME"
if [ $? -ne 0 ]; then
    exit 1
fi

# Read paths
PROJECT_DIR="$TOOL_DIR/projects/$PROJECT_NAME"
CONFIG="$PROJECT_DIR/config.json"
TARGET=$(jq -r '.target' "$CONFIG")
FEATURE_LIST="$PROJECT_DIR/feature_list.json"
PROGRESS_LOG="$PROJECT_DIR/progress.log"

# Lockfile — prevent concurrent runs on same project
LOCKFILE="$PROJECT_DIR/.lock"
if [ -f "$LOCKFILE" ]; then
    LOCK_PID=$(cat "$LOCKFILE")
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "ERROR: Another run.sh is already running for '$PROJECT_NAME' (PID: $LOCK_PID)"
        exit 1
    else
        echo "WARNING: Stale lockfile found (PID $LOCK_PID not running). Removing."
        rm -f "$LOCKFILE"
    fi
fi
echo $$ > "$LOCKFILE"

# Cleanup on exit
cleanup() {
    rm -f "$LOCKFILE"
    rm -f "$PROMPT_FILE"
}
trap cleanup EXIT

# Read protocol and agent prompts
PROTOCOL=$(cat "$TOOL_DIR/protocol.md")
LEAD_PROMPT=$(cat "$TOOL_DIR/agents/lead.md")
BACKEND_PROMPT=$(cat "$TOOL_DIR/agents/backend.md")
FRONTEND_PROMPT=$(cat "$TOOL_DIR/agents/frontend.md")
QA_PROMPT=$(cat "$TOOL_DIR/agents/qa.md")
TEAM_CONFIG=$(cat "$TOOL_DIR/team.json")

# Read engine definitions for prompt injection
ENGINES=$(jq -r '.engines | to_entries[] | "- \(.key): \(.value.command) — \(.value.description)"' "$TOOL_DIR/team.json")

FEATURES=$(cat "$FEATURE_LIST")

# Write mega-prompt to temp file (avoids shell escaping + ARG_MAX issues)
PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/auto-dev-prompt.XXXXXX")

cat > "$PROMPT_FILE" << 'PROMPT_HEADER'
PROMPT_HEADER

# Write lead prompt
echo "$LEAD_PROMPT" >> "$PROMPT_FILE"

cat >> "$PROMPT_FILE" << 'SECTION_BREAK'

---

## Protocol

SECTION_BREAK

# Substitute placeholders in protocol using sed on the temp file
echo "$PROTOCOL" >> "$PROMPT_FILE"
sed -i.bak "s|{{FEATURE_LIST_PATH}}|${FEATURE_LIST}|g" "$PROMPT_FILE"
sed -i.bak "s|{{PROGRESS_LOG_PATH}}|${PROGRESS_LOG}|g" "$PROMPT_FILE"
sed -i.bak "s|{{TARGET_PROJECT_PATH}}|${TARGET}|g" "$PROMPT_FILE"
rm -f "${PROMPT_FILE}.bak"

cat >> "$PROMPT_FILE" << FEATURES_SECTION

---

## Current Feature List

\`\`\`json
$(cat "$FEATURE_LIST")
\`\`\`

Feature list file (read/write — ONLY Lead Agent): $FEATURE_LIST
Progress log file (append — ONLY Lead Agent): $PROGRESS_LOG
Target project directory: $TARGET

---

## Team Configuration

\`\`\`json
$(cat "$TOOL_DIR/team.json")
\`\`\`

---

## Agent Prompts (pass to sub-agents when spawning via Task tool)

### Backend Agent Prompt (Claude version — filter for other engines at dispatch time)
$(cat "$TOOL_DIR/agents/backend.md")

### Frontend Agent Prompt (Claude version — filter for other engines at dispatch time)
$(cat "$TOOL_DIR/agents/frontend.md")

### QA Agent Prompt (Claude version — filter for other engines at dispatch time)
$(cat "$TOOL_DIR/agents/qa.md")

---

## Engine Configuration

Available engines:
$ENGINES

Agent-to-engine mapping:
$(jq -r '.agents[] | "- \(.name) (\(.role)): engine=\(.engine)"' "$TOOL_DIR/team.json")

### How to dispatch to non-Claude engines

When dispatching to an agent with engine != "claude", use the Bash tool to:
1. Filter the agent prompt: \`$TOOL_DIR/scripts/filter-prompt.sh $TOOL_DIR/agents/<name>.md <engine>\`
2. Write the filtered prompt + feature details to a temp file
3. Call the engine CLI command (see engines above) with the temp file
4. Check results per protocol §5b

Feature-level override: if a feature has an \`engine\` field, use that instead of the agent's default.

---

Begin execution now. Follow the protocol exactly.
FEATURES_SECTION

# Log session start
echo "{\"ts\":\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\",\"event\":\"session_started\"}" >> "$PROGRESS_LOG"

echo ""
echo "Starting Auto-Dev-Team v3.0..."
echo "  Project: $PROJECT_NAME"
echo "  Target:  $TARGET"
echo "  Prompt:  $PROMPT_FILE ($(wc -c < "$PROMPT_FILE" | tr -d ' ') bytes)"
echo ""

# Launch Claude Code — pipe prompt via stdin to avoid shell escaping issues
cd "$TARGET"
cat "$PROMPT_FILE" | claude --dangerously-skip-permissions -p -
