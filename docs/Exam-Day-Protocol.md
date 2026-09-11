---
created: 2026-09-02
tags: [rhce, ex294, exam, reference]
---
# Exam-Day Protocol

Applies to **both exams** — EX200 at Day 30 and EX294 at Day 60. The loop below
is identical for each; only the allowed documentation differs (EX200 gives you
`man` and `/usr/share/doc`; EX294 adds `ansible-doc`).

---

## The loop

```text
Read requirement
      ↓
Identify hosts        ← which group? one host or all?
      ↓
Implement
      ↓
Validate
      ↓
REBOOT
      ↓
Validate again
```

That last step is not optional. Red Hat exams are performance based and graded on
the state of the machine **after a reboot**. A configuration that works now but
disappears on reboot is not a partial answer — it is a zero.

## The persistence checklist

Before you consider any task finished, ask which of these applies:

| Did you… | Persistence requirement |
| --- | --- |
| Start a service | `systemctl enable` as well |
| Mount a filesystem | Entry in `/etc/fstab`, by UUID |
| Set a SELinux boolean | `setsebool **-P**` |
| Set a SELinux context | `semanage fcontext` + `restorecon`, not `chcon` |
| Open a firewall port | `--permanent` **and** `--reload` |
| Configure an IP | `nmcli` profile with autoconnect, not `ip addr add` |
| Set a hostname | `hostnamectl`, not `hostname` |
| Add swap | fstab entry |
| Change a kernel parameter | `/etc/sysctl.d/`, not just `sysctl -w` |
| Create a timer/cron | enabled, and `Persistent=true` for timers |

> [!warning] `findmnt --verify` before every reboot
> A malformed `/etc/fstab` drops the machine into emergency mode and can burn 20
> minutes of exam time. `findmnt --verify` and `mount -a` cost three seconds.

---

## Allowed documentation

Learn to move fast in these. They are all you get.

```bash
# Ansible — EX294 only
ansible-doc -l | grep -i <thing>        # find the module
ansible-doc <module>                    # full options
ansible-doc -s <module>                 # paste-ready skeleton  ← use this most
ansible-galaxy collection list          # what is installed

# System — both exams
man <command>
man -k <keyword>                        # apropos, when you forget the name
<command> --help
ls /usr/share/doc/                      # config examples live here
```

`/usr/share/doc` is underused. Example configs for httpd, chrony, autofs and
others are sitting right there, ready to copy.

---

## Time management

**RHCSA-style (2.5 h) / EX294-style (4 h)**

```text
First 10 min   Read every task. Number them by difficulty.
               Do NOT start on task 1 by default.
Then           Easy + high-confidence tasks first. Bank the marks.
Middle         Hard tasks, with a hard time cap each.
Last 30 min    REBOOT. Then verify every task from the top.
```

- Never let one task eat more than ~15% of your time. Flag it, move on, return.
- Tasks are independent. A task you cannot do does not block the rest.
- If a task depends on an earlier one you failed, do it anyway — partial state
  may still score.

## The reboot ritual

Reboot at least **twice**: once in the middle, once near the end. Mid-exam reboots
surface persistence failures while you still have time to fix them. Finding them
in the last five minutes is finding them too late.

```bash
findmnt --verify          # fstab sane?
mount -a                  # no errors?
systemctl --failed        # nothing failed?
reboot
# after it returns:
systemctl --failed
df -h; swapon --show; getenforce
firewall-cmd --list-all
# then re-verify every task
```

---

## Common zero-mark mistakes

- Service started but not enabled.
- `setsebool` without `-P`.
- `chcon` instead of `semanage fcontext` + `restorecon` (survives reboot, dies on relabel).
- Firewall rule runtime-only, no `--permanent`.
- fstab using `/dev/sdb1` instead of UUID, after device names shift.
- `setenforce 0` to "make it work" — SELinux must be enforcing.
- Playbook that reports success but `skipped=` everything.
- Plaintext password where a hash was required.
- Reading the requirement as you assume it, not as written. **Read it twice.**

---

## If you get stuck

1. Re-read the requirement. Half of all stuck moments are misread requirements.
2. `ansible-doc -s` / `man -k`. The answer is on the machine.
3. Check the logs: `journalctl -xeu <unit>`, `ausearch -m AVC -ts recent`.
4. Still stuck after your time cap? Flag it, move on, come back.

Never sit frozen. Never disable SELinux to unblock yourself — it converts a
partial score into a guaranteed zero across multiple tasks.

---

## The night before

- No new topics.
- Confirm exam time, ID requirements, and the check-in process.
- Verify your machine/environment requirements if it is a remote exam.
- Sleep properly. Tired beats under-prepared in the wrong direction.

Related: [08-EX294-Exam-Prep](08-EX294-Exam-Prep.md) · [Manual-to-Ansible-Map](Manual-to-Ansible-Map.md) · [RHCE Prep Hub](_Hub.md)
