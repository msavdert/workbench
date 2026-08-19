# 02 - Migration from agent-vm, dotfiles, ai-hub

Status: complete (2026-08-19). Kept as the record of what moved where;
`PLAN.md` tracks current work.

Ground rules for every phase:

- The live box (built by `agent-vm` on Proxmox until phase 1) keeps working
  throughout. Each phase ends with `make provision` green and `verify`
  passing.
- Snapshot before phases that touch the box: `make snapshot NAME=pre-phaseN`.
- Old repos are read-only references. Nothing is deleted from them until
  phase 6; nothing new is added to them after phase 1 starts.
- Nothing is committed or pushed without explicit approval. Push before any
  risky box operation: a rollback to the base snapshot discards `~/work`.

## Source map

Where each thing from the three repos ends up. "drop" means it is retired,
not migrated.

### from agent-vm

| Source | Destination |
|---|---|
| `pve/create-vm.sh`, `pve/vm.env`, `cloud-init/user-data.yaml` | `providers/proxmox/` |
| `provision/bootstrap.sh` | `box/bootstrap.sh` (steps: system apt docker user tools remotes verify; new step `home` calls `home/install.sh box`; `step_aihub` becomes the `agents/` link inside `home/install.sh`) |
| `provision/files/{bashrc,bash_profile,tmux.conf,agent-session}` | `box/files/` (bashrc trimmed to the guard + non-interactive part; interactive part -> `home/bash/`) |
| `provision/files/{docker-daemon.json,docker-prune.*,journald-agent.conf,limits-agent.conf,sysctl-agent.conf,needrestart-agent.conf,sudoers-agent,sshd-agent.conf}` | `box/files/` |
| `provision/files/{claude-remote.service,claude-remote@.service,remote-add,remote-ls,remote-rm}`, `provision/remotes.list` | `box/files/`, `box/remotes.list` |
| `provision/files/machine-CLAUDE.md` | `box/files/machine-CLAUDE.md` (rewritten for the new layout) |
| `provision/files/mise.toml` | merged into `home/mise/config.toml` + `config.box.toml` (dotfiles devbox.toml is the richer base) |
| `provision/files/{gitconfig,opwith}` | `home/git/config`, `home/bin/opwith` (dotfiles versions are the base; diff first) |
| `provision/files/claude-settings.json` | split into `home/claude/settings.base.json` + `settings.box.json` |
| `provision/files/claude-statusline.sh` | `home/claude/statusline.sh` (one statusline; dotfiles has a second one - pick one, keep the other's ideas in git history only) |
| `provision/op-env/*.env` | `home/op-env/` |
| `Makefile` | `Makefile` with `PROVIDER=` |
| `docs/design.md` | decisions folded into `docs/00-vision.md`; sizing/hardware notes into `providers/proxmox/README.md` |
| `docs/runbook.md` | `docs/03-runbook.md` |
| `README.md`, `CLAUDE.md`, `AGENTS.md` | rewritten |

### from dotfiles

| Source | Destination |
|---|---|
| `macos/Brewfile`, `macos/setup.sh` | `mac/` (`link_configs()` becomes `home/install.sh mac`) |
| `configs/mise/macos.toml` | `home/mise/config.mac.toml` (shared parts up to `config.toml`) |
| `configs/mise/devbox.toml` | `home/mise/config.box.toml` (minus container-only tasks; plus agent-vm's list; plus aws-cli) |
| `configs/claude/settings.json`, `statusline.sh` | `home/claude/` (see D8; the two statuslines are compared in phase 2) |
| `configs/herdr/`, `configs/gemini/`, `configs/omp/` | `home/herdr/`, `home/agy/` (settings composed like Claude's), `home/omp/` (minus the devbox-image and vps-deploy skills, retired with the container) |
| `configs/git/`, `configs/op-env/`, `opwith` | `home/git/`, `home/op-env/`, `home/bin/` (merged with agent-vm's) |
| `configs/zsh/`, `configs/starship.toml` | `home/zsh/`, `home/starship.toml`; on the box reached only through the interactive hand-off in `home/bash/interactive.sh` (D5) |
| `configs/ssh/`, `configs/ghostty/` | `mac/ssh/`, `mac/ghostty/` |
| `configs/nvim/`, `configs/zellij/` | `home/nvim/`, `home/zellij/`, linked for the box profile only (decided in phase 2; the mac never had them) |
| `Dockerfile`, `compose.yaml` | drop (D3) |
| `docs/00-08` | decisions with lasting value folded into `docs/00-vision.md`; the rest dropped |

### from ai-hub

| Source | Destination |
|---|---|
| `runtime/claude/CLAUDE.md`, `agents/`, `skills/`, `hooks/` | `agents/` |
| `runtime/project-templates/`, `runtime/overnight/` | `agents/templates/`, `agents/overnight/` |
| `install.sh` | absorbed into `home/install.sh` (same symlink pattern, same boundary-gate self-check) |
| `doctrine/`, `lab/`, `journal/`, README | stay in ai-hub |

## Phases

### Phase 0 - founding documents (this)

Deliverables: `AGENTS.md`, `CLAUDE.md`, `PLAN.md`, `README.md`,
`docs/00-vision.md`, `docs/01-architecture.md`, `docs/02-migration.md`.
Acceptance: `docs/00-vision.md` reviewed and accepted; repository published;
`remote-add workbench` done so app sessions can work in it.

### Phase 1 - move agent-vm in, unchanged behaviour

1. Copy agent-vm's `provision/`, `pve/`, `cloud-init/`, `Makefile` into
   `box/`, `providers/proxmox/`, `Makefile` per the source map (clean start,
   D1: files, not history).
2. Adjust paths in `Makefile` and `bootstrap.sh`; nothing else changes.
3. `box/files/machine-CLAUDE.md` rewritten to point at `~/work/workbench`.
4. `docs/03-runbook.md` written from agent-vm's runbook.
Acceptance: `make lint`; `make provision STEPS="user verify"` against the
live box prints the same result as from agent-vm; `remote-ls` unchanged.
Rollback: the box was not changed in substance; agent-vm still works.

### Phase 2 - home/ and mac/

1. `home/install.sh <profile>`: per-file symlinks, jq merge for Claude
   settings, idempotent, self-verifying (`--check`).
2. Move dotfiles configs per source map; merge the duplicated files
   (mise, gitconfig, opwith, settings, statusline) - each merge is a small
   commit with the diff explained.
3. `box/bootstrap.sh` gains `step_home` (runs `home/install.sh box` as
   `agent`), loses the files it no longer owns.
4. `mac/setup.sh` calls `home/install.sh mac`; `mise run mac:sync` re-pulls
   and re-links.
Acceptance: on the box `make provision STEPS="home tools verify"` green and
`home/install.sh --check box` reports zero drift; on the laptop `mac/setup.sh`
is idempotent (second run changes nothing); `ls -la ~/.claude/settings.json`
is a generated file whose content equals base+overlay.
Rollback: `make rollback NAME=pre-phase2`.

### Phase 3 - agents/

1. Move ai-hub `runtime/` into `agents/`; `home/install.sh` links it.
2. ai-hub: remove `runtime/` and `install.sh`, update its README to point
   here.
Acceptance: `~/.claude/CLAUDE.md`, `agents/`, `skills/omp-fleet`,
`hooks/boundary-gate.sh` resolve into `~/work/workbench/agents/`; the
boundary-gate self-check blocks `git push --force` and allows `git push`.

### Phase 4 - the human layer and parallel harnesses

1. `home/bash/interactive.sh`: colour, then hand-off to zsh with starship,
   eza, fzf, zoxide (`home/zsh/`), guarded by TTY, `TERM != dumb` and an
   opt-out variable. Confirm that `bash -c 'alias; echo $SHELL $PS1'`, an
   ssh command without a TTY, `docker exec`, and a Claude Code shell-tool
   call all see the plain path (this also settles the D5 assumption about
   `$SHELL`).
2. `home/mise/config.box.toml`: herdr, agy, aws-cli, plus what survives from
   devbox.toml. `mise run herdr:integrations`.
3. Claude Code plugins declared in `settings.base.json` (verify the key
   names against current docs first; D12 marks this as an assumption).
Acceptance: an interactive `ssh` shows the rich shell; a Remote Control
session and a `docker exec` shell show the plain one; `herdr`
runs two harnesses in parallel on a scratch repo; `mise ls` matches
`config.toml` + `config.box.toml`.

### Phase 5 - portability proof

1. `providers/orbstack/`: create an OrbStack Ubuntu 24.04 VM, run
   `make bootstrap-all PROVIDER=orbstack`.
2. `providers/cloud/`: cloud-init user-data usable by any Ubuntu cloud
   image; document one tested provider.
Acceptance: `bootstrap.sh verify` passes on OrbStack with no provider-
specific step; a Remote Control environment works from it.

Outcome (operator decision, 2026-08-19): step 1 done, `verify` green on a
from-scratch OrbStack build; the Remote Control item stays open until the
operator does the manual `claude auth login` there. Step 2 skipped: no
cloud account available; `providers/cloud/` stays in the backlog. Phase
closed with those two exceptions.

### Phase 6 - retire

1. Archive `agent-vm` and `dotfiles` on GitHub (read-only, README pointing
   here). Remove `~/work/agent-vm` from `box/remotes.list`.
2. Delete the devbox image references; stop the VPS container if it still
   runs.
Acceptance: `PLAN.md` says "migration complete"; `AGENTS.md` loses its
migration section.

Executed 2026-08-19. Step 1: both repositories archived with a README notice
(agent-vm 3f055ab, dotfiles 87a1c15); `agent-vm` removed from
`box/remotes.list` and from the box (`remote-rm`, clone deleted). Step 2:
container wording removed from `home/` (nvim `devbox.lua` is `box.lua`, omp
skills rewritten); on the VPS the `dotfiles` compose project taken down
with its volumes, the orphan `devbox_*` volumes and the
`ghcr.io/msavdert/devbox` image removed, `/home/opc/dotfiles` deleted.
Left on purpose or open: `/home/opc/devbox` (an older compose dir with a
`.env` token, deletion was blocked in the session; the operator removes it
by hand and rotates that service account), the mac's untracked
`~/.ssh/config.local` `Host dev`/`dev-sh` entries, the ghcr package itself
(needs a `delete:packages` token).

## What could go wrong

- Two statuslines and two settings.json exist; the merge is a judgement
  call. Do it in phase 2 with a written diff, not silently.
- The zsh hand-off (D5) must never trigger for a non-TTY or `TERM=dumb`
  shell; a wrong guard would leak the rich shell into the agent path.
- `home/install.sh` must not symlink `~/.claude` or `~/.gemini` wholesale;
  both hold runtime state and OAuth. Per-file links only.
- OrbStack VMs may differ in systemd user session availability
  (`loginctl enable-linger`) - check in phase 5, unverified today.
- herdr and agy config formats change fast; keep them in `home/` and accept
  churn there rather than in `box/`.
