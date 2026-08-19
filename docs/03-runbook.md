# 03 - Runbook

Status: procedures for the box built from this repository.

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

which enables `claude-remote.service`, the shared `work` environment
(`~/work`, `--name work`, capacity 2) - the only server by default; see the
next section for optional per-project ones. `claude-remote.service` is a
systemd user unit (`~/.config/systemd/user/claude-remote.service`). Two consents that Claude
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

## Working on a project (optional per-project Remote Control servers)

Default policy (D11): the shared `work` server is the only one running.
Sessions started in it are steered from the operator's machine, which
clones repositories and moves between them; `box/remotes.list` keeps those
clones present after a rebuild (`--clone-only`, no server).

A Remote Control server is bound to the directory it starts in and the app
cannot pick a directory per session. When a project deserves its own
environment, `remote-add <name>` starts a systemd user instance
`claude-remote@<name>` rooted in `~/work/<name>` and shown in the Claude app
as an environment called `<name>`. Sessions started there begin in that
checkout and see its `CLAUDE.md`, `.claude/`, memory, hooks, exactly like a
local `claude` run from that directory.

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
| `work` | `~/work` | the default and usually only environment; projects live in `~/work/<name>` |
| `<name>` | `~/work/<name>` | optional, one per project, created by `remote-add` without `--clone-only` |

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
provisioned).

## Interactive use

`box` (a mac-only zsh alias from `home/zsh/.zshrc`) is the everyday entry:
`herdr --remote agent-vm-ssh --session main`, the mac herdr client attached
over ssh to the herdr server on the box. The UI and keybindings are local,
the session and every agent in it live on the box and survive the laptop
closing. `make ssh` is the fallback below it: plain ssh into tmux session
`main` in `~/work` (`agent-session`), for when herdr is not running or is
being debugged. Other agents (`omp`, a second `claude`) run in further herdr
tabs, or tmux windows on the fallback path.

Every `claude` started on the box is Remote Control enabled
(`remoteControlAtStartup` in `home/claude/settings.box.json`): it prints a
notice at startup and shows up under Recents in the Claude app, so a session
begun in a herdr pane can be followed or continued from the phone. The rules:
one session has one host at a time - opening the same session in a second
terminal leaves Remote Control off there with a notice; `/rc` moves it. Keep
one active session per checkout (the `work` server is same-dir, bypass). To
change surface, finish the session: update PLAN.md, push, start fresh on the
other side; `claude --resume` in the same directory is the fallback when the
transcript itself is needed. Mac sessions are not registered: the mac overlay
does not set the key.

## Secrets

- `make secrets` writes `OP_SERVICE_ACCOUNT_TOKEN` to `~/.config/op/env`
  from the operator's shell environment, or, when unset, from 1Password
  (`op read op://dotfiles/agent-vm-op-service-account/credential`, the
  1Password app unlocked on the mac). Override with `OP_TOKEN_REF=`.
- `opwith git gh ...` for gh; `git push` over HTTPS needs nothing extra.
- Adding a secret: put it in the `dotfiles` vault, add an `op://` line to a
  file in `home/op-env/`, push, `make provision STEPS=home` (the box links
  `~/.config/op-env` into its clone of this repository).
- Audit, every few months: `env | grep -iE 'token|key|secret'` on both
  machines must print nothing, and `git log -p -- home/op-env/` must show
  only `op://` references.
- If a secret leaks: rotate it first (1Password revoke and reissue; the
  `op://` reference does not change, so no repo edit), then decide about git
  history - usually leave it, the value is dead and clones keep the old
  objects anyway. If the leaked value was `OP_SERVICE_ACCOUNT_TOKEN`, rotate
  the service account in 1Password and run `make secrets` to push the new
  token to `~/.config/op/env` on the box.

## Operator seat

Sessions run from the mac (`~/work/workbench`). The mac reaches the box
directly (`agent-vm-ssh` in `~/.ssh/config.local`, 1Password SSH agent),
so `make provision`, `make ssh` and `home/install.sh --check` over ssh
work from the laptop; `make lint` works there (shellcheck, shfmt from
mise). Snapshots and rollbacks need `pve-vm-ssh` (a 1Password `ssh-host`
item; `mise run ssh:sync` on the mac installs it) - not yet exercised from
the mac since the devbox seat is gone.

## Updating

| What | How |
|---|---|
| Routine maintenance (all of the below in one go) | `make maintain` (= `ssh agent-vm-ssh 'bash -lc "mise run box:maintain"'`): apt full-upgrade + autoremove, `mise up` + `mise prune`, `docker system df`, disk, and a final `reboot pending: yes/no` line. It never reboots; security patches also land daily on their own via `unattended-upgrades` (security pocket only), docker caches are pruned weekly by `docker-prune.timer` |
| OS packages only | `ssh agent-vm-ssh 'sudo apt update && sudo apt full-upgrade -y'`; `sudo needrestart -b` shows `KSTA: 3` if a reboot is pending |
| mise tools only | `ssh agent-vm-ssh 'mise up'`; `mise prune` drops versions no longer listed |
| Claude Code | self-updates; `claude update` to force |
| This repo's config | `make provision`; `box/` only: `STEPS=user`; `home/` only: `STEPS=home` (pulls `~/work/workbench` on the box and re-runs `home/install.sh box`) |
| The laptop | `mise run mac:sync` (pulls `~/work/workbench`, `mac/setup.sh --links-only`); full run `mac/setup.sh`, `CLEANUP=1` to also remove brew packages not in `mac/Brewfile` |
| zsh completion cache and plugins (both profiles) | `mise run completions:regen`, `mise run zsh:plugins`; also run by `mac/setup.sh` and `STEPS=tools` |
| Drift check of `home/` on the box | `ssh agent-vm-ssh 'bash -lc "~/work/workbench/home/install.sh --check box"'` (also part of `verify`) |
| Agent behaviour (`home/claude/`: global CLAUDE.md, subagents, omp-fleet, boundary gate) | same as `home/`: `STEPS=home` on the box, `mise run mac:sync` on the laptop; `home/install.sh` also self-checks the gate |

Why the split between unattended and `make maintain`, and why nothing
reboots on its own: `docs/00-vision.md` D14.

When `make maintain` ends with `reboot pending: yes` (a new kernel or libc
is installed but not running), reboot at a moment of your choosing - every
Remote Control server and tmux session on the box dies with it:

```
ssh agent-vm-ssh 'sudo systemctl reboot'
# ~20 s later
ssh -o ControlPath=none agent-vm-ssh 'uname -r; sudo needrestart -b | grep KSTA'
# expect the new kernel and NEEDRESTART-KSTA: 1
make claude-remote                # the Remote Control servers are enabled units
                                  # and come back by themselves; this only
                                  # confirms they did
```

`ControlPath=none` matters: the ssh ControlMaster socket from before the
reboot may still be in place and answer with a stale connection.

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
| `make bootstrap-all` = vm-create, vm-wait, secrets, provision | yes; provision also clones every repo in `box/remotes.list` (`--clone-only`: no per-project servers) |
| `ssh -t agent-vm-ssh claude auth login` | **manual** (OAuth code paste), unavoidable |
| `make claude-remote` | starts `work` (and any per-project server enabled by hand) |
| `omp` provider logins (`omp` on the VM, interactive) | **manual**, only if you use omp there |
| `make snapshot NAME=clean` | one command |

Rebuild gotcha (seen 2026-08-19): with `ControlMaster auto` in the mac's ssh
config, the multiplexed master to the box opens during `vm-wait`, before
`step_docker` adds `agent` to the `docker` group, so later `ssh agent-vm-ssh
docker ...` fails with "permission denied" until the master is closed:
`ssh -O exit agent-vm-ssh`. Provisioning itself is unaffected (`sudo -u`
starts fresh sessions).

Anything you clone or `remote-add` by hand and do not put in
`box/remotes.list` is lost on rebuild (the directory too, unless pushed);
a per-project server is only recreated if its line has no `--clone-only`. Anything under
`~/work/*` that is not pushed is lost on rebuild or rollback.

After a rebuild the ssh host key changes; the operator's ssh config uses
`StrictHostKeyChecking accept-new`, so remove the old entry:
`ssh-keygen -R 10.0.0.11`.

### OrbStack (the box on the laptop)

Same targets with `PROVIDER=orbstack`; nothing goes through the PVE host.
`VM_HOST` defaults to `agent@agent-vm@orb`, OrbStack's ssh path (mac
`~/.ssh/config` includes `~/.orbstack/ssh/config`); sshd on port 22 with
the 1Password key also works on the machine's LAN address (`orb info
agent-vm -f json`, `ip4`), useful for anything that expects a plain host.
`make secrets` reads the token from 1Password when it is not in the shell.

```
make bootstrap-all PROVIDER=orbstack     # orb create + provision + verify
make provision     PROVIDER=orbstack     # re-converge
make ssh           PROVIDER=orbstack
make vm-destroy    PROVIDER=orbstack     # orb delete
```

"Roll back" on OrbStack means delete and rebuild (a few minutes, from
scratch); there is no snapshot target. Sizing caps live in
`providers/orbstack/vm.env`. Measured 2026-08-19 on an M-series mac,
arm64: `orb create` 12 s, `bootstrap-all` end to end about 3 minutes.
The first `claude auth login` on it is manual, as on every substrate.

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
- **Every keystroke shows twice over ssh (`a` becomes `aa`)** - the mac's
  terminal reports a `TERM` the box has no terminfo entry for (Ghostty:
  `xterm-ghostty`), so zsh's line editor cannot move the cursor and redraws.
  `bootstrap.sh step_system` compiles `box/files/xterm-ghostty.terminfo`
  into `/etc/terminfo`; for another terminal, export its entry the same way
  (`infocmp -x $TERM`) and add it there. Quick check on the box: `infocmp
  $TERM`.
- **Duplicate or offline environments in the app's Remote Control picker**
  after a rebuild or after stopping a server - expected. An environment is
  registered per (machine, directory) and there is no way to deregister
  one (CLI, UI or expiry; anthropics/claude-code#78695). Entries of the
  destroyed VM stay "offline", freshly stopped ones can show "online" for a
  while. The live `work` server is the one reporting `N of 2 sessions`.
- **Remote Control session missing from the app** - `systemctl --user status
  claude-remote`; if it loops on auth, `claude auth login` again (token
  expired) and `systemctl --user restart claude-remote`.
- **`mise ls agy` and `agy --version` disagree** - expected, not drift. The
  agy backend replaces the binary inside the existing versioned install
  directory instead of creating a new one, so the directory name (and what
  `mise ls` reports from it) is whatever was first installed, while the
  binary is whatever the last `mise up` fetched. Seen: `mise ls` 1.1.13
  against a 1.1.15 binary. Trust `agy --version`. agy releases fast enough
  that pinning it would cost more than it buys.
- **agy runs unattended with no command guardrails, on purpose** - and the
  two settings that look like they would provide some do not, verified on
  2026-08-19 against agy 1.1.15:
  - `permissions: {allow, deny, ask}` IS parsed (agy logs `CLI settings
    initialized: permissions=&{Allow:[...] Deny:[...] Ask:[]}`) but is NOT
    enforced while `toolPermission: always-proceed` - a denied command still
    ran. agy also drops the key when it rewrites settings.json, so putting it
    back would make `install.sh --check` report drift forever. This is why
    it was removed in eceeaf9.
  - `permissions_v2` round-trips in the file but is inert: with only that key
    set, agy logs `permissions=<nil>` and runs the denied command.
  - `enableTerminalSandbox: true` FAILS OPEN on this box. Its seccomp sandbox
    server does not answer (`connecting to sandbox server: ... connection
    reset by peer`) and agy retries the command unsandboxed, successfully. It
    buys an error line per tool call and no containment.
  What actually contains agy is the box itself: rebuildable from this
  repository, projects in git, a `clean` Proxmox snapshot. Revisit if a
  future agy fixes the sandbox or enforces deny under `always-proceed`.

## Verification checklist (what `bootstrap.sh verify` covers)

A captured run is kept in `docs/reference/verify-2026-08-19.md`; regenerate
with `make provision STEPS=verify > docs/reference/verify-<date>.md`.

docker active and usable by `agent`, sshd active (or socket-activated),
qemu-guest-agent active where its virtio port exists, `mise node gh op
uv go bun omp agy herdr claude jq rg fd tmux` on PATH, passwordless sudo,
swap on, needrestart non-interactive, `home/install.sh --check box` reporting
no drift, `/etc/claude-code/CLAUDE.md` in place, and herdr's three integration
hooks (`~/.claude/hooks/herdr-agent-state.sh`, `~/.omp/agent/extensions/`,
`~/.gemini/config/hooks.json`) present - each fails open on its own, so only
this check makes their absence visible. Smoke tests that need the
operator's logins (`docker run hello-world`, `opwith git gh api user`,
`op whoami`, `claude --version`) are run by hand after `make claude-remote`;
the rebuild checklist above lists them.
