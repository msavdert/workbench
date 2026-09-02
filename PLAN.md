# PLAN.md - live state

This file is the handoff between sessions. Update `Now`, `Next` and `Log`
before ending a session. The migration phases below are complete; their
definition and record is `docs/02-migration.md`.

## Phases

| # | Phase | Status |
|---|---|---|
| 0 | Founding documents | done |
| 1 | Move agent-vm in, unchanged behaviour | done |
| 2 | home/ and mac/ | done |
| 3 | agents/ (from ai-hub runtime) | done |
| 4 | Human layer, herdr/agy/aws-cli, plugins | done |
| 5 | Portability proof (OrbStack, cloud) | done (cloud and OrbStack RC skipped) |
| 6 | Retire agent-vm, dotfiles, devbox | done |

## Now

2026-09-01 architecture review (workbench + vault) and its first fixes, all
committed and pushed in both repos. Vault: the nightly compile had
never distilled a note (marker off-by-one, compile.py) and the sessions
digest was reading its own headless runs (cwd=$HOME; now a dedicated
~/.cache/vault/headless dir); both fixed, marker reset so the next 03:00 run
distills all six daily logs. Vault content tiers decided (HANDOFF D16):
`private/` is git-crypt encrypted, key is the 1Password document
`vault-git-crypt-key`, one medical capture moved there. Workbench: hermes
SOUL refuses third-party/health captures (repo + live file), failure
notices to Telegram via `unit-failure-notify@` (self-test delivered), five
hand-started project checkouts added to `remotes.list` as clone-only,
git-crypt via mise (aqua, linux-only binary) on the box and brew on the mac.

Migration complete (2026-08-19). From-scratch rebuild test of the Proxmox
box done the same day: `make snapshot` from the mac worked, VM 105
destroyed with all snapshots, `make bootstrap-all` green in 3m14s (47 ok,
0 fail; disk re-imported from the noble cloud image). After the operator's
manual logins (claude, omp, agy) `make claude-remote` starts all five
servers, `home/install.sh --check box` reports no drift after an agy and an
omp run, `opwith git gh api user` and `op whoami` answer, docker runs
hello-world, `clean` snapshot taken (2026-08-19 03:27 UTC). Four bugs only
the fresh path shows, all fixed and pushed: vm-create rsynced into a
missing staging dir on the PVE host (41a4d64); `make claude-remote` never
started template instances because `list-unit-files` does not list them
(uses the `wants/` symlinks now); agy rewrites its settings.json without a
Claude-style `permissions` key and in its own key order, so the block is
gone from `home/agy/settings.base.json` (eceeaf9) and `install.sh` compares
JSON targets by content (0b44295); the mac's multiplexed ssh master
predates the docker group after a rebuild (runbook note). `box/remotes.list`
gained ai-hub, dba-to-dbre, suhuf so they survive rebuilds (188629c).
2026-08-19, later: Remote Control reduced to the single shared
`work` server (capacity 2); `remotes.list` entries are `--clone-only`, the
four per-project servers were disabled on the box (D11 updated). Ghostty
terminfo shipped in `box/files/` after ssh sessions from the mac echoed
every keystroke twice. No active phase; work is backlog-driven.

2026-08-27: `make provision STEPS=hermes` hung with no output.
`hermes gateway install` asks two questions when the answers are not on the
command line, and provisioning runs under a tty (`ssh -t`) with the prompt
swallowed by `>/dev/null`; the prompts come before the "already installed"
early exit, so even a converged box hangs. `step_hermes` now answers both
(`--no-start-now --start-on-login`) and redirects stdin from `/dev/null` for
every hermes call. Verified under a forced pty: 14s, exit 0, both gateways
active. Two doctor findings from the same session: savdert's live config
still carried `web.backend: ddgs` because config.yaml is seeded once and
1de6554 only changed the seed (cleared with `hermes config unset
web.backend`, gateway restarted), and doctor's
"No API key found in ~/.hermes/.env" is a false positive - its hint list is
28 fixed vendor keys and does not know the `HERMES_CUSTOM_API_*` convention
that `provider: custom` uses. `step_hermes` also initializes the Skills Hub
once (`hermes skills list` creates `~/.hermes/skills/.hub`); both live users
were initialized by hand, so the line only bites on a fresh install. The two
remaining browser warnings are by design: with `browser.backend` unset hermes
defaults to the Browser Use CLI, which hides the built-in `browser` and
`browser-cdp` toolsets - Playwright Chromium itself is recognized.
The box was still on `Etc/UTC`: D15's `timedatectl` line was committed
(8e048c0, 16:23 UTC 2026-08-19) one minute after `step_system` last ran, so
it had never executed. Applied; the box is `America/New_York` (EDT) now and
`vault-compile.timer` stayed at 03:00 local because its `OnCalendar` pins
the zone. cloud-init's conflicting `timezone: Etc/UTC` removed from
`providers/proxmox/user-data.yaml` - one setting, one owner.
Two ways to feed the vault from outside a brain session, since its hooks are
project-scoped and the operator never opens a session inside the vault on the
box: `home/bin/brain` (note into `00-inbox/` from any repo, either machine)
and `vault-sessions.timer` at 02:50 New York, which runs the vault's new
`.claude/scripts/sessions.py` (vault commit a84aa5a) over the previous day's
`~/.claude/projects` transcripts. Both timers are armed on the box; the box
filter turns 70 raw sessions into 7 real ones (3 repos, 9k chars). The first
live run (operator, vault commit c77f468) worked and exposed three defects,
all fixed in vault commits 13bc8a1 and 5308561: machine messages that arrive
as user turns were summarized as if typed; only prompts were sent, so every
bullet read "istendi" and never said what came of it; and a re-run appended a
second section to an append-only log. Thresholding now counts characters
typed, not prompts - counting prompts kept 11 sessions on 2026-08-26 that
only cleared the bar through machine messages. Tonight's 02:50 run is a
no-op because 2026-08-26 is already digested; the first digest under the new
logic is 2026-08-28 02:50, for 2026-08-27.

2026-08-27, later: the box and `pve` went unreachable together four times
since 2026-08-22. Not the box. The pve host's onboard Intel I219-LM wedges
its transmit ring (`e1000e ... Detected Hardware Unit Hang`) and the driver
never issues its recovering reset, which kills the Tailscale peer, the
`10.0.0.0/24` subnet route and the guest NAT gateway in one stroke. Ruled
out: SDN (its config predates the first hang by 18 days), kernel (started on
7.0.6-2, continued across upgrades to -12 and -14), memory and heat (no MCE,
no EDAC, no throttling), load (the host was idle for three minutes before the
last hang). Two changes applied by hand on the host, which this repository
deliberately does not manage: segmentation/receive offload and EEE off
through a `post-up` hook, and softdog replaced by the Intel PCH TCO watchdog
so a freeze resets itself instead of waiting for a Hetzner Robot console
reset. Record, re-apply and rollback: `docs/reference/pve-nic-hang.md`. No
alerting: the operator tracks `pve` reboots by hand, weekly, and a second
recurrence opens a Hetzner ticket from notes kept outside this repository.
Both changes verified across a reboot the same day (05:40 UTC): `watchdog0`
comes up as `iTCO_wdt` with no `softdog` loaded, the `post-up` hook has the
offloads and EEE off before the host is reachable, and the box returned on
its own with no failed units.

2026-08-31: Nightly encrypted hermes backup to OCI S3.
`box/files/hermes/hermes-backup.py` (PEP 723, uv runs it) zips `~/.hermes`
with `hermes backup`, encrypts with age (mise tool, commit 3dcbd09;
recipient only - the identity lives in op://dotfiles/Hermes/age-identity)
and uploads to `s3://general/hermes/backup/` via boto3 - the aws CLI v2
always sends aws-chunked encoding, which OCI's compat layer rejects
(NotImplemented); boto3 turns it off with
`request_checksum_calculation=when_required`. systemd user timer at
04:30 America/New_York, 30-day remote retention, 7 local copies.
Secrets resolve at runtime via `opwith hermes-backup`
(`home/op-env/hermes-backup.env`, op:// refs only - nothing sensitive
on disk); the private key never leaves 1Password. First run verified
end to end: 105 MB zip.age uploaded, downloaded back, decrypted with
the op identity, zip opened (3447 entries, config.yaml + .env
present). Agent gateway only - savdert has no op access by design.

## Next

1. Closed 2026-09-01: both repos committed and pushed, box clone locked
   (git-crypt from mise), mac unlocked with the 1Password key.
2. Closed 2026-09-01: the moved medical note stays in vault history; the
   operator judged it minor and the repo is private, so no history rewrite.
3. Verify the morning after: `~/work/vault/.state/compile.report` lists six
   inputs and at least one note under `50-knowledge/`; the 2026-09-01 daily
   log carries no "prompt injection" alarm.
4. Review debt from the same session (not started): PLAN.md `Now` and `Log`
   back to the two-line rule, a threat model and dependency inventory under
   docs/, ~/work backup before rollback, agentshard world reports out of
   `30-projects/` into `90-agent/`.
2. agy: run the $HOME instruction-layer probe (does agy read ~/AGENTS.md or
   ~/GEMINI.md?) and record the answer in docs/03-runbook.md; only workspace-
   relative paths were confirmed during the agy review.
3. Optional: add `knowledge` to `box/remotes.list` (`--clone-only`) if it
   should be present on the box again.

## Open questions

- none open. The pve alerting question was closed on 2026-08-27: no dead
  man's switch, the operator watches the host's reboots by hand (weekly) and
  a second recurrence opens the ticket. nvim/zellij (box only) and the
  statusline (one script, both repos had the same) were decided in phase 2.

## Backlog (not scheduled)

- `home/install.sh --check` as a `verify` sub-step on the box.
- mise lockfile for the mac profile (see docs/reference/mise-2026.md).
- Weekly `mise up` report as a systemd timer, opt-in.
- `providers/cloud/`: generic cloud-init user-data plus one tested cloud
  provider (Hetzner or equivalent). Skipped in phase 5: no cloud account.

## Log

One entry per session, two lines at most; details live in docs/ and git
history. Older entries are condensed; `git log` has the full trail.

- 2026-09-01: architecture review; vault compile and sessions digest fixed,
  `private/` git-crypt tier (vault D16), Telegram failure notices, hermes SOUL rule.

- 2026-08-31: nightly encrypted hermes backup to OCI S3 (age + boto3,
  04:30 timer; aws CLI cannot write to OCI - aws-chunked).
- 2026-08-27: box+pve outages traced to the pve host's I219-LM e1000e TX
  hang (four since 08-22); offloads/EEE off, chipset watchdog over softdog.
- 2026-08-27: vault gains two outside-in feeds: `brain` CLI and the 02:50
  sessions digest (workbench owns the units, vault owns the script).
- 2026-08-27: box moved to America/New_York (D15 finally applied; cloud-init
  no longer sets a second, conflicting zone).
- 2026-08-27: step_hermes made non-interactive (`gateway install` prompts
  under provisioning's tty were the hang); savdert's ddgs backend cleared.
- 2026-08-26: Hermes moved in (D17): step_hermes provisions two isolated
  gateways (agent personal+vault, savdert family), step_vault arms the
  nightly vault-compile timer; hermes-vm retired (docs/reference/hermes.md).
- 2026-08-19: `remoteControlAtStartup` on in the box overlay so herdr
  sessions are app-visible; surface handoff = PLAN.md + push (D8, D11, runbook).
- 2026-08-18/19: phases 0-6 executed in sequence (founding docs, agent-vm
  moved in, home/ and mac/, ai-hub runtime, harnesses, OrbStack proof,
  predecessors retired); migration complete, see docs/02-migration.md.
- 2026-08-19: from-scratch rebuild proven (3m14s, 47 ok / 0 fail), four
  fresh-path bugs fixed; RC reduced to one `work` server (D11); omp/agy
  configs reviewed against the live tools; ownership table completed.
- 2026-08-19: agents/ dissolved into home/claude/, ai-hub material handed
  back (ai-hub c4de199); statusline glyph exception and signing key
  recorded.
- 2026-08-19: starship.toml rewritten for both profiles; review follow-ups:
  unused omp skills removed, leak procedure in runbook, agy seed keys (D8),
  hooks merge deduplicated.
- 2026-08-19: README rewritten for an outside reader (prerequisites,
  quickstart, diagram, highlights), docs/glossary.md, lint workflow and
  badge, verify transcript under docs/reference/, PLAN log condensed,
  operator seat moved to the runbook.
- 2026-08-19: herdr prefix+q over ssh left "3;1:3u" / "35;64;25M" on the
  next prompt. Not a herdr mode leak (verified in a pty: resets are sent
  before the detach message); it is the q key release and mouse motion
  arriving in the latency window before the resets reach Ghostty. .zshrc
  wraps herdr and drains the tty for 0.2s of quiet when SSH_CONNECTION is
  set. zellij used to absorb this in the old container setup.
- 2026-08-19: `mise up` on the box warned "no latest version for
  http:sqlcl" because the pinned http tool had no version source (dotfiles
  never ran `mise up`, only `mise install` in docker build, so it was never
  visible). Fixed with version_list_url + version_regex scraping Oracle's
  download page (the Homebrew cask livecheck approach); verified on the box:
  ls-remote resolves 26.2.1.222.1617, install and `sql -V` work, warning
  gone.
- 2026-08-19: `mise run box:maintain` / `make maintain` added: apt
  full-upgrade + autoremove, `mise up` + `mise prune`, docker and disk
  usage, final reboot-pending line (never reboots). First run on the box:
  7 packages upgraded, old sqlcl pruned, reboot pending (kernel 6.8.0-137
  -> 138 installed, not booted) - the owner decides when.
- 2026-08-19: box rebooted with approval (6.8.0-137 -> 138, KSTA back to 1,
  claude-remote came back on its own via linger). Maintenance policy written
  down as vision D14; README, runbook (reboot procedure), architecture
  ownership table and the box CLAUDE.md updated, stale
  `box/files/mise.toml` reference removed.
- 2026-08-19: timezone check: the box was still on Etc/UTC (inherited from
  agent-vm, never decided). Switched to America/New_York in bootstrap
  step_system, recorded as D15; tzdata 2026c current, systemd-timesyncd
  synced against ntp.ubuntu.com, chrony deliberately not installed.
- 2026-08-19: agy auth check: the one re-login on the mac was a token
  refresh failing on DNS (cli log 14:09), not provision; agy keeps its
  token in the Keychain, install.sh never touches it. Silenced the
  first-run model warning by seeding the display name in settings.base.
- 2026-08-19: mac gets a `box` alias (herdr --remote agent-vm-ssh --session
  main) as the everyday entry; `make ssh` stays as the tmux fallback. Box
  herdr server 0.8.0 runs sessions default and main; box agy model fixed
  to the display name in the live seed key.
- 2026-08-19: colour audit (D16): Ghostty moved to Catppuccin Latte/Mocha
  auto pair; status lines dropped hardcoded 256-colour codes for the 16
  ANSI slots; Claude box theme auto; omp/nvim on the catppuccin pair.
- 2026-08-25: starship: drop direnv module from format to eliminate context
  directory scanning and context timeout warnings on large repos.
- 2026-08-25: omp: add no-polling rule to AGENTS.md and delegation skill to
  prevent turn-looping on background tasks.
