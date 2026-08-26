# Hermes gateways on the box

Reference for the two Hermes Agent (Nous Research,
https://hermes-agent.nousresearch.com) Telegram gateways provisioned by
`box/bootstrap.sh step_hermes`, and the nightly vault compiler installed by
`step_vault`. Decision record: `docs/00-vision.md` D17. Written 2026-08-26,
when both moved here from the retired `hermes-vm`.

## What runs where

| Unit | OS user | Purpose | Extras |
|---|---|---|---|
| `hermes-gateway.service` (user) | `agent` | Operator's personal Telegram assistant; mobile write path into the private vault repo | Full install (browser automation); vault clone at `~/work/vault` |
| `hermes-gateway.service` (user) | `savdert` | Shared family assistant for the household group chat | `--skip-browser` install; no vault, no sudo, no 1Password token |
| `vault-compile.service` + `.timer` (user) | `agent` | Nightly distill+retire of the vault (03:00 America/New_York) | Runs `~/work/vault/.claude/scripts/compile.py`, headless `claude -p --model sonnet` |

Both users have linger enabled, so the gateways start at boot and survive
logout. Each user is a complete, independent Hermes install (default
profile in `~/.hermes`); they share nothing - not config, not memory, not
sessions. That duplication (~2 GB each) is the price of the isolation
requirement: the family bot must be unable to reach the operator's
personal notes even if a chat member asks it to. `savdert` cannot read
`/home/agent` (0750, no shared groups), holds no secrets-manager token,
and has no sudo.

## Secrets and identity values

This repository is public. Every secret AND every personal identifier
(Telegram bot tokens, allowed-user ids, home-channel ids, the group chat
name) lives in the 1Password item `dotfiles/Hermes` and is referenced from
the tracked templates `box/files/hermes/env.*.tpl`:

| Field | Used by |
|---|---|
| `telegram-bot-melih`, `telegram-users-melih`, `telegram-home-melih` | agent gateway |
| `telegram-bot-savdert`, `telegram-users-savdert`, `telegram-home-savdert`, `telegram-home-name-savdert` | savdert gateway |
| `synthetic-api-key` | both (model provider, api.synthetic.new) |
| `firecrawl-api-key` | both (web extract) |

`step_hermes` renders each template with `op inject` on EVERY provision
(as the `agent` user, whose login shell has the service-account token) and
installs the result as `~/.hermes/.env`, mode 600, owned by the target
user. Rotation is therefore: change the field in 1Password, run
`make provision STEPS=hermes`, restart the gateway. The `savdert` user
never sees the 1Password token; it only ever receives the rendered file.

The gateways do NOT get a GitHub token. The agent user's git credential
helper (`home/git/config`) resolves GitHub HTTPS credentials from
1Password per invocation, so Hermes shelling out to git in `~/work/vault`
authenticates without any token in its environment; the savdert user has
no git credentials at all.

## File ownership: seeded once vs converged

| File | Policy |
|---|---|
| `~/.hermes/.env` | Converged: re-rendered from the template every provision. Hand edits are drift and will be overwritten |
| `~/.hermes/config.yaml` | Seeded once from `box/files/hermes/config.<user>.yaml` (then `hermes doctor --fix` migrates the schema). Runtime-owned afterwards: `hermes setup`/`config set` may change it and provisioning will not touch it again |
| `~/.hermes/SOUL.md` | Seeded once from `box/files/hermes/SOUL.<user>.md`; the running agent owns its identity afterwards |
| `~/.hermes/.workbench-seeded` | Marker recording that the one-time seeding happened. Delete it (and the two files above) to re-seed from the repo |
| `~/.config/systemd/user/hermes-gateway.service` | Written by `hermes gateway install` (hermes-owned, survives `hermes update`) |

The seed configs enable the officially recommended feature set (checked
against the docs on 2026-08-26, hermes-agent v0.20.5): persistent memory
(`memory_enabled` + `user_profile_enabled`, no write approval), skills
(bundled set auto-seeds), ddgs web search, edge TTS, local terminal
backend, and the synthetic.new custom OpenAI-compatible provider
(`syn:large:text` default, `syn:large:vision` vision, Nemotron fallback)
carried over from the old install. Cron jobs are available through the
`cronjob` tool at runtime; nothing is pre-scheduled.

## Vault integration (agent gateway only)

The private repo `github.com/msavdert/vault` is cloned to
`~/work/vault` by `step_remotes` (`box/remotes.list`). The gateway's
SOUL.md instructs it to:

- capture notes as new files `00-inbox/YYYY-MM-DD-HHMM-slug.md` (one note
  per file, ASCII names), never editing `90-agent/` state files;
- `git pull --rebase --autostash` before reading or writing, commit as
  `hermes <hermes@box>`, push after writing;
- answer questions from vault content only, saying so when the vault holds
  no evidence (the vault's anti-hallucination rule).

The nightly compiler (`vault-compile.timer`) then distills daily logs into
`50-knowledge/` notes and retires aged material. Its logic, locking and
error discipline live in the vault repo itself
(`.claude/scripts/compile.py`, documented in the vault's HANDOFF.md and
docs); this repository only owns the systemd wiring, so the mac and the
box always run whatever the vault repo currently defines.

## Operations

| What | How |
|---|---|
| Status | `ssh agent-vm-ssh 'systemctl --user status hermes-gateway'`; family: `ssh agent-vm-ssh 'sudo -u savdert XDG_RUNTIME_DIR=/run/user/$(id -u savdert) systemctl --user status hermes-gateway'` |
| Logs | `journalctl --user -u hermes-gateway -f` (as the respective user) |
| Restart | `systemctl --user restart hermes-gateway` (as the respective user) |
| Update hermes | as each user: `hermes update` (then the gateway restarts itself; check status). Installer re-runs are only for a missing install |
| Rotate a secret | edit `dotfiles/Hermes` in 1Password, `make provision STEPS=hermes`, restart both gateways |
| Re-seed config/SOUL | as the user: `rm ~/.hermes/.workbench-seeded ~/.hermes/config.yaml ~/.hermes/SOUL.md`, then `make provision STEPS=hermes` |
| Compile now | `ssh agent-vm-ssh 'systemctl --user start vault-compile.service'`; report lands in `~/work/vault/.state/compile.report`, errors in `.state/compile.err` |
| Vault health | `~/work/vault/.claude/scripts/doktor.sh` on any clone |

## Migration record (2026-08-26)

Previous home: Proxmox VM 101 `hermes-vm` (Ubuntu 24.04 at 10.0.0.10,
created 2026-08-03), user `hermes`, hermes-agent v0.20.4, two profiles via
`HERMES_HOME` (`~/.hermes` operator, `~/.hermes/profiles/ayse` family) -
both under ONE user, which is exactly the isolation gap the two-user
design closes. Secrets sat as literals in the profile `.env` files; they
were moved into `dotfiles/Hermes` before the rebuild. The VM also ran
Syncthing for `~/shared/obsidian_vaults/` (`invest101` - a git repo with a
GitHub remote - and `hermes-notes`); sync is git-only now (vault HANDOFF
D6/D13). Rollback for the first week: a vzdump cold backup of VM 101 taken
before destruction; restoring it restores the old gateways as they were.
The operator explicitly waived a content audit of the VM ("nothing there I
need"); the backup preserves everything regardless.

## Troubleshooting

- Gateway inactive right after provision: first start can lose the race
  with Telegram's single-poller rule if another process still holds the
  bot token (the old VM's gateway, a stray `hermes gateway run`). Stop the
  other poller, `systemctl --user restart hermes-gateway`.
- `hermes doctor` says Node.js not found: the launcher expects
  `~/.hermes/node/bin` reachable; run through a login shell (`bash -lc`)
  or re-run `step_hermes`, which uses login shells throughout.
- `op inject` fails during provision: the agent user's service-account
  token is missing or expired - `make secrets` pushes it again; the token
  only reads the `dotfiles` and `homelab` vaults.
- Compile did nothing: `.state/compile.report` names inputs and outputs;
  an empty inputs line means no new daily logs since the last marker
  (`.state/last-compile`). Errors are in `.state/compile.err`, never
  only in the journal.
