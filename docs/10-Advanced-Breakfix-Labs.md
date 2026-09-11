---
created: 2026-09-09
tags: [rhce, rhcsa, labs, troubleshooting, breakfix, advanced]
---
# 10 — Advanced Break-Fix Labs (Days 22–29, evenings)

Ten drills for the end of Month 1. A script damages the machine; you repair it
with nothing but the machine itself.

These are harder than the Week 3 drills in [02-Labs-Security-and-Breakfix](02-Labs-Security-and-Breakfix.md) on
purpose. Those faults each had one cause and announced themselves. These do not:
several are silent until a reboot, two have three or four causes behind a single
symptom, and two present as a permissions problem that is not a permissions
problem.

> [!important] The rule you set yourself
> **No AI.** Search engines and `man` are allowed; asking a model for the answer
> is not. The point of the drill is the search — working out which tool exposes
> the layer you have not thought of yet, and in what order to reach for them.
>
> Record the drill, the time, and your first hypothesis in the [Drill log](#drill-log)
> below. The wrong hypotheses are the useful data.

> [!danger] Snapshot, every single time
> Some of these fill a filesystem, move the clock, or disable SELinux until you
> repair them. One or two can leave the box unpleasant if you walk away
> mid-repair.
>
> ```bash
> .\lab.ps1 snap pre-lab rhel01
> ```
>
> The saboteur writes **no backups** of what it changed. That is deliberate:
> the snapshot is the escape hatch, and reverting costs you nothing but the
> drill. There is no undo command, and there should not be.

## Where this fits

| Day | Slot | What |
| --- | --- | --- |
| 22–25 | the 20-minute break-fix block, extended to ~40 | one drill per evening |
| 26–27 | after each mock | one drill, cold, via `random` |
| 28 | Mock EX200-C | `combo` before the mock, instead of `break.sh all` |
| 29 | — | nothing new. Rest. |
| 55 | Month 2 | `chaos 5` on top of `break-ansible.sh` — see [07-Scenario-Labs](07-Scenario-Labs.md) |

Doing all ten twice is worth more than doing twenty once. The second pass is
where the diagnostic order becomes automatic.

## Running a drill

The saboteur is at `/opt/rhce-labs/break/break-advanced.sh` inside every node.

```powershell
# from Windows
.\lab.ps1 break-advanced random rhel01    # one unknown fault — the honest version
.\lab.ps1 break-advanced f4 rhel01        # a specific drill
.\lab.ps1 reveal rhel01                   # afterwards
```

```bash
# or inside the node, where the full set of subcommands lives
sudo /opt/rhce-labs/break/break-advanced.sh list          # the ten symptoms
sudo /opt/rhce-labs/break/break-advanced.sh random --yes
sudo /opt/rhce-labs/break/break-advanced.sh combo --yes   # three at once
sudo /opt/rhce-labs/break/break-advanced.sh chaos 5 --yes # five, for Mock EX200-C
sudo /opt/rhce-labs/break/break-advanced.sh status
```

Then repair, verify, reboot, verify again, and only afterwards:

```bash
sudo /opt/rhce-labs/verify advanced --blind      # am I done yet? pass/fail only
sudo /opt/rhce-labs/verify advanced              # what is still wrong
sudo /opt/rhce-labs/verify advanced --only=f4    # just one drill
sudo /opt/rhce-labs/break/break-advanced.sh reveal
```

> [!tip] Use `--blind` while you are still hunting
> The full output names the domain each check examines, which narrows the search
> for you. `--blind` reports only which numbered checks pass, so you can tell
> whether you are finished without being told where to look.

> [!warning] Do not read `break-advanced.sh`
> The file states the cause of every drill in plain English. Reading it once
> spends the only chance you get to meet that fault cold. `reveal` exists so you
> never need to.

`random` is the version that matters. A named drill tells you the symptom in
advance, which is useful the first time and worthless the second.

## The ten drills

Each one gives you a **symptom**, not a fault. The requirement is always the
same three things, and the verifier checks all three:

1. The symptom is gone.
2. The repair is **minimal** — nothing disabled, no permissions widened, no
   `setenforce 0`, no `chmod 777`, no blanket policy module.
3. The repair **survives a reboot**.

The acceptance criteria below say what "done" looks like from the outside. They
deliberately do not say where to look.

---

### f1 — Names stop resolving, and `/etc/hosts` is demonstrably correct

`ping rhel02` fails. `ping 192.168.56.12` works. You `cat /etc/hosts` and the
entry is right there, correctly spelled. Nothing is wrong with the network, and
DNS itself answers normally.

**Acceptance criteria**

- [ ] `getent hosts rhel02` resolves again
- [ ] A name that *only* `/etc/hosts` knows about resolves
- [ ] Whatever manages that configuration on RHEL 9 reports itself consistent
- [ ] You changed one thing, not several
- [ ] Survives a reboot

**Time target:** 10 min.
**Verify:** `sudo ./verify advanced --only=f1`

---

### f2 — A service will not start, on a config error you cannot correct

The unit fails. `journalctl -xeu` names the file and the line. You open it, fix
it, and cannot save. As **root**. There is no SELinux denial in the audit log,
the filesystem is read-write, and `ls -l` shows exactly the permissions you
expect.

**Acceptance criteria**

- [ ] The file is editable by root again
- [ ] The configuration parses and the service runs
- [ ] Nothing else under `/etc` is left in the state that caused this
- [ ] You can name the one command that would have shown you the cause in a line
- [ ] Survives a reboot

**Time target:** 10 min.
**Verify:** `sudo ./verify advanced --only=f2`

---

### f3 — The website is unreachable, and fixing one thing is not enough

`curl rhel01` from rhel02 fails. So does `curl localhost`. This drill has
**three independent causes** behind that one symptom, and they surface one at a
time: each fix reveals the next failure. Do not stop when the first thing works.

**Acceptance criteria**

- [ ] `curl` against the configured port returns 200 from localhost **and** rhel02
- [ ] SELinux stayed enforcing throughout — no `setenforce 0`, not even briefly
- [ ] A full relabel of the served directory would change nothing
- [ ] Every port the server listens on is permitted, permanently
- [ ] Runtime and permanent firewall configuration match exactly
- [ ] Survives a reboot

**Time target:** 20 min. This is the longest of the ten.
**Verify:** `sudo ./verify advanced --only=f3`

---

### f4 — A unit starts by hand but never at boot, citing something that does not exist

`systemctl start httpd` works. After a reboot it is dead. `systemctl status`
mentions a unit name you have never seen, containing an escape sequence, and the
unit file itself looks entirely normal at first glance.

**Acceptance criteria**

- [ ] The unit starts automatically at boot, confirmed by an actual reboot
- [ ] Nothing on the system depends on anything that does not exist
- [ ] No unit is in a failed state
- [ ] `systemd-analyze verify` is quiet about it
- [ ] You can explain how a filesystem path becomes a systemd unit name, escape
      sequence and all

**Time target:** 15 min.
**Verify:** `sudo ./verify advanced --only=f4`

---

### f5 — The filesystem is full and `du` cannot account for it

Writes fail. `df` says 100%. `du -sh` over the whole filesystem adds up to a
fraction of that. Deleting things does not help, and there is nothing obviously
large anywhere.

**Acceptance criteria**

- [ ] The space is back, without deleting anything that mattered
- [ ] `du` and `df` agree again
- [ ] You did **not** reboot to fix it — a reboot would have hidden the cause
- [ ] You can explain why the space was invisible to `du`
- [ ] You can explain why a reboot would have "worked", and why that is worse

**Time target:** 10 min.
**Verify:** `sudo ./verify advanced --only=f5`

---

### f6 — Everything time-sensitive misbehaves at once

`journalctl` output is timestamped hours away from when things actually
happened. Timers show next-run times that make no sense. A couple of files under
`/etc` are dated over a month from now, so `find -newer` and anything that
compares file times disagree with reality. `date` looks perfectly reasonable
until you notice what it says after the time. And whatever you correct, a reboot
moves it again.

There are **four** independent faults here, on four different knobs, and one of
them is invisible until you restart.

**Acceptance criteria**

- [ ] Log and file timestamps agree with when things actually happened
- [ ] The service that maintains the clock is configured **and** running
- [ ] The timezone is the one this lab was built in
- [ ] A reboot no longer shifts the clock
- [ ] No files under `/etc` or `/root` are left dated in the future
- [ ] Survives a reboot — and you have actually rebooted to prove the last two

> [!note] The lab has no upstream time source
> There is no internet here, so nothing syncs you back automatically. Part of
> this drill is correcting the clock by hand and then making the service that
> maintains it configured and running, so that it would hold.
>
> The wall clock itself is deliberately *not* what this drill breaks: on
> VirtualBox the guest additions put it back within seconds. What it breaks are
> the four things RHEL itself owns, which is the more useful list anyway.

**Time target:** 20 min. It was 15 when this was one fault.
**Verify:** `sudo ./verify advanced --only=f6`

---

### f7 — `sudo` works for some commands and refuses others

`sudo ls` is fine. `sudo systemctl restart httpd` says the command was not
found — though it plainly exists and you can run it by absolute path. Separately,
a member of `developers` who had rules yesterday now has none, and `sudo -l` for
them is thinner than it was. Two things are wrong, not one.

**Acceptance criteria**

- [ ] Administrative commands work through `sudo` without typing an absolute path
- [ ] The `developers` rules are honoured again
- [ ] `visudo -c` is clean and `sudo` itself prints no warnings
- [ ] You fixed the rules rather than granting anyone more than they had before
- [ ] Survives a reboot

> [!danger] Know your way back in
> If you manage to remove your own `sudo` entirely, `su -` with the root
> password from the build script still works. Do not experiment past that point
> without a snapshot.

**Time target:** 15 min.
**Verify:** `sudo ./verify advanced --only=f7`

---

### f8 — SELinux is off after a reboot, and the config file says enforcing

`getenforce` reports `Disabled`. `/etc/selinux/config` says `SELINUX=enforcing`
and always has. `setenforce 1` refuses. Everything that used to be blocked now
works, which is its own kind of alarming.

**Acceptance criteria**

- [ ] `getenforce` reports `Enforcing`, and still does after a **second** reboot
- [ ] `restorecon -Rvn /etc` is silent, and no relabel is left outstanding
- [ ] You can say why `/etc/selinux/config` was never the authority here
- [ ] You can say why coming back from this state needs a relabel at all

**Time target:** 15 min, plus two reboots.
**Verify:** `sudo ./verify advanced --only=f8`

---

### f9 — DNS works now and breaks on every reboot

You fix `/etc/resolv.conf`. Resolution works. You reboot to confirm, and it is
broken again, with a nameserver you have never configured. You fix it again. It
survives until the next reboot.

**Acceptance criteria**

- [ ] Resolution survives a reboot **and** taking the connection down and up
- [ ] At least one configured nameserver actually answers
- [ ] `/etc/resolv.conf` is reproducible — nothing regenerates it differently
- [ ] Hand-editing a generated file was not your final answer
- [ ] You can name two other files on a RHEL box that are generated like this one

**Time target:** 10 min.
**Verify:** `sudo ./verify advanced --only=f9`

---

### f10 — The NFS mount succeeds and writes fail

`mount` reports success. `findmnt` looks right. `df` shows the share. Writing to
it fails — with one message as your user and a different one as root, which is
the clue.

> Stage this one on **rhel02** for the server-side variant, or on rhel01 for the
> client-side variant. They present almost identically and are fixed in
> different places, which is the lesson.

**Acceptance criteria**

- [ ] A write to the mount succeeds as an ordinary user
- [ ] The export permits what it should, and nothing more
- [ ] The mount is read-write both now and after a reboot
- [ ] You fixed it on the correct node, and can say why the other one was wrong
- [ ] `showmount -e` from the client agrees with `exportfs -v` on the server

**Time target:** 15 min.
**Verify:** `sudo ./verify advanced --only=f10`

---

## Mock EX200-C, hardened

[03-EX200-Exam-Prep](03-EX200-Exam-Prep.md) has Mock EX200-C running `break.sh all`. Replace that with
both saboteurs, which is much closer to inheriting a real estate:

```bash
.\lab.ps1 snap pre-mock rhel01
sudo /opt/rhce-labs/break/break.sh all
sudo /opt/rhce-labs/break/break-advanced.sh combo --yes
sudo reboot
```

Then repair the estate and complete Mock EX200-B's tasks on top, in 2.5 hours.
Grade with all three:

```bash
sudo /opt/rhce-labs/verify breakfix        # the Week 3 faults
sudo /opt/rhce-labs/verify advanced        # these ten
sudo /opt/rhce-labs/verify ex200-b         # the exam tasks
```

If that is comfortable, you are ready for Oct 1.

## The diagnostic order these drills are teaching

By the end of the ten, this should be reflex rather than recall:

```text
What exactly is the symptom?        ← reproduce it, deliberately
        ↓
What changed, and when?             ← journalctl --since, rpm -qa --last, ls -lt /etc
        ↓
Which LAYER?                        ← the question these drills exist for
        ↓
ONE hypothesis, written down
        ↓
Test it without fixing it
        ↓
Fix minimally
        ↓
Verify · REBOOT · verify again
```

The layer question is what separates these from the Week 3 drills. When a
service will not start, the cause can be in its own configuration, in something
layered on top of its unit, in a file attribute that is not a permission, in
SELinux, in the kernel command line, or in the clock. Each of those is invisible
to the tool that reveals the others.

Work out the list for yourself as you go — that is the exercise. Once you have
finished all ten, compare your list against this one:

> [!tip]- Spoiler: the layers, and the tool that exposes each
> Do not open this until every drill is done. It is effectively an index of the
> ten causes.
>
> | Layer | The tool that shows it |
> | --- | --- |
> | the unit as systemd actually assembles it | `systemctl cat`, `systemd-analyze verify` |
> | file attributes beyond permissions | `lsattr` |
> | SELinux labels, booleans and ports | `ls -Z`, `ausearch -m AVC -ts recent`, `semanage` |
> | the kernel command line | `/proc/cmdline`, `grubby --info=DEFAULT` |
> | name-service resolution order | `/etc/nsswitch.conf`, `authselect check` |
> | files that are generated, not edited | `nmcli con show`, `rpm -qf`, the managing daemon |
> | space with no directory entry | `lsof -nP +L1`, `df -i` |
> | the clock, the timezone, and how the RTC is read | `timedatectl`, `/etc/adjtime`, `rpm -qa --last` |
>
> If your own list had all eight before you read this, you are ready for the
> troubleshooting half of either exam.

## Drill log

Fill this in every time. It becomes the revision list for Day 29 — and the
pattern in the "first hypothesis right?" column is the most honest measure of
readiness in this whole project.

| Date | Drill | Time to find | Time to fix | First hypothesis right? | What gave it away |
| --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |
|  |  |  |  |  |  |
|  |  |  |  |  |  |
|  |  |  |  |  |  |
|  |  |  |  |  |  |
|  |  |  |  |  |  |
|  |  |  |  |  |  |
|  |  |  |  |  |  |
|  |  |  |  |  |  |
|  |  |  |  |  |  |

## Gate

- [ ] All ten drills completed at least once, closed to AI
- [ ] Every one of them re-run cold via `random`, under its time target
- [ ] `combo` repaired inside 45 minutes
- [ ] No drill was ever "fixed" by disabling SELinux, widening permissions, or rebooting blindly
- [ ] The drill log is filled in, including the wrong hypotheses
- [ ] I wrote my own layer list before reading the spoiler, and it was close

When all ten are comfortable, the next rung is [11-Incident-Drills](11-Incident-Drills.md): the same
fault types, but several at once, described the way a user would describe them,
with no count and a clock.

→ Back to [03-EX200-Exam-Prep](03-EX200-Exam-Prep.md) for the mocks · checkers: [09-Verification-Scripts](09-Verification-Scripts.md) · next: [11-Incident-Drills](11-Incident-Drills.md)
