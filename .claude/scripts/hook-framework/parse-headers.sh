#!/usr/bin/env bash
# Parse a hook file's `# CC-HOOK:` header block into a single JSON object on stdout.
#
# Workshop-internal tool. Run once per hook file. Pass-through translation: no
# defaults, no validation beyond the header grammar itself. Consumers (validator,
# dispatcher codegen, JSON index) apply policy.
#
# Usage:
#   bash parse-headers.sh path/to/hook.sh
#
# Aggregation:
#   for f in .claude/hooks/*.sh; do bash parse-headers.sh "$f"; done | jq -s .
#
# Exit codes:
#   0 — success (one JSON line on stdout, OR empty stdout if the file has no
#       header block; "missing header" is a validator concern)
#   1 — malformed CC-HOOK directive or duplicate key
#   2 — usage error (missing file argument, file not readable)

set -euo pipefail

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
    echo "parse-headers.sh: missing file argument" >&2
    exit 2
fi

file="$1"

if [ ! -r "$file" ]; then
    echo "parse-headers.sh: cannot read $file" >&2
    exit 2
fi

mapfile -t lines < "$file"

# Not a bash hook script — exit silently.
if [ "${#lines[@]}" -eq 0 ] || [ "${lines[0]}" != "#!/usr/bin/env bash" ]; then
    exit 0
fi

# List-typed keys: top-level comma split → JSON array.
is_list_key() {
    case "$1" in
        EVENTS|DISPATCHED-BY|SHIPS-IN|RELATES-TO) return 0 ;;
        *) return 1 ;;
    esac
}

# Split on top-level commas (commas inside parens stay attached). Prints one
# trimmed token per line.
split_top_level() {
    local s="$1" buf="" depth=0 i ch
    for ((i = 0; i < ${#s}; i++)); do
        ch="${s:i:1}"
        case "$ch" in
            '(') depth=$((depth + 1)); buf+="$ch" ;;
            ')') depth=$((depth - 1)); buf+="$ch" ;;
            ',')
                if [ "$depth" -eq 0 ]; then
                    # trim leading/trailing whitespace
                    buf="${buf#"${buf%%[![:space:]]*}"}"
                    buf="${buf%"${buf##*[![:space:]]}"}"
                    printf '%s\n' "$buf"
                    buf=""
                else
                    buf+="$ch"
                fi
                ;;
            *) buf+="$ch" ;;
        esac
    done
    buf="${buf#"${buf%%[![:space:]]*}"}"
    buf="${buf%"${buf##*[![:space:]]}"}"
    printf '%s\n' "$buf"
}

keys=()
vals=()
declare -A seen=()

re_directive='^#[[:space:]]CC-HOOK:[[:space:]]([A-Z][A-Z0-9-]*):[[:space:]](.*)$'
re_directive_bad='^#[[:space:]]CC-HOOK:'

for ((i = 1; i < ${#lines[@]}; i++)); do
    line="${lines[$i]}"
    # Block ends at first blank line, first non-comment, or first non-CC comment.
    if [ -z "$line" ]; then break; fi
    if [ "${line:0:1}" != "#" ]; then break; fi

    if [[ "$line" =~ $re_directive ]]; then
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        # trim trailing whitespace
        val="${val%"${val##*[![:space:]]}"}"
        if [ -n "${seen[$key]:-}" ]; then
            echo "parse-headers.sh: $file:$((i + 1)): duplicate CC-HOOK key '$key'" >&2
            exit 1
        fi
        seen[$key]=1
        keys+=("$key")
        vals+=("$val")
    elif [[ "$line" =~ $re_directive_bad ]]; then
        echo "parse-headers.sh: $file:$((i + 1)): malformed CC-HOOK directive" >&2
        exit 1
    else
        # Non-CC comment — end of block.
        break
    fi
done

if [ "${#keys[@]}" -eq 0 ]; then
    exit 0
fi

# Build jq invocation. Scalars via --arg; list-typed via --argjson with a
# pre-built JSON array; assemble with `+ {KEY: $valN}` in declaration order.
jq_args=(-n --arg _file "$file")
filter='{}'
for ((n = 0; n < ${#keys[@]}; n++)); do
    key="${keys[$n]}"
    val="${vals[$n]}"
    var="v$n"
    if is_list_key "$key"; then
        # Build JSON array from top-level comma split.
        arr_json=$(split_top_level "$val" | jq -R . | jq -s .)
        jq_args+=(--argjson "$var" "$arr_json")
    else
        jq_args+=(--arg "$var" "$val")
    fi
    # Quote key for jq (keys may contain '-').
    filter+=" + {\"$key\": \$$var}"
done
filter+=' + {file: $_file}'

jq -c "${jq_args[@]}" "$filter"
