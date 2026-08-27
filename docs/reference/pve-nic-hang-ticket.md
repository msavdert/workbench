Subject: Recurring onboard NIC failure (I219-LM, e1000e TX unit hang) - server 88.99.150.113

Server: 88.99.150.113 (hostname: pve)
Server number: <ROBOT'TAN DOLDUR>

Hello,

Since 2026-08-22 the onboard network interface of this server has locked up
four times. Each time the machine becomes completely unreachable and only a
hardware reset from the Robot console restores it - it never recovers on its
own. I have waited several hours on one occasion; the link did not come back.

Hardware and software:

  NIC        Intel Ethernet Connection (7) I219-LM
             PCI 00:1f.6, ID 8086:15bb rev 10 (onboard, Gigabyte board)
  Driver     e1000e, firmware-version 0.4-4
  OS         Proxmox VE 9.2.11, kernel 7.0.14-14-pve
  Link       1000 Mb/s, full duplex, autonegotiation on

Kernel log signature, repeated every 2 seconds once it starts:

  e1000e 0000:00:1f.6 eno1: Detected Hardware Unit Hang:
    TDH                  <52>
    TDT                  <3a>
    next_to_use          <3a>
    next_to_clean        <4f>
    next_to_watch.status <0>
    MAC Status           <40080083>
    PHY Status           <796d>
    PCI Status           <10>

The transmit descriptor head and tail never advance again, and the driver
never logs a recovering "Reset adapter unexpectedly" - the interface stays
dead until the machine is reset.

Incident timeline (all times UTC):

  2026-08-22 16:54:03  first occurrence, ~8900 hang messages over 6 hours,
                       host reachable on console but no network; reset 22:47
  2026-08-25 02:04:23  75 messages, host stopped responding entirely 02:06:51
  2026-08-25 17:08:31  108 messages, host stopped responding entirely 17:12:05
  2026-08-27 04:35:42  83 messages, host stopped responding entirely 04:38:26

The system journal reaches back to 2026-06-11 and contains no occurrence of
this message before 2026-08-22 16:54:03. The machine ran for 2.5 months
without a single incident and then started failing without any change on my
side: no kernel upgrade that day, no package installation that day, and the
network configuration had been unchanged since 2026-08-04.

What I have already ruled out on the software side:

  - No MCE, no Machine Check, no EDAC errors, no thermal throttling in any log
  - The failure is not load related: in the most recent incident the host was
    idle for the three minutes preceding the hang
  - Interface error counters are clean between incidents
  - Not a kernel regression: the first incidents happened on kernel
    7.0.6-2-pve, and they continued after upgrades to 7.0.14-12 and -14

As a workaround I have now disabled TCP/generic segmentation offload, generic
receive offload and EEE on the interface. This is the commonly cited
mitigation for this erratum, so the symptom may be masked from now on, but I
do not consider it a fix.

Could you please:

  1. Check the switch port and the cabling for this server
  2. Check the onboard NIC / consider replacing the mainboard or the server

If replacing the hardware is not straightforward, I would also be happy with
an additional PCIe network card so the onboard I219 can be taken out of the
path.

Thank you.
