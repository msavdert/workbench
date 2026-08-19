# PLAN.md - live state

This file is the handoff between sessions. Update `Now`, `Next` and `Log`
before ending a session. The migration phases below are complete; their
definition and record is `docs/02-migration.md`.

## Phases

| # | Phase | Status |
|---|---|---|
| 0 | Founding documents | done |
| 1 | Move agent-vm in, unchanged behaviour | done |
| 2 | home/ and mac/ | done |
| 3 | agents/ (from ai-hub runtime) | done |
| 4 | Human layer, herdr/agy/aws-cli, plugins | done |
| 5 | Portability proof (OrbStack, cloud) | done (cloud and OrbStack RC skipped) |
| 6 | Retire agent-vm, dotfiles, devbox | done |

## Now

Migration complete (2026-08-19). From-scratch rebuild test of the Proxmox
box done the same day: `make snapshot` from the mac worked, VM 105
destroyed with all snapshots, `make bootstrap-all` green in 3m14s (47 ok,
0 fail; disk re-imported from the noble cloud image). After the operator's
manual logins (claude, omp, agy) `make claude-remote` starts all five
servers, `home/install.sh --check box` reports no drift after an agy and an
omp run, `opwith git gh api user` and `op whoami` answer, docker runs
hello-world, `clean` snapshot taken (2026-08-19 03:27 UTC). Four bugs only
the fresh path shows, all fixed and pushed: vm-create rsynced into a
missing staging dir on the PVE host (41a4d64); `make claude-remote` never
started template instances because `list-unit-files` does not list them
(uses the `wants/` symlinks now); agy rewrites its settings.json without a
Claude-style `permissions` key and in its own key order, so the block is
gone from `home/agy/settings.base.json` (eceeaf9) and `install.sh` compares
JSON targets by content (0b44295); the mac's multiplexed ssh master
predates the docker group after a rebuild (runbook note). `box/remotes.list`
gained ai-hub, dba-to-dbre, suhuf so they survive rebuilds (188629c).
2026-08-19, later: Remote Control reduced to the single shared
`work` server (capacity 2); `remotes.list` entries are `--clone-only`, the
four per-project servers were disabled on the box (D11 updated). Ghostty
terminfo shipped in `box/files/` after ssh sessions from the mac echoed
every keystroke twice. No active phase; work is backlog-driven.

## Operator seat

Sessions run from the mac (`~/work/workbench`). The mac reaches the box
directly (`agent-vm-ssh` in `~/.ssh/config.local`, 1Password SSH agent),
so `make provision`, `make ssh` and `home/install.sh --check` over ssh
work from the laptop; `make lint` works there (shellcheck, shfmt from
mise). Snapshots and rollbacks need `pve-vm-ssh` (a 1Password `ssh-host`
item; `mise run ssh:sync` on the mac installs it) - not yet exercised from
the mac since the devbox seat is gone.

## Next

1. Pick from the backlog below; nothing else is scheduled.
2. Optional: add `knowledge` to `box/remotes.list` (`--clone-only`) if it
   should be present on the box again.

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
  re-applied green (bb56517). Step 2 repository side: devbox wording and
  the two omp skills rewritten for the box, devbox.lua -> box.lua,
  provision re-applied (c227908). VPS container deferred by the operator.
- 2026-08-19: phase 6 step 2 machine side and acceptance: operator chose
  stop + delete all volumes; compose down -v on the VPS, orphan devbox_*
  volumes and image removed, /home/opc/dotfiles deleted (/home/opc/devbox
  deletion blocked, left to the operator). AGENTS.md migration section,
  README, 02-migration, 03-runbook, PLAN updated: migration complete.
- 2026-08-19: operator finished the hand items (VPS ~/devbox, service
  account rotated, mac ssh entries, ghcr package) and skipped the OrbStack
  Remote Control login for good. Migration record closed.
- 2026-08-19: rebuild test: snapshot from the mac ok, VM 105 destroyed
  with snapshots, bootstrap-all green from scratch in 3m14s after fixing
  vm-create's missing staging dir on the PVE host. Manual logins pending.
- 2026-08-19: rebuild test closed: logins done by the operator, all RC
  servers up, no drift, clean snapshot. Fixed on the way: claude-remote
  template-instance start, agy settings drift (base + JSON-aware check),
  ssh-master docker gotcha documented.
- 2026-08-19: Remote Control cut to the single `work` server (D11);
  `remote-add --clone-only`, remotes.list entries switched, four project
  servers disabled on the box. Ghostty terminfo compiled by step_system
  (doubled keystrokes over ssh). Repo audit by subagents; doc cleanups.
- 2026-08-19: docs/01 operator surface corrected: it listed `mac-setup` and
  `mac-sync` make targets that never existed. The client is driven by
  `mac/setup.sh` and `mise run mac:sync`; `claude-remote` and `vm-destroy`
  added to the Makefile list.
- 2026-08-19: omp's config.yml is generated, not symlinked. An omp 17 schema
  migration (advisor.subagents -> task.agentAdvisor) had rewritten the tracked
  file through the link and stripped its comments; the arrangement now matches
  agy's, with a YAML branch in install.sh's content comparison. Acceptance run
  on the box: `omp config set` leaves the repo clean, `--check` reports the
  drift and exits 1, `install.sh box` reverts it. Settings changed with it:
  modelRoles.default -> gemini-3.7-flash:high, advisor.enabled -> false.
  Applied on both machines, `--check` clean on both. `install.sh mac` also
  reverted ~/.claude/settings.json `model` from a runtime `opus[1m]` back to
  the repo's `claude-fable-5[1m]`; the operator chose to let the repo win
  rather than encode the runtime value, so `/model` in a session is an
  experiment there too, not a setting.
- 2026-08-19: omp config reviewed against `omp models` and the omp-fleet
  benchmark notes. Key fact recovered: Synthetic aliases resolve to concrete
  models (syn:large:text = GLM-5.2, syn:large:vision = Kimi-K3), so `slow`/
  `plan` share a slot with audit/security-reviewer and were NOT moved to the
  vision alias to regain snapcompact - that would queue them in front of
  librarian and docs. Changed: `tiny` :high -> :minimal (comment and suffix
  disagreed), and the `default` fallback chain, whose second rung was the
  primary itself and which no longer crossed providers. Corrected claims in
  config.yml and AGENTS.md: no model here has an `xhigh` rung, snapcompact
  never worked on the main session before the move to flash, the reviewer's
  stated reason, "no subagent sits on the session's model", and a hook said to
  deploy "via the Dockerfile COPY". Also: the `work` Remote Control server was
  stopped, disabled and re-enabled; it came back with the same environment id,
  which is the runbook's point that registrations cannot be removed.
