#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
checker="$root/scripts/check_public_docs.sh"
if [[ ! -x "$checker" ]]; then
    echo "checker not executable: $checker" >&2
    exit 1
fi

temporary_root="$(mktemp -d)"
trap 'rm -rf "$temporary_root"' EXIT
repository="$temporary_root/repository"
output="$temporary_root/output"

git init -q "$repository"
git -C "$repository" config user.name "Sideby Tests"
git -C "$repository" config user.email "tests@example.invalid"
mkdir -p "$repository/scripts" "$repository/docs"
cp "$checker" "$repository/scripts/check_public_docs.sh"
chmod +x "$repository/scripts/check_public_docs.sh"
printf '# Safe\n\nUse DISPLAY-UUID and SPACE-ID placeholders.\n' > "$repository/docs/SAFE.md"
git -C "$repository" add scripts/check_public_docs.sh docs/SAFE.md
git -C "$repository" commit -qm "test fixture"

expect_pass() {
    if ! (cd "$repository" && bash scripts/check_public_docs.sh) >"$output" 2>&1; then
        cat "$output" >&2
        exit 1
    fi
}

expect_fail() {
    local expected="$1"
    if (cd "$repository" && bash scripts/check_public_docs.sh) >"$output" 2>&1; then
        echo "expected checker failure containing: $expected" >&2
        exit 1
    fi
    if ! grep -q "$expected" "$output"; then
        cat "$output" >&2
        exit 1
    fi
}

remove_fixture() {
    local path="$1"
    git -C "$repository" reset -q HEAD -- "$path"
    rm -rf "$repository/$path"
}

expect_pass

mkdir -p "$repository/docs/superpowers/plans"
printf '# Internal plan\n' > "$repository/docs/superpowers/plans/example.md"
git -C "$repository" add -f docs/superpowers/plans/example.md
expect_fail "forbidden public documentation path"
remove_fixture docs/superpowers/plans/example.md

mkdir -p "$repository/docs/superpowers/specs"
printf '# Internal spec\n' > "$repository/docs/superpowers/specs/example.md"
git -C "$repository" add -f docs/superpowers/specs/example.md
expect_fail "forbidden public documentation path"
remove_fixture docs/superpowers/specs/example.md

printf 'Internal artifact\n' > "$repository/docs/superpowers/example.txt"
git -C "$repository" add -f docs/superpowers/example.txt
expect_fail "forbidden public documentation path"
remove_fixture docs/superpowers/example.txt

printf '# Raw research\n' > "$repository/docs/SPACE_SAMPLE_RESEARCH.md"
git -C "$repository" add -f docs/SPACE_SAMPLE_RESEARCH.md
expect_fail "forbidden public documentation path"
remove_fixture docs/SPACE_SAMPLE_RESEARCH.md

printf '# Root note\n\n29047B54-6562-49DE-AA42-F7A696BE4F6B\n' > "$repository/NOTES.md"
git -C "$repository" add NOTES.md
expect_fail "machine-specific UUID"
remove_fixture NOTES.md

mkdir -p "$repository/docs/superpowers/plans"
printf '# Tracked plan pending deletion\n' > "$repository/docs/superpowers/plans/pending-deletion.md"
git -C "$repository" add -f docs/superpowers/plans/pending-deletion.md
git -C "$repository" commit -qm "add plan pending deletion"
rm "$repository/docs/superpowers/plans/pending-deletion.md"
expect_pass
git -C "$repository" rm -q docs/superpowers/plans/pending-deletion.md
git -C "$repository" commit -qm "remove plan fixture"

printf '# UUID\n\n29047B54-6562-49DE-AA42-F7A696BE4F6B\n' > "$repository/docs/SAFE.md"
expect_fail "machine-specific UUID"

printf '# Path\n\n/Users/example/Develop/sideby\n' > "$repository/docs/SAFE.md"
expect_fail "local macOS path"

printf '# Spaces\n\nspaceIDs: [1, 928, 959]\n' > "$repository/docs/SAFE.md"
expect_fail "numeric private Space list"

printf '# Current Space\n\ncurrentSpaceID: 959\n' > "$repository/docs/SAFE.md"
expect_fail "numeric current Space ID"

printf '# Safe\n\nUse DISPLAY-UUID and SPACE-ID placeholders.\n' > "$repository/docs/SAFE.md"
expect_pass

echo "public docs checker tests passed"
