# 01 - Architecture

Status: target layout. `PLAN.md` says how much of it exists today.

## Four planes

| Plane | Directory | Runs where | Owns |
|---|---|---|---|
| Client | `mac/` | the laptop | Brewfile, `setup.sh`, terminal and ssh client config, 1Password SSH agent |
| Box | `box/` | inside the VM, as root | apt packages, Docker daemon, sysctl/limits/journald, sshd, sudoers, systemd units (Remote Control, prune timer), `/etc/claude-code/CLAUDE.md`, the plain agent bashrc guard |
| Home | `home/` | inside the VM and on the laptop, as the user | mise config per profile, interactive shell (bash block, zsh, starship), git config, `opwith` + `op-env`, Claude Code settings, herdr / agy / omp config, aws config, statusline |
| Agents | `agents/` | linked into `~/.claude` | global CLAUDE.md, subagents, skills, hooks |

Plus:

| Directory | Purpose |
|---|---|
| `providers/proxmox/` | `create-vm.sh`, `vm.env`, cloud-init: create the box on the Proxmox host |
| `providers/orbstack/` | create the box as an OrbStack Linux VM on the laptop |
| `providers/cloud/` | generic cloud-init user-data for any Ubuntu cloud image |
| `docs/` | 00 vision, 01 architecture, 02 migration, 03 runbook |
| `Makefile` | operator surface (run from the laptop) |
| `PLAN.md` | live state of the migration and the handoff between sessions |

## Layout

```
workbench/
  AGENTS.md  CLAUDE.md (-> @AGENTS.md)  PLAN.md  README.md  Makefile
  mac/
    Brewfile  setup.sh  ghostty/  ssh/
  box/
    bootstrap.sh            idempotent, root, step_<name> functions, STEPS list
    files/                  exact files that land on the box (put <mode> <src> <dst>)
    remotes.list            Remote Control environments that survive a rebuild
  home/
    install.sh <profile>    idempotent per-file symlinks + settings merge
    mise/config.toml  mise/config.mac.toml  mise/config.box.toml  (tasks inline)
    bash/interactive.sh     interactive-only block sourced by the box bashrc; hands off to zsh
    zsh/  starship.toml     rich interactive shell, both profiles
    git/  op-env/  bin/opwith
    claude/settings.base.json  settings.box.json  settings.mac.json  statusline.sh
    herdr/  agy/  omp/  aws/  nvim/  zellij/
  agents/
    CLAUDE.md  agents/  skills/  hooks/  templates/  overnight/
  providers/
    proxmox/  orbstack/  cloud/
  docs/
```

## Ownership table (single source, P1)

| File on the machine | Origin in repo | Installed by |
|---|---|---|
| `/etc/apt`, `/etc/docker/daemon.json`, `/etc/sysctl.d/*`, `/etc/ssh/sshd_config.d/*`, `/etc/sudoers.d/*` | `box/files/` | `box/bootstrap.sh` |
| `~/.config/systemd/user/claude-remote*.service`, `~/.local/bin/remote-*` | `box/files/` | `box/bootstrap.sh` |
| `/etc/claude-code/CLAUDE.md` | `box/files/machine-CLAUDE.md` | `box/bootstrap.sh` |
| `~/.bashrc` (guard + non-interactive part) | `box/files/bashrc` | `box/bootstrap.sh` |
| `~/.config/bash/interactive.sh`, `~/.zshrc`, `~/.zshenv`, `~/.config/starship.toml` | `home/bash/`, `home/zsh/`, `home/starship.toml` | `home/install.sh` |
| `~/.config/mise/config.toml`, `config.<profile>.toml` | `home/mise/` | `home/install.sh <profile>` |
| `~/.config/workbench/env` (`MISE_ENV`, `WORKBENCH_PROFILE`; sourced by the box bashrc and by `.zshenv`) | generated | `home/install.sh <profile>` |
| `~/.gitconfig`, `~/.config/op-env/*`, `~/.local/bin/opwith` | `home/git/`, `home/op-env/`, `home/bin/` | `home/install.sh` |
| `~/.claude/settings.json` | `home/claude/settings.base.json` + overlay | `home/install.sh` (jq merge) |
| `~/.claude/statusline.sh` | `home/claude/statusline.sh` | `home/install.sh` |
| `~/.config/herdr/config.toml`, `~/.gemini/antigravity-cli/statusline.sh`, `~/.omp/agent/*` (per file), `~/.aws/config` | `home/herdr/ agy/ omp/ aws/` | `home/install.sh` |
| `~/.gemini/antigravity-cli/settings.json` | `home/agy/settings.base.json` + overlay | `home/install.sh` (jq merge, `~` in path lists expanded) |
| `~/.config/nvim`, `~/.config/zellij` (box only) | `home/nvim/`, `home/zellij/` | `home/install.sh box` |
| `~/.claude/CLAUDE.md`, `~/.claude/agents/`, `~/.claude/skills/omp-fleet`, `~/.claude/omp-delegate.yml`, `~/.claude/hooks/boundary-gate.sh` | `agents/` | `home/install.sh` (links, both profiles; the gate self-check runs in every mode) |
| `~/.ssh/config`, `~/.ssh/config.macos`, `~/.config/ghostty/config` (mac only) | `mac/ssh/`, `mac/ghostty/` | `mac/setup.sh` |
| `~/.config/op/env` (the token) | not in repo | `make secrets` |
| `~/.claude.json`, `~/.claude/*.jsonl`, sessions, credentials | runtime state, not in repo | the tools themselves |

Rule of thumb: if root writes it, `box/`; if the user writes it and it is not
agent behaviour, `home/`; if it changes how an agent thinks, `agents/`.

`home/install.sh` has two kinds of target: links (a `$HOME` path is a
symlink into `home/`) and generated files (`~/.claude/settings.json`,
`~/.config/workbench/env`), rewritten only when their content differs. It
never links a whole dotdir (`~/.claude`, `~/.omp/agent`, `~/.gemini` hold
runtime state). A regular file in the way is moved to
`~/.config/workbench/backup-<utc>/`, never deleted. `--check` reports drift
and exits 1; `--dry-run` prints without touching. Missing sources are
reported and skipped, so the manifest can be ahead of the tree.

## Layering inside the box (D7)

```
apt        OS, Docker, ssh, build tools, diagnostics          root, changes rarely
mise       runtimes and CLIs incl. herdr, agy, aws-cli, omp   user, per profile, pinnable
native     Claude Code                                        self-updating
```

## Shell modes (P3, D5)

`box/files/bashrc` is installed for the `agent` user. Above the
`case $- in *i*) ;; *) return` guard: `PAGER=cat`, `NO_COLOR`,
`DEBIAN_FRONTEND=noninteractive`, mise shims on PATH. Below the guard, one
line: source `~/.config/bash/interactive.sh` if present. That file comes from
`home/`; it enables colour and, when a TTY is attached, `TERM` is not `dumb`,
bash was not given a `-c` command and `WORKBENCH_PLAIN` is unset, hands off
to zsh (`home/zsh/`) with starship, eza, fzf and zoxide, lifting `NO_COLOR`
and the `cat` pagers first. Both halves source `~/.config/workbench/env`
(`MISE_ENV`): bash above the guard, zsh in `.zshenv`, so agents and humans
get the same mise profile. An agent-spawned shell returns at the guard and sees
none of it; `$SHELL` stays `/bin/bash` (D5). `docker exec` and captured
output stay clean because they have no TTY or run with `TERM=dumb`.

## Profiles (D6)

| | `mac` | `box` |
|---|---|---|
| shell | zsh (starship, eza, fzf, zoxide) | login bash, agent-safe; interactive hand-off to the same zsh |
| mise list | short: gh, jq, fzf, ripgrep, fd, uv, claude-code, agy, herdr, 1password-cli, usage | long: runtimes, LSPs, k8s tooling, herdr, agy, aws-cli, omp, ... |
| Claude settings | base + `settings.mac.json` (auto mode) | base + `settings.box.json` (bypassPermissions, Remote Control) |
| secrets | 1Password app + SSH agent | service-account token in `~/.config/op/env` |

## Providers contract (P2)

A provider must deliver: Ubuntu 24.04 cloud image, user `agent` uid 1000 with
the operator's ssh key and passwordless sudo, ssh reachable, qemu-guest-agent or
equivalent, hostname set. Nothing else. `make provision` then runs
`box/bootstrap.sh` over ssh, which ends with `home/install.sh box` and the
`agents/` links, then `verify`.

## Operator surface (Makefile, run on the laptop)

Carried over from agent-vm and generalised by `PROVIDER=proxmox|orbstack|cloud`:
`vm-create`, `vm-wait`, `vm-status`, `secrets`, `provision [STEPS=...]`,
`bootstrap-all`, `remote-add/ls/rm`, `snapshot`/`rollback`/`snapshots`
(Proxmox only), `ssh`, `lint`, and `mac-setup` / `mac-sync` for the client.
