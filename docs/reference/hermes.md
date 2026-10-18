# Hermes gateways on the box

Reference for the two Hermes Agent (Nous Research,
https://hermes-agent.nousresearch.com) Telegram gateways provisioned by
`box/bootstrap.sh step_hermes`. Decision record: `docs/00-vision.md` D17. Written 2026-08-26,
when both moved here from the retired `hermes-vm`.

## What runs where

| Unit | OS user | Purpose | Extras |
|---|---|---|---|
| `hermes-gateway.service` (user) | `agent` | Operator's personal Telegram assistant (plain assistant; no notes repository since 2026-10-16) | Full install (browser automation) |
| `hermes-gateway.service` (user) | `savdert` | Shared family assistant for the household group chat | `--skip-browser` install; no access to the operator's home, no sudo, no 1Password token |

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
| `anthropic-api-key` | agent gateway only (Anthropic API key, `ANTHROPIC_API_KEY`) |
| `firecrawl-api-key` | both (web extract) |

`step_hermes` renders each template with `op inject` on EVERY provision
(as the `agent` user, whose login shell has the service-account token) and
installs the result as `~/.hermes/.env`, mode 600, owned by the target
user. Rotation is therefore: change the field in 1Password, run
`make provision STEPS=hermes`, restart the gateway. The `savdert` user
never sees the 1Password token; it only ever receives the rendered file.

The gateways do NOT get a GitHub token. The agent user's git credential
helper (`home/git/config`) resolves GitHub HTTPS credentials from
1Password per invocation, so Hermes shelling out to git
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
(bundled set auto-seeds), keyless web search (no backend set, no API
key), edge TTS, local terminal backend, and the synthetic.new custom
OpenAI-compatible provider (`syn:large:text` default and `syn:large:vision`
vision for the savdert gateway, Qwen3.8-27B fallback) carried over from the old
install. Cron jobs
are available through the `cronjob` tool at runtime; nothing is
pre-scheduled. Since 2026-10-17 the agent gateway's main model is
`claude-haiku-5-5` on the Anthropic API (`agent.reasoning_effort: medium`),
with synthetic.new kept as `fallback_providers`; the savdert gateway stays
on synthetic.new. The live agent `config.yaml` was edited to match the seed
(the seed is installed only once), so a re-seed yields the same model. The
agent gateway also gets `GITHUB_TOKEN` in `.env`
(resolved from `op://dotfiles/GitHub/admintoken`) so `hermes skills`
and `gh` CLI authenticate without the git credential helper; the savdert
gateway does not (no git operations).

## Vault retired (2026-10-16)

Until 2026-10-16 the agent gateway was the mobile write path into the private
`vault` repository (notes into `00-inbox/`, answers from the vault, a
`private/` tier for family and health material that must never pass through
Telegram), and two nightly timers (`vault-sessions`, `vault-compile`) fed and
compiled it. The vault was a write-only system with no reader and is now
archived (github.com/msavdert/vault, read-only). The gateway runs as a plain
Telegram assistant: `SOUL.agent.md` no longer has a vault section, and
`step_user` removes the two timers and their units on the next provision.
SOUL.md is seeded once, so the live `~/.hermes/SOUL.md` was edited by hand
on 2026-10-16 to drop the same section (and two vault entries in
`~/.hermes/memories/MEMORY.md`).

## Backup (agent gateway, nightly)

`hermes-backup.timer` (04:30 America/New_York) runs
`~/.hermes/hermes-backup.py`: `hermes backup` full zip (~100 MB), age
encryption with the recipient from `op://dotfiles/Hermes/age-recipient`
(the private `age-identity` never leaves 1Password), upload to
`s3://general/hermes/backup/hermes-backup-<date>.zip.age` via boto3,
30-day remote retention, 7 local copies in `~/backup/hermes/`. boto3
instead of the aws CLI because OCI's compat layer rejects aws-chunked
encoding; boto3 disables it with
`request_checksum_calculation=when_required`. `hermes backup -q` exits 0
without producing a zip (0.20.5 bug), so the script always runs full
mode. Restoring a backup:

    op read 'op://dotfiles/Hermes/age-identity' > identity.txt   # 0600, delete after
    aws s3api get-object --bucket general \
      --key hermes/backup/hermes-backup-<date>.zip.age out.zip.age \
      --endpoint-url "$S3_URL" --region us-ashburn-1
    age -d -i identity.txt -o restored.zip out.zip.age && hermes import restored.zip

## Operations

| What | How |
|---|---|
| Status | `ssh agent-vm-ssh 'systemctl --user status hermes-gateway'`; family: `ssh agent-vm-ssh 'sudo -u savdert XDG_RUNTIME_DIR=/run/user/$(id -u savdert) systemctl --user status hermes-gateway'` |
| Logs | `journalctl --user -u hermes-gateway -f` (as the respective user) |
| Restart | `systemctl --user restart hermes-gateway` (as the respective user) |
| Update hermes | as each user: `hermes update` (then the gateway restarts itself; check status). Installer re-runs are only for a missing install |
| Rotate a secret | edit `dotfiles/Hermes` in 1Password, `make provision STEPS=hermes`, restart both gateways |
| Re-seed config/SOUL | as the user: `rm ~/.hermes/.workbench-seeded ~/.hermes/config.yaml ~/.hermes/SOUL.md`, then `make provision STEPS=hermes` |
| Backup now | `ssh agent-vm-ssh 'systemctl --user start hermes-backup.service'`; log: `journalctl --user -u hermes-backup.service` |
| Backup health | `ssh agent-vm-ssh 'systemctl --user list-timers hermes-backup.timer'`; last key in `~/backup/hermes/hermes-backup-state.json` |

## Migration record (2026-08-26)

Previous home: Proxmox VM 101 `hermes-vm` (Ubuntu 24.04 at 10.0.0.10,
created 2026-08-03), user `hermes`, hermes-agent v0.20.4, two profiles via
`HERMES_HOME` (`~/.hermes` operator, `~/.hermes/profiles/ayse` family) -
both under ONE user, which is exactly the isolation gap the two-user
design closes. Secrets sat as literals in the profile `.env` files; they
were moved into `dotfiles/Hermes` before the rebuild. The VM also ran
Syncthing for `~/shared/obsidian_vaults/` (`invest101` - a git repo with a
GitHub remote - and `hermes-notes`); sync is git-only now (decided in the vault
repository, D6/D13, since archived). Rollback for the first week: a vzdump cold backup of VM 101 taken
before destruction; restoring it restores the old gateways as they were.
The operator explicitly waived a content audit of the VM ("nothing there I
need"); the backup preserves everything regardless.

## Troubleshooting

- Gateway inactive right after provision: first start can lose the race
  with Telegram's single-poller rule if another process still holds the
  bot token (the old VM's gateway, a stray `hermes gateway run`). Stop the
  other poller, `systemctl --user restart hermes-gateway`.
- `make provision STEPS=hermes` hangs with no output: `hermes gateway
  install` asks "start now?" and "start on login?" when the answers are not
  on the command line, and provisioning runs under a tty (`ssh -t`) with the
  prompt swallowed by `>/dev/null`. `step_hermes` passes
  `--no-start-now --start-on-login` and redirects stdin from `/dev/null` for
  every hermes call; keep both when adding one.
- `hermes doctor` says Node.js not found: the launcher expects
  `~/.hermes/node/bin` reachable; run through a login shell (`bash -lc`)
  or re-run `step_hermes`, which uses login shells throughout.
- `op inject` fails during provision: the agent user's service-account
  token is missing or expired - `make secrets` pushes it again; the token
  only reads the `dotfiles` and `homelab` vaults.
