#!/usr/bin/env bash
#
# Keep the fitd-builder skill in this repo in step with Extendly's partner-resources repo.
#
#   scripts/sync-fitd-builder.sh           update the copy in this repo, then review and commit
#   scripts/sync-fitd-builder.sh --check   only report what upstream would change (exit 1 if anything)
#   scripts/sync-fitd-builder.sh --auto    session-start hook mode, see AUTOMATIC UPDATES
#
# It mirrors upstream's plugin layout into this repo's project-level locations:
#   fitd-builder/skills/fitd-builder/   ->  .claude/skills/fitd-builder/
#   fitd-builder/LICENSE                ->  .claude/skills/fitd-builder/LICENSE
#   fitd-builder/commands/              ->  .claude/commands/fitd-builder/
#
# AUTOMATIC UPDATES
#   Two layers run this without anyone asking:
#   - .github/workflows/auto-update-fitd-builder.yml runs it every 4 hours and commits any
#     change to the default branch, so new sessions and `git pull` pick the update up.
#   - .claude/settings.json runs it with --auto when a Claude Code cloud session starts, so the
#     session is current even before the workflow catches up, or while GitHub has it paused.
#   --auto acts only in cloud sessions (CLAUDE_CODE_REMOTE=true); a local checkout gets updates
#   through `git pull`. It checks at most once per EXTENDLY_SKILL_UPDATE_TTL, prints nothing
#   unless it found an update (what it prints becomes context for Claude), and always exits 0:
#   a session-start hook must never get in the way of the session.
#
# ENVIRONMENT
#   EXTENDLY_SKILL_UPDATE_CHECK=off      --auto does nothing (the switch Extendly's plugin uses)
#   EXTENDLY_SKILL_UPDATE_CHECK=notify   --auto reports an update without applying it
#   EXTENDLY_SKILL_UPDATE_TTL=<seconds>  minimum time between --auto checks (default 14400 = 4h)
#   FITD_UPSTREAM_REPO                   git URL to pull from (default: Extendly's partner-resources)
#   FITD_UPSTREAM_REF                    branch or tag to pull (default: upstream's default branch)
#   GITHUB_OUTPUT                        set by GitHub Actions; receives updated, version, commit

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
upstream_repo="${FITD_UPSTREAM_REPO:-https://github.com/chathqio/partner-resources.git}"
upstream_ref="${FITD_UPSTREAM_REF:-}"
targets=(.claude/skills/fitd-builder .claude/commands/fitd-builder)

mode=apply
case "${1:-}" in
    --check) mode=check ;;
    --auto) mode=auto ;;
    '') ;;
    *) echo "usage: $0 [--check | --auto]" >&2; exit 2 ;;
esac

work=''
cleanup() {
    [ -n "$work" ] && rm -rf "$work"
    # Exit 2 from a SessionStart hook would block the session, so --auto swallows every failure.
    [ "$mode" = auto ] && exit 0
    return 0
}
trap cleanup EXIT

# Scratch space goes inside the git dir: that keeps it on the repo's filesystem, so the final
# swap is a rename, and out of `git status`. Outside a git checkout, use the system temp dir.
git_dir=$(git -C "$repo_root" rev-parse --absolute-git-dir 2>/dev/null) || git_dir=''

if [ "$mode" = auto ]; then
    update_check="${EXTENDLY_SKILL_UPDATE_CHECK:-update}"
    [ "$update_check" = off ] && exit 0
    [ "${CLAUDE_CODE_REMOTE:-}" = true ] || exit 0
    exec 2>/dev/null

    ttl="${EXTENDLY_SKILL_UPDATE_TTL:-14400}"
    case "$ttl" in ''|*[!0-9]*) ttl=14400 ;; esac
    stamp="${git_dir:+$git_dir/fitd-builder-update.stamp}"
    if [ -n "$stamp" ] && [ -f "$stamp" ]; then
        last=$(stat -c %Y "$stamp" || stat -f %m "$stamp" || echo 0)
        case "$last" in ''|*[!0-9]*) last=0 ;; esac
        [ $(( $(date +%s) - last )) -lt "$ttl" ] && exit 0
    fi
    # Stamp before the network work, so a check that hangs or fails doesn't re-run every session.
    [ -n "$stamp" ] && : > "$stamp"
fi

work=$(mktemp -d "${git_dir:-${TMPDIR:-/tmp}}/fitd-sync.XXXXXX")

export GIT_TERMINAL_PROMPT=0 GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=15
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

skill_version() {  # metadata.version from a SKILL.md frontmatter, reduced to safe characters
    [ -f "$1" ] || return 0
    awk 'NR == 1 && $0 != "---" { exit }
         NR > 1 && $0 == "---" { exit }
         /^[[:space:]]+version:/ { sub(/^[[:space:]]+version:[[:space:]]*/, ""); print; exit }' "$1" |
        tr -cd '0-9A-Za-z.+-'
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

apply_update() {  # swap each target for its staged copy, by rename where the filesystem allows
    local i dst
    for i in "${!targets[@]}"; do
        dst="$repo_root/${targets[$i]}"
        mkdir -p "$(dirname "$dst")"
        if [ -e "$dst" ]; then mv "$dst" "$work/old-$i"; fi
        mv "$new/${targets[$i]}" "$dst"
    done
}

set_output() {  # step outputs for the GitHub Actions workflow
    [ -n "${GITHUB_OUTPUT:-}" ] || return 0
    printf '%s\n' "$@" >> "$GITHUB_OUTPUT"
}

current=$(skill_version "$repo_root/.claude/skills/fitd-builder/SKILL.md")
latest=$(skill_version "$new/.claude/skills/fitd-builder/SKILL.md")
commit=$(git -C "$work/upstream" rev-parse --short HEAD)
report=$(diff_report)

if [ -z "$report" ]; then
    set_output updated=false "version=$latest" "commit=$commit"
    [ "$mode" = auto ] || echo "fitd-builder is up to date: ${current:-unknown} (upstream commit $commit)"
    exit 0
fi

if [ "${current:-none}" = "${latest:-unknown}" ]; then
    change="$latest, with upstream content changes"
else
    change="${current:-none} -> ${latest:-unknown}"
fi

case "$mode" in
    check)
        echo "fitd-builder: this repo has ${current:-nothing}, upstream has ${latest:-unknown} (commit $commit)"
        printf '%s\n' "$report"
        echo "run scripts/sync-fitd-builder.sh to apply"
        exit 1
        ;;
    auto)
        if [ "$update_check" = notify ]; then
            echo "fitd-builder update available: $change (Extendly partner-resources @$commit). It was" \
                 "not applied because EXTENDLY_SKILL_UPDATE_CHECK=notify. Tell the user:" \
                 "scripts/sync-fitd-builder.sh applies it, and the repo's auto-update workflow commits" \
                 "it within a few hours."
            exit 0
        fi
        ;;
    apply)
        echo "fitd-builder: this repo has ${current:-nothing}, upstream has ${latest:-unknown} (commit $commit)"
        printf '%s\n' "$report"
        ;;
esac

apply_update
set_output updated=true "version=$latest" "commit=$commit"

if [ "$mode" = auto ]; then
    echo "fitd-builder was auto-updated at session start: $change (Extendly partner-resources" \
         "@$commit). Its files under .claude/skills/fitd-builder and .claude/commands/fitd-builder" \
         "are modified in the working tree on purpose. The repo's auto-update workflow commits the" \
         "same change, so leave them out of unrelated commits."
else
    echo "updated to ${latest:-upstream} ($commit). Review with 'git diff -- .claude', then commit."
fi
