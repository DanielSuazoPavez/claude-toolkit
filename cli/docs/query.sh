#!/usr/bin/env bash
#
# Emit workshop-side agent-facing contract docs to stdout.
#
# Usage:
#     query.sh                      # List available contracts
#     query.sh <contract-name>      # Emit one contract to stdout
#     query.sh -h | --help          # Show usage
#
# Wire contract (see .claude/docs/relevant-toolkit-satellite-contracts.md):
#   stdout / markdown / exit 0 on success / read-only / UTF-8
#   unknown contract: exit 1, print available names to stderr

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCS_DIR="$PROJECT_ROOT/.claude/docs"

# name|file|description (one per line)
CONTRACTS=$(cat <<'EOF'
satellite-contracts|relevant-toolkit-satellite-contracts.md|Convention for satellite CLIs paired with workshop skills — how to expose agent-facing contracts via `<satellite> docs <name>`
backlog-schema|relevant-workflow-backlog.md|Backlog metadata vocabulary — fields, status values, relationship kinds
EOF
)

usage() {
    cat <<'EOF'
claude-toolkit docs - Emit workshop agent-facing contracts

USAGE:
    claude-toolkit docs                 List available contracts
    claude-toolkit docs <contract>      Emit one contract to stdout

ARGUMENTS:
    <contract>    Contract name (see list from bare `claude-toolkit docs`)

EXAMPLES:
    claude-toolkit docs
    claude-toolkit docs satellite-contracts
EOF
}

list_names() {
    while IFS='|' read -r name _file _desc; do
        [[ -z "$name" ]] && continue
        echo "$name"
    done <<< "$CONTRACTS"
}

list_contracts() {
    while IFS='|' read -r name _file desc; do
        [[ -z "$name" ]] && continue
        printf '%-22s %s\n' "$name" "$desc"
    done <<< "$CONTRACTS"
}

find_file() {
    local query="$1"
    while IFS='|' read -r name file _desc; do
        [[ -z "$name" ]] && continue
        if [[ "$name" == "$query" ]]; then
            echo "$file"
            return 0
        fi
    done <<< "$CONTRACTS"
    return 1
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    "")
        list_contracts
        exit 0
        ;;
    *)
        name="$1"
        if ! file=$(find_file "$name"); then
            {
                echo "Error: unknown contract '$name'"
                echo "Available contracts:"
                list_names | sed 's/^/  /'
            } >&2
            exit 1
        fi
        path="$DOCS_DIR/$file"
        if [[ ! -f "$path" ]]; then
            echo "Error: contract file missing: $path" >&2
            exit 1
        fi
        cat "$path"
        ;;
esac
