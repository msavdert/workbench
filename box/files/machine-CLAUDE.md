# workbench box: machine-level instructions

Installed at /etc/claude-code/CLAUDE.md by github.com/msavdert/workbench
(box/files/machine-CLAUDE.md). Loaded into every Claude Code session on this
machine, in every directory. Edit it in the repo, then `make provision
STEPS=user`; hand edits are lost on the next provision.

## Where you are

Proxmox VM `105 agent-vm` (10.0.0.11), Ubuntu 24.04, user `agent` with
passwordless sudo and Docker. This VM ("the box") exists to run AI coding
agents; it is disposable (ZFS snapshot `clean` on the host) and reachable only
through the owner's tailnet. Full documentation: `~/work/workbench`
(README.md, AGENTS.md, PLAN.md, docs/00-vision.md, docs/01-architecture.md,
docs/03-runbook.md).

Layout:
- `~/work/<name>` one checkout per project; sessions from the Claude app start
  in one of these.
- `~/work/workbench` how this machine is built and how the operator's
  environment and agents are configured (`home/`).
- `~/work/vault` the operator's knowledge base and agent memory; doctrine
  and journal about working with AI are under `50-knowledge/ai/`.
- `agent-vm`, `dotfiles` and `ai-hub`, the predecessors of workbench, are
  archived on GitHub and are not checked out here.

## Secrets and auth

The only secret you use is the 1Password service-account token
(`~/.config/op/env`, already in your environment as OP_SERVICE_ACCOUNT_TOKEN).
The tools' own login tokens (Claude Code under `~/.claude`, agy under
`~/.gemini`) are also on disk; leave them where they are.
- `git` over HTTPS to github.com works as-is: the credential helper reads the
  token from 1Password on every call. Author is `msavdert`.
- `gh`: a bare `gh` is intentionally not logged in. Use `opwith git gh <args>`.
  Never run `gh auth login`.
- Other secrets: `op read "op://dotfiles/<item>/<field>"`, or `opwith <env>
  <command>` with an env file from `~/.config/op-env/`.
- Never write a secret value into a file, a repo, a log or a commit message.

## Sessions from the Claude app (Remote Control)

One always-on server, `work` (`claude-remote.service`, `~/work`). The
operator talks to it from the phone and asks it to open project sessions.
When asked to "open a session in <project>" (or similar), run:

    remote-session open <name> [git-url] [--model M]   # clone/trust ~/work/<name>, start a bypass Remote Control session, print its URL
    remote-session ls                                   # work server + open sessions
    remote-session close <name>                         # ends it; history stays in the app
    remote-session clone <name> <git-url>               # clone + trust only

and give the operator the printed URL. The session appears in the app on its
own, runs in `bypassPermissions` and always starts the newest installed
Claude Code. There are no per-project servers and no other helpers
(`remote-add/rm/ls` are gone). Do not hand-write systemd units. Repositories
that must survive a rebuild go in `~/work/workbench/box/remotes.list`.

Updating Claude Code: `claude update` (it also updates itself). The `work`
server keeps its start-up binary until restarted; `claude-drift-check.timer`
restarts it within 15 minutes once it has no open session. Never restart
`claude-remote.service` yourself: your own session runs inside it.

agy (Antigravity) works the other way round: one daemon for the whole
machine, `antigravity-cli-daemon.service`, and the project directory is
picked per session in the hub at https://antigravity.google.com. `agy
remote-control status` shows it; there is no `remote-session` for agy and the
`agy-daemon.sh` installer from the docs is deprecated, do not run it.

## Tools

apt owns the OS layer; mise owns user tools (`mise ls`, `mise up`); Claude Code
updates itself. Docker is native (`docker`, `docker compose`). The shell is
plain bash without colour or pagers on purpose - do not "improve" it. If you
need a new tool permanently, add it to the mise config in `~/work/workbench`
(`home/mise/config.box.toml`) or the apt list in `box/bootstrap.sh` rather
than only installing it. Routine updates are one command, `mise run
box:maintain` (apt, mise up, mise prune, usage, reboot-pending report);
security patches land daily on their own. The task never reboots; if it says
a reboot is pending, tell the owner.

## Rules

- Change the machine through `~/work/workbench` and `make provision` (run
  from the operator's machine), not by hand. Ad-hoc `sudo apt install` for a
  task is fine; anything that should survive a rebuild goes in the repo.
- Reboots, VM resizes, snapshots and rollbacks are the owner's call; the VM
  itself has no access to the Proxmox host. Ask.
- Push work to GitHub before long-running or risky operations; a rollback to
  `clean` discards everything under `~/work`.
