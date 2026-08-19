# PLAN.md - live state

This file is the handoff between sessions. Update `Now`, `Next` and `Log`
before ending a session. Phases are defined in `docs/02-migration.md`.

## Phases

| # | Phase | Status |
|---|---|---|
| 0 | Founding documents | done |
| 1 | Move agent-vm in, unchanged behaviour | done |
| 2 | home/ and mac/ | done |
| 3 | agents/ (from ai-hub runtime) | done |
| 4 | Human layer, herdr/agy/aws-cli, plugins | active |
| 5 | Portability proof (OrbStack, cloud) | not started |
| 6 | Retire agent-vm, dotfiles, devbox | not started |

## Now

Phases 2 and 3 are done on both profiles. `agents/` holds what was ai-hub
`runtime/` (CLAUDE.md, agents/, skills/, hooks/, templates/, overnight/);
`home/install.sh` links `~/.claude/CLAUDE.md`, `~/.claude/agents`,
`~/.claude/skills/omp-fleet`, `~/.claude/omp-delegate.yml` and
`~/.claude/hooks/boundary-gate.sh` from it on both profiles and self-checks
the gate in every mode (registered in settings.base.json, blocks a forced
push, allows a plain push). `box/bootstrap.sh` has no `step_aihub` any
more; the box got the links through `make provision STEPS="home verify"`
(green, run from the mac on 2026-08-19; links resolve into
`/home/agent/work/workbench/agents/`, `--check box` no drift). ai-hub
(fc2e4e2) has no `runtime/`, `install.sh` or `.claude/skills`; its README,
CLAUDE.md and two doctrine lines point at `workbench/agents/`.

Mac state: `CLEANUP=1 mac/setup.sh` removed the `1password-cli` cask (op is
mise's, Touch ID confirmed by the operator); mise 2026.8.8 via the new
self-update step; `home/claude/settings.mac.json` carries the `autoMode`
block that `/auto-mode-setup` had written into the live settings.json.
Backups on the mac: `~/.config/workbench/backup-20260819T0053*Z/` (phase 2)
and `backup-20260819T010842Z/` (phase 3); on the box
`backup-20260819T011158Z/`.

Phase 4 has not started.

## Operator seat

Sessions run from the mac (`~/work/workbench`) or devbox. The mac reaches
the box directly (`agent-vm-ssh` in `~/.ssh/config.local`, 1Password SSH
agent), so `make provision`, `make ssh` and `home/install.sh --check`
over ssh work from the laptop; `make lint` works there (shellcheck, shfmt
from mise). Snapshots and rollbacks still need the Proxmox ssh that devbox
has (`pve-vm-ssh`, Tailscale SSH).

## Next

1. Phase 4 step 1: `home/bash/interactive.sh` hand-off audit - confirm on
   the box that `bash -c 'alias; echo $SHELL $PS1'`, an ssh command without
   a TTY, `docker exec` and a Claude Code shell-tool call all see the plain
   path, and an interactive `ssh` gets zsh + starship (D5). Then step 2:
   `home/mise/config.box.toml` herdr/agy/aws-cli, `mise run
   herdr:integrations`; step 3: plugins in `settings.base.json` (verify key
   names first). Acceptance list in `docs/02-migration.md` phase 4.
2. Leftovers, not blocking: `~/Documents/all/github/knowledge/.claude/skills`
   on the mac links to `/home/dev/work/ai-hub/runtime/claude/skills` (a
   devbox path, dangling since before this migration) - repoint to
   `~/work/workbench/agents/skills` when the knowledge repo is next
   touched; ai-hub `lab/` records still say `runtime/` (history, left as
   is). Backlog from phase 2: zsh plugins (autosuggestions,
   syntax-highlighting) referenced by `.zshrc` but installed by nothing
   (phase 4); omp prompts (WATCHDOG.md, skills) still describe the
   dotfiles/container workflow (phase 4); `providers/proxmox/README.md`
   sizing notes; `DRY_RUN=1 mac/setup.sh` does not say what is currently
   at each target.

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
- 2026-08-19: phase 2 mac acceptance from the laptop. Three fixes: mise
  `bun` moved from config.box.toml to config.toml (the npm backend is set
  to bun in the base settings and omp is a base tool, so the mac install
  of omp failed without it); `home/install.sh log()` printed `\~/` instead
  of `~/`; `BACKUP_DIR` is now shared between mac/setup.sh and
  home/install.sh (was two dirs one second apart). Findings: `brew bundle
  cleanup` proposed only cache files, no packages (fd/fzf/gh/... brew
  copies were already gone); Apple bash 3.2 runs the scripts fine. Phase 2
  done, phase 3 active.
- 2026-08-19: phase 3 executed from the mac in one workbench commit
  (c14838c) plus ai-hub fc2e4e2. `home/install.sh` grew `link_agents` and
  `verify_gate` (the gate blocked this session's own edit command because
  the literal forced-push string appeared in it - the check works). Also:
  AGENTS.md now states bash 3.2 compatibility for scripts shared with the
  mac (macOS updates never move Apple's bash; no brew bash added);
  `mac/setup.sh` runs `mise self-update --yes`; the `1password-cli` cask
  left the Brewfile and the laptop; `autoMode` block kept in
  settings.mac.json. Phase 3 done, phase 4 active.
