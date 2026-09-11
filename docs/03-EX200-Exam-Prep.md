---
created: 2026-09-02
tags: [rhcsa, ex200, exam, labs, containers, podman]
---
# 03 — EX200 Exam Prep (Days 22–30)

Week 4 and the end of Month 1. This is where RHCSA stops being "foundation
work" and becomes **an exam you sit and pass**.

You need EX200 anyway: RHCSA is the prerequisite that makes an EX294 pass count
toward RHCE. Certifying it first is the correct order, not a detour.

> [!important] Month 1 ends with a certificate, not a feeling
> Target: **book EX200 for on or near Day 30 (Oct 1)**. Book it in Week 1, while
> there is still time to move it. A booked date is the thing that makes the
> first three weeks honest.

---

> [!tip] The evening break-fix block, Days 22–29
> [10-Advanced-Breakfix-Labs](10-Advanced-Breakfix-Labs.md) holds ten harder drills — faults that stay silent
> until a reboot, or put three causes behind one symptom. One per evening, on top
> of the gap-closing labs below.

> [!tip] Automated checks: `./verify 4.1`, `sudo ./verify 4.2`, and the mock graders
> `./verify ex200-a --spec` prints the exam paper with every value pinned;
> `sudo ./verify ex200-a --after-reboot` scores it out of 300.
> See [09-Verification-Scripts](09-Verification-Scripts.md).

## Days 22–23 — Gap-closing labs

Weeks 1–3 covered the classic RHCSA ground. Current EX200 objectives include two
areas those labs did **not** touch. Close them now.

### Lab 4.1 — Containers with podman (Day 22, 90 min)

Current RHCSA objectives include managing containers: finding and retrieving
images, running them, attaching persistent storage, and starting them
automatically via systemd. This is the most commonly missed section by people who
prepared from older material.

**Requirement**

As a **non-root** user on rhel01:

1. Find and pull a web server image from a registry.
2. Inspect the image and report which ports it exposes.
3. Run it rootless, published on host port 8080.
4. Attach persistent storage: host directory `/opt/webdata` mounted into the
   container's document root, with SELinux labelling handled correctly.
5. Serve a file placed in `/opt/webdata` from the host, verified with curl.
6. Generate a systemd unit so the container starts automatically **at boot as
   that non-root user**, without anyone logging in.
7. Set an environment variable inside the container at run time.

**Acceptance criteria**

- [ ] Container runs rootless — `podman ps` as the user, not root
- [ ] `curl localhost:8080` returns the file from `/opt/webdata`
- [ ] The container restarts automatically after a **full reboot**, with nobody
      logged in
- [ ] Storage persists across `podman rm` and recreation

**Verify**

```bash
podman images; podman ps
podman inspect <image> | grep -i exposedports
curl localhost:8080
systemctl --user is-enabled <unit>
loginctl show-user "$USER" | grep Linger      # must be yes
sudo reboot
# after reboot, WITHOUT logging in as the user, from another session:
curl localhost:8080
```

> [!warning] The two traps in this lab
> **Lingering:** a `--user` unit does not start at boot unless
> `loginctl enable-linger <user>` is set. Without it your container only starts
> when the user logs in — which the grader will not do.
> **SELinux on the volume:** mount with `:Z` (or set the container file context),
> or the container gets permission denied on a directory that looks perfectly
> readable.

> [!tip]- Hint
> `podman search`, `podman pull`, `podman run -d -p 8080:8080 -v /opt/webdata:/var/www/html:Z`,
> `podman generate systemd --new --files --name`, or a Quadlet `.container` file
> in `~/.config/containers/systemd/` on newer RHEL. Then
> `systemctl --user daemon-reload && systemctl --user enable --now`.

### Lab 4.2 — tuned, kernel and boot targets (Day 23, 60 min)

**Requirement**

1. Report the currently active tuned profile and switch to one appropriate for
   a virtual guest, persistently.
2. Let tuned recommend a profile and explain why it chose it.
3. List installed kernels and boot into a **specific, non-default** kernel once,
   without making it permanent.
4. Set a different kernel as the permanent default.
5. Add a kernel command-line parameter persistently.
6. Boot into `rescue.target` deliberately and return to multi-user.

**Acceptance criteria**

- [ ] `tuned-adm active` shows the chosen profile after reboot
- [ ] You booted a non-default kernel exactly once, then it reverted
- [ ] The kernel parameter appears in `/proc/cmdline` after reboot
- [ ] Default target restored and verified

**Verify**

```bash
tuned-adm active; tuned-adm recommend
grubby --info=ALL | grep -E '^(kernel|index)'
grubby --default-kernel
cat /proc/cmdline
systemctl get-default
```

> [!tip]- Hint
> `tuned-adm profile virtual-guest`, `grubby --set-default`,
> `grubby --update-kernel=ALL --args="..."`, and `grub2-reboot <index>` for a
> one-time boot.

---

## Days 24–25 — Objective self-audit

Go through the **current published EX200 objectives** on Red Hat's site and score
yourself honestly on each line: *confident / shaky / cannot do*.

> Do this against the live objectives page, not this note. Objectives shift
> between RHEL versions, and you confirmed your target version in Week 1.

| Objective area | Confident | Shaky | Can't | Lab to redo |
| --- | --- | --- | --- | --- |
| Essential tools (shell, redirection, grep, archives, ssh) |  |  |  | Labs 1.1, 1.5 |
| Shell scripts (conditionals, loops, exit codes) |  |  |  | Lab 1.6 |
| Operate running systems (boot, targets, processes, logs, services) |  |  |  | Labs 2.1, 2.2, 4.2 |
| Local storage (partitions, LVM, swap) |  |  |  | Labs 2.5, 2.6 |
| File systems (xfs/ext4, NFS, autofs, ACLs, SGID) |  |  |  | Labs 1.3, 2.7 |
| Deploy/configure/maintain (dnf, cron/timers, network, kernel) |  |  |  | Labs 2.3, 2.4, 4.2 |
| Users and groups |  |  |  | Lab 1.2 |
| Security (firewall, key SSH, SELinux, ACLs) |  |  |  | Labs 1.4, 3.1–3.3 |
| **Containers (podman, rootless, systemd, storage)** |  |  |  | **Lab 4.1** |

Anything marked *shaky* or *can't* gets redone before Day 26. No exceptions.

---

## Days 26–28 — Timed EX200 mocks

Real conditions. See [Exam-Day-Protocol](Exam-Day-Protocol.md).

- **2.5 hours**, timer visible.
- Closed book — only `man`, `--help`, `/usr/share/doc`.
- Revert rhel01 to `clean` first.
- Graded **after a reboot**. Anything that does not survive scores zero.

### Mock EX200-A (Day 26)

1. Set the hostname to `server-a.lab.local` permanently.
2. Configure a static IP with two DNS servers and a search domain, surviving reboot.
3. Group `finance` (GID 6000); users `fin1`, `fin2` in it; `fin2` cannot log in
   interactively.
4. `fin1`'s password expires in 45 days with a 10-day warning.
5. `/srv/finance` — group-owned by `finance`, group-writable, users cannot delete
   each other's files, new files inherit the group.
6. Read-only ACL for `auditor` on `/srv/finance`, inherited by new files, with no
   group membership change.
7. A 3 GB XFS filesystem from the blank disk mounted at `/finance` by UUID, `nodev`.
8. 1 GB of swap, persistent.
9. VG `vgapp` (32 MB extents), 2 GB LV at `/appdata`, then extended to 5 GB with
   the filesystem grown.
10. httpd installed and enabled, serving from `/finance/www`, SELinux enforcing.
11. http open in the firewall permanently.
12. A systemd timer running `/usr/local/bin/audit.sh` daily at 03:00, persistent.
13. Journal persistent, capped at 300 MB.
14. `fin2` denied the use of cron.
15. Reset the root password from GRUB (simulate the lockout).

### Mock EX200-B (Day 27)

1. Configure a repository from a local directory and install a package from it.
2. Create three users from a spec, one with a specified UID and no shell.
3. A directory where every new file is group-owned by `developers` automatically.
4. Default ACLs so a named user always gets write access to new files there.
5. Extend an existing LV by 2 GB with the filesystem grown online.
6. Reduce an ext4 LV by 1 GB safely.
7. NFS export from rhel02, mounted persistently on rhel01.
8. autofs mounting a share on demand with a 60-second idle timeout.
9. **Rootless container** serving a page on port 8080, persistent storage, auto-started
   at boot via systemd.
10. Move sshd to a non-standard port with SELinux enforcing and the firewall open.
11. Find all SUID files and write the list to a file.
12. A script that exits non-zero when any systemd unit has failed.
13. Set a tuned profile persistently.
14. Boot a non-default kernel permanently.
15. Configure `/etc/fstab` so a mount failure does **not** prevent boot.

### Mock EX200-C (Day 28) — hostile

Run **both** saboteurs on rhel01 first, then reboot:

```bash
sudo ./break.sh all                       # the Week 3 faults
sudo ./break-advanced.sh combo --yes      # three of the harder ones
sudo reboot
```

Repair the estate, then complete Mock EX200-B's tasks on top. Same 2.5 hours.
Grade with `./verify breakfix`, `./verify advanced` and `./verify ex200-b`.
See [10-Advanced-Breakfix-Labs](10-Advanced-Breakfix-Labs.md).

### Scoring

Pass mark is 210/300 — about **70%**. Score after reboot only.

| Mock | Date | Score | Time used | Weak areas |
| --- | --- | --- | --- | --- |
| EX200-A | Oct 26* |  |  |  |
| EX200-B |  |  |  |  |
| EX200-C |  |  |  |  |

\* Adjust to your actual Day 26 (Sep 27) — the table is a template.

> [!important] The go/no-go rule
> Two consecutive mocks at **85%+** with everything surviving reboot means sit
> the exam. Below 70% on Day 28 means move the booking by a week — and shift
> Month 2 with it. Sitting it unprepared costs more time than rescheduling.

---

## Days 29–30 — Sit EX200

- **Day 29:** weak areas only. No new topics. Light.
- **Day 30 (Oct 1):** sit EX200.

- [ ] EX200 booked
- [ ] EX200 passed → RHCSA earned
- [ ] Result recorded in the hub log

> [!tip] If you do not pass
> It is not a failure of the plan. Rebook, spend Days 31–37 on exactly the
> sections you lost marks on, and start Month 2 a week late. Month 2 has some
> slack built in for precisely this.

---

## Month 1 gate

Everything below must be true before Ansible begins.

- [ ] EX200 sat (passed, or rebooked with a date)
- [ ] Blank RHEL VM + written requirement → I build it without searching
- [ ] Containers: rootless, persistent storage, systemd auto-start — from memory
- [ ] Every fault in `break.sh list` fixed in under 10 minutes
- [ ] `findmnt --verify` before every reboot is automatic
- [ ] Confirmed EX294 (or its current equivalent code) with L&D

→ Month 2 begins: [04-Labs-Ansible-Fundamentals](04-Labs-Ansible-Fundamentals.md)

Harder drills for these last evenings: [10-Advanced-Breakfix-Labs](10-Advanced-Breakfix-Labs.md)
