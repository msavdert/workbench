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
| 5 | Portability proof (OrbStack, cloud) | done (cloud skipped, RC login open) |
| 6 | Retire agent-vm, dotfiles, devbox | active |

## Now

Phase 5 closed by operator decision on 2026-08-19 with two exceptions
recorded in `docs/02-migration.md`: the Remote Control acceptance item on
OrbStack waits for the manual `claude auth login`; `providers/cloud/` is
skipped (no cloud account) and moved to the backlog. Everything else from
step 1 is committed and pushed (cffaeee, b1333a4, 6519024): OrbStack
provider, Makefile `PROVIDER=orbstack`, three bootstrap.sh fixes found by
the from-scratch build, `make secrets` reading the token from 1Password
(`dotfiles/agent-vm-op-service-account`). The OrbStack machine is deleted;
`make bootstrap-all PROVIDER=orbstack` rebuilds it in about 3 minutes.
`loginctl enable-linger` on OrbStack was not measured (systemd user units
were listable; the "what could go wrong" note stays open).

Phase 6 (retire) is active. Step 1 executed on 2026-08-19: archive notice
committed to both READMEs (agent-vm 3f055ab, dotfiles 87a1c15) and both
repositories archived on GitHub (`isArchived=true` verified); `agent-vm`
removed from `box/remotes.list`; on the box `remote-rm agent-vm` run and
the clean `~/work/agent-vm` clone deleted; `make provision STEPS="user
remotes verify"` re-applied (27 ok, 0 fail; `/etc/claude-code/CLAUDE.md`
carries the new Layout block; remotes step recreated only workbench).
Nothing on the box or the mac reads from the old repos except session
transcripts (grep on both). Step 2 findings: the devbox container
(`ghcr.io/msavdert/devbox:latest`, from dotfiles `compose.yaml`) still runs
on the OCI VPS `oci-aysesmenn-us-devenv` next to unrelated services
(dokploy, suhuf, trader, dba-dbre); volumes `devbox_*` hold its state;
the operator chose to leave it running for now. workbench has no
`ghcr.io` reference; "devbox" survives only in comments (`home/omp/
config.yml`, `home/mise/config.box.toml`, `home/nvim/lua/{plugins/
devbox.lua,config/lazy.lua,config/options.lua}`, `home/zsh/.zshenv`,
`Makefile`). GitHub: neither old repo had branch protection; agent-vm has
no workflows; ghcr package listing needs the `read:packages` scope (not
confirmed). Step 1 edits are uncommitted.

## Operator seat

Sessions run from the mac (`~/work/workbench`) or devbox. The mac reaches
the box directly (`agent-vm-ssh` in `~/.ssh/config.local`, 1Password SSH
agent), so `make provision`, `make ssh` and `home/install.sh --check`
over ssh work from the laptop; `make lint` works there (shellcheck, shfmt
from mise). Snapshots and rollbacks still need the Proxmox ssh that devbox
has (`pve-vm-ssh`, Tailscale SSH).

## Next

1. Commit the phase 6 step 1 edits (PLAN.md, README.md, box/remotes.list,
   box/files/machine-CLAUDE.md) when the operator asks.
2. Phase 6 step 2: `docker compose down` the devbox container on the VPS
   (`ssh -o RemoteCommand=none opc@oci-aysesmenn-us-devenv`; the compose
   project dir is not yet located), keep or remove `devbox_*` volumes
   (operator decision, destructive), remove `Host dev`/`dev-sh` from the
   mac's `~/.ssh/config.local`, and retire the "devbox" wording in the
   comments listed under Now. Then acceptance: PLAN.md "migration
   complete", AGENTS.md loses its migration section, README status.
3. Open from phase 5: `ssh -t agent@agent-vm@orb claude auth login` then
   `make claude-remote PROVIDER=orbstack` (machine must be rebuilt first);
   `loginctl enable-linger` check on OrbStack.
4. Leftovers, not blocking (unchanged): the mac's
   `~/Documents/all/github/knowledge/.claude/skills` link to a devbox
   path; ai-hub `lab/` records say `runtime/`; omp prompts describe the
   dotfiles/container workflow; `providers/proxmox/README.md` sizing
   notes; `DRY_RUN=1 mac/setup.sh` output; phase 4 Remote Control item
   measured by shape only.

## Open questions

- none open; nvim/zellij (box only) and the statusline (one script, both
  repos had the same) were decided in phase 2.

## Backlog (not scheduled)

- `home/install.sh --check` as a `verify` sub-step on the box.
- mise lockfile for the mac profile (see docs/reference/mise-2026.md).
- Weekly `mise up` report as a systemd timer, opt-in.
- `providers/cloud/`: generic cloud-init user-data plus one tested cloud
  provider (Hetzner or equivalent). Skipped in phase 5: no cloud account.

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
- 2026-08-19: operator closed phase 5 (OrbStack done, cloud skipped, RC
  login open) and set phase 6 active. Token item created in 1Password,
  OrbStack machine deleted, work pushed.
- 2026-08-19: phase 6 step 1 executed from the mac: agent-vm and dotfiles
  archived on GitHub with a README notice pointing here, agent-vm removed
  from remotes.list, remote-rm + clone deletion on the box, provision
  re-applied green. Operator deferred the VPS devbox container (step 2).
  Uncommitted.
