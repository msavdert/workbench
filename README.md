# workbench

[![lint](https://github.com/msavdert/workbench/actions/workflows/lint.yml/badge.svg)](https://github.com/msavdert/workbench/actions/workflows/lint.yml)

A reproducible development platform for one engineer working with AI coding
agents: one Ubuntu VM ("the box") that is built identically on Proxmox or
OrbStack from an empty hypervisor in about three minutes, plus a thin macOS
client. Agents run in the box; the operator works in the same box over ssh.
Every setting on either machine has exactly one source in this repository,
and the repository can prove it (`home/install.sh --check`).

## Who this is for

This is one operator's environment, published as a worked example of how to
run a development platform as code: idempotent provisioning, drift
detection, secrets by reference, decision records, and a measured
from-scratch rebuild. It is meant to be read and copied, not installed as a
product: paths, hostnames and the tool mix are mine (see
`docs/00-vision.md`, non-goals). If you run agents on a disposable VM and
want the laptop and the VM to stop drifting apart, the structure transfers;
the contents are a starting point.

## What you get

```
mac (thin client)                     the box (Ubuntu VM, one user)
+---------------------------+         +-----------------------------------------+
| Ghostty, zsh, mise        |  ssh    | root:  apt, Docker, sshd, sysctl,       |
| 1Password SSH agent       | ------> |        systemd units, agent guard       |
| make targets (operator)   |         | user:  mise tools, zsh/starship,        |
| mac/setup.sh              |         |        Claude Code + herdr/agy/omp,     |
+---------------------------+         |        ~/work/<repos>                   |
          |                           |        plain shell for agents,          |
          | op:// references          |        rich shell for the operator      |
          v                           +-----------------------------------------+
   1Password (the only place                    ^ one service-account token on disk,
   a secret value lives)                        | everything else resolved per command
                                                |
   Proxmox host or OrbStack: provides an Ubuntu cloud image + ssh, nothing else
```

Inside the box three layers, each with one owner (D7 in the vision):

```
apt        OS, Docker, ssh, build tools, diagnostics          root, changes rarely
mise       runtimes and CLIs incl. herdr, agy, aws-cli, omp   user, per profile, pinnable
native     Claude Code                                        self-updating
```

## Highlights (what to look at if you have ten minutes)

- Idempotent root provisioning with a verify step: `box/bootstrap.sh` is a
  list of converge functions (`step_apt`, `step_docker`, ...) plus
  `step_verify`; `put()` converges content and mode, every step is safe to
  re-run. Checklist: `docs/03-runbook.md`, "Verification checklist".
- Drift detection for user config: `home/install.sh --check` exits non-zero
  when any managed file differs from the repository, compares JSON and YAML
  by meaning (tools rewrite their own files), backs up rather than deletes,
  and knows which keys a tool owns after first install ("seed keys", D8).
- One source per setting, written down: the ownership table in
  `docs/01-architecture.md` maps every managed path on both machines to the
  file that produces it and the installer that applies it.
- Decisions with reasons: `docs/00-vision.md` D1-D13, dated amendments
  when a decision changed, and the rule that a decision without a recorded
  reason does not exist.
- Secrets by reference: one 1Password service-account token on the box;
  everything else is an `op://` reference in `home/op-env/` resolved per
  command by `home/bin/opwith`. Leak procedure and audit cadence in the
  runbook; a pre-tool hook (`home/claude/hooks/boundary-gate.sh`) stops
  agents from writing credential-shaped strings or force-pushing.
- Measured rebuild: VM destroyed with all snapshots, `make bootstrap-all`
  green in 3m14s (47 checks ok, 0 failed, 2026-08-19), four bugs that only
  the fresh path shows found and fixed the same day. A captured `verify`
  transcript is in `docs/reference/verify-2026-08-19.md`.
- Substrate portability with a minimal provider contract: a provider only
  has to deliver an Ubuntu cloud image with ssh; quirks stay in
  `providers/<name>/`, never in `box/`.
- Agent and human shells separated by shell mode, not by user: agent-spawned
  shells are plain (no colour, pager, aliases); the operator's interactive
  shell is rich; the guard has negative tests in `verify`.
- Lint in CI (`make lint`: shellcheck + shfmt); every script that also runs
  on the mac stays bash 3.2 compatible.

## Why I built it

The repository supersedes three earlier ones that grew into each other: a
Proxmox VM for agents that became my daily environment, a dotfiles repo that
carried much of the same user configuration a second time, and the runtime
half of a notes repo about AI usage. The cost was never the tooling; it was
that every new setting had two plausible homes, so they drifted. Two things
stuck with me while consolidating: a provisioning step that fails open is a
step you do not have (a manual hook-install was silently skipped on a
rebuild and nothing noticed, so it became a verified step, D12); and
"compare by meaning, not bytes" is the only way to manage config files that
the tool itself rewrites, which is most of them now.

## Prerequisites

- A Proxmox host reachable over ssh (`pve-vm-ssh`), or OrbStack on the mac
  for the local variant. No cloud provider yet (backlog).
- A 1Password account with a service-account token for the box and the
  `op` CLI on the mac; secrets are `op://` references, never values.
- A Claude Pro/Max subscription if you use Claude Code and Remote Control
  in the box; herdr, agy and omp are optional and installed by mise.
- On the mac: `mise` (installs shellcheck, shfmt and the rest from
  `home/mise/`), `make`, `ssh` with the 1Password SSH agent.

## Quickstart (operator, from the mac)

```
mac/setup.sh                      # once: brew, links, ssh config, mise
make bootstrap-all                # vm-create, vm-wait, secrets, provision (~3 min)
ssh -t agent-vm-ssh claude auth login   # the one unavoidable manual step (OAuth)
make claude-remote                # start the Remote Control server
make snapshot NAME=clean          # Proxmox only
```

Day to day: `box` (herdr remote attach) or `make ssh` for a shell, `make provision STEPS=home` after a
config change, `make maintain` for OS and tool updates (it tells you if a
reboot is pending, and leaves it to you), `home/install.sh --check box`
(part of `verify`) to prove there is no drift, `make rollback NAME=clean`
to go back.

## Repository layout

```
mac/         the laptop as a thin client: one script to set up, one task to sync
box/         the VM: idempotent bootstrap, OS config, systemd units, plain agent shell
home/        user configuration, two profiles (mac, box): mise, shell, git, 1Password
             wrappers, Claude Code settings incl. its global CLAUDE.md,
             subagents, skills, hooks, herdr / agy / omp config
providers/   how to create the box on each substrate (proxmox, orbstack; cloud is backlog)
docs/        00 vision and decisions, 01 architecture, 02 migration, 03 runbook,
             glossary, reference/ (tool notes, captured transcripts)
Makefile     the operator surface, run from the mac (`make help`)
PLAN.md      live state and the handoff between working sessions
AGENTS.md    rules for the AI agents that maintain this repository
```

## Reading order

1. `docs/00-vision.md` - goals, non-goals, decisions D1-D13 with reasons.
2. `docs/01-architecture.md` - the four planes, the ownership table, the
   provider contract.
3. `docs/03-runbook.md` - procedures: first login, secrets, updating,
   rollback and rebuild, troubleshooting, verification checklist.
4. `docs/02-migration.md` - where every setting came from (history).
5. `docs/glossary.md` - the short names used throughout (box, agy, omp,
   herdr, opwith, seed keys, ...).
6. `PLAN.md` - current state; `AGENTS.md` - if you are an agent working here.

## Status

Migration complete and the from-scratch rebuild proven (2026-08-19). Work
is backlog-driven (`PLAN.md`). The predecessors `agent-vm`, `dotfiles`
and `ai-hub` are archived on GitHub; ai-hub's doctrine and journal live in
the vault (`50-knowledge/ai/`) since 2026-09-02.

License: MIT (`LICENSE`).
