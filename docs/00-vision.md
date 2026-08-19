# 00 - Vision and decisions

Status: accepted 2026-08-18. Decisions change here first, then in code.

## What workbench is

workbench is a reproducible personal platform for working with AI coding
agents. It builds one Ubuntu virtual machine - "the box" - on any VM
substrate (Proxmox, OrbStack, a cloud provider), and configures a laptop as a
thin client to it. Agents (Claude Code, harnesses driven by herdr, other CLIs)
run inside the box; the operator works inside the same box over ssh. Every
setting that lands on either machine has exactly one origin in this
repository.

## Background

The repository supersedes three earlier ones that grew into each other: an
`agent-vm` repo (a Proxmox VM built for agents that became the daily
development environment), a `dotfiles` repo (macOS client plus a development
container, carrying much of the same user configuration a second time), and
the runtime part of an `ai-hub` repo (originally a place to learn and measure
AI usage, which started to hold harness configuration). The recurring cost
was not the tooling but the ambiguity: every new tool had two plausible
homes, and settings drifted between them. workbench exists to remove that
ambiguity for years, not months.

## Goals

1. The laptop is set up by one script and kept in sync by one task.
2. The box is built identically on any VM substrate: agents run in a plain,
   predictable environment, and the operator has a comfortable interactive
   shell in the same machine.
3. Every configuration item has exactly one source, and the repository
   states which.
4. Idempotent, verifiable, boring: apt, mise, systemd, bash, make.

## Non-goals

- More than one working environment at a time. One box; it may move
  between substrates, it is not multiplied.
- Running the box as a container (D3).
- A general-purpose framework. This is one operator's environment; the
  structure is meant to be copied and adapted, not parameterised.
- Learning notes, experiments and journals about AI usage. Those stay in
  `ai-hub`.

## Principles

- P1 Single source. Every file on a machine has one origin in this repo,
  listed in the ownership table of `docs/01-architecture.md`.
- P2 The substrate only provides "an Ubuntu with ssh". Everything after
  that is the same `box/bootstrap.sh` + `home/install.sh box`, everywhere.
- P3 Agent path and human path are separated by shell mode, not by
  machine. Non-interactive shells (what agents spawn) are plain;
  interactive terminals may be rich. Same user, same box.
- P4 Idempotent and verifiable. Re-running provisioning on a provisioned
  box changes nothing; `verify` proves the state.
- P5 Secrets are never on disk except one 1Password service-account
  token; everything else is an `op://` reference resolved at run time.
- P6 Documentation changes in the same commit as the code it describes. A
  decision without a recorded reason does not exist.
- P7 Boring on purpose. Nothing that needs a framework to explain itself.

## Decisions

D1 One repository, clean start. `workbench` starts from an empty tree and
takes files from the predecessor repositories by hand, per the source map in
`docs/02-migration.md`. Their git history stays readable in the archived
repositories; importing it would carry three incompatible layouts into a
fourth. `ai-hub` remains a separate repository for doctrine, experiments and
journal; its runtime artifacts move here (D9).

D2 One box, VM only, Ubuntu 24.04 LTS. Substrates: Proxmox VM (primary),
OrbStack Linux VM on the laptop, generic cloud VM via cloud-init. An LTS
release is what agent tooling is tested against first, and five years of
support outlive any tool churn.

D3 The box is not a container. Agents constantly need Docker inside the
box; the box needs systemd (Remote Control services, timers) and snapshots.
A container would need Docker-in-Docker or privileged mode and still lack a
proper init: the "same environment everywhere" promise would break at
exactly the layer agents use most. Containers are tools inside the box.

D4 User `agent`, uid 1000, passwordless sudo, member of `docker`. The
operator logs in as the same user (P3). One user keeps Remote Control
units, file ownership and snapshots simple.

D5 Login shell is bash; the interactive terminal may be zsh. `agent`'s
login shell and `$SHELL` stay `/bin/bash` so that systemd units, ssh
commands, `docker exec` and agent tools that consult `$SHELL` all get the
plain path. `box/files/bashrc` returns early for non-interactive shells;
its interactive block sources `home/` configuration and may hand off to
zsh (with starship, eza, fzf, zoxide) when a TTY is attached, `TERM` is not
`dumb`, and the operator has not opted out. Everything rich lives in
`home/`, nothing rich is reachable from the non-interactive path. Whether
Claude Code's shell tool follows `$SHELL` is an assumption verified in
phase 4; the guard is designed so the answer does not matter.

D6 Profiles, exactly two: `mac` and `box`. `home/install.sh <profile>`
links the files for that profile and exports `MISE_ENV=<profile>`. mise
config is `home/mise/config.toml` (shared base) plus `config.<profile>.toml`
(delta), which mise loads natively from `~/.config/mise/` when `MISE_ENV`
is set (verified on mise 2026.8.8, `docs/reference/mise-2026.md`). Mac stays
short; box carries the long list. A third profile needs a new decision.

D7 Tool layering inside the box: apt owns the OS layer (Docker, ssh, build
tools, diagnostics); mise owns user tools and runtimes (node, go, uv, gh,
1password-cli, herdr, agy, aws-cli, omp, ...); Claude Code uses its native
installer and self-updates. apt for what needs root and rarely changes,
mise for what changes weekly and must be pinnable per profile, the native
installer for the one tool that updates itself faster than any registry.
mise specifics are in `docs/reference/mise-2026.md`.

D8 Claude Code configuration is composed, not copied.
`home/claude/settings.base.json` holds what is true everywhere; a small
profile overlay (`settings.box.json`: bypass permissions for the
unattended box, Remote Control statusline; `settings.mac.json`: interactive
mode) is merged with jq by `home/install.sh`. `~/.claude` is never
symlinked wholesale: it holds runtime state and credentials.

D9 Agent behaviour (global CLAUDE.md, subagents, skills, hooks) lives in
`agents/` and is linked into `~/.claude` by `home/install.sh`. `ai-hub`
keeps doctrine, lab and journal - text a person reads, not files a machine
loads.

D10 Secrets: only the 1Password service-account token is on the box
(`~/.config/op/env`, pushed by `make secrets`). git over HTTPS uses a
credential helper reading `op://`; `gh` runs as `opwith git gh`; other
tools via `opwith <env> <cmd>` with `home/op-env/*.env`. Claude Code and
agy use their own OAuth logins.

D11 Remote Control (Claude app sessions): one shared server, `work`
(`claude-remote.service`, `~/work`, capacity 2). Sessions in it are steered
from the operator's machine, which clones and switches projects on demand,
so per-project servers are optional: `remote-add <name>` starts a
`claude-remote@<name>` unit rooted in `~/work/<name>` when a project needs its
own environment. Repositories that must be present after a rebuild are listed
in `box/remotes.list` (`--clone-only` by default). Requires systemd - one more
reason for D3.

D12 Parallel harnesses: herdr is installed by mise (D7), configured in
`home/herdr/`, and its integrations are applied by a mise task
(`mise run herdr:integrations`) so they are declarative and re-runnable.
Claude Code plugins are declared in `settings.base.json` (`enabledPlugins`,
`extraKnownMarketplaces`; verified 2026-08-19) and installed by `mise run
claude:plugins`, not by hand; declaring alone does not install them. None
is enabled today. A harness config file that the harness itself writes is
generated by `home/install.sh`, never symlinked: agy's `settings.json` and
omp's `config.yml` both qualify, and both are compared by meaning rather than
bytes so the harness reformatting its own file is not drift.

D13 Repository language is English; commits are imperative, one topic
each; no emoji; comments say why, not what.

## Known differences between substrates (accepted, documented)

- Snapshots: Proxmox has ZFS snapshots and `make snapshot` / `make rollback`;
  OrbStack and cloud VMs have their own mechanisms or none.
  `docs/03-runbook.md` states per substrate what "roll back" means.
- Networking: the Proxmox box is reachable only over a private overlay
  network; OrbStack is local; a cloud VM needs a firewall or the same
  overlay. Documented as an expectation, not automated here.
- Sizing: 4 vCPU / 32 GB / 200 GB is the reference; smaller substrates work
  with fewer parallel harnesses (OrbStack: 4 / 8 GB / 100 GB caps, thin).
- OrbStack machines are not full VMs: `systemd-detect-virt` says `lxc`, the
  kernel is OrbStack's shared one, `agent` gets the mac uid (501), the mac
  home is mounted at `/mnt/mac`, and OrbStack's own `ssh agent-vm@orb`
  path exists next to sshd on port 22. systemd, Docker, swap and
  `bootstrap.sh verify` all work unchanged (measured 2026-08-19, arm64).
