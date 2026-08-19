# 03 - Runbook

Status: procedures for the box built from this repository (phase 1: identical
to agent-vm's).

## First-time Claude Code login and Remote Control

```
ssh -t agent-vm-ssh claude auth login
```

Follow the URL it prints in a browser on any device, sign in with the
claude.ai account (Pro/Max/Team), and paste the code back into the terminal.
Then:

```
make claude-remote
```

which enables `claude-remote.service`, the generic `work` environment
(`~/work`, `--name work`, capacity 2). Per-project environments come from
`make remote-add`, next section. `claude-remote.service` (systemd user unit,
`~/.config/systemd/user/claude-remote.service`). Two consents that Claude
normally asks for on a TTY - workspace trust for `~/work` and "Enable Remote
Control? (y/n)" - are pre-seeded into `~/.claude.json` by `bootstrap.sh
step_user`, so the service starts without a terminal. Check it:

```
ssh agent-vm-ssh 'systemctl --user status claude-remote.service; journalctl --user -u claude-remote -n 30'
```

The session appears at https://claude.ai/code and in the Claude mobile app,
named `agent-vm`. Working directory is `~/work`; clone projects there.

To change the session name/capacity edit `box/files/claude-remote.service`
and `make provision STEPS=user && ssh agent-vm-ssh 'systemctl --user daemon-reload && systemctl --user restart claude-remote'`.

## Working on a project (per-project Remote Control servers)

A Remote Control server is bound to the directory it starts in and the app
cannot pick a directory per session. So: **one server per project**, each a
systemd user instance `claude-remote@<name>` rooted in `~/work/<name>` and
shown in the Claude app as an environment called `<name>`. Sessions started
there begin in that checkout and see its `CLAUDE.md`, `.claude/`, memory,
hooks, exactly like a local `claude` run from that directory.

```
make remote-add NAME=suhuf URL=https://github.com/msavdert/suhuf.git   # clone + trust + start
make remote-add NAME=suhuf OPTS="--worktree"                           # each app session in its own git worktree
make remote-ls
make remote-rm NAME=suhuf                                              # stops the server, keeps ~/work/suhuf
```

The same works from inside the VM (for example from a session in the generic
`work` environment): `remote-add suhuf https://github.com/msavdert/suhuf.git`.
Cloning private repos needs no token: the git credential helper reads it from
1Password.

In the app the environments do not appear under Recents (that list is
sessions). Click **+ New**; above the chat box there are three targets -
Local / Cloud / Remote control. Under Remote control each server is listed as
`<name>  agent-vm  N of M sessions`; pick one and the new session starts in
that server's directory. Or open the URL that `remote-add` prints
(`https://claude.ai/code?environment=env_...`). Sessions you then start
land under Recents with the environment's name.

Environments you will see in the app:

| Environment | Directory | Purpose |
|---|---|---|
| `work` | `~/work` | generic scratch space; use it to clone repos and run `remote-add` |
| `<name>` | `~/work/<name>` | one per project, created by `remote-add` |

Per-project knobs: `--capacity N` (concurrent sessions, default 4),
`--permission-mode M` (default `bypassPermissions`; the `defaultMode` in
`~/.claude/settings.json` does not reach spawned remote sessions, so the
server passes it explicitly) and `--worktree` / `--same-dir` (default same-dir: all sessions share the
checkout; worktree: each on-demand session gets `git worktree` isolation,
good for parallel tasks on one repo). They are stored in
`~/.config/claude-remote/<name>.env` and picked up by the template unit.

In the app (claude.ai/code, macOS desktop Code tab, mobile): pick the
environment (`work`, `suhuf`, ...) and start a new session, or open the
session the server pre-created on start. Sessions survive an app disconnect;
after a server restart run `claude remote-control --continue` in that
directory within ~4 hours to bring them back (see
https://code.claude.com/docs/en/remote-control.md). Anthropic does not document the exact UI flow, so expect the
labels to move.

## Machine-level instructions for agents

`/etc/claude-code/CLAUDE.md` (source: `box/files/machine-CLAUDE.md`) is
loaded into every Claude Code session on the VM. Edit in the repo, then
`make provision STEPS=user`. Keep it short. `omp` does not read it; if omp
needs the same context, put it in `~/.omp/agent/AGENTS.md` (currently not
provisioned; the devbox version lives in dotfiles).

## Interactive use

`make ssh` attaches to (or creates) tmux session `main` in `~/work`. Other
agents (`omp`, a second `claude`) run in further tmux windows or sessions.

## Secrets

- `make secrets` writes `OP_SERVICE_ACCOUNT_TOKEN` to `~/.config/op/env`
  from the operator's current shell environment.
- `opwith git gh ...` for gh; `git push` over HTTPS needs nothing extra.
- Adding a secret: put it in the `dotfiles` vault, add an `op://` line to a
  file in `home/op-env/`, push, `make provision STEPS=home` (the box links
  `~/.config/op-env` into its clone of this repository).

## Updating

| What | How |
|---|---|
| OS packages | `ssh agent-vm-ssh 'sudo apt update && sudo apt full-upgrade -y'`; `sudo needrestart -b` shows `KSTA: 3` if a reboot is pending |
| mise tools | `ssh agent-vm-ssh 'mise up'` |
| Claude Code | self-updates; `claude update` to force |
| This repo's config | `make provision`; `box/` only: `STEPS=user`; `home/` only: `STEPS=home` (pulls `~/work/workbench` on the box and re-runs `home/install.sh box`) |
| Drift check of `home/` on the box | `ssh agent-vm-ssh 'bash -lc "~/work/workbench/home/install.sh --check box"'` (also part of `verify`) |
| ai-hub (global CLAUDE.md, agents, skills, hooks) | `make provision STEPS=aihub` or on the VM `git -C ~/work/ai-hub pull && bash ~/work/ai-hub/install.sh` |

## Rollback / rebuild

```
make snapshots
make rollback NAME=clean          # stops, rolls back, starts
```

Full rebuild checklist (what is automated and what is not):

| Step | Automated? |
|---|---|
| `make vm-destroy` | asks for confirmation |
| `ssh-keygen -R 10.0.0.11` on the operator machine (new host key) | manual, one command |
| `make bootstrap-all` = vm-create, vm-wait, secrets, provision | yes; provision also clones ai-hub, installs it, and clones every repo in `box/remotes.list` (servers enabled, not started) |
| `ssh -t agent-vm-ssh claude auth login` | **manual** (OAuth code paste), unavoidable |
| `make claude-remote` | starts `work` + all listed project servers |
| `omp` provider logins (`omp` on the VM, interactive) | **manual**, only if you use omp there |
| `make snapshot NAME=clean` | one command |

Anything you `remote-add` by hand and do not put in `box/remotes.list`
is lost on rebuild (the directory too, unless pushed). Anything under
`~/work/*` that is not pushed is lost on rebuild or rollback.

After a rebuild the ssh host key changes; the operator's ssh config uses
`StrictHostKeyChecking accept-new`, so remove the old entry:
`ssh-keygen -R 10.0.0.11`.

## Troubleshooting

- **`permission denied ... docker.sock` right after provisioning** - the ssh
  ControlMaster connection predates the `docker` group membership. Reconnect
  with `ssh -o ControlPath=none agent-vm-ssh` or wait for ControlPersist to
  expire.
- **`apt` hangs in a dialog** - something bypassed the env; run with
  `sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt ...`.
- **`mise` installs an old version** - try the explicit backend
  (`mise ls-remote aqua:<owner>/<repo>`); see `docs/00-vision.md` D7.
- **VM unreachable** - `make vm-status`; console via
  `ssh pve-vm-ssh qm terminal 105` (exit with `Ctrl-O`).
- **cloud-init did not run as expected** - on the VM:
  `sudo cloud-init status --long; sudo cat /var/log/cloud-init-output.log`.
- **claude-remote fails with "Workspace not trusted" or loops on "Enable
  Remote Control? (y/n)"** - the consents in `~/.claude.json` are missing;
  `make provision STEPS=user` re-seeds them.
- **"Remote Control requires feature-flag evaluation ... DO_NOT_TRACK"** -
  something exported `DO_NOT_TRACK`; it must stay unset for the agent user
  (removed from `bashrc` for this reason).
- **Remote Control session missing from the app** - `systemctl --user status
  claude-remote`; if it loops on auth, `claude auth login` again (token
  expired) and `systemctl --user restart claude-remote`.

## Verification checklist (what `bootstrap.sh verify` covers)

docker active and usable by `agent`, qemu-guest-agent active, `mise node gh op
uv go bun omp claude jq rg fd tmux` on PATH, passwordless sudo, swap on,
needrestart non-interactive. Smoke tests done at build time:
`docker run hello-world`, `opwith git gh auth status`, `git clone` of this
private repo via the op credential helper, `omp --version`, `claude --version`, tmux session create,
interactive `PS1`.
