#!/usr/bin/env bash
# Create the agent VM on a Proxmox VE host from the Ubuntu 24.04 cloud image.
#
# Runs ON THE PVE HOST as root. The Makefile copies this directory and the
# cloud-init snippet over and invokes it; you can also run it by hand:
#
#   ./create-vm.sh            # create + start
#   VMID=106 ./create-vm.sh   # override anything from vm.env
#
# Idempotency: refuses to touch an existing VMID. Destroy first if you really
# want to rebuild (make vm-destroy).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=vm.env
source "$here/vm.env"

log() { printf '[create-vm] %s\n' "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}

command -v qm >/dev/null || die "qm not found - this must run on the PVE host"
[[ $EUID -eq 0 ]] || die "run as root"

if qm status "$VMID" >/dev/null 2>&1; then
  die "VMID $VMID already exists ($(qm config "$VMID" | awk -F': ' '/^name/{print $2}')). Refusing to overwrite."
fi

# --- cloud-init snippet -----------------------------------------------------
snippet_src="$here/user-data.yaml"
[[ -f $snippet_src ]] || die "missing $snippet_src"
mkdir -p "$SNIPPET_DIR"
install -m 0644 "$snippet_src" "$SNIPPET_DIR/$SNIPPET_NAME"
log "installed snippet $SNIPPET_DIR/$SNIPPET_NAME"

# --- cloud image ------------------------------------------------------------
mkdir -p "$IMAGE_DIR"
image="$IMAGE_DIR/$(basename "$IMAGE_URL")"
sums="$IMAGE_DIR/$(basename "$IMAGE_URL").SHA256SUMS"
log "fetching checksum list"
curl -fsSL "$IMAGE_SUMS_URL" -o "$sums"
expected="$(awk -v f="*$(basename "$IMAGE_URL")" '$2==f{print $1}' "$sums")"
[[ -n $expected ]] || die "could not find checksum for $(basename "$IMAGE_URL")"
if [[ -f $image ]] && [[ "$(sha256sum "$image" | cut -d' ' -f1)" == "$expected" ]]; then
  log "image already present and checksum matches: $image"
else
  log "downloading $IMAGE_URL"
  curl -fL --progress-bar "$IMAGE_URL" -o "$image.part"
  actual="$(sha256sum "$image.part" | cut -d' ' -f1)"
  [[ $actual == "$expected" ]] || {
    rm -f "$image.part"
    die "checksum mismatch: $actual != $expected"
  }
  mv "$image.part" "$image"
  log "image verified"
fi

# --- VM ---------------------------------------------------------------------
# cpu=host: single-node, no live migration, so expose the full i7 feature set.
# balloon=0: Docker + build caches behave badly under ballooning; the RAM is
#            reserved for this VM anyway.
# scsi-single + iothread: one queue per disk, better under parallel builds.
# discard/ssd: let fstrim in the guest release ZFS blocks on the host.
# rng0: cloud images stall on entropy at first boot without it.
# serial console: cloud images log to ttyS0; `qm terminal` works without VNC.
log "creating VM $VMID ($VM_NAME)"
qm create "$VMID" \
  --name "$VM_NAME" \
  --ostype l26 \
  --machine q35 \
  --cpu host \
  --cores "$VM_CORES" --sockets 1 \
  --memory "$VM_MEMORY_MB" --balloon 0 \
  --scsihw virtio-scsi-single \
  --net0 "virtio,bridge=$VM_BRIDGE" \
  --ipconfig0 "ip=$VM_IP_CIDR,gw=$VM_GATEWAY" \
  --nameserver "$VM_DNS" \
  --cicustom "user=$SNIPPET_STORAGE:snippets/$SNIPPET_NAME" \
  --ide2 "$VM_STORAGE:cloudinit" \
  --serial0 socket --vga serial0 \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --rng0 source=/dev/urandom \
  --onboot 1 \
  --tags "$VM_TAGS"

log "importing disk"
qm set "$VMID" --scsi0 "$VM_STORAGE:0,import-from=$image,discard=on,ssd=1,iothread=1"
qm set "$VMID" --boot order=scsi0
qm disk resize "$VMID" scsi0 "${VM_DISK_GB}G"

log "starting"
qm start "$VMID"
log "done. cloud-init will finish in the guest; wait for the guest agent:"
log "  qm agent $VMID ping"
