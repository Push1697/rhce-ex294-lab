---
created: 2026-09-02
tags: [rhce, ex294, ansible, mock-exam, exam]
---
# 08 — EX294 Exam Prep (Days 56–60)

The end of Month 2. Exam mode for the Ansible half.

> [!warning] Closed book. Genuinely.
> No YouTube. No Google. No AI. No personal notes. No step-by-step tutorial.
> **Only** what exists on the exam machine — for EX294 that means
> `ansible-doc`, `man`, and `/usr/share/doc`.
>
> Red Hat exams are performance based, and your work is graded on machine state
> **after a reboot**. Rehearse under exactly those conditions.

Full protocol: [Exam-Day-Protocol](Exam-Day-Protocol.md).

> [!tip] Automated grader: `./verify ex294-a --spec`, then `./verify ex294-a`
> The spec pins every ambiguous value so the score is deterministic. Grade
> EX294-B with the same script. See [09-Verification-Scripts](09-Verification-Scripts.md).

---

## ⚠️ Read this before Day 56

Month 2 is compressed. EX294 is a 4-hour exam, and these mocks are 4 hours each —
which does not fit a 1.5–2 h weekday budget. Pick one, deliberately, in Week 7:

1. **Take two days of leave** for Days 56–57 and run the mocks properly.
2. **Move the mocks to the weekend** (Days 53–54 are already scenario-heavy, so
   this means shifting scenarios earlier).
3. **Push EX294 by one to two weeks.** Entirely legitimate. RHCSA is already
   banked at Day 30, so the KPI's headline result is secured; EX294 slipping to
   mid-November costs nothing but the date.

A half-run 4-hour mock teaches you very little. A properly run one is the single
best predictor of your result.

---

## Schedule

| Day | Date | Activity |
| --- | --- | --- |
| 56 | Oct 27 | Mock EX294-A — full 4 h |
| 57 | Oct 28 | Mock EX294-B — hostile, 4 h |
| 58 | Oct 29 | **Weak areas only.** No new topics. |
| 59 | Oct 30 | Light revision + one short mock |
| 60 | Oct 31 | Sit EX294 |

---

## Mock EX294-A (Day 56, 4 hours)

Restore **all three** nodes to `clean`. Work only from `rhel-control`.
You may not SSH into a managed node except to verify.

**Setup**

1. Create `/home/pushpendra/ansible-exam/` with an `ansible.cfg` setting the
   inventory, roles path, collections path, remote user and privilege escalation.
2. Build an inventory: groups `webservers`, `databases`, `prod`, `dev`, and a
   parent group `all_managed`.
3. Install `ansible.posix` and `community.general` into a project-local path
   from a `requirements.yml`.

**Playbooks** — each a separate file in the project directory.

4. `packages.yml` — install a defined package list on all managed hosts; install
   an extra package only on hosts with more than 1 GB of RAM, decided by a fact.
5. `users.yml` — create users from a **vault-encrypted** variable file; the `web`
   list gets accounts on webservers only, the `db` list on databases only.
   Passwords hashed, never plaintext. Deploy SSH keys.
6. `webserver.yml` — install and enable httpd on webservers; serve a templated
   `index.html` naming the host and its IP from facts; open the firewall; set
   correct SELinux contexts for a non-default document root.
7. `storage.yml` — on databases, create a VG and LV from a blank disk, format XFS,
   mount persistently at `/dbdata`. If the disk is absent the play must fail with
   a clear message rather than crash.
8. `roles/apache/` — a role fully configuring a web server, all tunables in
   `defaults/`, with handlers.
9. `site.yml` — runs everything in the right order, with tags per stage.
10. `report.yml` — generates `/root/report.txt` on every managed host containing
    hostname, IP, kernel, memory and free disk, from a template.
11. A rolling update across webservers, two at a time, aborting above 25% failure.
12. Every playbook idempotent: a second run reports `changed=0`.

**Grade yourself**

```bash
# reboot every managed node first, then:
ansible-playbook site.yml                                  # changed=0
ansible all_managed -m command -a 'cat /root/report.txt'
grep -r 'password' --include='*.yml' . | grep -v vault     # no plaintext
ansible-playbook site.yml --list-tags
```

---

## Mock EX294-B (Day 57, 4 hours) — hostile

The hardest one. You inherit a broken estate.

1. Before starting, run `break.sh all` on rhel01 and `break-ansible.sh random`
   against your project directory.
2. Repair everything, then complete Mock EX294-A's tasks 4–12 on top.
3. Additionally, destroy one managed node (`lab-destroy.sh`), rebuild it with
   `lab-build.sh`, and bring it back to full parity using **only** `site.yml`.

**Acceptance**

- [ ] Estate repaired and fully configured inside 4 hours
- [ ] Rebuilt node indistinguishable from the others afterwards
- [ ] Everything survives a final reboot of all three nodes
- [ ] You never hand-edited anything on a managed node

---

## Scoring sheet

Copy per mock. Pass mark is 210/300 — roughly **70%**. Score after reboot only;
partial credit does not exist for something that fails on restart.

| # | Task | Done | Survived reboot | Idempotent | What I had to look up |
| --- | --- | --- | --- | --- | --- |
| 4 |  |  |  |  |  |
| 5 |  |  |  |  |  |
| 6 |  |  |  |  |  |

**Result:** ___ / ___ = ___%

**Weak areas:**

**Action for Day 58:**

> [!important] The go/no-go rule
> Two mocks at **85%+**, everything surviving reboot and idempotent, means sit
> the exam. Below 70% on Day 57 means move the booking — see the compression
> options at the top of this note.

---

## Mock results log

| Date | Mock | Score | Time used | Biggest failure mode |
| --- | --- | --- | --- | --- |
| Oct 27 | EX294-A |  |  |  |
| Oct 28 | EX294-B |  |  |  |
| Oct 30 | Short |  |  |  |

---

## Days 58–60 — Land it

**Day 58 — weak areas only.** Fix only what the mocks proved is weak.
Do **not** start a new topic; cramming something unfamiliar in the final week
displaces something you already know.

**Day 59 — light revision.**

- [ ] Re-read [Manual-to-Ansible-Map](Manual-to-Ansible-Map.md) — module names and which collection each lives in
- [ ] Re-read [Exam-Day-Protocol](Exam-Day-Protocol.md)
- [ ] Scaffold a role from scratch, from memory, in under 5 minutes
- [ ] Write a working `ansible.cfg` + inventory from memory in under 5 minutes
- [ ] Encrypt a vault file and consume it unattended, from memory
- [ ] One 60-minute short mock, then stop

**Day 60 — sit EX294.** Sleep properly first. Do not study the night before.

- [ ] EX294 booked
- [ ] EX294 sat
- [ ] Result recorded in the hub log

---

## Final gate

- [ ] RHCSA earned at Day 30
- [ ] Two full EX294 mocks completed under real conditions
- [ ] Every playbook I write is idempotent by habit, not by checking
- [ ] `ansible-doc -s` is faster for me than trying to recall syntax

> [!tip] The last thing to internalise
> When you are stuck, the answer is almost always `ansible-doc -s <module>` or
> `man <thing>`. Reaching for documentation is not failure — it is the skill
> being tested. Freezing because you cannot recall syntax is what costs marks.
