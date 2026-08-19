# AGENTS.md - instructions for AI agents working in this repository

This repository is maintained largely by AI coding agents (Claude Code,
herdr-driven harnesses, omp) on behalf of its operator. It is the single
source of truth for the operator's working environment: a thin macOS client
and one Ubuntu VM ("the box") where agents run and the operator works.
`README.md` is the map, `docs/` holds the decisions, `PLAN.md` holds the
current state of work and the handoff between sessions.

## Start of every session

1. Read `PLAN.md`. It names the active phase, the next concrete action, and
   what the previous session left behind.
2. Read the document that governs what you are about to touch:
   `docs/00-vision.md` before questioning a decision,
   `docs/01-architecture.md` before adding or moving a file,
   `docs/02-migration.md` before doing phase work,
   `docs/03-runbook.md` before touching a live machine.
3. Do not re-derive decisions recorded in `docs/00-vision.md`. If one is
   wrong, change the document in the same commit as the code and say why.

## Hard rules

1. Never write a secret into this repository, a log, or a commit message.
   Secrets are `op://` references resolved at run time. Before committing,
   grep the diff for `ops_`, `ghp_`, `sk-`, `-----BEGIN`.
2. Machines are changed through this repository, never by hand. A hand fix
   is drift until it is encoded in `box/` or `home/` and re-applied.
3. Idempotency is a requirement. Every provisioning step and
   `home/install.sh` must be safe to re-run on an already-provisioned
   machine.
4. One source per setting. If a file exists under `home/`, it does not also
   exist under `box/files/`, and vice versa. Consult the ownership table in
   `docs/01-architecture.md` before creating a file.
5. Documentation moves with code, in the same change: decisions in
   `docs/00-vision.md`, layout and ownership in `docs/01-architecture.md`,
   procedures in `docs/03-runbook.md`, progress in `PLAN.md`.
6. Never commit or push unless explicitly asked. Never commit a red tree:
   `make lint` must pass.
7. No emoji anywhere in the repository. Comments explain why, not what.
8. Reboots, VM resizes, snapshots, rollbacks and anything on a hypervisor
   host require explicit approval.
9. Nothing from the interactive human shell (zsh, starship, eza, fzf, ...)
   may become reachable from the non-interactive path. Agent-spawned shells
   stay plain: no colour, no pager, no aliases that change output shape.

## Conventions

- Bash 5 on the box; scripts that also run on the mac (`home/install.sh`,
  `home/bin/*`, `mac/setup.sh`) stay bash 3.2 compatible because macOS ships
  Apple's frozen 3.2 and this repository does not install another bash
  (no associative arrays, `mapfile`, `${x,,}`). `set -euo pipefail`,
  functions over inline blocks, 2-space indent, shellcheck and shfmt clean.
- OS packages: apt, in `box/bootstrap.sh` `step_apt`. User tools: mise, in
  `home/mise/`. Claude Code: native installer. See `docs/00-vision.md` D7
  before moving a tool between layers.
- Commit messages: imperative subject, body says why. One topic per commit.
- Repository language is English.

## Phase work protocol

- Work on the phase `PLAN.md` marks as active. Do not start the next phase
  in the same change.
- A phase is done when every item of its acceptance list in
  `docs/02-migration.md` has been executed and its output reported, not
  described.
- Before ending a session, update `PLAN.md`: `Now` (state), `Next` (the one
  concrete action), and one dated line in `Log`. This is the handoff; there
  is no other memory between sessions.

## Related repositories

- `ai-hub` - doctrine, experiments and journal about working with AI. Its
  runtime artifacts (global CLAUDE.md, agents, skills, hooks) move here in
  phase 3; after that `ai-hub` holds no configuration.
- `agent-vm` and `dotfiles` - the predecessors this repository replaces.
  Read-only references during the migration; archived at the end (phase 6).
