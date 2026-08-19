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

## Next

1. Pick from the backlog below; nothing else is scheduled.
2. agy: run the $HOME instruction-layer probe (does agy read ~/AGENTS.md or
   ~/GEMINI.md?) and record the answer in docs/03-runbook.md; only workspace-
   relative paths were confirmed during the agy review.
3. Optional: add `knowledge` to `box/remotes.list` (`--clone-only`) if it
   should be present on the box again.

## Open questions

- none open; nvim/zellij (box only) and the statusline (one script, both
  repos had the same) were decided in phase 2.

## Backlog (not scheduled)

- `home/install.sh --check` as a `verify` sub-step on the box.
- mise lockfile for the mac profile (see docs/reference/mise-2026.md).
- Weekly `mise up` report as a systemd timer, opt-in.
- `providers/cloud/`: generic cloud-init user-data plus one tested cloud
  provider (Hetzner or equivalent). Skipped in phase 5: no cloud account.

## Log

One entry per session, two lines at most; details live in docs/ and git
history. Older entries are condensed; `git log` has the full trail.
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
