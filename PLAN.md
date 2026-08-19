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

## Operator seat

Sessions run from the mac (`~/work/workbench`). The mac reaches the box
directly (`agent-vm-ssh` in `~/.ssh/config.local`, 1Password SSH agent),
so `make provision`, `make ssh` and `home/install.sh --check` over ssh
work from the laptop; `make lint` works there (shellcheck, shfmt from
mise). Snapshots and rollbacks need `pve-vm-ssh` (a 1Password `ssh-host`
item; `mise run ssh:sync` on the mac installs it) - not yet exercised from
the mac since the devbox seat is gone.

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
history.
- 2026-08-18: repo created; AGENTS.md/CLAUDE.md/docs 00-02 drafted from
  agent-vm, dotfiles, ai-hub. D1 clean start, D5 zsh hand-off.
- 2026-08-19: first commit, repo published; RC env `workbench` added. Phase 0
  done, phase 1 active.
- 2026-08-19: phase 1 executed: staging-dir paths moved, remotes.list gained
  workbench, SC2015 fixed. `make lint` green.
- 2026-08-19: phase 1 committed and pushed (5f47c7e); seat moves to devbox.
- 2026-08-19: phase 1 acceptance green from devbox; phase 2 executed
  (8325835..aaa5925). Box acceptance green, mac pending.
- 2026-08-19: phase 2 mac acceptance: three fixes (mise `bun` placement,
  install.sh log(), shared BACKUP_DIR). Phase 2 done, phase 3 active.
- 2026-08-19: phase 3 executed (c14838c, ai-hub fc2e4e2): `link_agents` and
  `verify_gate` added. Phase 3 done, phase 4 active.
- 2026-08-19: phase 4 executed (9ecfd4c..5315e16): mise tasks, D12 text. Phase
  4 done, phase 5 active.
- 2026-08-19: session end: omp:auth verified on box; merged ~/.claude.json
  installed on mac. Next session starts phase 5.
- 2026-08-19: phase 5 step 1 (OrbStack): bootstrap-all green in ~3 min;
  fresh-machine bugs fixed. RC login item remains, uncommitted.
- 2026-08-19: operator closed phase 5 (OrbStack done, cloud skipped, RC login
  open); phase 6 active.
- 2026-08-19: phase 6 step 1: agent-vm/dotfiles archived, remotes.list updated
  (bb56517), devbox renamed to box (c227908).
- 2026-08-19: phase 6 step 2: VPS volumes/compose torn down; docs/PLAN updated
  - migration complete.
- 2026-08-19: operator finished hand items (VPS devbox, service account, mac
  ssh, ghcr); OrbStack RC login skipped for good.
- 2026-08-19: rebuild test: VM 105 destroyed, bootstrap-all green from scratch
  in 3m14s (vm-create staging-dir fix). Logins pending.
- 2026-08-19: rebuild test closed: logins done, all RC servers up, no drift,
  clean snapshot; agy settings drift check added.
- 2026-08-19: RC cut to single `work` server (D11); four project servers
  disabled. Ghostty terminfo fix applied.
- 2026-08-19: docs/01 corrected: removed nonexistent mac-setup/mac-sync
  targets, added claude-remote and vm-destroy.
- 2026-08-19: omp's config.yml made generated, not symlinked;
  modelRoles.default -> gemini-3.7-flash:high, advisor disabled.
- 2026-08-19: omp config reviewed against `omp models`/benchmarks: `tiny` fixed
  to :minimal, default fallback chain now crosses providers.
- 2026-08-19: policy: no Antigravity gemini reference runs below `:high` (six
  bare refs fixed). webSearchGeminiModel stays bare.
- 2026-08-19: agy reviewed: herdr hooks absent, bootstrap now fixes it; pinned
  gemini-3.7-flash-high effort high; sandbox gap noted; item -> Next.
- 2026-08-19: drift sweep after a full repo review: omp-run.sh default model
  aligned with the omp-fleet policy (3.7-flash:high), box ssh:sync got the
  mac's empty-hostname guard, bootstrap put() converges file mode, ownership
  table gained the missing box/files rows and lost the phantom home/aws, mise
  reference doc matches inline tasks, PLAN log condensed. Non-finding: the
  smol chain's gemini-3.5-flash is real (`omp models` on the box lists 3.5,
  3.6, 3.7-flash); config.yml's fingerprint table now says so.
