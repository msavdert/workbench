# PLAN.md - live state

This file is the handoff between sessions. Update `Now`, `Next` and `Log`
before ending a session. Phases are defined in `docs/02-migration.md`.

## Phases

| # | Phase | Status |
|---|---|---|
| 0 | Founding documents | done |
| 1 | Move agent-vm in, unchanged behaviour | done |
| 2 | home/ and mac/ | done |
| 3 | agents/ (from ai-hub runtime) | active |
| 4 | Human layer, herdr/agy/aws-cli, plugins | not started |
| 5 | Portability proof (OrbStack, cloud) | not started |
| 6 | Retire agent-vm, dotfiles, devbox | not started |

## Now

Phase 2 is done on both profiles. Box: `make provision STEPS="home tools
verify"` green, `home/install.sh --check box` no drift. Mac (2026-08-19,
session on the laptop): `mac/setup.sh` run three times - the first moved
27 dotfiles links plus the agy settings file into
`~/.config/workbench/backup-20260819T005304Z/` (and `...05Z/`, see the
BACKUP_DIR fix), the second installed the tools after the bun fix, the
third changed nothing (brew "Using ...", `mise all tools are installed`,
every link `ok`). `home/install.sh --check mac` no drift;
`~/.claude/settings.json` is a regular file equal to `base * mac` (jq);
a fresh `zsh -il` has MISE_ENV=mac, starship, opwith, gh, shfmt, bun, omp,
op from mise. `make lint` green on the mac. Snapshot `pre-phase2` still on
the PVE host; the mac originals are the two backup dirs above.

Phase 3 has not started; nothing under `agents/` yet.

## Operator seat

Sessions run from `devbox` (the dotfiles container) or the mac; the mac now
has shellcheck 0.11 and shfmt 3.13 from mise so `make lint` works there
too. Box work (`provision`, `snapshot`, `rollback`) needs the Proxmox ssh
that devbox has (`pve-vm-ssh`, Tailscale SSH); the mac reaches the box
via `agent-vm-ssh` in `~/.ssh/config.local` once `mise run ssh:sync` has
run.

## Next

1. Phase 3 step 1: move ai-hub `runtime/` into `agents/` and link it from
   `home/install.sh` (`~/.claude/CLAUDE.md`, agents, skills, hooks resolve
   into `~/work/workbench/agents/`; `step_aihub` in `box/bootstrap.sh`
   becomes those links). Read ai-hub `install.sh` first to get the exact
   target list, then `docs/02-migration.md` phase 3 acceptance.
2. Decisions left from the mac acceptance, not blocking: `op` exists twice
   on the mac (brew cask `1password-cli` from mac/Brewfile and mise
   `1password-cli` from home/mise/config.toml; mise wins on PATH). Whether
   the 1Password app integration (Touch ID) works with a non-brew `op` was
   not verified - pick one owner. macOS runs the scripts under Apple's
   bash 3.2 (no brew bash); they use no bash 4+ features today, AGENTS.md
   says "Bash 5" - either add `brew "bash"` or note 3.2 compatibility as a
   constraint. mise self-update on the mac (2026.7.18 vs 2026.8.8) is not
   done by mac/setup.sh.
3. Backlog from phase 2: zsh plugins (autosuggestions,
   syntax-highlighting) are referenced by `.zshrc` but nothing installs
   `~/.local/share/zsh-plugins` on either profile (phase 4); omp prompts
   (WATCHDOG.md, skills) still describe the dotfiles/container workflow and
   want a content pass in phase 4; `providers/proxmox/README.md` sizing
   notes (phase 1 leftover); `DRY_RUN=1 mac/setup.sh` does not say what is
   currently at each target (link, file, missing).

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
