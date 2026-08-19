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
- `~/work/ai-hub` doctrine, experiments and journal about working with AI;
  it holds no configuration since workbench phase 3.
- `agent-vm` and `dotfiles`, the predecessors of workbench, are archived on
  GitHub and are not checked out here.

## Secrets and auth

The only secret on disk is the 1Password service-account token
(`~/.config/op/env`, already in your environment as OP_SERVICE_ACCOUNT_TOKEN).
- `git` over HTTPS to github.com works as-is: the credential helper reads the
  token from 1Password on every call. Author is `msavdert`.
- `gh`: a bare `gh` is intentionally not logged in. Use `opwith git gh <args>`.
  Never run `gh auth login`.
- Other secrets: `op read "op://dotfiles/<item>/<field>"`, or `opwith <env>
  <command>` with an env file from `~/.config/op-env/`.
- Never write a secret value into a file, a repo, a log or a commit message.

## Sessions from the Claude app (Remote Control)

One server per project directory, as systemd user units. To make a repo
available as an environment in the app:

    remote-add <name> <git-url>      # clone to ~/work/<name>, trust, start claude-remote@<name>
    remote-add <name> --worktree     # each app session in its own git worktree
    remote-ls
    remote-rm <name>                 # stops the server, keeps the directory

Do not hand-write systemd units for this. The generic environment `work`
(`~/work`) is for exactly this bootstrapping. Environments that must survive
a rebuild are listed in `~/work/workbench/box/remotes.list`.

## Tools

apt owns the OS layer; mise owns user tools (`mise ls`, `mise up`); Claude Code
updates itself. Docker is native (`docker`, `docker compose`). The shell is
plain bash without colour or pagers on purpose - do not "improve" it. If you
need a new tool permanently, add it to the mise config in `~/work/workbench`
(`box/files/mise.toml` today, `home/mise/` after phase 2) or the apt list in
`box/bootstrap.sh` rather than only installing it.

## Rules

- Change the machine through `~/work/workbench` and `make provision` (run
  from the operator's machine), not by hand. Ad-hoc `sudo apt install` for a
  task is fine; anything that should survive a rebuild goes in the repo.
- Reboots, VM resizes, snapshots and rollbacks are the owner's call; the VM
  itself has no access to the Proxmox host. Ask.
- Push work to GitHub before long-running or risky operations; a rollback to
  `clean` discards everything under `~/work`.
