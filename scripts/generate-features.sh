#!/bin/bash
set -e

TOOL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$1"
shift || true

# --- Parse flags ---
REQ_FILE=""
REQ_PROMPT=""
APPLY=false
OVERWRITE=false
FORCE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --file)
            REQ_FILE="$2"
            shift 2
            ;;
        --prompt)
            REQ_PROMPT="$2"
            shift 2
            ;;
        --apply)
            APPLY=true
            shift
            ;;
        --overwrite)
            OVERWRITE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "ERROR: Unknown flag: $1"
            echo "Usage: $0 <project-name> --file <path> | --prompt <text> [--apply] [--overwrite] [--force]"
            exit 1
            ;;
    esac
done

# --- Validate inputs ---
if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: $0 <project-name> --file <path> | --prompt <text> [--apply] [--overwrite] [--force]"
    exit 1
fi

PROJECT_DIR="$TOOL_DIR/projects/$PROJECT_NAME"
if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: Project '$PROJECT_NAME' not found in projects/"
    echo "Run: ./scripts/init-project.sh $PROJECT_NAME /path/to/project"
    exit 1
fi

if [ -z "$REQ_FILE" ] && [ -z "$REQ_PROMPT" ]; then
    echo "ERROR: Provide requirements via --file <path> or --prompt <text>"
    exit 1
fi

# Read requirements
if [ -n "$REQ_FILE" ]; then
    if [ ! -f "$REQ_FILE" ]; then
        echo "ERROR: Requirements file not found: $REQ_FILE"
        exit 1
    fi
    REQUIREMENTS=$(cat "$REQ_FILE")
else
    REQUIREMENTS="$REQ_PROMPT"
fi

# --- Read project config ---
CONFIG="$PROJECT_DIR/config.json"
TARGET=$(jq -r '.target' "$CONFIG")
FEATURE_LIST="$PROJECT_DIR/feature_list.json"

# --- Detect tech stack from target ---
TECH_STACK=""
[ -f "$TARGET/package.json" ] && TECH_STACK="${TECH_STACK}nodejs, " || true
{ [ -f "$TARGET/requirements.txt" ] || [ -f "$TARGET/pyproject.toml" ] || [ -f "$TARGET/setup.py" ]; } && TECH_STACK="${TECH_STACK}python, " || true
[ -f "$TARGET/go.mod" ] && TECH_STACK="${TECH_STACK}golang, " || true
[ -f "$TARGET/Cargo.toml" ] && TECH_STACK="${TECH_STACK}rust, " || true
{ [ -f "$TARGET/pom.xml" ] || [ -f "$TARGET/build.gradle" ]; } && TECH_STACK="${TECH_STACK}java, " || true
[ -f "$TARGET/Gemfile" ] && TECH_STACK="${TECH_STACK}ruby, " || true
[ -f "$TARGET/composer.json" ] && TECH_STACK="${TECH_STACK}php, " || true

# Trim trailing comma+space
TECH_STACK="${TECH_STACK%, }"
if [ -z "$TECH_STACK" ]; then
    TECH_STACK="(none detected)"
fi

# --- Read existing features ---
EXISTING_IDS="(none)"
START_ID="001"
HAS_NON_PENDING=false

if [ -f "$FEATURE_LIST" ]; then
    FEATURE_COUNT=$(jq '.features | length' "$FEATURE_LIST")
    if [ "$FEATURE_COUNT" -gt 0 ]; then
        EXISTING_IDS=$(jq -r '[.features[].id] | join(", ")' "$FEATURE_LIST")
        MAX_NUM=$(jq -r '[.features[].id | ltrimstr("F-") | tonumber] | max' "$FEATURE_LIST")
        START_ID=$(printf "%03d" $((MAX_NUM + 1)))
        NON_PENDING_COUNT=$(jq '[.features[] | select(.status != "pending")] | length' "$FEATURE_LIST")
        if [ "$NON_PENDING_COUNT" -gt 0 ]; then
            HAS_NON_PENDING=true
        fi
    fi
fi

# --- Build prompt ---
TEMPLATE="$TOOL_DIR/scripts/templates/generate-features.md"
if [ ! -f "$TEMPLATE" ]; then
    echo "ERROR: Prompt template not found: $TEMPLATE"
    exit 1
fi

PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/generate-features-prompt.XXXXXX")
cleanup() {
    rm -f "$PROMPT_FILE" "$REQ_TMP"
}
trap cleanup EXIT

cp "$TEMPLATE" "$PROMPT_FILE"

# Substitute single-line placeholders
sed -i.bak "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" "$PROMPT_FILE"
sed -i.bak "s|{{TECH_STACK}}|${TECH_STACK}|g" "$PROMPT_FILE"
sed -i.bak "s|{{START_ID}}|${START_ID}|g" "$PROMPT_FILE"
sed -i.bak "s|{{EXISTING_FEATURES}}|${EXISTING_IDS}|g" "$PROMPT_FILE"
rm -f "${PROMPT_FILE}.bak"

# Substitute multiline {{REQUIREMENTS}}
REQ_TMP=$(mktemp "${TMPDIR:-/tmp}/generate-features-req.XXXXXX")
printf '%s' "$REQUIREMENTS" > "$REQ_TMP"
awk -v reqfile="$REQ_TMP" '{
    if (index($0, "{{REQUIREMENTS}}") > 0) {
        while ((getline line < reqfile) > 0) print line
        close(reqfile)
    } else {
        print
    }
}' "$PROMPT_FILE" > "${PROMPT_FILE}.new"
mv "${PROMPT_FILE}.new" "$PROMPT_FILE"

echo ""
echo "Generating features for '$PROJECT_NAME'..."
echo "  Tech stack: $TECH_STACK"
echo "  Start ID:   F-$START_ID"
echo ""

# --- Call Claude ---
RAW_OUTPUT=$(claude -p - < "$PROMPT_FILE")

# --- Post-process output ---
CLEANED=$(echo "$RAW_OUTPUT" | sed '/^```.*$/d')
CLEANED=$(echo "$CLEANED" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Validate JSON
if ! echo "$CLEANED" | jq empty 2>/dev/null; then
    RAW_FILE="$PROJECT_DIR/generate-features.raw"
    echo "$RAW_OUTPUT" > "$RAW_FILE"
    echo "ERROR: Generated output is not valid JSON. Raw output saved to: $RAW_FILE"
    echo "To retry: re-run the same command"
    exit 1
fi

# Validate required fields
VALIDATION=$(echo "$CLEANED" | jq '
  [.[] | select(
    (has("id") and has("category") and has("title") and has("description") and has("depends_on") and has("priority")) | not
  )] | length
')
if [ "$VALIDATION" -gt 0 ]; then
    RAW_FILE="$PROJECT_DIR/generate-features.raw"
    echo "$RAW_OUTPUT" > "$RAW_FILE"
    echo "ERROR: Generated features missing required fields. Raw output saved to: $RAW_FILE"
    echo "To retry: re-run the same command"
    exit 1
fi

GENERATED_COUNT=$(echo "$CLEANED" | jq 'length')

# --- Preview mode (no --apply) ---
if [ "$APPLY" = false ]; then
    echo "Generated $GENERATED_COUNT features:"
    echo ""
    printf "  %-8s %-12s %-30s %s\n" "ID" "Category" "Title" "Depends On"
    echo "$CLEANED" | jq -r '.[] | "\(.id)|\(.category)|\(.title)|\(if (.depends_on | length) == 0 then "(none)" else (.depends_on | join(", ")) end)"' | while IFS='|' read -r fid fcat ftitle fdeps; do
        printf "  %-8s %-12s %-30s %s\n" "$fid" "$fcat" "$ftitle" "$fdeps"
    done
    echo ""
    echo "To apply: re-run with --apply"
    exit 0
fi

# --- Apply mode ---
TODAY=$(date '+%Y-%m-%d')

FULL_FEATURES=$(echo "$CLEANED" | jq --arg today "$TODAY" '
  [.[] | {
    id: .id,
    category: .category,
    title: .title,
    description: .description,
    status: "pending",
    assigned_to: null,
    depends_on: .depends_on,
    priority: .priority,
    attempts: 0,
    max_attempts: 3,
    branch: null,
    created_at: $today,
    started_at: null,
    completed_at: null,
    error_log: [],
    notes: ""
  }]
')

if [ "$OVERWRITE" = true ]; then
    if [ "$HAS_NON_PENDING" = true ] && [ "$FORCE" = false ]; then
        echo "ERROR: feature_list.json contains non-pending features."
        echo "Use --force to overwrite anyway."
        exit 1
    fi
    TMP_OUT=$(mktemp "${TMPDIR:-/tmp}/generate-features-out.XXXXXX")
    jq --argjson feats "$FULL_FEATURES" '.features = $feats' "$FEATURE_LIST" > "$TMP_OUT"
    mv "$TMP_OUT" "$FEATURE_LIST"
else
    TMP_OUT=$(mktemp "${TMPDIR:-/tmp}/generate-features-out.XXXXXX")
    jq --argjson feats "$FULL_FEATURES" '.features += $feats' "$FEATURE_LIST" > "$TMP_OUT"
    mv "$TMP_OUT" "$FEATURE_LIST"
fi

echo "Applied $GENERATED_COUNT features to projects/$PROJECT_NAME/feature_list.json"
