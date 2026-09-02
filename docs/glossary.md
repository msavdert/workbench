# Glossary

Short names used throughout this repository. Where a term is a decision,
the vision document is the authority; this page only says what the word
means.

| Term | Meaning |
|---|---|
| the box | The single Ubuntu VM this repository builds. Agents and the operator share it as one user; it may move between substrates (Proxmox, OrbStack) but is never multiplied. |
| the mac, thin client | The operator's laptop. It runs a terminal, ssh, `make` and the 1Password agent; it does no agent work itself. `mac/` configures it. |
| substrate, provider | Whatever provides the VM: a Proxmox host or OrbStack. A provider only has to deliver an Ubuntu cloud image with ssh; everything else is `box/` and `home/`. See `providers/`. |
| PVE | Proxmox Virtual Environment, the hypervisor host. `pve-vm-ssh` is the ssh alias to it (snapshots, rollback, VM create/destroy). |
| `agent-vm-ssh` | The ssh alias from the mac to the box. |
| profile | `mac` or `box`: which variant of `home/` is installed. `home/install.sh <profile>` and `home/mise/config.<profile>.toml` select it; `~/.config/workbench/env` records it. |
| operator | The human who owns the environment (me). Distinguished from agents because both use the same user account on the box. |
| agent | An AI coding agent process: Claude Code, or a harness driven by herdr, agy, omp. Agent-spawned shells are plain; the operator's are rich. |
| Claude Code | Anthropic's terminal coding agent; installed natively (self-updating), configured from `home/claude/`. |
| Remote Control | Claude Code's feature that exposes a session in the box to the claude.ai app; runs as a systemd user service (`claude-remote.service`, `claude-remote@<project>.service`). |
| herdr | A harness runner that manages agent sessions and integrates with Claude Code through hooks; installed by mise, configured in `home/herdr/`. |
| agy | Google's Antigravity CLI (`~/.gemini/antigravity-cli/`); installed by mise, settings composed from `home/agy/`. |
| omp | `@oh-my-pi/pi-coding-agent`, a terminal coding agent with its own provider logins; installed by mise (npm backend), configured from `home/omp/`. |
| omp-fleet | A Claude Code skill (`home/claude/skills/omp-fleet/`) that delegates large-output work to local omp agents on separate subscriptions. |
| harness | Any of the agent CLIs above plus the configuration that drives them. "Parallel harnesses" (D12) means several installed side by side. |
| mise | The per-user tool manager (`home/mise/`): runtimes and CLIs, pinned per profile, plus `mise run <task>` for repeatable chores. |
| `op`, `op://` | The 1Password CLI and its secret-reference syntax. Files under `home/op-env/` hold only `op://` references; values are resolved per command. |
| opwith | `home/bin/opwith <env> <command>`: runs a command with the `op://` references of `home/op-env/<env>.env` resolved into its environment, and nowhere else. |
| service-account token | The one secret on the box's disk (`~/.config/op/env`): a 1Password service account that can read the vault. Pushed by `make secrets`. |
| `bootstrap.sh`, step | `box/bootstrap.sh`, run as root, is a list of idempotent `step_*` functions (`system apt docker user home tools remotes verify`); `make provision STEPS="..."` runs a subset. |
| `install.sh` | `home/install.sh <profile>`: links or generates every user-level file from `home/`; `--check` reports drift, `--dry-run` shows what would change. |
| drift | A managed file on a machine that differs from what the repository would produce. A hand fix is drift until it is encoded in `box/` or `home/`. |
| compare by meaning | `install.sh` compares JSON and YAML targets by parsed content, not bytes, because tools rewrite their own files (key order, comments). |
| seed keys | Keys in a generated settings file that the repository sets once and the tool owns afterwards (agy's `model`, `trustedWorkspaces`); not drift when the tool changes them. D8. |
| one source per setting | The rule that a managed path comes from exactly one file in this repository; the ownership table in `docs/01-architecture.md` lists them. |
| boundary gate | `home/claude/hooks/boundary-gate.sh`, a Claude Code pre-tool hook that blocks force pushes and credential-shaped strings heading for disk. |
| read gate | `home/claude/hooks/read-gate.sh`, a Claude Code pre-tool hook that refuses a whole-file Read or a bare `cat` over 200 lines; the mechanical form of the narrow-read rule in the global CLAUDE.md. |
| audit skill | `home/claude/skills/audit/`: internal `auditor` subagent plus one external model on the omp fleet (two for risky code) before a requested commit. Lifted from agentshard's dual-audit rule on 2026-09-02. |
| agent guard | The part of `box/files/bashrc` that keeps agent-spawned (non-interactive) shells plain; the interactive hand-off to zsh happens only with a TTY and a real `TERM`. |
| agent-session | `~/.local/bin/agent-session`: attaches to the long-lived tmux session agents run in; the human entry point after ssh. |
| verify | `step_verify` in `bootstrap.sh`: the list of checks that prove a box converged (services, tools, guard, drift). Transcript: `docs/reference/verify-2026-08-19.md`. |
| D1..D13 | Numbered decisions in `docs/00-vision.md`, each with its reason and dated amendments. |
| PLAN.md | The live state of work and the handoff between sessions: `Now`, `Next`, `Log`. |
| ai-hub, agent-vm, dotfiles | The archived predecessors; `ai-hub`'s doctrine and journal live in the vault (`50-knowledge/ai/`) since 2026-09-02. `docs/02-migration.md` records what moved where. |
