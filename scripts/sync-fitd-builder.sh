#!/usr/bin/env bash
#
# Pull the latest fitd-builder skill from Extendly's partner-resources repo into this one.
#
#   scripts/sync-fitd-builder.sh           update the copy in this repo, then review and commit
#   scripts/sync-fitd-builder.sh --check   only report what upstream would change (exit 1 if anything)
#
# It mirrors upstream's plugin layout into this repo's project-level locations:
#   fitd-builder/skills/fitd-builder/   ->  .claude/skills/fitd-builder/
#   fitd-builder/LICENSE                ->  .claude/skills/fitd-builder/LICENSE
#   fitd-builder/commands/              ->  .claude/commands/fitd-builder/
#
# The marketplace install keeps itself current with a hook that runs `claude plugin update`.
# That hook cannot reach a copy that lives in a repo, so this script is the manual equivalent.
#
# ENVIRONMENT
#   FITD_UPSTREAM_REPO   git URL to pull from (default: Extendly's partner-resources on GitHub)
#   FITD_UPSTREAM_REF    branch or tag to pull (default: upstream's default branch)

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
upstream_repo="${FITD_UPSTREAM_REPO:-https://github.com/chathqio/partner-resources.git}"
upstream_ref="${FITD_UPSTREAM_REF:-}"
targets=(.claude/skills/fitd-builder .claude/commands/fitd-builder)

check_only=0
case "${1:-}" in
    --check) check_only=1 ;;
    '') ;;
    *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

clone_args=(--quiet --depth 1)
[ -n "$upstream_ref" ] && clone_args+=(--branch "$upstream_ref")
if ! git clone "${clone_args[@]}" "$upstream_repo" "$work/upstream"; then
    echo "could not clone $upstream_repo (offline, or it needs GitHub auth: try 'gh auth login')" >&2
    exit 1
fi

src="$work/upstream/fitd-builder"
[ -f "$src/skills/fitd-builder/SKILL.md" ] || { echo "no fitd-builder skill in $upstream_repo" >&2; exit 1; }

# Stage upstream in this repo's layout so the two trees compare file for file.
new="$work/new"
mkdir -p "$new/.claude/skills" "$new/.claude/commands"
cp -R "$src/skills/fitd-builder" "$new/.claude/skills/fitd-builder"
cp "$src/LICENSE" "$new/.claude/skills/fitd-builder/LICENSE"
cp -R "$src/commands" "$new/.claude/commands/fitd-builder"

skill_version() {  # metadata.version from a SKILL.md frontmatter
    [ -f "$1" ] || return 0
    awk 'NR == 1 && $0 != "---" { exit }
         NR > 1 && $0 == "---" { exit }
         /^[[:space:]]+version:/ { sub(/^[[:space:]]+version:[[:space:]]*/, ""); print; exit }' "$1"
}

diff_report() {  # one line per file that applying upstream would add, change, or remove
    local t f
    for t in "${targets[@]}"; do
        while IFS= read -r f; do
            if [ ! -f "$repo_root/$f" ]; then
                echo "  added    $f"
            elif ! cmp -s "$new/$f" "$repo_root/$f"; then
                echo "  changed  $f"
            fi
        done < <(cd "$new" && find "$t" -type f | sort)
        if [ -d "$repo_root/$t" ]; then
            while IFS= read -r f; do
                [ -f "$new/$f" ] || echo "  removed  $f"
            done < <(cd "$repo_root" && find "$t" -type f | sort)
        fi
    done
}

current=$(skill_version "$repo_root/.claude/skills/fitd-builder/SKILL.md")
latest=$(skill_version "$new/.claude/skills/fitd-builder/SKILL.md")
commit=$(git -C "$work/upstream" rev-parse --short HEAD)
report=$(diff_report)

if [ -z "$report" ]; then
    echo "fitd-builder is up to date: ${current:-unknown} (upstream commit $commit)"
    exit 0
fi

echo "fitd-builder: this repo has ${current:-nothing}, upstream has ${latest:-unknown} (commit $commit)"
printf '%s\n' "$report"

if [ "$check_only" -eq 1 ]; then
    echo "run scripts/sync-fitd-builder.sh to apply"
    exit 1
fi

for t in "${targets[@]}"; do
    rm -rf "${repo_root:?}/$t"
    mkdir -p "$(dirname "$repo_root/$t")"
    cp -R "$new/$t" "$repo_root/$t"
done
echo "updated to ${latest:-upstream} ($commit). Review with 'git diff -- .claude', then commit."
