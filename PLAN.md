# PLAN.md - live state

This file is the handoff between sessions. Update `Now`, `Next` and `Log`
before ending a session. Phases are defined in `docs/02-migration.md`.

## Phases

| # | Phase | Status |
|---|---|---|
| 0 | Founding documents | done |
| 1 | Move agent-vm in, unchanged behaviour | done |
| 2 | home/ and mac/ | active |
| 3 | agents/ (from ai-hub runtime) | not started |
| 4 | Human layer, herdr/agy/aws-cli, plugins | not started |
| 5 | Portability proof (OrbStack, cloud) | not started |
| 6 | Retire agent-vm, dotfiles, devbox | not started |

## Now

Phase 2 is implemented and its box-side acceptance is green; the mac side
has not been executed yet (this session ran on devbox). State of the tree:
`home/install.sh <profile>` (per-file links, jq-composed Claude and agy
settings, `~/.config/workbench/env` with `MISE_ENV`, `--check`, `--dry-run`,
move-aside backups) and everything the source map sends to `home/`:
mise (base + mac + box), git, op-env, bin/opwith, claude (base + box + mac
overlays, one statusline), bash/interactive.sh (D5 hand-off to zsh), zsh,
starship, herdr, agy, omp, nvim, zellij. `box/files/` lost the duplicates;
`box/bootstrap.sh` has `step_home` (clones `~/work/workbench` on the box,
runs `home/install.sh box`), zsh in apt, mise under the agent's login shell
with `opwith git` for the GitHub API limit, and three new verify checks.
`mac/` has Brewfile, setup.sh, ssh/, ghostty/; `mise run mac:sync`.

Live box: `make provision STEPS="home tools verify"` green, 50 mise tools
current, `home/install.sh --check box` no drift, 6 Remote Control units
active. Originals moved to `~/.config/workbench/backup-20260819T003951Z/`
on the box. Snapshot `pre-phase2` exists on the PVE host.

## Operator seat

Sessions run from `devbox` (the dotfiles container) until phase 6: it has
ssh to the Proxmox host (`pve-vm-ssh`, Tailscale SSH - may ask for a
browser re-auth) and to the box (`agent-vm-ssh`), shellcheck 0.11 and shfmt
3.13 via mise, so `make lint`, `provision`, `snapshot`, `rollback` all work
there. The mac steps (`mac/setup.sh`) need a session on the laptop.

## Next

1. On the mac, with `~/work/workbench` cloned: `DRY_RUN=1 mac/setup.sh`,
   then `mac/setup.sh`, then a second `mac/setup.sh` that changes nothing;
   `ls -la ~/.claude/settings.json` is a regular file equal to
   base+mac overlay; `home/install.sh --check mac` no drift. Fix what
   breaks (assumptions marked in mac/setup.sh: mise on PATH after the
   standalone install, `brew bundle cleanup` subcommand form). Then mark
   phase 2 done and start phase 3 (agents/ from ai-hub runtime;
   `step_aihub` becomes links inside `home/install.sh`).
2. Backlog from this session: zsh plugins (autosuggestions,
   syntax-highlighting) are referenced by `.zshrc` but nothing installs
   `~/.local/share/zsh-plugins` on either profile (phase 4); omp prompts
   (WATCHDOG.md, skills) still describe the dotfiles/container workflow and
   want a content pass in phase 4; `providers/proxmox/README.md` sizing
   notes (phase 1 leftover).

## Open questions

- none open; nvim/zellij (box only) and the statusline (one script, both
  repos had the same) were decided in phase 2.

## Backlog (not scheduled)

- `home/install.sh --check` as a `verify` sub-step on the box.
- mise lockfile for the mac profile (see docs/reference/mise-2026.md).
- Weekly `mise up` report as a systemd timer, opt-in.
- Cloud provider test (Hetzner or equivalent) once phase 5 OrbStack passes.

## Log

- 2026-08-18: repo created locally; AGENTS.md, CLAUDE.md, PLAN.md, README,
  docs 00-02 drafted from a survey of agent-vm, dotfiles, ai-hub. Decisions:
  new repo `workbench`, box is VM-only (container target dropped), user
  `agent`, bash, two profiles, settings composed by overlay, ai-hub keeps
  only doctrine/lab/journal. mise researched; profiles = MISE_ENV +
  config.<profile>.toml (verified on 2026.8.8). Review round 1: D1 clean
  start, D5 zsh hand-off, documents rewritten for a public repository.
- 2026-08-19: first commit, repository published (public), Remote Control
  environment `workbench` added. Phase 0 done, phase 1 active.
- 2026-08-19: phase 1 executed. Path changes: rsync staging dir on the box
  is `~/workbench-box/` (was `~/agent-vm-provision/`), on the PVE host
  `/root/workbench/providers/proxmox/` (was `/root/agent-vm/`), Makefile
  gained `PROVIDER ?= proxmox` used only by `vm-create`; `create-vm.sh`
  reads `user-data.yaml` from its own directory. `box/remotes.list` gained
  `workbench` (already registered on the live box in phase 0, so
  `remote-ls` is unchanged; a rebuild now reproduces it). SC2015 in
  `step_system` (`pro config`) rewritten as `if`, same behaviour; it failed
  `make lint` in agent-vm too with shellcheck 0.9.0. Acceptance: `make lint`
  green; `bootstrap.sh user verify` run on the box itself (the session ran
  inside the VM, where the `agent-vm-ssh` alias does not resolve, so the
  rsync + sudo steps of `make provision` were executed by hand with the
  same arguments) - output identical to agent-vm's run except the expected
  `updated /etc/claude-code/CLAUDE.md`; `remote-ls` unchanged (6 units
  active). Not done: `providers/proxmox/README.md` sizing notes from
  agent-vm `docs/design.md` (source map row, not a phase 1 step).
- 2026-08-19: phase 1 committed and pushed (5f47c7e). Operator seat moves
  to devbox (has Proxmox ssh); the in-box session ends here.
- 2026-08-19: phase 1 literal acceptance from devbox: `make provision
  STEPS="user verify"` green, `remote-ls` 6 units; snapshot `pre-phase2`
  (VM 105). Phase 2 executed in eleven commits (8325835..aaa5925): step 1
  install.sh; step 2 merges (mise, git, opwith/op-env, Claude settings,
  statusline, shell layer, herdr/agy/omp/nvim/zellij); step 3 bootstrap
  `step_home`; step 4 mac/. Decisions taken in passing: pull.ff=only over
  pull.rebase; core.pager and color.ui=never dropped from the shared
  gitconfig (env handles the agent path); node pinned to major 24; uv
  backend pin dropped (registry fixed); nvim/zellij box-only; agy settings
  composed with `~` expansion in path lists; MISE_ENV via generated
  `~/.config/workbench/env`. Two live findings fixed in step 3: mise must
  run under the agent's login shell (else only the base 18 tools install)
  and needs GITHUB_TOKEN (anonymous API limit hit at 49 tools) - both in
  `step_tools` now. Box acceptance green; mac acceptance pending.
