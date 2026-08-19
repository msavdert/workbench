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

Phase 1 is done: agent-vm's `provision/`, `pve/`, `cloud-init/`, `Makefile`
live here as `box/`, `providers/proxmox/`, `Makefile` (files, not history).
`box/bootstrap.sh` is byte-identical to agent-vm's except for comments and
one shellcheck fix; the box is now provisioned from this repository
(`/etc/claude-code/CLAUDE.md` comes from `box/files/machine-CLAUDE.md`).
`docs/03-runbook.md` exists. Phase 2 is active; nothing of it exists yet.
`~/work/agent-vm` and the `dotfiles` clone remain the read-only sources.
Still in `box/files/` although the source map sends them to `home/`:
mise.toml, gitconfig, opwith, claude-settings.json, claude-statusline.sh,
`box/op-env/` - they move in phase 2 step 3.

## Operator seat

Sessions run from `devbox` (the dotfiles container) until phase 6: it has
ssh to the Proxmox host (`pve-vm-ssh`) and to the box (`agent-vm-ssh`), so
`make provision`, `snapshot`, `rollback` and `vm-create` work from there.
A session inside the box itself cannot reach the host and cannot run
`make provision` literally (no ssh alias); it can only run
`sudo box/bootstrap.sh <steps>` locally. Verify tooling on devbox first
(`make lint` needs shellcheck and shfmt - unconfirmed there).

## Next

1. From devbox: `make provision STEPS="user verify"` - the literal phase 1
   acceptance run (so far only executed by hand inside the box), then
   `make snapshot NAME=pre-phase2` (owner's call).
2. Phase 2, step 1: `home/install.sh <profile>` - per-file symlinks, jq
   merge for Claude settings, idempotent, `--check`. Then step 2, one merge
   per commit (mise, gitconfig, opwith, settings, statusline).

## Open questions

- nvim / zellij: keep under `home/` for both profiles, or drop? (phase 2)
- Which statusline survives, agent-vm's or dotfiles'? (phase 2)

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
