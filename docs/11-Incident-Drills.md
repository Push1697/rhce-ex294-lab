---
created: 2026-09-11
tags: [rhce, rhcsa, labs, troubleshooting, breakfix, incident, hard-mode]
---
# 11 — Incident Drills (Days 26–29 · Month 2 · and before either exam)

The drills in [02-Labs-Security-and-Breakfix](02-Labs-Security-and-Breakfix.md) and [10-Advanced-Breakfix-Labs](10-Advanced-Breakfix-Labs.md)
hand you **one fault and its symptom**. This one hands you a **work order**:
several faults at once, across the estate, described only the way a user would
describe them — and a clock.

It is the last rung. Nothing here is a new fault type. What is new is that you
do not know how many things are wrong, whether two reports share a cause, or
whether the alarming one matters at all.

> [!important] The rule you set yourself
> **No AI.** Search engines, `man`, and the machine's own logs are allowed;
> asking a model for the answer is not. That rule matters more here than
> anywhere else in this project, because an incident is exactly the situation
> where you will want to ask.
>
> Also: **restoring the snapshot is a surrender.** Record it as one in the
> [Drill log](#drill-log). A drill you abandoned honestly is worth more than one you
> quietly reset.

> [!danger] Snapshot first — there is no other undo
> ```powershell
> .\lab.ps1 snap pre-incident rhel01
> ```
> A severity-4 incident can disable SELinux at the kernel command line, move the
> clock, fill a filesystem, and leave something on the box that undoes your
> repairs. The saboteur keeps no record of what it changed. `abandon` reveals
> the causes and removes only the persistence — it does **not** repair the
> estate.

## How this differs from the other break-fix work

|  | Week 3 drills | Advanced drills | **Incident drills** |
| --- | --- | --- | --- |
| Faults at once | 1 | 1, or 3 with `combo` | 1–8 by severity, chosen so none overlap |
| You are told | the symptom | the symptom | a user's description of it |
| How many faults | you know | you know | **you do not know** |
| Hosts | one | one | **rhel01 and rhel02** at severity 3+ |
| Fights back | no | no | **yes**, at severity 4 |
| Clock | your own target | a target per drill | an **SLA the grader checks** |
| Irrelevant noise | none | none | **yes** — one report is a decoy |

## Severity levels

```bash
sudo /opt/rhce-labs/break/incident.sh open 2 --yes
```

| Sev | Composition | Target | Use it for |
| --- | --- | --- | --- |
| 1 | 1 single-cause fault | 15 min | a warm-up, or a cold start after a week off |
| 2 | 1 single-cause + 2 advanced | 40 min | the standard evening drill |
| 3 | 2 single-cause + 2 advanced + 1 of the two worst, **plus a fault on rhel02** | 75 min | Days 26–29, and before each mock |
| 4 | severity 3, **plus something that undoes your repairs**, plus a decoy | 120 min | once. Then again a fortnight later |

Two things the composer guarantees, so the difficulty is real rather than
accidental:

- **No two faults share a mechanism.** Two faults that both point the resolver
  at a black hole are not a harder drill — fixing either fixes both, and the
  reveal reads as though it repeated itself. Faults that share only a *symptom*
  are kept: a disabled SELinux hiding a mislabelled file is the exercise.
- **A fault that cannot be staged is replaced, not dropped.** If rhel02 is down
  or a package is missing, you still get a full severity-4 workload.

> [!warning] Severity 3 and above will touch rhel02
> Bring it up first, or the composer quietly keeps the drill single-node:
> ```powershell
> .\lab.ps1 up rhel02
> .\lab.ps1 snap pre-incident rhel02
> ```

## The work order

Opening an incident writes `/root/INCIDENT.md`. It is the only briefing you get,
and it contains no causes — only what was reported, what "resolved" means, and
the rules.

```text
# INCIDENT 20260910-1858 — severity 4

**Target:** restore service within **120 minutes**
**Scope:** rhel01, rhel02

## What was reported

- everything time-sensitive misbehaves at once
- DNS works now and breaks on every reboot
- the filesystem is full and du cannot account for it
- repairs do not stick — something you fixed comes back broken a few minutes later
- a unit is stopped and disabled, and the journal carries a warning about it
```

The reports are **shuffled**. Their order tells you nothing about severity,
dependency, or which to take first. Deciding that order is the skill being
drilled.

```bash
sudo /opt/rhce-labs/break/incident.sh objective   # re-print the work order
sudo /opt/rhce-labs/break/incident.sh status      # how long it has been open
```

### What "resolved" means

Copied here because it is the same every time, and worth knowing by heart:

- Every service that should be running is running, and is **enabled**.
- Everything a client needs is reachable **from the other node**, not just from
  localhost.
- SELinux is **enforcing**, and every label survives a relabel.
- The firewall's runtime and permanent configuration are identical.
- `findmnt --verify` is clean and `mount -a` is silent.
- **It all still holds after a reboot.**

### Rules of engagement

- No `setenforce 0`. Not even briefly, not even to test a theory.
- No `chmod 777`, and no widening a permission to make something work.
- No rebuilding the node, and no restoring a snapshot.
- No reading anything in `/opt/rhce-labs/break/`.
- Searching, `man`, and the machine's own logs are all fair game.

The grader checks the first three. It cannot check the fourth, which is why that
is the one that actually matters.

## Grading

```bash
sudo /opt/rhce-labs/verify incident --blind    # am I there yet? pass/fail only
sudo /opt/rhce-labs/verify incident            # what is still wrong
sudo /opt/rhce-labs/break/incident.sh reveal   # the causes, and your elapsed time
```

`verify incident` grades seven things the individual checkers do not:

1. **Both health sweeps pass outright** — `breakfix` and `advanced`, aggregated
   into one verdict each. It does not matter which faults were staged; the whole
   estate has to be healthy.
2. **You finished inside the target**, measured from when the incident opened.
3. **SELinux was never left off** — in all three places it can be turned off:
   the running state, `/etc/selinux/config`, and the kernel command line.
4. **Nothing was made world-writable** to force something to work.
5. **No generated policy module was loaded.** `audit2allow` papers over a
   mislabelled file; it is not a repair.
6. **The persistence mechanism is gone, not merely stopped.** A repair that
   lasts until the next timer firing is not a repair.
7. **The node rebooted since the incident opened.** Several of these faults only
   reappear after a restart, so a repair you have not rebooted is unproven.

Then it asks two things it cannot check, and you should answer them honestly
before running `reveal`: can you name the cause behind every report, and which
report misled you longest.

## Hard mode

Every checker in [09-Verification-Scripts](09-Verification-Scripts.md) takes `--hard`, and it changes what
the harness is willing to tell you:

```bash
sudo /opt/rhce-labs/verify incident --hard
```

| Normally | With `--hard` |
| --- | --- |
| a failed check prints the value it found | it prints nothing but the requirement |
| a warning is a warning | a warning is a **failure** |
| numeric tolerances are generous | the tolerance **halves** |
| a pass is a pass | success is not reported until it is **boot-proven** |

Use it for the second pass of an incident, and for everything in the fortnight
before the exam. The first pass with diagnostics teaches you the fault; the
`--hard` pass proves you can tell you are finished without being told where to
look.

`--blind` and `--hard` compose. Together they report a bare list of numbered
requirements met and unmet, which is roughly what the exam gives you.

## The thing that fights back

At severity 4 something on the box re-applies a fault every few minutes. It is
not hidden by obscurity — the script and both units carry a comment marking them
as a lab artifact — but nothing points you at them. You find them the way you
would find a real one:

```text
a repair that does not stick
        ↓
what runs on a schedule here?          systemctl list-timers --all
        ↓
what did it run, and when?             journalctl -u <unit> --since -20min
        ↓
what does that unit actually execute?  systemctl cat <unit>
        ↓
remove the cause, not the symptom      disable AND delete, then daemon-reload
```

`verify incident` fails you for leaving the timer merely stopped, because a
stopped timer comes back at the next boot.

> [!tip] The decoy is the other half of the exercise
> One report at severity 4 is deliberately irrelevant: a service is stopped and
> disabled, and there is an alarming line in the journal about it. Nothing
> depends on it, and nothing in "what resolved means" mentions it.
>
> An incident always contains one of these. Recognising it — and *leaving it
> alone* — is worth as much as any repair, and the clock is how you find out
> whether you can.

## Where this fits in the plan

| Day | Slot | What |
| --- | --- | --- |
| 26 | after the mock | severity 1, cold — the warm-up |
| 27 | evening | severity 2 |
| 28 | after Mock EX200-C | severity 3, with rhel02 up |
| 29 | — | nothing new. Rest. Fill in the log. |
| 55 | Month 2 | severity 3 on top of `break-ansible.sh` — see [07-Scenario-Labs](07-Scenario-Labs.md) |
| 58 | before EX294 | **severity 4**, `--hard`, two hours, no notes |

One severity-4 drill done properly is worth more than five reset halfway. If you
are over the target, keep going and write down the real number.

## Drill log

The columns that matter are the last three. "Took first" is the triage decision,
"misled longest" is the habit you will keep unless you write it down, and the
snapshot column is the one it would be easiest to leave blank.

| Date | Sev | Faults staged | Time to green | Over target? | Took first | Misled longest | Snapshot restored? |
| --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |

## Gate

- [ ] Severity 1 and 2 each completed inside target, closed to AI
- [ ] Severity 3 completed with rhel02 actually in scope
- [ ] Severity 4 completed once, persistence found and **deleted**, decoy left alone
- [ ] One incident graded with `--hard` and passed
- [ ] No incident was ever "fixed" with `setenforce 0`, a `chmod`, or a policy module
- [ ] No incident ended in a snapshot restore
- [ ] For every report in the last drill, I can name the cause without `reveal`

→ Drills: [10-Advanced-Breakfix-Labs](10-Advanced-Breakfix-Labs.md) · checkers: [09-Verification-Scripts](09-Verification-Scripts.md) · environment: [00-Lab-Environment](00-Lab-Environment.md) · back to [_Hub](_Hub.md)
