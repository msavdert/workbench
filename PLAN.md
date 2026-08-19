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
| 4 | Human layer, herdr/agy/aws-cli, plugins | done |
| 5 | Portability proof (OrbStack, cloud) | active |
| 6 | Retire agent-vm, dotfiles, devbox | not started |

## Now

Phases 2-4 are done on both profiles. Phase 4 findings, all fixed and
applied on the box (`make provision STEPS="home tools verify"` green,
`--check box` no drift) and on the mac: the completion/init cache was
never generated on the box and `~/.local/share/zsh-plugins` existed
nowhere (`home/zsh/install-plugins.sh`, run by mac/setup.sh and
step_tools, `mise run zsh:plugins`); `herdr integration install claude`
appends its own SessionStart hook to the composed settings.json (the
`herdr:integrations` task now ends with `home/install.sh <profile>`;
mise tasks run under dash on the box, so `set -eu` only); Claude Code
plugin keys verified (`enabledPlugins`, `extraKnownMarketplaces`),
`mise run claude:plugins` installs what the settings enable (nothing
today); `.zshenv` no longer exports `CLAUDE_CONFIG_DIR` (a devbox
Docker-volume leftover that gave the box two Claude identities: bash saw
`~/.claude.json`, zsh saw `~/.claude/.claude.json` and a login screen);
`theme: dark` in the box overlay (Claude wrote it during that onboarding).

Measured on the box: `ssh host cmd`, `bash -c`, `bash -lc`, `docker run`
all plain (PS1 empty, 0 aliases, NO_COLOR=1); `bash -ic` stays bash; a TTY
login is zsh 5.9 with starship, fzf widget, autosuggestions,
syntax-highlighting, zoxide, `$SHELL` still `/bin/bash`. herdr (0.8.0,
started headless in tmux, driven over its socket API: workspace create,
pane split, agent start/prompt/wait/read) ran claude and omp in two panes
on a scratch repo and both answered a prompt; omp's Synthetic key comes
from its agent.db, `mise run omp:auth` was not needed. `mise ls
--current --missing` empty on the box.

Phase 5 has not started; `providers/orbstack/` and `providers/cloud/` do
not exist yet.

## Operator seat

Sessions run from the mac (`~/work/workbench`) or devbox. The mac reaches
the box directly (`agent-vm-ssh` in `~/.ssh/config.local`, 1Password SSH
agent), so `make provision`, `make ssh` and `home/install.sh --check`
over ssh work from the laptop; `make lint` works there (shellcheck, shfmt
from mise). Snapshots and rollbacks still need the Proxmox ssh that devbox
has (`pve-vm-ssh`, Tailscale SSH).

## Next

1. Phase 5 step 1: `providers/orbstack/` - create an OrbStack Ubuntu 24.04
   VM on the mac (OrbStack is in mac/Brewfile), run `make bootstrap-all
   PROVIDER=orbstack`, then `bootstrap.sh verify` with no provider-specific
   step and a Remote Control environment from it. Read
   `docs/01-architecture.md` "A provider must deliver" and
   `providers/proxmox/` first; the operator's question "is a from-scratch
   rebuild tested" is answered by this phase, not by destroying the
   Proxmox VM (rule 8; not planned).
2. Nothing pending from phase 4: `omp:auth` works (Synthetic API
   Credential created in the dotfiles vault; the mac's `~/.claude.json` is
   the merged file, originals in
   `~/.config/workbench/backup-claudejson-20260819T012830Z/`).
3. Leftovers, not blocking: `~/Documents/all/github/knowledge/.claude/skills`
   on the mac links to a devbox path (repoint to
   `~/work/workbench/agents/skills`); ai-hub `lab/` records still say
   `runtime/` (history); omp prompts (WATCHDOG.md, skills) still describe
   the dotfiles/container workflow; `providers/proxmox/README.md` sizing
   notes; `DRY_RUN=1 mac/setup.sh` does not say what is currently at each
   target; the phase 4 "Remote Control session shows the plain shell"
   item was measured by shape (`bash -c` under the agent's environment),
   not from inside a live Remote Control session.

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
- 2026-08-19: phase 4 executed from the mac (9ecfd4c..5315e16). Commit
  split note: 9ecfd4c carries all three new mise tasks (zsh:plugins,
  claude:plugins, herdr:integrations rewrite) because the hunks were
  adjacent; 2545a93 is the D12 text only. Phase 4 done, phase 5 active.
- 2026-08-19: session end. omp:auth verified on the box after the Synthetic
  item was recreated as an API Credential in the dotfiles vault (op item
  move refused the original: unsupported SSO field type); merged
  ~/.claude.json installed on the mac. Next session starts phase 5.
