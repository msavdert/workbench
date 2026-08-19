# workbench

A reproducible personal platform for working with AI coding agents: one
Ubuntu VM ("the box") built identically on Proxmox, OrbStack or a cloud
provider, plus a thin macOS client. Agents run in the box; the operator
works in the same box over ssh. Every setting has exactly one source here.

```
mac/         the laptop as a thin client: one script to set up, one task to sync
box/         the VM: idempotent bootstrap, OS config, systemd units, plain agent shell
home/        user configuration, two profiles (mac, box): mise, shell, git, 1Password
             wrappers, Claude Code settings, herdr / agy / omp / aws config
agents/      how agents behave: global CLAUDE.md, subagents, skills, hooks
providers/   how to create the box on each substrate (proxmox, orbstack, cloud)
docs/        00 vision and decisions, 01 architecture, 02 migration, 03 runbook
```

Design in one paragraph: the substrate only provides an Ubuntu with ssh;
`box/bootstrap.sh` (root, idempotent) and `home/install.sh box` (user,
idempotent) do the rest, the same way everywhere. Agent-spawned shells are
plain and predictable; the operator's interactive terminal is rich; both are
the same user on the same machine, separated by shell mode. Secrets never
touch disk except one 1Password service-account token; everything else is an
`op://` reference resolved per command.

Read `docs/00-vision.md` for the decisions and their reasons, `PLAN.md` for
the current state, `AGENTS.md` if you are an agent working here.

Status: migration complete (2026-08-19). The box and the mac are built from
this repository alone; `agent-vm` and `dotfiles` are archived on GitHub,
`ai-hub` keeps doctrine and journal only.

License: MIT (`LICENSE`).
