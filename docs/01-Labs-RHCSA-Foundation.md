---
created: 2026-09-02
tags: [rhce, rhcsa, labs, rhel]
---
# 01 — RHCSA Foundation Labs (Days 1–14)

**Month 1 — EX200 track.**

Weeks 1–2. You have Linux/server experience already, so this is compressed:
14 days, not 30. The goal is not exposure, it is **fluency without searching**.

> [!important] How to use these
> Read only the *Requirement*. Do not read the hint until you have genuinely
> tried. Every lab ends with a reboot — a configuration that works now but
> vanishes after reboot is **not finished** and would score zero.

Run these on `rhel01` unless stated. Snapshot first:
`.\lab.ps1 snap pre-lab rhel01`.

> [!tip] Automated checks: `sudo ./verify 1.1` … `./verify 2.7`, or `./verify week1`
> Build it from the *Requirement*, then let the script grade the acceptance
> criteria — before the reboot and again after. See [09-Verification-Scripts](09-Verification-Scripts.md).

---

## Week 1 — Days 1–7

### Lab 1.1 — Navigation, vim, text processing (Day 1, 60 min)

**Requirement**

`/var/log` on rhel01 holds the system logs. Without leaving the terminal:

1. Produce `/root/reports/large-logs.txt` listing every file under `/var/log`
   larger than 100 KB, largest first, showing size and path only.
2. Produce `/root/reports/boot-errors.txt` containing every line of
   `/var/log/messages` (or the journal) that mentions `error` or `fail`,
   case-insensitively, with line numbers preserved.
3. Produce `/root/reports/users.csv` from `/etc/passwd` containing only
   username, UID and shell for accounts with UID ≥ 1000, comma-separated.
4. Do all editing in `vim`. No `nano`, no desktop editor.

**Acceptance criteria**

- [ ] All three files exist under `/root/reports/`
- [ ] `large-logs.txt` is sorted descending by real size, not lexically
- [ ] `boot-errors.txt` catches `Error`, `ERROR`, `failed`, `FAIL`
- [ ] `users.csv` has exactly three comma-separated fields per line and no root

**Verify**

```bash
head -5 /root/reports/large-logs.txt
wc -l /root/reports/boot-errors.txt
awk -F, 'NF!=3 {print "BAD:", $0}' /root/reports/users.csv    # prints nothing
awk -F, '$2<1000' /root/reports/users.csv                     # prints nothing
```

> [!tip]- Hint
> `find -size`, `du`, `sort -h`, `grep -n -iE`, `awk -F:` with `$3>=1000` and
> `OFS=,`. In vim: `:%s/old/new/g`, `:g/pattern/d`, `dd`, `yy`, `:wq`.

---

### Lab 1.2 — Users, groups, and password policy (Day 2, 60 min)

**Requirement**

The team needs accounts on rhel01:

- Group `developers`, GID **5000**.
- Group `contractors`.
- Users `amit`, `sara`, `raj` — primary group `developers`, no login shell
  restriction, home directories under `/home`.
- User `vendor1` — member of `contractors`, must **not** have an interactive
  shell, home `/opt/vendor1`.
- `sara`'s password must expire every 30 days and warn 7 days before.
- `raj`'s account must be locked without being deleted.
- `amit` must be forced to change their password at first login.
- Any user created from now on must get UID ≥ 3000.

**Acceptance criteria**

- [ ] `developers` has GID exactly 5000
- [ ] `vendor1` cannot log in interactively but the account exists
- [ ] `sara` shows max 30 / warn 7 in `chage -l`
- [ ] `raj` is locked (`!` prefix in the shadow hash)
- [ ] `amit`'s last-change date forces a reset
- [ ] A test user created afterwards gets a UID of 3000 or above

**Verify**

```bash
getent group developers            # GID 5000
getent passwd vendor1              # shell is nologin/false
chage -l sara | head -6
passwd -S raj                      # LK
useradd testuid && id -u testuid   # >= 3000
userdel -r testuid
```

**Reboot check** — `sudo reboot`, then re-run every command above.

> [!tip]- Hint
> `groupadd -g`, `useradd -g -s -d`, `chage -M -W -d 0`, `usermod -L`,
> and `/etc/login.defs` for `UID_MIN`.

---

### Lab 1.3 — Permissions, special bits, ACLs (Day 3, 75 min)

**Requirement**

Build a shared project area on rhel01 at `/srv/project`:

1. Owned by `root`, group `developers`.
2. Members of `developers` can create files there; **nobody can delete another
   user's files**, including their own group members.
3. Every new file created inside automatically belongs to group `developers`,
   regardless of who creates it.
4. `sara` gets read-write access to `/srv/project/reports` even though the
   directory's group is `developers` and she must not be added to any new group.
5. `vendor1` gets read-only access to `/srv/project/public` — again without
   group membership changes.
6. New files created in `/srv/project/reports` must inherit sara's access
   automatically.
7. Everything survives a reboot.

**Acceptance criteria**

- [ ] Sticky bit set on `/srv/project`
- [ ] SGID set so group ownership is inherited
- [ ] Named ACL entry for `sara` = `rw` on `reports`
- [ ] Named ACL entry for `vendor1` = `r` on `public`
- [ ] A **default** ACL exists on `reports` so new files inherit it
- [ ] `amit` cannot delete a file created by `raj` in `/srv/project`

**Verify**

```bash
ls -ld /srv/project              # drwxrws--T or similar
getfacl /srv/project/reports
sudo -u raj  touch /srv/project/rajfile
sudo -u amit rm  /srv/project/rajfile     # must FAIL
sudo -u sara touch /srv/project/reports/new && getfacl /srv/project/reports/new
```

**Reboot check** — ACLs live in the filesystem; confirm `getfacl` still reports
them and that the mount still supports ACLs.

> [!tip]- Hint
> `chmod 3770`, or `chmod g+s,o+t`. `setfacl -m u:sara:rw`, and the default ACL
> is `setfacl -d -m u:sara:rw`.

---

### Lab 1.4 — sudo and SSH key authentication (Day 4, 60 min)

**Requirement**

1. `developers` may run **only** `systemctl restart httpd` and
   `systemctl status httpd` as root, without a password. Nothing else.
2. `amit` may run any command as root, but must type their password.
3. Key-based SSH login from `rhel-control` to rhel01 as `amit` must work.
4. Password authentication over SSH must be **disabled entirely** on rhel01.
5. Root must not be able to log in over SSH.
6. SSH must listen on port **2222** in addition to 22.

**Acceptance criteria**

- [ ] `sudo -l -U amit` shows ALL with password
- [ ] A `developers` member can restart httpd without a password
- [ ] The same member cannot run `sudo systemctl restart sshd`
- [ ] `ssh amit@rhel01` from control works with the key, no password prompt
- [ ] `ssh -o PubkeyAuthentication=no amit@rhel01` is refused
- [ ] `ssh -p 2222 amit@rhel01` works
- [ ] `ssh root@rhel01` is refused

**Verify**

```bash
sudo -l -U amit
sudo -u sara sudo -n systemctl status httpd      # works
sudo -u sara sudo -n systemctl restart sshd      # denied
ss -tlnp | grep -E ':(22|2222)'
ssh -p 2222 amit@rhel01 hostname
```

**Reboot check** — mandatory. Port 2222 also needs firewalld **and** SELinux to
allow it; if you skipped either, this is where it fails. That is the point.

> [!tip]- Hint
> `/etc/sudoers.d/` + `visudo -c`. `sshd_config`: `PasswordAuthentication no`,
> `PermitRootLogin no`, `Port 22` / `Port 2222`. Then
> `semanage port -a -t ssh_port_t -p tcp 2222` and `firewall-cmd --add-port`.
> If you have not met `semanage` yet, this is your introduction — see
> [02-Labs-Security-and-Breakfix](02-Labs-Security-and-Breakfix.md).

---

### Lab 1.5 — Find, archives, compression (Day 5, 45 min)

**Requirement**

1. Create `/root/backup/etc-$(date +%F).tar.gz` containing all of `/etc`,
   preserving permissions, ownership and SELinux contexts.
2. Create `/root/backup/logs.tar.bz2` containing every `*.log` file under
   `/var/log` modified in the last 7 days — and nothing else.
3. Find every file on the system owned by `amit` outside `/home` and list it.
4. Find every file with the SUID bit set and write the list to
   `/root/reports/suid.txt`.
5. Extract only `etc/hostname` from the first archive into `/tmp/restore/`
   without extracting anything else.

**Acceptance criteria**

- [ ] Both archives exist and are the correct compression format
- [ ] `logs.tar.bz2` contains only `.log` files, all recent
- [ ] `/tmp/restore/etc/hostname` exists, nothing else does
- [ ] `suid.txt` includes `/usr/bin/passwd` and `/usr/bin/sudo`

**Verify**

```bash
file /root/backup/*.tar.*
tar tzf /root/backup/etc-*.tar.gz | head
tar tjf /root/backup/logs.tar.bz2 | grep -cv '\.log$'    # must be 0
ls -R /tmp/restore
grep -c . /root/reports/suid.txt
```

> [!tip]- Hint
> `tar --selinux --acls --xattrs -czpf`, `find -mtime -7 -name '*.log'` piped
> with `-print0` / `tar -T -`, `find / -perm -4000 -type f`.

---

### Lab 1.6 — Bash scripting (Day 6, 60 min)

**Requirement**

Write `/usr/local/bin/sysreport`, executable by root only, that:

1. Accepts an optional `-o FILE` argument; defaults to stdout.
2. Prints hostname, kernel version, uptime, and RHEL version.
3. Prints the top 5 processes by memory.
4. Prints every filesystem over 80% full, or `OK` if none.
5. Prints any systemd unit in a failed state, or `OK` if none.
6. Exits **1** if any filesystem is over 80% or any unit failed; **0** otherwise.
7. Fails cleanly with a usage message on an unknown flag.

**Acceptance criteria**

- [ ] `sysreport` runs from any directory without a path prefix
- [ ] `sysreport -o /tmp/r.txt` writes the file and prints nothing
- [ ] `echo $?` reflects the health state correctly
- [ ] `sysreport --bogus` prints usage and exits non-zero
- [ ] Script begins with a shebang and uses `set -euo pipefail`

**Verify**

```bash
sysreport | head -20
sysreport -o /tmp/r.txt && echo "healthy" || echo "problem found"
sysreport --bogus; echo "exit=$?"
# force the failure path:
sudo systemctl start nonexistent.service 2>/dev/null; sysreport; echo $?
```

> [!tip]- Hint
> `while getopts` or a `case` loop over `$@`, `df -h --output=pcent,target`,
> `systemctl --failed --no-legend`, `ps --sort=-%mem`.

---

### Lab 1.7 — Week 1 consolidation, timed (Day 7, 90 min)

Restore rhel01 to the `clean` snapshot first. **90 minutes, no notes, no internet.**

**Requirement**

From a fresh rhel01:

1. Group `ops` (GID 4000); users `dev1`, `dev2` in it; `svcacct` with no shell.
2. `/srv/ops` — group-owned by `ops`, SGID, sticky, group-writable.
3. `dev1` may run all commands via sudo without a password; `dev2` may not use
   sudo at all.
4. ACL giving `svcacct` read-only on `/srv/ops`, inherited by new files.
5. SSH: key-only, root login denied.
6. `/usr/local/bin/opscheck` reporting failed units, exiting 1 when any exist.
7. A gzip archive of `/etc/ssh` at `/root/ssh-backup.tar.gz` preserving contexts.
8. **Everything survives a reboot.**

**Score yourself honestly.** Anything you had to look up is your Week 2 revision
list. Write those items into the hub's log.

---

## Week 2 — Days 8–14

### Lab 2.1 — systemd services and targets (Day 8, 60 min)

**Requirement**

1. Install `httpd` and make it start automatically at boot.
2. Create a custom service `siteguard.service` that runs
   `/usr/local/bin/siteguard` (write a script that appends a timestamp to
   `/var/log/siteguard.log` and exits 0), starts after the network is online,
   restarts automatically on failure, and is enabled at boot.
3. The system must boot to a **multi-user** target, never graphical.
4. Mask `debug-shell.service` so it can never be started.
5. Identify which unit is the slowest to start at boot.

**Acceptance criteria**

- [ ] `httpd` enabled and active
- [ ] `siteguard.service` enabled, and its log grows after a reboot
- [ ] `systemctl get-default` → `multi-user.target`
- [ ] `systemctl start debug-shell` fails because it is masked
- [ ] You can name the slowest unit

**Verify**

```bash
systemctl is-enabled httpd siteguard
systemctl cat siteguard.service
systemctl get-default
systemctl start debug-shell.service          # must fail
systemd-analyze blame | head -5
```

**Reboot check** — mandatory. Confirm `/var/log/siteguard.log` gained a line.

> [!tip]- Hint
> Unit files in `/etc/systemd/system/`, `[Unit] After=network-online.target`,
> `[Service] Restart=on-failure`, `[Install] WantedBy=multi-user.target`, then
> `systemctl daemon-reload`.

---

### Lab 2.2 — Processes, journald, scheduled tasks (Day 9, 60 min)

**Requirement**

1. Make the journal **persistent** across reboots.
2. Cap the journal at 200 MB.
3. Find every process owned by `amit` and terminate them all with one command.
4. Start a long-running process, renice it to priority 10, and prove it.
5. A cron job as `amit` running `/usr/local/bin/sysreport -o /tmp/hourly.txt`
   at the top of every hour.
6. A **systemd timer** (not cron) running the same script daily at 02:30, with
   the run persisted if the machine was off.
7. `dev2` must be forbidden from using cron at all.

**Acceptance criteria**

- [ ] `/var/log/journal/` exists and survives reboot
- [ ] `journalctl --disk-usage` respects the 200 MB cap
- [ ] The timer shows a NEXT run at 02:30 and `Persistent=true`
- [ ] `crontab -e` as `dev2` is denied
- [ ] Yesterday's boot is readable via `journalctl -b -1`

**Verify**

```bash
journalctl --disk-usage
systemctl list-timers --all | grep sysreport
crontab -l -u amit
sudo -u dev2 crontab -e            # denied
journalctl -b -1 --no-pager | head
ps -eo pid,ni,comm --sort=-ni | head
```

**Reboot check** — mandatory, this lab is mostly *about* persistence.

> [!tip]- Hint
> `Storage=persistent` and `SystemMaxUse=200M` in `journald.conf`.
> `/etc/cron.deny`. `pkill -u`. Timer needs both `.timer` and `.service` units,
> with `OnCalendar=*-*-* 02:30:00` and `Persistent=true`.

---

### Lab 2.3 — dnf, rpm, repositories (Day 10, 45 min)

**Requirement**

1. Configure a repository from a local directory `/repo` containing at least one
   RPM you place there, with gpgcheck disabled, named `locallab`.
2. Install a package from it.
3. Find which package owns `/etc/hosts` and which files a given package installs.
4. Install the `container-tools` module/group, then list what came with it.
5. Downgrade a package, then roll the transaction back using dnf history.
6. List every package installed in the last 24 hours.

**Acceptance criteria**

- [ ] `dnf repolist` shows `locallab` as enabled
- [ ] The local package installs cleanly
- [ ] You can name the owner of `/etc/hosts` without guessing
- [ ] `dnf history undo` successfully reverses the downgrade

**Verify**

```bash
dnf repolist enabled
rpm -qf /etc/hosts
rpm -ql setup | head
dnf history list | head
dnf history info <ID>
```

> [!tip]- Hint
> `createrepo_c /repo`, a `.repo` file in `/etc/yum.repos.d/` with
> `baseurl=file:///repo`. `dnf history undo <ID>`.

---

### Lab 2.4 — Networking with nmcli (Day 11, 60 min)

**Requirement**

On rhel01, without ever editing a file in `/etc/sysconfig/network-scripts` by hand.

> [!important] Configure the **spare** interface, never the one you arrived on
> `eth0` is how Vagrant reaches this VM and `eth1` carries the lab network —
> reconfiguring either ends your session or gets undone on the next `reload`.
> The environment sets aside a **third NIC with no address** for this lab and
> records it in `/etc/rhce-lab.env`; `verify 2.4` fails you if you configure
> anything else. `ip -4 addr show` will show you which one is empty.

1. Create a connection profile named `lab-static` on the **spare** interface with
   a **static** address `192.168.56.31/24`, two DNS servers, and search domain
   `lab.local`.
2. Set `ipv4.never-default yes` on it. A VirtualBox host-only network has no
   router, so a profile that claims the default route blackholes everything the
   NAT interface was carrying.
3. Set the hostname to `rhel01.lab.local` permanently.
4. Add a second IP `192.168.56.51/24` to the same profile.
5. Ensure the profile autoconnects at boot.
6. Confirm the other nodes are still reachable and resolution still works.

**Acceptance criteria**

- [ ] `nmcli con show lab-static` reports both static addresses
- [ ] It is bound to the spare interface, not `eth0` or `eth1`
- [ ] `192.168.56.11` — the address the environment gave this node — is untouched
- [ ] `hostnamectl` shows the FQDN
- [ ] `ipv4.never-default` is `yes`
- [ ] rhel02 and rhel-control still answer
- [ ] Everything survives `nmcli con down`/`up` **and** a reboot

**Verify**

```bash
ip -4 addr show                        # which interface is empty?
nmcli -f NAME,DEVICE,AUTOCONNECT con show
nmcli con show lab-static | grep -E 'ipv4\.(addresses|dns|never-default)'
hostnamectl
ping -c1 rhel02
```

**Reboot check** — mandatory. A static IP that reverts to DHCP after reboot is a
zero-mark answer.

> [!note] On a KVM host this lab differs
> The libvirt build has a routed lab network with a real gateway at
> `192.168.124.1`, so there the requirement includes a gateway and no
> `never-default`. Everything else is identical — see
> [00-Lab-Environment](00-Lab-Environment.md) §6.

> [!tip]- Hint
> `nmcli con add type ethernet con-name lab-static ifname <spare> ipv4.method
> manual ipv4.addresses ... ipv4.dns "..." ipv4.never-default yes`, then
> `nmcli con up lab-static`. Add a second address with `+ipv4.addresses`.
> `hostnamectl set-hostname`.

---

### Lab 2.5 — Partitions, filesystems, swap, fstab (Day 12, 75 min)

Uses the first blank lab disk (`/dev/sdb` here) on rhel01.

**Requirement**

1. Partition `/dev/sdb`: a 2 GB partition, a 1 GB partition, and leave the rest free.
2. Format the 2 GB partition XFS, labelled `DATA`; mount persistently at
   `/data` **by UUID**.
3. Make the 1 GB partition swap and activate it persistently with priority 10.
4. Mount `/data` with `noexec` and `nodev`.
5. Prove that a script in `/data` cannot execute.
6. Grow the XFS filesystem after enlarging its partition to 4 GB.

**Acceptance criteria**

- [ ] `/data` mounted from a **UUID** entry, not `/dev/sdb1`
- [ ] `swapon --show` lists the partition with priority 10
- [ ] Executing a script under `/data` fails with permission denied
- [ ] `df -h /data` shows ~4 GB after the grow
- [ ] Reboot changes nothing

**Verify**

```bash
lsblk -f /dev/sdb
blkid /dev/sdb1
grep -E 'data|swap' /etc/fstab
findmnt /data                      # shows noexec,nodev
swapon --show
echo -e '#!/bin/bash\necho hi' | sudo tee /data/t.sh; sudo chmod +x /data/t.sh
/data/t.sh                         # must FAIL
```

**Reboot check** — mandatory, and this is the classic exam killer. A wrong
`/etc/fstab` line can leave the box unbootable. Snapshot first, and practise
recovering from exactly that in [02-Labs-Security-and-Breakfix](02-Labs-Security-and-Breakfix.md).

> [!tip]- Hint
> `parted`/`fdisk`, `mkfs.xfs -L`, `mkswap`, `blkid`, fstab fields, `xfs_growfs`
> (XFS grows only, never shrinks), `mount -a` to test **before** rebooting.

---

### Lab 2.6 — LVM (Day 13, 75 min)

Uses `/dev/sdc` on rhel01.

**Requirement**

This is the canonical example of learning by requirement, not by definition:

> Add a new disk → create a PV → add it to a VG → extend an LV by 5 GB → grow the
> XFS filesystem → make sure everything survives a reboot.

Concretely:

1. Volume group `vgdata` with a 16 MB extent size, built on `/dev/sdc`.
2. Logical volume `lvapp`, 4 GB, XFS, mounted persistently at `/app`.
3. Logical volume `lvlogs`, 2 GB, ext4, mounted persistently at `/applogs`.
4. Extend `lvapp` by 5 GB and grow its filesystem online, with no unmount.
5. Reduce `lvlogs` to 1 GB (note which filesystem allows this and which does not).
6. Create a 500 MB snapshot of `lvapp`, then remove it.

**Acceptance criteria**

- [ ] `vgs` shows `vgdata` with a 16 MB extent size
- [ ] `/app` is ~9 GB after extension, with no downtime
- [ ] `/applogs` is 1 GB after reduction and still mounts
- [ ] Both mounts persist across reboot
- [ ] You can explain why shrinking XFS is impossible

**Verify**

```bash
pvs; vgs; lvs
vgdisplay vgdata | grep 'PE Size'
df -h /app /applogs
grep -E 'app' /etc/fstab
lvs -o+seg_size
```

**Reboot check** — mandatory.

> [!tip]- Hint
> `pvcreate`, `vgcreate -s 16M`, `lvcreate -L 4G -n`, `lvextend -L +5G -r`
> (the `-r` resizes the filesystem for you), and for ext4 shrink:
> unmount → `e2fsck -f` → `resize2fs` → `lvreduce`. XFS cannot shrink, ever.

---

### Lab 2.7 — NFS, autofs, Week 2 consolidation (Day 14, 90 min)

**Requirement**

1. On **rhel02**: export `/srv/share` read-write to rhel01 only, and
   `/srv/home-dirs` read-write for home directories.
2. On **rhel01**: mount `rhel02:/srv/share` persistently at `/mnt/share`.
3. Configure **autofs** on rhel01 so that `/net/data` mounts
   `rhel02:/srv/share` on demand and unmounts after 60 seconds idle.
4. Configure autofs so `amit`'s home directory is served from
   `rhel02:/srv/home-dirs/amit` on login.
5. Firewall on rhel02 must permit NFS and nothing extra.

**Acceptance criteria**

- [ ] `showmount -e rhel02` from rhel01 lists both exports
- [ ] `/mnt/share` is writable from rhel01 and persists across reboot
- [ ] `ls /net/data` triggers the mount; it disappears after idle timeout
- [ ] `su - amit` lands in the NFS-served home
- [ ] `firewall-cmd --list-services` on rhel02 shows nfs, mountd, rpc-bind only

**Verify**

```bash
# on rhel01
showmount -e rhel02
findmnt /mnt/share
ls /net/data && findmnt /net/data
sleep 90 && findmnt /net/data          # gone
# on rhel02
sudo exportfs -v
sudo firewall-cmd --list-all
```

**Reboot check** — mandatory on **both** nodes.

> [!tip]- Hint
> `/etc/exports` + `exportfs -rav`. Direct vs indirect autofs maps in
> `/etc/auto.master.d/*.autofs`; `--timeout=60`; wildcard `*` with `&` for homes.

---

## Day 14 gate

Do not move on until every box is ticked. These are EX200 exam objectives, and
Week 3 layers security on top of them — a shaky foundation here shows up as lost
marks on Oct 1.

- [ ] I can add a disk, build LVM on it and grow a filesystem without notes
- [ ] I can configure a static IP with nmcli without notes
- [ ] I can write a systemd unit and timer from memory
- [ ] I can set ACLs including default ACLs without notes
- [ ] I have rebooted after every lab and fixed what broke
- [ ] Nothing on my Week-1 "had to look up" list is still unresolved
- [ ] EX200 is booked (see the hub checklist)

→ Next: [02-Labs-Security-and-Breakfix](02-Labs-Security-and-Breakfix.md)
