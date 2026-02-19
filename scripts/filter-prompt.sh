#!/bin/bash
# filter-prompt.sh — Filter agent prompt by engine marker blocks
#
# Usage: ./scripts/filter-prompt.sh <prompt-file> <engine>
#
# Keeps all unmarked content (shared across engines).
# Keeps content inside <!-- engine:<engine> --> blocks.
# Removes content inside <!-- engine:<other> --> blocks.

set -e

PROMPT_FILE="$1"
ENGINE="$2"

if [ -z "$PROMPT_FILE" ] || [ -z "$ENGINE" ]; then
    echo "Usage: $0 <prompt-file> <engine>" >&2
    exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
    echo "ERROR: Prompt file not found: $PROMPT_FILE" >&2
    exit 1
fi

# State machine: track whether we're inside a matching or non-matching block
awk -v engine="$ENGINE" '
BEGIN { skip = 0 }
/^<!-- engine:[a-z]+ -->$/ {
    block_engine = $0
    gsub(/<!-- engine:/, "", block_engine)
    gsub(/ -->/, "", block_engine)
    if (block_engine != engine) {
        skip = 1
    }
    next
}
/^<!-- \/engine:[a-z]+ -->$/ {
    skip = 0
    next
}
{ if (!skip) print }
' "$PROMPT_FILE"
