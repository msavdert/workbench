# Operator-side entry points. Run from any machine that can ssh to the PVE host
# and to the VM (macOS today). Nothing here runs on the VM itself except via
# ssh; the VM-side logic is box/bootstrap.sh.
#
#   make vm-create      create + start the VM on Proxmox
#   make provision      converge the VM on this repo (idempotent, re-run freely)
#   make secrets        push the 1Password service-account token
#   make snapshot NAME=clean
#   make ssh
#
# Hosts are ssh config aliases (managed by `mise run ssh:sync` from 1Password).
SHELL    := /bin/bash
PROVIDER ?= proxmox
PVE_HOST ?= pve-vm-ssh
# proxmox: an ssh config alias to the box (mise run ssh:sync). orbstack: the
# machine reached through OrbStack's own ssh config (`Include ~/.orbstack/ssh/config`).
ifeq ($(PROVIDER),orbstack)
VM_HOST  ?= agent@agent-vm@orb
else
VM_HOST  ?= agent-vm-ssh
endif
VMID     ?= 105
NAME     ?=
STEPS    ?=
# NAME/STEPS/VMID reach the recipes through the environment ($$NAME), never by
# text substitution ($(NAME)) - substitution into a quoted ssh command would
# let a stray quote inject shell. Recipes validate them against a strict pattern.
URL      ?=
OPTS     ?=
export NAME STEPS VMID URL OPTS
define need_name
	@[[ "$$NAME" =~ ^[A-Za-z0-9_.-]+$$ ]] || { echo "NAME must match [A-Za-z0-9_.-]+"; exit 1; }
endef
define check_url_opts
	@re='^[A-Za-z0-9_.:/@+-]*$$'; [[ "$$URL" =~ $$re ]] || { echo "URL has unexpected characters"; exit 1; }
	@re='^[A-Za-z0-9_ -]*$$'; [[ "$$OPTS" =~ $$re ]] || { echo "OPTS has unexpected characters"; exit 1; }
endef
define check_steps
	@re='^[a-z ]+$$'; [[ -z "$$STEPS" || "$$STEPS" =~ $$re ]] || { echo "STEPS must be space-separated step names"; exit 1; }
endef
SSH       = ssh -o BatchMode=yes
RSYNC     = rsync -az --delete --exclude .git

.PHONY: help vm-create vm-wait provision secrets bootstrap-all snapshot rollback snapshots \
        vm-status vm-destroy ssh claude-remote remote-add remote-rm remote-ls lint

help:
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

vm-create: ## create/start the VM: PROVIDER=proxmox (default) on the PVE host, PROVIDER=orbstack on this mac
ifeq ($(PROVIDER),orbstack)
	bash providers/orbstack/create-vm.sh
else
	$(RSYNC) providers/$(PROVIDER)/ $(PVE_HOST):/root/workbench/providers/$(PROVIDER)/
	$(SSH) $(PVE_HOST) "VMID=$$VMID bash /root/workbench/providers/$(PROVIDER)/create-vm.sh"
endif

vm-wait: ## block until the VM answers ssh and cloud-init is done
	@until $(SSH) -o ConnectTimeout=5 $(VM_HOST) true 2>/dev/null; do printf .; sleep 5; done; echo
	$(SSH) $(VM_HOST) 'cloud-init status --wait >/dev/null; cloud-init status'

provision: ## rsync box/ to the VM and run bootstrap.sh (all steps, or STEPS="apt docker")
	$(check_steps)
	$(RSYNC) box/ $(VM_HOST):~/workbench-box/
	$(SSH) -t $(VM_HOST) "sudo ~/workbench-box/bootstrap.sh $$STEPS"

OP_TOKEN_REF ?= op://dotfiles/agent-vm-op-service-account/credential
secrets: ## push OP_SERVICE_ACCOUNT_TOKEN (this shell, else `op read $(OP_TOKEN_REF)`) to ~/.config/op/env on the VM (before provision: step_tools needs it for the GitHub API)
	@t="$$OP_SERVICE_ACCOUNT_TOKEN"; [ -n "$$t" ] || t="$$(op read '$(OP_TOKEN_REF)')"; [ -n "$$t" ] || { echo "no token: set OP_SERVICE_ACCOUNT_TOKEN or unlock 1Password"; exit 1; }; \
	  $(SSH) $(VM_HOST) 'umask 077; mkdir -p ~/.config/op; cat > ~/.config/op/env' <<< "OP_SERVICE_ACCOUNT_TOKEN=$$t"
	@$(SSH) $(VM_HOST) 'bash -lc "if command -v op >/dev/null; then op whoami >/dev/null && echo op: ok; else echo op: token written, op not installed yet; fi"'

bootstrap-all: vm-create vm-wait secrets provision ## fresh VM end to end

claude-remote: ## after `claude auth login`: start the generic `work` server and every project server from box/remotes.list
	$(SSH) $(VM_HOST) 'test -f ~/.claude/.credentials.json || { echo "run: ssh $(VM_HOST) -t claude auth login"; exit 1; }; systemctl --user daemon-reload && systemctl --user enable --now claude-remote.service && for u in $$(systemctl --user list-unit-files "claude-remote@*.service" --state=enabled --no-legend | cut -d" " -f1); do systemctl --user start "$$u"; done; sleep 3; bash -lc remote-ls'

remote-add: ## per-project Remote Control server: NAME=<dir under ~/work> [URL=<git url>] [OPTS="--worktree"]; add it to box/remotes.list to survive a rebuild
	$(need_name)
	$(check_url_opts)
	$(SSH) $(VM_HOST) "bash -lc 'remote-add $$NAME $$URL $$OPTS'"

remote-rm: ## stop + disable the per-project server NAME=<name> (keeps the directory)
	$(need_name)
	$(SSH) $(VM_HOST) "bash -lc 'remote-rm $$NAME'"

remote-ls: ## list Remote Control servers on the VM
	$(SSH) $(VM_HOST) "bash -lc remote-ls"

snapshot: ## qm snapshot NAME=<name>
	$(need_name)
	$(SSH) $(PVE_HOST) "qm snapshot $$VMID $$NAME --description \"$$(date -u +%FT%TZ) $$USER\""

rollback: ## qm rollback NAME=<name> (VM is stopped, rolled back, started)
	$(need_name)
	$(SSH) $(PVE_HOST) "qm rollback $$VMID $$NAME && qm start $$VMID"

snapshots: ## list snapshots
	$(SSH) $(PVE_HOST) "qm listsnapshot $$VMID"

vm-status: ## qm status + guest agent ping
	$(SSH) $(PVE_HOST) "qm status $$VMID; qm agent $$VMID ping && echo 'guest agent: ok'"

vm-destroy: ## stop and destroy the VM (asks for confirmation)
ifeq ($(PROVIDER),orbstack)
	@read -p "delete OrbStack machine agent-vm? type the name to confirm: " a && test "$$a" = agent-vm
	orb delete -f agent-vm
else
	@read -p "destroy VMID $$VMID on $(PVE_HOST)? type the VMID to confirm: " a && test "$$a" = "$$VMID"
	$(SSH) $(PVE_HOST) "qm stop $$VMID || true; qm destroy $$VMID --purge 1"
endif

ssh: ## interactive shell on the VM (tmux session "main")
	ssh -t $(VM_HOST) 'bash -lc agent-session'

lint: ## shellcheck + shfmt check
	shellcheck -e SC1091 providers/proxmox/create-vm.sh providers/orbstack/create-vm.sh box/bootstrap.sh home/install.sh home/bin/opwith home/zsh/install-plugins.sh mac/setup.sh home/claude/statusline.sh home/agy/statusline.sh home/bash/interactive.sh box/files/agent-session box/files/remote-add box/files/remote-rm box/files/remote-ls
	shfmt -d -i 2 -ci providers/proxmox/create-vm.sh providers/orbstack/create-vm.sh box/bootstrap.sh home/install.sh home/zsh/install-plugins.sh mac/setup.sh home/claude/statusline.sh home/agy/statusline.sh home/bash/interactive.sh
