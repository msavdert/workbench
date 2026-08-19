# PLAN.md - live state

This file is the handoff between sessions. Update `Now`, `Next` and `Log`
before ending a session. Phases are defined in `docs/02-migration.md`.

## Phases

| # | Phase | Status |
|---|---|---|
| 0 | Founding documents | in progress |
| 1 | Move agent-vm in, unchanged behaviour | not started |
| 2 | home/ and mac/ | not started |
| 3 | agents/ (from ai-hub runtime) | not started |
| 4 | Human layer, herdr/agy/aws-cli, plugins | not started |
| 5 | Portability proof (OrbStack, cloud) | not started |
| 6 | Retire agent-vm, dotfiles, devbox | not started |

## Now

Phase 0. Documents drafted in `~/work/workbench` on the box, not committed,
not yet published. `docs/00-vision.md` reviewed once: D1 changed to a clean
start (no history import), D5 changed to allow a zsh hand-off for
interactive terminals; all other decisions accepted.

## Next

1. On explicit approval: first commit, `opwith git gh repo create
   msavdert/workbench --public` (the repository is written to be public;
   nothing in it may ever depend on being private), push, then
   `remote-add workbench https://github.com/msavdert/workbench.git`.
2. Then phase 1.

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
