#!/bin/bash
# Analyze Claude Code transcripts for skill and agent usage
#
# Usage:
#   ./scripts/analyze-usage.sh                    # Analyze current project transcripts
#   ./scripts/analyze-usage.sh /path/to/file.jsonl  # Analyze specific file
#   ./scripts/analyze-usage.sh --all              # Analyze all projects
#
# Output format:
#   TIMESTAMP TYPE NAME [DETAILS]
#
# Examples:
#   2026-01-25T10:30:00 skill hook-judge invoked_by=user
#   2026-01-25T10:31:00 skill hook-judge invoked_by=agent
#   2026-01-25T10:32:00 agent Explore description="Find error handlers"

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get Claude projects directory
CLAUDE_PROJECTS_DIR="${HOME}/.claude/projects"

usage() {
    echo "Usage: $0 [OPTIONS] [FILE]"
    echo ""
    echo "Options:"
    echo "  --all             Analyze all projects"
    echo "  --since DATE      Only show entries after DATE (YYYY-MM-DD)"
    echo "  --summary         Show summary counts only"
    echo "  --skills          Show only skill usage"
    echo "  --agents          Show only agent usage"
    echo "  --json            Output as JSON"
    echo "  -h, --help        Show this help"
    echo ""
    echo "If no file specified, analyzes current project's transcripts."
}

# Parse arguments
SHOW_SUMMARY=false
SHOW_SKILLS=true
SHOW_AGENTS=true
OUTPUT_JSON=false
TARGET_FILE=""
ANALYZE_ALL=false
SINCE_DATE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            ANALYZE_ALL=true
            shift
            ;;
        --since)
            SINCE_DATE="$2"
            shift 2
            ;;
        --summary)
            SHOW_SUMMARY=true
            shift
            ;;
        --skills)
            SHOW_SKILLS=true
            SHOW_AGENTS=false
            shift
            ;;
        --agents)
            SHOW_AGENTS=true
            SHOW_SKILLS=false
            shift
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            TARGET_FILE="$1"
            shift
            ;;
    esac
done

# Find transcript files to analyze
find_transcripts() {
    local find_opts=""

    # If --since is specified, only look at files modified after that date
    if [[ -n "$SINCE_DATE" ]]; then
        find_opts="-newermt $SINCE_DATE"
    fi

    if [[ -n "$TARGET_FILE" ]]; then
        echo "$TARGET_FILE"
    elif [[ "$ANALYZE_ALL" == true ]]; then
        find "$CLAUDE_PROJECTS_DIR" -name "*.jsonl" -type f $find_opts 2>/dev/null
    else
        # Current project - find by CWD (path encoded with leading dash)
        local cwd_encoded=$(pwd | sed 's|/|-|g')
        local project_dir="$CLAUDE_PROJECTS_DIR/$cwd_encoded"
        if [[ -d "$project_dir" ]]; then
            find "$project_dir" -name "*.jsonl" -type f $find_opts 2>/dev/null
        else
            echo "No transcripts found for current project: $project_dir" >&2
            exit 1
        fi
    fi
}

# Extract skill invocations from user messages
# User-invoked skills appear as <command-name>/skill-name</command-name>
extract_user_skills() {
    local file="$1"
    jq -r '
        select(.type == "user") |
        select(.message.content | type == "string") |
        select(.message.content | test("<command-name>/[a-z][a-z0-9-]*</command-name>")) |
        {
            timestamp: .timestamp,
            skill: (.message.content | capture("<command-name>/(?<name>[a-z][a-z0-9-]*)</command-name>") | .name),
            invoked_by: "user"
        } |
        "\(.timestamp) skill \(.skill) invoked_by=\(.invoked_by)"
    ' "$file" 2>/dev/null
}

# Extract skill invocations from Skill tool calls (agent-invoked)
extract_agent_skills() {
    local file="$1"
    jq -r '
        select(.type == "assistant") |
        .timestamp as $ts |
        .message.content[]? |
        select(.type == "tool_use" and .name == "Skill") |
        "\($ts) skill \(.input.skill) invoked_by=agent"
    ' "$file" 2>/dev/null
}

# Extract agent invocations from Task tool calls
extract_agents() {
    local file="$1"
    jq -r '
        select(.type == "assistant") |
        .timestamp as $ts |
        .message.content[]? |
        select(.type == "tool_use" and .name == "Task") |
        {
            timestamp: $ts,
            agent: (.input.subagent_type // "unknown"),
            description: (.input.description // "-")
        } |
        "\(.timestamp) agent \(.agent) description=\"\(.description)\""
    ' "$file" 2>/dev/null
}

# Main analysis
analyze_file() {
    local file="$1"

    if [[ "$SHOW_SKILLS" == true ]]; then
        extract_user_skills "$file"
        extract_agent_skills "$file"
    fi

    if [[ "$SHOW_AGENTS" == true ]]; then
        extract_agents "$file"
    fi
}

# Extract project name from file path
# e.g., /home/user/.claude/projects/-home-user-projects-personal-myproject/abc.jsonl -> myproject
get_project_name() {
    local file="$1"
    local dir=$(dirname "$file")
    local encoded=$(basename "$dir")
    # Remove common prefixes and worktree suffixes
    echo "$encoded" | sed -E 's/^-home-[^-]+-projects-(personal|raiz)-//' | sed 's/--worktrees-.*//'
}

# Collect all results
results=""
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    project=$(get_project_name "$file")
    file_results=$(analyze_file "$file")
    if [[ -n "$file_results" ]]; then
        # Prepend project name to each line
        file_results=$(echo "$file_results" | sed "s/^/[$project] /")
        results+="$file_results"$'\n'
    fi
done < <(find_transcripts)

# Remove trailing newline
results="${results%$'\n'}"

# Filter by date if --since specified
# Timestamp is now in $2 due to [project] prefix
if [[ -n "$SINCE_DATE" ]]; then
    results=$(echo "$results" | awk -v since="$SINCE_DATE" '$2 >= since')
fi

if [[ -z "$results" ]]; then
    echo "No usage data found." >&2
    exit 0
fi

if [[ "$SHOW_SUMMARY" == true ]]; then
    echo -e "${CYAN}=== Usage Summary ===${NC}"
    echo ""

    if [[ "$SHOW_SKILLS" == true ]]; then
        echo -e "${GREEN}Skills:${NC}"
        echo "$results" | grep " skill " | awk '{print $3}' | sort | uniq -c | sort -rn | head -20
        echo ""

        echo -e "${YELLOW}By invoker:${NC}"
        echo "$results" | grep " skill " | grep -o "invoked_by=[a-z]*" | sort | uniq -c
        echo ""
    fi

    if [[ "$SHOW_AGENTS" == true ]]; then
        echo -e "${GREEN}Agents:${NC}"
        echo "$results" | grep " agent " | awk '{print $3}' | sort | uniq -c | sort -rn | head -20
    fi
else
    # Sort by timestamp and deduplicate
    echo "$results" | sort -u
fi
