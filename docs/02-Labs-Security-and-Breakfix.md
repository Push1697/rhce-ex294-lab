---
created: 2026-09-02
tags: [rhce, rhcsa, labs, selinux, firewalld, troubleshooting]
---
# 02 — Security & Break-Fix Labs (Days 15–21)

**Month 1 — EX200 track.**

Week 3. SELinux, firewalld, boot recovery — then you deliberately destroy things
and repair them **without Google**.

> [!important] The rule for this week
> No search engine, no AI, no notes from previous weeks. Only what is on the
> machine: `man`, `--help`, `/usr/share/doc`, `apropos`.
> If you cannot fix it from the box itself, you cannot fix it in the exam.

Snapshot before every drill: `.\lab.ps1 snap pre-lab rhel01`.

> [!tip] Automated checks: `sudo ./verify 3.1` … `3.4`, and `sudo ./verify breakfix`
> `breakfix` has one section per fault `break.sh` injects — run it after every
> repair to catch the second fault you did not notice.
> See [09-Verification-Scripts](09-Verification-Scripts.md).

---

## Day 15 — SELinux fundamentals

### Lab 3.1 — Contexts, booleans, ports (75 min)

**Requirement**

1. Confirm SELinux is **enforcing** and will stay that way after reboot.
2. Serve a website from `/web/site` instead of `/var/www/html`. Apache must be
   able to read it with SELinux enforcing — do **not** disable SELinux, and do
   **not** use `chcon` (the fix must survive a full filesystem relabel).
3. Allow Apache to make outbound network connections to a database.
4. Move `sshd` to port 2222 with SELinux enforcing.
5. Allow Apache to serve content from an NFS-mounted directory.
6. Set the default context for `/web(/.*)?` so that anything created there is
   labelled correctly from the start.

**Acceptance criteria**

- [ ] `getenforce` → Enforcing, and `/etc/selinux/config` agrees
- [ ] `curl http://localhost` returns the page from `/web/site`
- [ ] `restorecon -Rv /web` makes **no** changes (proving the policy is right)
- [ ] `semanage port -l | grep ssh` includes 2222
- [ ] The relevant booleans are persistent, not runtime-only

**Verify**

```bash
getenforce; grep ^SELINUX= /etc/selinux/config
ls -Zd /web/site
semanage fcontext -l | grep '^/web'
semanage port -l | grep -E '^ssh'
getsebool -a | grep -E 'httpd_can_network_connect|httpd_use_nfs'
restorecon -Rvn /web            # dry-run: must output nothing
```

**Reboot check** — mandatory. A `setsebool` without `-P` disappears on reboot;
that is a zero-mark answer and this lab is designed to catch it.

> [!tip]- Hint
> `semanage fcontext -a -t httpd_sys_content_t "/web(/.*)?"` then
> `restorecon -Rv /web`. `setsebool -P httpd_can_network_connect on`.
> `semanage port -a -t ssh_port_t -p tcp 2222`.

---

### Lab 3.2 — Reading SELinux denials (Day 16, 60 min)

**Requirement**

You will be given a broken service (use the saboteur below, fault `selinux-*`).
Your task is to diagnose it **from the audit log alone**:

1. Find the denial.
2. Translate it into plain English — which process, which target, which permission.
3. Decide whether the correct fix is a context change, a boolean, or a port
   definition. Justify the choice.
4. Apply the minimal fix. Never `setenforce 0`, never a blanket module.

**Acceptance criteria**

- [ ] You can locate the denial without knowing in advance what was broken
- [ ] The fix is minimal and targeted
- [ ] SELinux remains enforcing throughout
- [ ] You wrote down the reasoning before applying the fix

**Verify**

```bash
ausearch -m AVC -ts recent
sealert -a /var/log/audit/audit.log | head -40
journalctl -t setroubleshoot --since -10min
semanage fcontext -l | grep <path>
```

> [!warning] The trap
> `audit2allow` will happily generate a policy module that "fixes" anything.
> In the exam that is almost always the wrong answer — it papers over a
> mislabelled file. Reach for `semanage fcontext` + `restorecon` first.

---

## Day 17 — firewalld

### Lab 3.3 — Zones, services, ports, rich rules (75 min)

**Requirement**

1. Default zone `public`; only SSH reachable from anywhere.
2. Zone `internal` containing the `192.168.56.0/24` source, permitting http,
   https and nfs.
3. Open TCP 8080 permanently in `public`, and confirm SELinux also permits
   Apache to bind it.
4. A rich rule rejecting all traffic from `192.168.56.99` with a log entry.
5. Forward port 8080 → 80 on the same host.
6. Everything permanent — no `--runtime` only.

**Acceptance criteria**

- [ ] `firewall-cmd --list-all-zones` shows the intended layout
- [ ] From rhel02, `curl rhel01:8080` succeeds
- [ ] `firewall-cmd --permanent` config matches the runtime config exactly
- [ ] Surviving a reboot changes nothing

**Verify**

```bash
firewall-cmd --get-default-zone
firewall-cmd --list-all --zone=public
firewall-cmd --list-all --zone=internal
firewall-cmd --permanent --list-all --zone=public
firewall-cmd --runtime-to-permanent --dry-run 2>/dev/null || \
  diff <(firewall-cmd --list-all) <(firewall-cmd --permanent --list-all)
```

**Reboot check** — mandatory.

> [!tip]- Hint
> `--permanent` then `--reload`, or configure runtime and commit with
> `--runtime-to-permanent`. Rich rule syntax:
> `--add-rich-rule='rule family=ipv4 source address=192.168.56.99 log prefix="BLOCK" reject'`.

---

## Day 18 — Boot and root recovery

### Lab 3.4 — The four boot failures (90 min)

Snapshot first. Each of these is a real exam scenario.

**Requirement**

1. **Lost root password.** Reset it from the GRUB prompt with no existing access.
   SELinux must still be correct afterwards.
2. **Broken `/etc/fstab`.** Add a bogus entry referencing a non-existent UUID,
   reboot, land in emergency mode, and recover.
3. **Wrong default target.** Set the system to boot to `rescue.target`, reboot,
   and restore multi-user from there.
4. **Missing `/boot` entry.** Regenerate the GRUB configuration after a kernel
   update leaves the menu broken.

**Acceptance criteria**

- [ ] Root password reset without external media
- [ ] You know why `/.autorelabel` matters after a password reset
- [ ] Recovered from emergency mode by fixing fstab, not by reinstalling
- [ ] `systemctl set-default multi-user.target` restored and verified by reboot
- [ ] GRUB config regenerated at the correct path for the boot mode (BIOS vs UEFI)

**Verify**

```bash
systemctl get-default
findmnt --verify --verbose        # validates fstab BEFORE you reboot
mount -a                          # must be silent
ls /boot/grub2/grub.cfg /boot/efi/EFI/redhat/grub.cfg 2>/dev/null
```

> [!tip]- Hint
> At GRUB: `e`, append `rd.break` to the kernel line, `Ctrl-x`, then
> `mount -o remount,rw /sysroot`, `chroot /sysroot`, `passwd`,
> `touch /.autorelabel`, exit twice.
> **`findmnt --verify` before every reboot** is the habit that prevents fstab
> disasters entirely.

---

## Days 19–21 — Break-fix drills

This is the most valuable block of the entire 60 days.

### The saboteur script

Save outside the vault as `~/Desktop/projects/rhce-lab/break.sh` on **rhel01**.
Have a colleague run it, or run it yourself and then wait long enough to forget
which fault you picked. `./break.sh random` is the honest version.

```bash
#!/usr/bin/env bash
# break.sh — deliberately damage this box so you can practise repairing it.
# ALWAYS snapshot first:  .\lab.ps1 snap pre-lab rhel01
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }

fault_fstab() {        # boot fails into emergency mode
  printf 'UUID=00000000-dead-beef-0000-000000000000 /data xfs defaults 0 0\n' >> /etc/fstab
}
fault_selinux_ctx() {  # httpd 403s on correctly-permissioned files
  mkdir -p /web/site; echo ok > /web/site/index.html
  chcon -t user_home_t /web/site/index.html 2>/dev/null || true
  sed -i 's#^DocumentRoot.*#DocumentRoot "/web/site"#' /etc/httpd/conf/httpd.conf
  systemctl restart httpd 2>/dev/null || true
}
fault_selinux_port() { # sshd refuses to start on a new port
  sed -i 's/^#\?Port 22$/Port 2222/' /etc/ssh/sshd_config
  semanage port -d -t ssh_port_t -p tcp 2222 2>/dev/null || true
}
fault_firewall() {     # service runs, nothing can reach it
  firewall-cmd --permanent --remove-service=http >/dev/null 2>&1 || true
  firewall-cmd --permanent --remove-port=8080/tcp >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null
}
fault_service() {      # unit fails at start
  printf '\nInvalidDirective yes\n' >> /etc/httpd/conf/httpd.conf
  systemctl restart httpd 2>/dev/null || true
}
fault_perms() {        # ssh key auth silently stops working
  chmod 777 /home/amit/.ssh 2>/dev/null || true
  chmod 666 /home/amit/.ssh/authorized_keys 2>/dev/null || true
}
fault_repo() {         # dnf breaks
  sed -i 's#^baseurl=.*#baseurl=file:///nonexistent#' /etc/yum.repos.d/locallab.repo 2>/dev/null || \
    printf '[broken]\nname=broken\nbaseurl=http://invalid.example.com/repo\nenabled=1\ngpgcheck=0\n' \
      > /etc/yum.repos.d/broken.repo
}
fault_dns() {          # name resolution dies, IPs still work
  nmcli con mod lab-static ipv4.dns "203.0.113.99" 2>/dev/null || true
  nmcli con up lab-static >/dev/null 2>&1 || true
}
fault_sudo() {         # a group loses privilege escalation
  sed -i 's/^%wheel/#%wheel/' /etc/sudoers
}
fault_mount() {        # persistent mount silently absent after reboot
  sed -i '/\/app/s/^/#/' /etc/fstab
  umount /app 2>/dev/null || true
}

FAULTS=(fstab selinux_ctx selinux_port firewall service perms repo dns sudo mount)

case "${1:-random}" in
  random) f="${FAULTS[$RANDOM % ${#FAULTS[@]}]}"; "fault_$f"
          echo "A fault has been applied. Good luck." ;;
  list)   printf '%s\n' "${FAULTS[@]}" ;;
  all)    for f in "${FAULTS[@]}"; do "fault_$f"; done; echo "All faults applied. Brutal mode." ;;
  *)      "fault_$1" && echo "Applied: $1" ;;
esac
```

### The drill

```text
Symptom
   ↓
Reproduce it deliberately        ← never fix what you cannot reproduce
   ↓
Read the logs (journalctl -xe, /var/log, ausearch)
   ↓
Form ONE hypothesis
   ↓
Test the hypothesis
   ↓
Fix minimally
   ↓
Verify
   ↓
REBOOT
   ↓
Verify again
```

Time yourself. Target by Day 21: **under 10 minutes per fault**, closed-book.

### Fault log

Keep this table filled in — it becomes your Week 4 revision list before the
EX200 mocks.

| Date | Fault | Time to fix | First hypothesis right? | What gave it away |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

### Diagnostic reflexes worth drilling

| Symptom | First three commands |
| --- | --- |
| Service will not start | `systemctl status -l`, `journalctl -xeu <unit>`, config syntax check |
| Service runs, unreachable | `ss -tlnp`, `firewall-cmd --list-all`, `ausearch -m AVC -ts recent` |
| Permission denied despite correct `ls -l` | `ls -Z`, `ausearch -m AVC`, `getfacl` |
| Works until reboot | `systemctl is-enabled`, `grep /etc/fstab`, `setsebool` without `-P` |
| Cannot resolve names | `resolvectl status`, `cat /etc/resolv.conf`, `nmcli con show` |
| SSH key auth fails | `ls -ld ~/.ssh`, `journalctl -u sshd`, `sshd -T \| grep -i pubkey` |
| dnf fails | `dnf repolist --all`, `dnf clean all`, check `baseurl` reachability |
| Disk full but `du` disagrees | `lsof +L1`, deleted-but-open file handles |

---

## Day 21 gate — RHCSA consolidation

By now, given a blank RHEL VM and a written requirement, you should build it
without searching. Test yourself: restore `clean`, then complete Lab 1.7 plus
Labs 2.5 and 2.6 in **two hours total**, closed-book.

- [ ] SELinux never disabled to make something work
- [ ] Every fault in `break.sh list` fixed in under 10 minutes
- [ ] `findmnt --verify` is now automatic before any reboot
- [ ] I can reset a root password from GRUB from memory
- [ ] Confirmed the exam code with L&D (from the hub checklist)
- [ ] EX200 booked for ~Day 30

When these ten faults stop being interesting, the harder set is in
[10-Advanced-Breakfix-Labs](10-Advanced-Breakfix-Labs.md) — one cause that needs three fixes, faults that
only appear after a reboot, and a permissions problem that is not one.

→ Next: [03-EX200-Exam-Prep](03-EX200-Exam-Prep.md) — containers, tuned, and the EX200 mocks.
