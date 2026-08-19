# PLAN.md - live state

This file is the handoff between sessions. Update `Now`, `Next` and `Log`
before ending a session. Phases are defined in `docs/02-migration.md`.

## Phases

| # | Phase | Status |
|---|---|---|
| 0 | Founding documents | done |
| 1 | Move agent-vm in, unchanged behaviour | done |
| 2 | home/ and mac/ | done |
| 3 | agents/ (from ai-hub runtime) | done |
| 4 | Human layer, herdr/agy/aws-cli, plugins | done |
| 5 | Portability proof (OrbStack, cloud) | active |
| 6 | Retire agent-vm, dotfiles, devbox | not started |

## Now

Phase 5 step 1 executed from the mac on 2026-08-19: `providers/orbstack/`
(`create-vm.sh`, `vm.env`, `user-data.yaml`), Makefile branches on
`PROVIDER=orbstack` (`vm-create` runs locally, `VM_HOST=agent@agent-vm@orb`,
`vm-destroy` = `orb delete`). `make bootstrap-all PROVIDER=orbstack` on a
deleted-then-recreated machine: exit 0, `verify` 43 ok, about 3 minutes
end to end (Ubuntu 24.04.4 arm64, `systemd-detect-virt` = lxc, uid 501).
sshd on port 22 answers the 1Password key on the machine's LAN address.

From-scratch findings, all fixed in `box/bootstrap.sh` and re-verified on
both substrates (`make provision STEPS="system verify"` green on Proxmox
and OrbStack): `chown -R` in step_user assumed `.gitconfig`/`.claude`
that only step_home creates (hidden on Proxmox by prior runs); `sshd -t`
ran unguarded (OrbStack image has no sshd; `openssh-server` is now in
step_apt and the check tolerates an idle socket-activated sshd, missing
`/run/sshd`); `verify` required qemu-guest-agent unconditionally (now only
where `/dev/virtio-ports/org.qemu.guest_agent.0` exists) and had a
duplicated check. Provider-side quirks stay in `providers/orbstack/`:
image lacks `rsync`; OrbStack seeds a one-line `/etc/ssh/sshd_config`
(no Include, `UsePAM no` -> "account is locked" for the passwordless
user), removed by cloud-init `runcmd` before openssh-server lands.

Not done: the "Remote Control environment works from it" acceptance
item needs the manual OAuth login on the OrbStack machine
(`claude auth status` there: loggedIn false; units and `remotes` clones
are in place). Phase 5 step 2 (`providers/cloud/`) not started.
Working tree uncommitted (5 files + providers/orbstack/), `make lint`
green, no secrets in the diff.

## Operator seat

Sessions run from the mac (`~/work/workbench`) or devbox. The mac reaches
the box directly (`agent-vm-ssh` in `~/.ssh/config.local`, 1Password SSH
agent), so `make provision`, `make ssh` and `home/install.sh --check`
over ssh work from the laptop; `make lint` works there (shellcheck, shfmt
from mise). Snapshots and rollbacks still need the Proxmox ssh that devbox
has (`pve-vm-ssh`, Tailscale SSH).

## Next

1. Operator, on the mac: `ssh -t agent@agent-vm@orb claude auth login`,
   then `make claude-remote PROVIDER=orbstack` and open the environment
   from claude.ai. That closes phase 5 step 1's acceptance; record the
   result here.
2. Commit the phase 5 step 1 work (operator decides; nothing committed).
3. Phase 5 step 2: `providers/cloud/user-data.yaml` generic for any Ubuntu
   cloud image (start from `providers/orbstack/user-data.yaml` minus the
   OrbStack `runcmd`; add `qemu-guest-agent`, `rsync`) and one tested
   provider (backlog says Hetzner). Then decide whether
   `providers/orbstack/user-data.yaml` should include the cloud one
   instead of duplicating the users block.
4. Leftovers, not blocking (unchanged from phase 4):
   `~/Documents/all/github/knowledge/.claude/skills` on the mac links to a
   devbox path; ai-hub `lab/` records still say `runtime/`; omp prompts
   still describe the dotfiles/container workflow;
   `providers/proxmox/README.md` sizing notes; `DRY_RUN=1 mac/setup.sh`
   does not say what is at each target; the phase 4 Remote Control item
   was measured by shape only.

## Open questions

- none open; nvim/zellij (box only) and the statusline (one script, both
  repos had the same) were decided in phase 2.

## Backlog (not scheduled)

- `home/install.sh --check` as a `verify` sub-step on the box.
- mise lockfile for the mac profile (see docs/reference/mise-2026.md).
- Weekly `mise up` report as a systemd timer, opt-in.
- Cloud provider test (Hetzner or equivalent) once phase 5 OrbStack passes.

## Log

- 2026-08-18: repo created locally; AGENTS.md, CLAUDE.md, PLAN.md, README,
  docs 00-02 drafted from a survey of agent-vm, dotfiles, ai-hub. Decisions:
  new repo `workbench`, box is VM-only (container target dropped), user
  `agent`, bash, two profiles, settings composed by overlay, ai-hub keeps
  only doctrine/lab/journal. mise researched; profiles = MISE_ENV +
  config.<profile>.toml (verified on 2026.8.8). Review round 1: D1 clean
  start, D5 zsh hand-off, documents rewritten for a public repository.
- 2026-08-19: first commit, repository published (public), Remote Control
  environment `workbench` added. Phase 0 done, phase 1 active.
- 2026-08-19: phase 1 executed. Path changes: rsync staging dir on the box
  is `~/workbench-box/` (was `~/agent-vm-provision/`), on the PVE host
  `/root/workbench/providers/proxmox/` (was `/root/agent-vm/`), Makefile
  gained `PROVIDER ?= proxmox` used only by `vm-create`; `create-vm.sh`
  reads `user-data.yaml` from its own directory. `box/remotes.list` gained
  `workbench` (already registered on the live box in phase 0, so
  `remote-ls` is unchanged; a rebuild now reproduces it). SC2015 in
  `step_system` (`pro config`) rewritten as `if`, same behaviour; it failed
  `make lint` in agent-vm too with shellcheck 0.9.0. Acceptance: `make lint`
  green; `bootstrap.sh user verify` run on the box itself (the session ran
  inside the VM, where the `agent-vm-ssh` alias does not resolve, so the
  rsync + sudo steps of `make provision` were executed by hand with the
  same arguments) - output identical to agent-vm's run except the expected
  `updated /etc/claude-code/CLAUDE.md`; `remote-ls` unchanged (6 units
  active). Not done: `providers/proxmox/README.md` sizing notes from
  agent-vm `docs/design.md` (source map row, not a phase 1 step).
- 2026-08-19: phase 1 committed and pushed (5f47c7e). Operator seat moves
  to devbox (has Proxmox ssh); the in-box session ends here.
- 2026-08-19: phase 1 literal acceptance from devbox: `make provision
  STEPS="user verify"` green, `remote-ls` 6 units; snapshot `pre-phase2`
  (VM 105). Phase 2 executed in eleven commits (8325835..aaa5925): step 1
  install.sh; step 2 merges (mise, git, opwith/op-env, Claude settings,
  statusline, shell layer, herdr/agy/omp/nvim/zellij); step 3 bootstrap
  `step_home`; step 4 mac/. Decisions taken in passing: pull.ff=only over
  pull.rebase; core.pager and color.ui=never dropped from the shared
  gitconfig (env handles the agent path); node pinned to major 24; uv
  backend pin dropped (registry fixed); nvim/zellij box-only; agy settings
  composed with `~` expansion in path lists; MISE_ENV via generated
  `~/.config/workbench/env`. Two live findings fixed in step 3: mise must
  run under the agent's login shell (else only the base 18 tools install)
  and needs GITHUB_TOKEN (anonymous API limit hit at 49 tools) - both in
  `step_tools` now. Box acceptance green; mac acceptance pending.
- 2026-08-19: phase 2 mac acceptance from the laptop. Three fixes: mise
  `bun` moved from config.box.toml to config.toml (the npm backend is set
  to bun in the base settings and omp is a base tool, so the mac install
  of omp failed without it); `home/install.sh log()` printed `\~/` instead
  of `~/`; `BACKUP_DIR` is now shared between mac/setup.sh and
  home/install.sh (was two dirs one second apart). Findings: `brew bundle
  cleanup` proposed only cache files, no packages (fd/fzf/gh/... brew
  copies were already gone); Apple bash 3.2 runs the scripts fine. Phase 2
  done, phase 3 active.
- 2026-08-19: phase 3 executed from the mac in one workbench commit
  (c14838c) plus ai-hub fc2e4e2. `home/install.sh` grew `link_agents` and
  `verify_gate` (the gate blocked this session's own edit command because
  the literal forced-push string appeared in it - the check works). Also:
  AGENTS.md now states bash 3.2 compatibility for scripts shared with the
  mac (macOS updates never move Apple's bash; no brew bash added);
  `mac/setup.sh` runs `mise self-update --yes`; the `1password-cli` cask
  left the Brewfile and the laptop; `autoMode` block kept in
  settings.mac.json. Phase 3 done, phase 4 active.
- 2026-08-19: phase 4 executed from the mac (9ecfd4c..5315e16). Commit
  split note: 9ecfd4c carries all three new mise tasks (zsh:plugins,
  claude:plugins, herdr:integrations rewrite) because the hunks were
  adjacent; 2545a93 is the D12 text only. Phase 4 done, phase 5 active.
- 2026-08-19: session end. omp:auth verified on the box after the Synthetic
  item was recreated as an API Credential in the dotfiles vault (op item
  move refused the original: unsupported SSO field type); merged
  ~/.claude.json installed on the mac. Next session starts phase 5.
- 2026-08-19: phase 5 step 1 (OrbStack) executed from the mac. Machine
  created, deleted, recreated with `make bootstrap-all PROVIDER=orbstack`:
  verify green in about 3 minutes. Three bootstrap.sh bugs only a fresh
  machine shows (chown before home, unguarded sshd -t, unconditional
  qemu-guest-agent) fixed and re-verified on Proxmox too. Remaining
  acceptance item: manual `claude auth login` + `make claude-remote
  PROVIDER=orbstack`. Uncommitted.
