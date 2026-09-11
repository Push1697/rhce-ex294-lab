---
created: 2026-09-09
tags: [rhce, rhcsa, labs, verification, tooling]
---
# 09 — Verification Scripts

An offline checker for every lab in this project. You build the lab from the
*Requirement*; the script tells you whether the **acceptance criteria** are
genuinely met — after a reboot, which is the only state either exam grades.

**Where they live:** `1-Projects/RHCE-EX294-Prep/verify/` in this vault, so they
are versioned alongside the notes. They *run* on the lab VMs — see
[Getting them onto the lab machines](#getting-them-onto-the-lab-machines).

**Public copy:** the same tree, plus `lab-build.sh` and all three saboteurs, is
in the Quartz repo at
<https://github.com/Push1697/published_quartz_blog/tree/v4/rhce-labs> — that is
what the garden articles link readers at, and it is the easiest way to get them
onto a node (`git clone` rather than `scp`). Edits here need copying there.

> [!important] They tell you what is wrong, never how to fix it
> A failure prints the requirement that is not met and what the machine actually
> reported. It never prints the command. Working that out is the lab — the same
> rule as the collapsed hints in the lab notes.

## Why bother

Three habits this project depends on are exactly the ones that are hard to hold
yourself to, and easy for a script to hold you to:

1. **Reboot before you believe it.** Every check that classically vanishes on
   restart is marked `[P]`. The harness records the boot ID on each clean pass,
   so running a lab again after a reboot reports **reboot-proven** rather than
   *passed on the same boot*. That distinction is full marks versus zero.
2. **Grade the requirement, not the command.** `setsebool` without `-P`,
   a firewall rule never committed, a service started but not enabled — all
   score zero, and all look fine if you only check the obvious thing.
3. **Score honestly.** The mock graders score *tasks fully correct*, scaled to
   300 with the real 210 pass mark. One broken check fails its whole task, which
   is how Red Hat grades.

## Quick reference

```bash
./verify                    # list every check and group
./verify 1.2                # one lab
./verify week1              # a whole week, in order
./verify breakfix           # after every break.sh drill
./verify advanced           # the ten advanced drills
./verify advanced --only=f4 # just one of them
./verify ex200-a --spec     # print a mock's exam paper
./verify history            # what has been run on this machine
./verify bundle             # build self-contained copies for transfer
```

| Flag | Effect |
| --- | --- |
| `-v` | show command output for passing checks too |
| `--no-mutate` | skip checks that create or delete anything |
| `--after-reboot` | refuse to run unless the machine booted in the last 30 min |
| `--spec` | mocks only — the exam paper, with every value pinned |
| `--only=fN` | `advanced` only — check a single drill |
| `--blind` | report pass/fail only, without naming what was checked |
| `--hard` | no diagnostics, warnings count as failures, tolerances halve, and success needs a reboot to prove it — see [11-Incident-Drills § Hard mode](11-Incident-Drills.md#hard-mode) |
| `--proj=PATH` | Ansible labs — project directory, default `~/ansible` |

Exit status: `0` all automated checks passed, `1` something failed, `2` the
script refused to run (wrong user, no reboot, no project directory).

## What covers what

| Check | Lab note | Run on | As |
| --- | --- | --- | --- |
| `env` | [00-Lab-Environment](00-Lab-Environment.md) | every node (it detects which) | root |
| `1.1`–`1.7` | [01-Labs-RHCSA-Foundation](01-Labs-RHCSA-Foundation.md) | rhel01 | root |
| `2.1`–`2.6` | [01-Labs-RHCSA-Foundation](01-Labs-RHCSA-Foundation.md) | rhel01 | root |
| `2.7` | [01-Labs-RHCSA-Foundation](01-Labs-RHCSA-Foundation.md) | rhel01 **and** rhel02 | root |
| `3.1`–`3.4` | [02-Labs-Security-and-Breakfix](02-Labs-Security-and-Breakfix.md) | rhel01 | root |
| `breakfix` | [02-Labs-Security-and-Breakfix](02-Labs-Security-and-Breakfix.md) | rhel01 | root |
| `advanced` | [10-Advanced-Breakfix-Labs](10-Advanced-Breakfix-Labs.md) | rhel01 (f10: rhel02) | root |
| `4.1` | [03-EX200-Exam-Prep](03-EX200-Exam-Prep.md) | rhel01 | **the ordinary user** |
| `4.2` | [03-EX200-Exam-Prep](03-EX200-Exam-Prep.md) | rhel01 | root |
| `ex200-a`, `ex200-b` | [03-EX200-Exam-Prep](03-EX200-Exam-Prep.md) | rhel01 | root |
| `5.1`–`5.7` | [04-Labs-Ansible-Fundamentals](04-Labs-Ansible-Fundamentals.md) | rhel-control | the ordinary user |
| `6.1`–`6.5` | [05-Labs-Automate-the-RHCSA-Set](05-Labs-Automate-the-RHCSA-Set.md) | rhel-control | the ordinary user |
| `7.1`–`7.5` | [06-Labs-Advanced-Ansible](06-Labs-Advanced-Ansible.md) | rhel-control | the ordinary user |
| `s1`–`s5` | [07-Scenario-Labs](07-Scenario-Labs.md) | rhel-control | the ordinary user |
| `ex294-a` | [08-EX294-Exam-Prep](08-EX294-Exam-Prep.md) | rhel-control | the ordinary user |

Groups: `week1`…`week8`, `month1`, `month2`, `mocks`.

## Getting them onto the lab machines

Nothing to transfer. Vagrant mounts the whole kit into every node, read-only, at
`/opt/rhce-labs`:

```powershell
.\lab.ps1 check 2.5 rhel01           # from Windows
.\lab.ps1 check env rhel-control
```

```bash
# or from inside a node
sudo /opt/rhce-labs/verify 2.5
sudo /opt/rhce-labs/verify --help
```

Read-only is deliberate: a lab mistake inside a VM can never reach the vault
copy on Windows. It also means `./verify bundle` cannot write there — and does
not need to.

> [!note] The bundle path still exists for other machines
> `./verify bundle` writes `dist/`, one self-contained file per checker with the
> harness embedded, for any node that is not a Vagrant guest — a KVM lab, or a
> box you only have `scp` to. See [00-Lab-Environment](00-Lab-Environment.md).

## The daily loop

```text
Read the Requirement (not the hint)
        ↓
Build it
        ↓
./verify <lab>                    ← fix what it reports, not what it suggests
        ↓
findmnt --verify   (if you touched fstab)
        ↓
sudo reboot
        ↓
./verify <lab> --after-reboot     ← this is the run that counts
        ↓
"reboot-proven" in the summary → the lab is done
```

## Break-fix drills (Days 19–21)

`./verify breakfix` has one section per fault `break.sh` can inject — fstab,
SELinux context, SELinux port, firewall, service, permissions, repo, DNS, sudo,
mount. It is the fastest way to catch the classic mistake of fixing the symptom
you were looking for and leaving a second fault behind.

Run it **before** the reboot and again after. Record the time in the fault-log
table in [02-Labs-Security-and-Breakfix](02-Labs-Security-and-Breakfix.md).

For Lab 3.2, take a baseline of the loaded SELinux policy modules on a clean box
first, so a later run can tell whether the repair was `semanage fcontext` or a
generated `audit2allow` module:

```bash
sudo /opt/rhce-labs/verify 3.2 --snapshot     # on a clean box, once
```

## The advanced drills

[10-Advanced-Breakfix-Labs](10-Advanced-Breakfix-Labs.md) adds ten harder faults, staged by
`verify/break/break-advanced.sh`. It deliberately tells you nothing: `list`
prints symptoms only, and `reveal` gives you the cause plus your elapsed time
once you have finished repairing and verifying.

```bash
sudo ./break-advanced.sh random --yes    # one unknown fault
# ... repair, reboot, repair ...
sudo ./verify advanced
sudo ./break-advanced.sh reveal
```

`./verify advanced` doubles as a general sanity sweep — every section passes on
a healthy box, so it is worth running before any mock. While you are still
diagnosing, run it `--blind`: the normal output names the domain each check
examines, which does some of the hunting for you.

> [!warning] Do not read the saboteur
> `break-advanced.sh` states the cause of all ten drills in plain English.
> `reveal` exists so you never need to open it.

## The mock graders

`--spec` prints the exam paper with every ambiguous value pinned — usernames,
UIDs, GIDs, sizes, ports, profile names — so the grading is deterministic. Build
exactly what the spec says.

```bash
./verify ex200-b --spec > /tmp/paper.txt
# ... 2.5 hours, closed book ...
sudo reboot
sudo ./verify ex200-b --after-reboot
```

- **Mock EX200-C** is EX200-B on a box wrecked with `break.sh all` **and**
  `break-advanced.sh combo`: grade with `ex200-b`, `breakfix` and `advanced`.
- **Mock EX294-B** is EX294-A on a wrecked estate: grade with `ex294-a`.

Record the scaled score in the scoring tables in [03-EX200-Exam-Prep](03-EX200-Exam-Prep.md) and
[08-EX294-Exam-Prep](08-EX294-Exam-Prep.md). The go/no-go rule needs two consecutive mocks at 85%+
(255/300), which the summary states outright.

## Month 2: the Month 1 checks, run remotely

Week 6 is "re-do all of RHCSA *through* Ansible", and the end state is identical
— so the same check scripts grade it. `6.1`, `6.2`, `6.3` and `6.4` bundle the
relevant Week 1–3 script, ship it to the managed node with the `script` module
and run it there, from the control node. You never log in, which is
[05-Labs-Automate-the-RHCSA-Set](05-Labs-Automate-the-RHCSA-Set.md)'s one rule for the week.

The Month 2 scripts also **run your playbooks**, because idempotence is the
requirement and it cannot be checked any other way. Two consequences:

- Snapshot before running `6.3` — a storage playbook mistake costs you the node.
- `5.6` deliberately disturbs a config file on a target to prove the handler
  fires, and leaves the playbook to put it back. That is the test.

## What the scripts will not grade

Anything that is judgement or transient shows up as a `[CHECK]` line, counted
separately from passes and failures:

- "You can explain why XFS can never be shrunk."
- "You reset the root password from the GRUB prompt."
- "Your first hypothesis was the right one."
- "All editing was done in vim."

These are usually the ones that decide whether Day 30 goes well. Nobody is
checking them but you.

## Log

- **2026-09-09**: Verification scripts written — 47 checkers covering every lab,
  the environment acceptance test, the break-fix health check and all four mocks.
- **2026-09-09**: Added the advanced drills — `break-advanced.sh` plus `./verify
  advanced`, taking the total to 48 checkers. See [10-Advanced-Breakfix-Labs](10-Advanced-Breakfix-Labs.md).
- **2026-09-11**: Added `./verify incident` and the `--hard` flag. The checker
  aggregates both health sweeps, times you against the work order's SLA, and
  fails a repair bought with a security control or left with its persistence in
  place. See [11-Incident-Drills](11-Incident-Drills.md).
