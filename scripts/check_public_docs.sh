#!/bin/bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "$repository_root"

violations=0

report_path_violation() {
    local file="$1"
    echo "forbidden public documentation path: $file" >&2
    echo "  Keep agent plans and raw research in ignored local paths." >&2
    violations=1
}

report_content_violation() {
    local label="$1"
    local pattern="$2"
    local file="$3"
    local matches
    if matches="$(grep -En "$pattern" "$file")"; then
        echo "$label in $file:" >&2
        echo "$matches" >&2
        echo "  Replace machine-specific values with synthetic placeholders." >&2
        violations=1
    fi
}

while IFS= read -r file; do
    case "$file" in
        *.md) ;;
        *) continue ;;
    esac

    [[ -f "$file" ]] || continue

    case "$file" in
        docs/superpowers/*|docs/local-research/*|docs/SPACE_*_RESEARCH.md)
            report_path_violation "$file"
            ;;
    esac

    report_content_violation \
        "machine-specific UUID" \
        '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
        "$file"
    report_content_violation \
        "local macOS path" \
        '/Users/[^/[:space:]]+' \
        "$file"
    report_content_violation \
        "numeric private Space list" \
        '(spaceIDs|Spaces)[[:space:]]*[:=][[:space:]]*\[[[:space:]]*[0-9]' \
        "$file"
    report_content_violation \
        "numeric current Space ID" \
        'currentSpaceID[[:space:]]*[:=][[:space:]]*[0-9]' \
        "$file"
done < <(git ls-files)

if (( violations != 0 )); then
    exit 1
fi

echo "public documentation check passed"
