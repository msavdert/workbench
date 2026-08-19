#!/usr/bin/env bash
# Create the box as an OrbStack Linux machine on the laptop.
#
# Runs ON THE MAC (bash 3.2). The Makefile invokes it for PROVIDER=orbstack;
# by hand:
#
#   ./create-vm.sh                 # create + start
#   VM_NAME=agent-2 ./create-vm.sh # override anything from vm.env
#
# Idempotency: an existing machine of that name is started if stopped and
# otherwise left alone. Delete first if you really want to rebuild
# (make vm-destroy PROVIDER=orbstack).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=vm.env
source "$here/vm.env"

log() { printf '[create-vm] %s\n' "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}

command -v orb >/dev/null || die "orb not found - install OrbStack (mac/Brewfile) and open it once"

state="$(orb info "$VM_NAME" -f json 2>/dev/null | sed -n 's/.*"state": *"\([a-z]*\)".*/\1/p' | head -n1 || true)"
if [ -n "$state" ]; then
  log "machine $VM_NAME exists (state: $state)"
  if [ "$state" != "running" ]; then
    orb start "$VM_NAME"
    log "started"
  fi
  exit 0
fi

log "creating $VM_NAME ($VM_DISTRO, ${VM_CPUS} cpu, ${VM_MEMORY} mem, ${VM_DISK} disk, user $VM_USER)"
orb create \
  --user "$VM_USER" \
  --user-data "$here/user-data.yaml" \
  --cpus "$VM_CPUS" \
  --memory "$VM_MEMORY" \
  --disk "$VM_DISK" \
  "$VM_DISTRO" "$VM_NAME"

log "created. ssh: ssh $VM_USER@$VM_NAME@orb (OrbStack ssh config) - next: make vm-wait provision PROVIDER=orbstack"
