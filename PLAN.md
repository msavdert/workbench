# PLAN.md - live state

This file is the handoff between sessions. Update `Now`, `Next` and `Log`
before ending a session. Phases are defined in `docs/02-migration.md`.

## Phases

| # | Phase | Status |
|---|---|---|
| 0 | Founding documents | done |
| 1 | Move agent-vm in, unchanged behaviour | active |
| 2 | home/ and mac/ | not started |
| 3 | agents/ (from ai-hub runtime) | not started |
| 4 | Human layer, herdr/agy/aws-cli, plugins | not started |
| 5 | Portability proof (OrbStack, cloud) | not started |
| 6 | Retire agent-vm, dotfiles, devbox | not started |

## Now

Phase 1 is active; nothing of it exists yet. Phase 0 is complete: the
repository is published at https://github.com/msavdert/workbench and
registered as Remote Control environment `workbench`. The live box is still
built by `agent-vm`; `~/work/agent-vm` and the `dotfiles` clone are the
read-only sources for the source map in `docs/02-migration.md`.

## Next

1. Phase 1, step 1: copy agent-vm's `provision/`, `pve/`, `cloud-init/`,
   `Makefile` into `box/`, `providers/proxmox/`, `Makefile` per the source
   map. Behaviour must not change.
2. Adjust paths; `make lint` green; `make provision STEPS="user verify"`
   against the live box; `remote-ls` unchanged.
3. Update this file, then stop and ask before committing.

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
