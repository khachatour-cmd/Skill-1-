# FITD Builder for Claude Code

This repo carries Extendly's **fitd-builder** skill as a Claude Code project skill. Claude Code
loads everything under `.claude/` on its own, so there is no install step: open this repo in
Claude Code on your machine, or start a Claude Code on the web session on it, and the skill and
its commands are ready.

Source: the `fitd-builder` plugin in
[chathqio/partner-resources](https://github.com/chathqio/partner-resources/tree/master/fitd-builder).
Only fitd-builder is included, not that repo's other plugins. It keeps itself current (see
[Automatic updates](#automatic-updates)); `metadata.version` in
[`SKILL.md`](.claude/skills/fitd-builder/SKILL.md) shows which version is in the repo.

## Commands

| Command | What it does |
|---|---|
| `/fitd-builder` | Opens the skill and asks which workflow you want |
| `/fitd-builder:contextualize <niche + menu offer>` | Adapts an existing Extendly menu offer to a niche: hook and story, the 7 OfferIQ pillars, ad/VSL/landing copy, and a HighLevel AI Studio brief. Delivered as a markdown package plus a visual HTML artifact |
| `/fitd-builder:build <what you deliver + who it's for>` | Builds a new offer from scratch against the OfferIQ 7-pillar standard, as a submission packet for Extendly |
| `/fitd-builder:research <niche + menu offer>` | Runs only the niche research: pains, vocabulary, current vehicle, dollars at stake, objections |

Example: `/fitd-builder:contextualize single-location med spas + Speed-to-Lead`

The command names match the plugin install. Plain language works too ("adapt Speed-to-Lead for
single-location med spas"), since Claude picks the skill up from its description.

Output lands in `./niche-offers/<niche>.md` (contextualize, plus the HTML artifact) or
`./offer-drafts/<offer-slug>.md` (build). The skill confirms the path before it writes.

## What's in the repo

| Path | Contents |
|---|---|
| `.claude/skills/fitd-builder/` | The skill, byte-for-byte as upstream, plus Extendly's `LICENSE` |
| `.claude/commands/fitd-builder/` | The three commands. The folder name gives them their `fitd-builder:` prefix |
| `.claude/settings.json` | Permissions for the skill's web and file tools (below), and the session-start update check |
| `.github/workflows/auto-update-fitd-builder.yml` | Commits upstream updates to the repo every 4 hours |
| `scripts/sync-fitd-builder.sh` | Syncs the two fitd-builder folders with upstream. Both update layers run it |

## Web search, fetch, and grep

The skill's frontmatter pre-approves `Read`, `Write`, `Glob`, `Grep`, `Edit`, `AskUserQuestion`,
`WebSearch`, `WebFetch`, and `Artifact`, but only for the turn that starts it. Every workflow
pauses for your approval between stages and each reply starts a new turn, so
`.claude/settings.json` keeps the essentials allowed for the whole session in this repo:

| Rule | Why |
|---|---|
| `WebSearch` | Niche research and the Pillar 1 market-anchor check |
| `WebFetch(domain:partner.extendly.com)` | The live offer menu, fetched on every run |
| `Edit(/niche-offers/**)`, `Edit(/offer-drafts/**)` | Writing the output files (new files included) |

Cloud sessions apply these rules when this is the session's only repository. On your own
machine they apply once you accept Claude Code's trust prompt for the folder.

Reading and searching inside the repo never needs approval. Some Claude Code builds search with
Bash `grep`/`find` instead of separate `Grep`/`Glob` tools, and read-only searches don't prompt
either way. Fetching other pages during research (forums, review sites) still asks first; add
`"WebFetch"` to the `allow` list if you'd rather it didn't.

### Claude Code on the web: allow the offer-menu host

A cloud session can only reach the hosts its environment's network access allows. If that
excludes `partner.extendly.com`, as it did in the environment this was set up in, the skill uses
the offer-menu snapshot bundled at `.claude/skills/fitd-builder/context/offer-menu-snapshot.yaml`
and tells you so. For the live menu, open the cloud environment menu in the session's title bar
and choose Edit. Set **Network access** to **Custom**, add `partner.extendly.com` under
**Allowed domains**, and tick **Also include default list of common package managers** to keep
the default allowlist (or pick a broader access level). Pages the research step fetches need
their hosts allowed the same way. `WebSearch` works either way.

## Automatic updates

Updates are on and need nothing from you. Two layers keep the skill current with Extendly's
repo:

1. **The repo updates itself.** The
   [Auto-update fitd-builder](.github/workflows/auto-update-fitd-builder.yml) workflow checks
   upstream every 4 hours and commits any change to the default branch. New sessions start from
   that, and `git pull` brings it to a local checkout.
2. **Every cloud session checks when it starts.** A `SessionStart` hook in
   `.claude/settings.json` runs `scripts/sync-fitd-builder.sh --auto` as a Claude Code on the web
   session opens, so the session uses the newest version even before the workflow catches up.
   It stays silent when there's nothing new, adds about a second to startup, and a failed check
   never holds up the session. If it does update, the changed files show up as uncommitted in
   that session; the workflow commits the same change.

| To | Do |
|---|---|
| Update right now | Actions tab > **Auto-update fitd-builder** > **Run workflow**, or run `scripts/sync-fitd-builder.sh` |
| See what an update would change | `scripts/sync-fitd-builder.sh --check` |
| Be told about updates instead of getting them | Set `EXTENDLY_SKILL_UPDATE_CHECK=notify` in the cloud environment's variables (session layer only) |
| Turn updates off | Disable the workflow in the Actions tab, and set `EXTENDLY_SKILL_UPDATE_CHECK=off` |

GitHub pauses scheduled workflows in a public repo after 60 days without a commit. Every update
the workflow commits resets that clock, and the session check works either way; if GitHub does
pause it, re-enable it from the Actions tab.

Updates replace anything edited in the two fitd-builder folders, so keep your own changes
elsewhere, or turn updates off before customizing the skill.

## claude.ai chat and Cowork

The skill folder is a valid claude.ai skill as it stands. Zip `.claude/skills/fitd-builder/` so
the zip's top level is a single `fitd-builder` folder with `SKILL.md` directly inside, then
upload it under **Settings > Capabilities > Skills**. There are no slash commands there, so ask in
plain language.

## License

fitd-builder belongs to Extendly and is licensed under the **Extendly Partner Program License
(Members-Only)** in [`.claude/skills/fitd-builder/LICENSE`](.claude/skills/fitd-builder/LICENSE).
This copy is published with Extendly's permission, and that permission doesn't pass to anyone
reading it: the license only covers active Extendly partner-program members, so don't copy,
reuse, or redistribute the skill unless you are one.
