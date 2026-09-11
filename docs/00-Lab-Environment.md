---
created: 2026-09-02
tags: [rhce, lab, vagrant, virtualbox, windows, rhel]
---
# 00 — Lab Environment (Vagrant + VirtualBox on Windows)

Three nodes on the Windows box, built by one `Vagrantfile`, driven by one
PowerShell wrapper. Everything the labs and checkers need is provisioned; nothing
a lab is supposed to teach you is.

```text
              CONTROL NODE
               rhel-control          192.168.56.10
               2 vCPU / 2 GB
                    │
             ┌──────┴──────┐
             │             │
          SSH/Ansible   SSH/Ansible
             │             │
             ▼             ▼
          rhel01          rhel02
      192.168.56.11    192.168.56.12
       2 vCPU / 1.5 GB  1 vCPU / 1.5 GB
       + 2 blank disks  + 2 blank disks   ← the LVM/partition labs
       + 1 spare NIC                      ← the nmcli lab
```

**Where it lives:** `verify/vagrant/` in this project. `vagrant up` from there.

## 1. Host prerequisites

Confirmed present on this machine:

| | |
| --- | --- |
| Vagrant | 2.4.9 |
| VirtualBox | 7.2.16 |
| Host-only adapter | 192.168.56.1/24 |
| RAM / CPU | 23.7 GB · 12 logical |
| Free disk | 263 GB (the lab needs ~8 GB) |

```powershell
cd 1-Projects\RHCE-EX294-Prep\verify\vagrant
.\lab.ps1 doctor        # re-check any time
```

> [!warning] A hypervisor is already running on this machine
> Memory Integrity (Core Isolation) and WSL2 keep Hyper-V active, so VirtualBox
> runs **nested** — it works, but boots and disk I/O are noticeably slower.
>
> Full speed means turning off Core Isolation ▸ Memory Integrity and
> `bcdedit /set hypervisorlaunchtype off`, then rebooting. That also disables
> WSL2 and Docker Desktop, and lowers the machine's security hardening. For
> these labs the slower nested mode is perfectly usable — start there, and only
> trade it away if boots become genuinely painful.

> [!important] VirtualBox restricts host-only addressing
> Only `192.168.56.0/21` is permitted unless you create
> `%ProgramData%\VirtualBox\networks.conf`. That is why the lab sits on
> 192.168.56.x rather than the 192.168.124.x the KVM build used. All the labs and
> checkers detect the network rather than assuming it, so nothing breaks if you
> change it — set `LAB_NET` and rebuild.

## 2. Which distribution

The `Vagrantfile` defaults to **Rocky Linux 9** — free, no subscription, boots in
one command, and behaves identically to RHEL for every objective in this
curriculum.

```powershell
# the default
.\lab.ps1 up

# real RHEL instead, if L&D wants it (needs a developer subscription
# and `subscription-manager register` on each node afterwards)
$env:LAB_BOX = 'generic/rhel9'; .\lab.ps1 up
```

> [!note] What Rocky costs you
> Only `subscription-manager` practice. It is not an RHCSA objective, and
> "configure a repository" — which *is* one — works the same on both (Lab 2.3).
> Everything else, SELinux included, is identical. Confirm the target RHEL
> version with L&D and match the major version.

## 3. Build it

```powershell
cd 1-Projects\RHCE-EX294-Prep\verify\vagrant
.\lab.ps1 up            # first run downloads a ~1 GB box; later rebuilds ~2 min
.\lab.ps1 status
.\lab.ps1 ssh rhel01
```

What `vagrant up` does that you would otherwise do by hand:

- **Linked clones.** Each VM shares the base box's disk, so three nodes cost
  megabytes rather than gigabytes — the Vagrant equivalent of a qcow2 overlay.
- **Two blank 10 GB disks** on rhel01 and rhel02. VirtualBox presents them as
  **`/dev/sdb` and `/dev/sdc`**, where KVM gave `vdb`/`vdc`. Every lab and
  checker detects this, so no lab text depends on the name.
- **A spare unconfigured NIC on rhel01** for the nmcli lab — see §6.
- **A shared lab SSH key** in `vagrant/keys/`, so rhel-control can reach both
  managed nodes. Vagrant's own per-VM key is no use for node-to-node access.
- **`/etc/hosts`** naming all three nodes on every node.
- **The lab kit mounted read-only at `/opt/rhce-labs`** — no `scp`, no bundling.
- **`~/ansible/`** on the control node with the `ansible.cfg` and inventory that
  [04-Labs-Ansible-Fundamentals](04-Labs-Ansible-Fundamentals.md) Lab 5.1 expects.

The lab account is **`vagrant`**, with passwordless sudo. That is the user the
Ansible inventory and the checkers assume.

## 4. Snapshots — the habit the whole break-fix half depends on

`vagrant snapshot` is a straight replacement for `virsh snapshot-*`, and
`lab.ps1` wraps all three nodes at once.

```powershell
.\lab.ps1 snap clean            # after the acceptance test passes
.\lab.ps1 snap pre-lab rhel01   # before any destructive lab
.\lab.ps1 restore clean         # recovery, in seconds
.\lab.ps1 snaps                 # what exists
```

> [!warning] Take `clean` once the lab is *known good*, not when it is empty
> Reverting past provisioning means re-running it every time. Build, run the
> acceptance test, then snapshot.

> [!info]- Why the lab disks are attached by hand, and not with `config.vm.disk`
> Vagrant's experimental disk support reconciles the extra disks on every `up`
> and `reload`, matching them by the **filename** of the medium currently
> attached. A `vagrant snapshot restore` swaps that medium for the snapshot's
> differencing image, whose filename is `{uuid}.vdi` — so the reconciliation
> decides `rhel01-lab1` has gone missing, tries to create it, and aborts
> because the base VDI is still there. The machine is then powered off and
> `vagrant up` keeps failing until you hand-edit
> `.vagrant/machines/*/virtualbox/disk_meta`.
>
> Snapshots are taken before every break-fix drill here, so that is the normal
> path, not an edge case. The Vagrantfile therefore creates and attaches the
> two blank disks itself and skips any port that already has something on it.
> `VAGRANT_EXPERIMENTAL=disks` is no longer needed.

## 5. Running the labs and the checkers

The kit is already inside every node, so there is nothing to copy:

```powershell
.\lab.ps1 check env rhel-control     # the acceptance test
.\lab.ps1 check 2.5 rhel01           # one lab
.\lab.ps1 ssh rhel01                 # or work inside the node
```

```bash
# inside a node
sudo /opt/rhce-labs/verify              # list every check
sudo /opt/rhce-labs/verify 2.5
sudo reboot
sudo /opt/rhce-labs/verify 2.5 --after-reboot
```

The saboteurs are there too:

```powershell
.\lab.ps1 break firewall rhel01           # a single-cause fault
.\lab.ps1 break-advanced random rhel01    # one of the ten harder ones
.\lab.ps1 reveal rhel01                   # afterwards: what it did, and your time
```

> [!tip] `/opt/rhce-labs` is mounted read-only
> Deliberately: a mistake inside a VM can never reach the vault copy on Windows.
> It also means `./verify bundle` cannot write there — and does not need to,
> since the kit is already mounted.

## 6. Three places this differs from the KVM build

All three are consequences of VirtualBox, and all three are handled — but know
why.

**The nmcli lab targets a spare interface.** Vagrant manages `eth1` (the lab
network) and reaches the VM over NAT on `eth0`. Reconfiguring either would end
your session or fight Vagrant on the next `reload`. So rhel01 gets a **third
NIC, created and left unconfigured**, and [01-Labs-RHCSA-Foundation](01-Labs-RHCSA-Foundation.md) Lab 2.4
configures that. `verify 2.4` refuses to pass if you configured the management
interface instead.

**There is no gateway on the lab network.** A VirtualBox host-only network has
no router — 192.168.56.1 is the Windows host, not a gateway. So Lab 2.4 drops
the "set a gateway" requirement and adds `ipv4.never-default yes` instead, which
is the correct answer for a secondary interface anyway and a better habit than
what the KVM version taught.

**firewalld is installed by the provisioner.** A stock RHEL 9 minimal install
has firewalld installed and enabled; this Vagrant box does not ship it. Every
firewall lab, checker and saboteur assumes it exists — without it the break-fix
drills stage a firewall fault against nothing and report a symptom that is not
there. So the provisioner installs and enables it, with its **default ruleset
untouched**: opening a port is always the lab's job, never the environment's.
The same applies to `chronyd`, so the clock drill has a service to re-enable.

> [!note] This is the line the provisioner tries to hold
> It installs what a real RHEL box would already have, and nothing a lab is
> supposed to teach you to install. `httpd`, `podman`, `nfs-utils` and the
> SELinux tooling are deliberately absent — working out that you need them is
> part of the exercise.

## 7. Acceptance test

Do not start Week 1 until this passes on **all three** nodes.

```powershell
.\lab.ps1 doctor                      # the Windows side
.\lab.ps1 check env rhel-control
.\lab.ps1 check env rhel01
.\lab.ps1 check env rhel02
.\lab.ps1 snap clean
```

- [ ] All three nodes build and boot
- [ ] Every node resolves and pings the other two
- [ ] Passwordless sudo on all three
- [ ] `ansible managed -m ping` returns SUCCESS for both, and become gives uid 0
- [ ] `~/ansible` is **not** world-writable — otherwise Ansible ignores its config
- [ ] Two lab disks detected on rhel01 and rhel02
- [ ] An unconfigured interface exists on rhel01
- [ ] `clean` snapshot on all three

## 8. Editing playbooks from Windows (optional)

Month 2 means a lot of YAML. You can edit it in VS Code on Windows and run it in
the VM:

```powershell
$env:LAB_ANSIBLE_SYNC = '1'; .\lab.ps1 reload
```

That shares `verify/vagrant/ansible/` as `~/ansible` on the control node, mounted
`dmode=755,fmode=644`.

> [!warning] Why those mount options matter
> VirtualBox mounts shares **777** by default, and Ansible **silently ignores**
> an `ansible.cfg` in a world-writable directory. That is exactly the trap Lab
> 5.1 warns about, and an unqualified synced folder walks straight into it. The
> provisioner checks for it and says so.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `up` hangs at "Waiting for machine to boot" | Nested virtualisation is slow; give it 2–3 minutes before worrying |
| "VT-x is not available" | Virtualisation disabled in BIOS/UEFI, or Hyper-V has taken exclusive control |
| Host-only network refused | The IP is outside 192.168.56.0/21 → set `LAB_NET` or write `networks.conf` |
| No `/dev/sdb`, `/dev/sdc` | The Vagrantfile attaches them itself; check `VBoxManage showvminfo rhel01` for its SATA ports and re-run `.\lab.ps1 up` |
| `Disk 'rhel01-lab1' not found in guest` on `up` | An older Vagrantfile that still used `config.vm.disk` — see the snapshot note in §4 |
| The clock keeps correcting itself | Expected: the guest additions sync it from the host. The clock drill breaks the timezone, `/etc/adjtime` and the time service instead, none of which the hypervisor touches |
| `\r: command not found` inside a VM | A script reached the guest with CRLF endings; `verify/.gitattributes` pins `*.sh eol=lf`, so check your git config did not override it |
| `ansible.cfg` ignored | `~/ansible` is world-writable — see §8 |
| SSH between nodes asks for a password | `vagrant/keys/` was deleted after provisioning → `.\lab.ps1 provision` |
| Everything is slow | See the nested-hypervisor warning in §1 |

## Appendix — the KVM/libvirt build

The original Linux-host version still works and is unchanged: `lab-build.sh`
and `lab-destroy.sh` at the root of the lab repo, documented in
[Building a Three-Node RHEL Lab on KVM](https://learning.overflowbyte.cloud/blog/building-a-three-node-rhel-lab-on-kvm). It uses virtio disks (`vdb`, `vdc`)
and the routed 192.168.124.0/24 libvirt network with a real gateway.

Nothing in the labs or checkers cares which of the two you are on — they detect
the platform, the disks and the network. `verify env` prints what it found.

## Next

→ [01-Labs-RHCSA-Foundation](01-Labs-RHCSA-Foundation.md)
