# PVE host NIC hang (Intel I219-LM, e1000e)

The Proxmox host `pve` (Hetzner, 88.99.150.113) is deliberately **not**
managed by this repository. `providers/proxmox/` creates and destroys VMs on
it; the host's own configuration is hand-maintained. The two changes below
were applied by hand on 2026-08-27 and are recorded here rather than encoded,
by the operator's decision. This file is the procedure for re-applying them
after a host reinstall, for backing them out, and for escalating if the
failure returns.

Do not "fix the drift" by moving these into `box/` or `home/`: the ownership
rule in `docs/01-architecture.md` covers the box and the mac, not the
hypervisor.

## The failure

The host's only physical interface is an onboard Intel Ethernet Connection
(7) I219-LM (`00:1f.6`, `8086:15bb` rev 10, Gigabyte board) driven by
`e1000e`, firmware `0.4-4`. Its transmit ring wedges and the driver never
recovers:

```
e1000e 0000:00:1f.6 eno1: Detected Hardware Unit Hang:
  TDH <52>  TDT <3a>  next_to_clean <4f>  next_to_watch.status <0>
  MAC Status <40080083>  PHY Status <796d>  PCI Status <10>
```

TDH and TDT never advance again and the message repeats every two seconds.
No `Reset adapter unexpectedly` line is ever logged, i.e. the driver's own
recovery path never fires. Only a hardware reset restores the link; waiting
does not.

`pve` and the box go dark together because there is one path and one NIC.
`pve` is simultaneously the operator's Tailscale peer (`100.121.170.22`), the
subnet router advertising `10.0.0.0/24` and `10.0.1.0/24`, and the guest NAT
gateway on `vnet0` (`10.0.0.1`, SNAT to the public address). The box itself
is healthy throughout.

Two severities have been seen. Either the kernel stays alive and only the
network is dead (2026-08-22, six hours of logging with no connectivity), or
the host stops responding entirely a few minutes after the first hang.

## Evidence, 2026-08-27 investigation

The journal reaches back to 2026-06-11 and contains no occurrence before
2026-08-22 16:54:03. All times UTC.

| First hang | Boot ended | Hang messages |
|---|---|---|
| 2026-08-22 16:54:03 | 2026-08-22 22:47:53 (operator reset) | ~8900 |
| 2026-08-25 02:04:23 | 2026-08-25 02:06:51 | 75 |
| 2026-08-25 17:08:31 | 2026-08-25 17:12:05 | 108 |
| 2026-08-27 04:35:42 | 2026-08-27 04:38:26 | 83 |

Ruled out, so that a future session does not repeat the work:

- Not SDN. `/etc/pve/sdn/{vnets,subnets}.cfg` date from 2026-08-04, eighteen
  days before the first hang; `zones.cfg` from 2026-05-07.
- Not a kernel regression. The first hangs happened on `7.0.6-2-pve` and
  continued across upgrades to `-12` and `-14`. No apt run on 2026-08-22.
- Not memory or heat. No MCE, no Machine Check, no EDAC error, no thermal
  throttling in any boot. The board is non-ECC (`ie31200`, "No ECC support").
- Not load. In the 2026-08-27 incident the host was idle for the three
  minutes before the hang; only tailscaled DERP keepalives were logged.
- Interface error counters are clean between incidents; link negotiates
  1000 Mb/s full duplex.

The host ran 2.5 months without an incident and then began failing with no
change on this side, which points at the NIC, its firmware, or the switch
port rather than at anything in software.

## What was changed on the host

### 1. Offloads and EEE off (the workaround)

Disabling segmentation and receive offload plus EEE is the commonly cited
mitigation for this erratum. Applied through `/usr/local/sbin/nic-tuning.sh`
(idempotent, tolerates unsupported settings) hooked onto the `vmbr0` stanza
of `/etc/network/interfaces`, next to the `ethtool -K vmbr0` line Proxmox
already put there:

```
  post-up /usr/local/sbin/nic-tuning.sh eno1
```

`eno1` is brought up as a bridge port, so `vmbr0`'s `post-up` is the reliable
hook: it runs after the port exists. `enp0s31f6` in that file is only an
altname of `eno1`; both names work.

Verify:

```
ethtool -k eno1 | grep -E '^(tcp|generic)-(segmentation|receive)-offload:'
ethtool --show-eee eno1 | head -2
```

Expect three `off` lines and `EEE status: disabled`.

### 2. softdog replaced by the Intel PCH TCO hardware watchdog

The host never recovered on its own, so the operator had to reset it from the
Hetzner Robot console every time. `softdog`, which Proxmox arms by default,
cannot help here: it is a kernel timer, so it stops firing exactly when the
kernel stops scheduling. The chipset TCO watchdog does not.

`/etc/default/pve-ha-manager` now sets `WATCHDOG_MODULE=iTCO_wdt`;
`watchdog-mux` loads and feeds it. Verify:

```
cat /sys/class/watchdog/watchdog0/identity   # iTCO_wdt
cat /sys/class/watchdog/watchdog0/state      # active
fuser -v /dev/watchdog                       # watchdog-mux
```

One gotcha when switching on a live host: `/dev/watchdog` is the node of
`watchdog0`, and the module that registers first owns it. Loading `iTCO_wdt`
while `softdog` is still loaded puts it on `watchdog1`, and removing
`softdog` afterwards does not renumber it - `/dev/watchdog` simply
disappears and `watchdog-mux` fails to start. The order that works is: stop
`watchdog-mux`, `rmmod softdog`, `rmmod iTCO_wdt`, `modprobe iTCO_wdt`,
start `watchdog-mux`. At boot the question does not arise, because
`watchdog-mux` now loads only `iTCO_wdt`.

Verified across a reboot on 2026-08-27 05:40 UTC: `watchdog0` is `iTCO_wdt`,
`softdog` is not loaded at all, and no second watchdog registers, so the
live-switch ordering problem above does not recur at boot. The `post-up` hook
had applied the offloads by the time the host was reachable again.

Consequence to be aware of: `watchdog-mux` has `Restart=no`. If it dies, the
TCO resets the host within its 10 s timeout. That was already true with
`softdog`; the reset is now real rather than a kernel timer.

## Re-applying after a host reinstall

```
scp nic-tuning.sh pve-vm-ssh:/usr/local/sbin/nic-tuning.sh
ssh pve-vm-ssh chmod 755 /usr/local/sbin/nic-tuning.sh
```

Add the `post-up` line above to the `vmbr0` stanza, set
`WATCHDOG_MODULE=iTCO_wdt` in `/etc/default/pve-ha-manager`, then run
`/usr/local/sbin/nic-tuning.sh eno1` and `systemctl restart watchdog-mux`.
The script text is reproduced at the end of this file.

## Rolling back

Both originals were copied before the change and are untouched:

```
ssh pve-vm-ssh cp -a /etc/network/interfaces.bak.20260827 /etc/network/interfaces
ssh pve-vm-ssh cp -a /etc/default/pve-ha-manager.bak.20260827 /etc/default/pve-ha-manager
```

Then, to return to the previous runtime state:

```
ssh pve-vm-ssh ethtool -K eno1 tso on gso on gro on
ssh pve-vm-ssh systemctl stop watchdog-mux
ssh pve-vm-ssh rmmod iTCO_wdt
ssh pve-vm-ssh systemctl start watchdog-mux    # loads softdog again
```

Rolling back only the watchdog is enough if the suspicion is a spurious
reset; rolling back only the offloads is enough if throughput on the host
matters more than the hang. They are independent.

## Noticing a recurrence

The chipset watchdog now resets the host on its own, so an outage can pass
unnoticed. Nothing was wired up to announce it. A frozen host cannot send its
own alert, so the only design covering both severities would be an external
dead man's switch - pve pinging out every minute, the absence raising the
alarm - and the operator judged that not worth the moving parts for a fault
this rare. The check is manual and weekly instead:

```
ssh pve-vm-ssh last -x -n 10 reboot
ssh pve-vm-ssh "journalctl -b -1 -k --no-pager | grep -c 'Hardware Unit Hang'"
```

A boot nobody ordered, with a non-zero hang count in the boot before it, is a
recurrence.

## If it happens again

One more occurrence and a Hetzner ticket goes out (operator's decision,
2026-08-27). The draft lives in the operator's own notes rather than in this
repository; what it needs is all above - the hardware identification, the log
signature, the incident timeline and the list of what has been ruled out. The
server number comes from the Robot console. The ask is a switch port and
cabling check, then a NIC or mainboard replacement, or an additional PCIe
card so the onboard I219 leaves the path.

Add the new incident to the timeline table above first, so this record stays
the source the ticket is written from.

## `nic-tuning.sh`

```bash
#!/usr/bin/env bash
# Mitigation for the Intel I219-LM (e1000e) transmit "Detected Hardware Unit
# Hang" erratum. When the TX ring wedges the driver never issues a recovering
# reset, so the host, its Tailscale subnet routes (10.0.0.0/24, 10.0.1.0/24)
# and the guest NAT gateway on vnet0 all go dark until a hardware reset.
# Disabling segmentation/receive offload and EEE is the known workaround.
# First observed 2026-08-22; four outages in six days.
set -euo pipefail

iface="${1:-eno1}"

ip link show "$iface" >/dev/null 2>&1 || exit 0

# Each setting is applied independently: an unsupported one must not stop the
# others, and this runs from an interfaces post-up hook where a hard failure
# would surface as a broken network bring-up.
/usr/sbin/ethtool -K "$iface" tso off gso off gro off || true
/usr/sbin/ethtool --set-eee "$iface" eee off || true
```
