---
project: true
status: active
priority: 1
area: work
started_date: 2026-09-02
target_date: 2026-10-31
next_action: "Book EX200 for ~Oct 1, then build the 3-node KVM lab"
tags: [project-hub, rhce, rhcsa, ansible, certification]
---
# RHCSA → RHCE — 60-Day Prep

**Status:** Active — work-track #1 (KPI-linked, separate from the personal SaaS priority list)
**Next action:** Book EX200 for ~Oct 1, then build the 3-node KVM lab
**Window:** 2026-09-02 → 2026-10-31 (Day 1 → Day 60)

> [!goal] Two exams, in order
> **Month 1 → EX200 (RHCSA).** Core Linux, certified.
> **Month 2 → EX294 (RHCE).** Ansible automation, certified.
>
> This is not an arbitrary split. RHCSA is the **prerequisite** — an EX294 pass
> only becomes RHCE once you hold a current RHCSA. Certifying EX200 first also
> banks a real credential at the halfway mark instead of betting everything on
> one exam at Day 60.

> [!important] What success looks like
> Not "I finished the videos." It is this, in order:
> 1. Give me a blank RHEL VM and a requirement — I can build it. **(EX200)**
> 2. Give me 20 blank RHEL machines — I can automate the same build. **(EX294)**
>
> Every lab here is written as a **requirement**, never as a command definition.
> If you can only recite `lvextend`, you are not ready.

## ⚠️ Verify before booking

Red Hat restructured its certification framework in **May 2026** and now
separates the Enterprise Linux and Ansible tracks. EX200 remains foundational to
both.

**Ask your L&D team for the exact exam codes and RHEL version your KPI expects**
— do not assume the older blanket wording "RHCE". Confirm in Week 1, because it
determines what both exam phases rehearse against.

- [ ] Confirm exact exam codes + RHEL version with L&D
- [ ] Confirm who pays for the vouchers and the booking deadline
- [ ] **Book EX200 now, for on or near Day 30.** A booked date is what makes
      Month 1 honest.
- [ ] Book EX294 provisionally for Day 60

## 📅 The 60 days

```text
DAY 1 ─────────────── DAY 30 ─────────────── DAY 60
│                     │                      │
│   MONTH 1           │   MONTH 2            │
│   CORE LINUX        │   ANSIBLE            │
│   → EX200 / RHCSA   │   → EX294 / RHCE     │
│                     │                      │
└── Weeks 1–4 ────────┴── Weeks 5–8 ─────────┘
    build → break →       automate → break →
    fix → CERTIFY         fix → CERTIFY
```

### Month 1 — EX200 (RHCSA)

| Week | Days | Dates | Focus | Lab note |
| --- | --- | --- | --- | --- |
| 1 | 1–7 | Sep 2–8 | Files, users, permissions, ACL, sudo, SSH, bash | [01-Labs-RHCSA-Foundation](01-Labs-RHCSA-Foundation.md) |
| 2 | 8–14 | Sep 9–15 | systemd, dnf, networking, storage, LVM, NFS | [01-Labs-RHCSA-Foundation](01-Labs-RHCSA-Foundation.md) |
| 3 | 15–21 | Sep 16–22 | SELinux, firewalld, boot, **break-fix** | [02-Labs-Security-and-Breakfix](02-Labs-Security-and-Breakfix.md) |
| 4 | 22–30 | Sep 23–Oct 1 | Containers, tuned, kernel, **EX200 mocks → sit exam** | [03-EX200-Exam-Prep](03-EX200-Exam-Prep.md) |

### Month 2 — EX294 (RHCE)

| Week | Days | Dates | Focus | Lab note |
| --- | --- | --- | --- | --- |
| 5 | 31–37 | Oct 2–8 | Ansible fundamentals | [04-Labs-Ansible-Fundamentals](04-Labs-Ansible-Fundamentals.md) |
| 6 | 38–44 | Oct 9–15 | Re-do all of RHCSA *through* Ansible | [05-Labs-Automate-the-RHCSA-Set](05-Labs-Automate-the-RHCSA-Set.md) |
| 7 | 45–51 | Oct 16–22 | Roles, Jinja2, Vault, collections | [06-Labs-Advanced-Ansible](06-Labs-Advanced-Ansible.md) |
| 8 | 52–55 | Oct 23–26 | Full scenarios + deliberate breakage | [07-Scenario-Labs](07-Scenario-Labs.md) |
| — | 56–60 | Oct 27–31 | **EX294 mocks → sit exam** | [08-EX294-Exam-Prep](08-EX294-Exam-Prep.md) |

Day 1 is anchored to 2026-09-02. Shift every date by the same offset if you
start later.

> [!warning] Month 2 is the tight half
> Month 1 gets a full four weeks because EX200 is a real exam with its own
> objectives. That leaves 30 days for Ansible from a standing start, and the
> EX294 mocks are 4 hours each — which does not fit a weekday evening. Decide in
> Week 7 whether to take leave for the mocks or push EX294 into mid-November.
> Slipping EX294 costs a date; sitting it unprepared costs a retake.

## 📚 Project notes

- [00-Lab-Environment](00-Lab-Environment.md) — 3-node KVM/libvirt lab, RHEL developer subscription, snapshots
- [01-Labs-RHCSA-Foundation](01-Labs-RHCSA-Foundation.md) — Days 1–14
- [02-Labs-Security-and-Breakfix](02-Labs-Security-and-Breakfix.md) — Days 15–21
- [03-EX200-Exam-Prep](03-EX200-Exam-Prep.md) — Days 22–30, containers + EX200 mocks
- [04-Labs-Ansible-Fundamentals](04-Labs-Ansible-Fundamentals.md) — Days 31–37
- [05-Labs-Automate-the-RHCSA-Set](05-Labs-Automate-the-RHCSA-Set.md) — Days 38–44
- [06-Labs-Advanced-Ansible](06-Labs-Advanced-Ansible.md) — Days 45–51
- [07-Scenario-Labs](07-Scenario-Labs.md) — Days 52–55
- [08-EX294-Exam-Prep](08-EX294-Exam-Prep.md) — Days 56–60
- [10-Advanced-Breakfix-Labs](10-Advanced-Breakfix-Labs.md) — ten harder drills for Days 22–29; the saboteur and the rules
- [11-Incident-Drills](11-Incident-Drills.md) — the last rung: several faults at once, a work order, and a clock
- [09-Verification-Scripts](09-Verification-Scripts.md) — offline checkers for every lab; the reboot-proof loop
- [Manual-to-Ansible-Map](Manual-to-Ansible-Map.md) — the RHCSA→RHCE bridge; the most important reference here
- [Exam-Day-Protocol](Exam-Day-Protocol.md) — the loop to run on every task, both exams

## 🌱 Published to the garden

The whole curriculum is public at <https://learning.overflowbyte.cloud> — 14
standalone articles derived from the notes below, with the dates, bookings and
KPI context stripped out. **These notes stay the working copy;** the articles are
the published derivative, so a change here needs mirroring there.

The scripts are public too, which is what the articles link readers at:
<https://github.com/Push1697/published_quartz_blog/tree/v4/rhce-labs>

| Covers | Article | Working copy |
| --- | --- | --- |
| The curriculum index | [RHCSA to RHCE - A 60-Day Lab Curriculum](https://learning.overflowbyte.cloud/blog/rhcsa-to-rhce-a-60-day-lab-curriculum) | this note |
| Lab environment | [Building a Three-Node RHEL Lab on KVM](https://learning.overflowbyte.cloud/blog/building-a-three-node-rhel-lab-on-kvm) | [00-Lab-Environment](00-Lab-Environment.md) |
| Weeks 1–2 labs | [RHCSA Foundation Labs - Users Permissions and Storage](https://learning.overflowbyte.cloud/blog/rhcsa-foundation-labs-users-permissions-and-storage) | [01-Labs-RHCSA-Foundation](01-Labs-RHCSA-Foundation.md) |
| Week 3 labs | [RHCSA Security Labs - SELinux firewalld and Boot Recovery](https://learning.overflowbyte.cloud/blog/rhcsa-security-labs-selinux-firewalld-and-boot-recovery) | [02-Labs-Security-and-Breakfix](02-Labs-Security-and-Breakfix.md) |
| Week 4 labs | [RHCSA Container and Kernel Labs](https://learning.overflowbyte.cloud/blog/rhcsa-container-and-kernel-labs) | [03-EX200-Exam-Prep](03-EX200-Exam-Prep.md) |
| The RHCSA mocks | [Two RHCSA Mock Exam Papers](https://learning.overflowbyte.cloud/blog/two-rhcsa-mock-exam-papers) | [03-EX200-Exam-Prep](03-EX200-Exam-Prep.md) |
| Week 5 labs | [Ansible Fundamentals Labs](https://learning.overflowbyte.cloud/blog/ansible-fundamentals-labs) | [04-Labs-Ansible-Fundamentals](04-Labs-Ansible-Fundamentals.md) |
| Week 6 labs | [Automating the RHCSA Set with Ansible](https://learning.overflowbyte.cloud/blog/automating-the-rhcsa-set-with-ansible) | [05-Labs-Automate-the-RHCSA-Set](05-Labs-Automate-the-RHCSA-Set.md) |
| Week 7 labs | [Advanced Ansible Labs - Roles Templates and Vault](https://learning.overflowbyte.cloud/blog/advanced-ansible-labs-roles-templates-and-vault) | [06-Labs-Advanced-Ansible](06-Labs-Advanced-Ansible.md) |
| Week 8 + EX294 mock | [Ansible Scenario Labs and the EX294 Mock](https://learning.overflowbyte.cloud/blog/ansible-scenario-labs-and-the-ex294-mock) | [07-Scenario-Labs](07-Scenario-Labs.md) |
| The module map | [Manual to Ansible - A Module Map](https://learning.overflowbyte.cloud/blog/manual-to-ansible-a-module-map) | [Manual-to-Ansible-Map](Manual-to-Ansible-Map.md) |
| Exam-day protocol | [Red Hat Exam Day Protocol](https://learning.overflowbyte.cloud/blog/red-hat-exam-day-protocol) | [Exam-Day-Protocol](Exam-Day-Protocol.md) |
| The check harness | [Verifying Your Own Labs Offline](https://learning.overflowbyte.cloud/blog/verifying-your-own-labs-offline) | [09-Verification-Scripts](09-Verification-Scripts.md) |
| The hard drills | [Ten Advanced RHEL Break-Fix Drills](https://learning.overflowbyte.cloud/blog/ten-advanced-rhel-break-fix-drills) | [10-Advanced-Breakfix-Labs](10-Advanced-Breakfix-Labs.md) |
| Incident drills | [Incident Drills — Troubleshooting a Broken Estate Under a Clock](https://learning.overflowbyte.cloud/blog/incident-drills-troubleshooting-a-broken-estate-under-a-clock) | [11-Incident-Drills](11-Incident-Drills.md) |

> [!warning] The auto-publish workflow does not run
> `.github/workflows/publish-garden.yml` fails on every push with
> `Input required and not supplied: token` — the vault repo has no
> `GARDEN_PUBLISH_TOKEN` secret, so it has never actually published anything.
>
> Until that secret exists, publish by hand from the Quartz repo:
>
> ```powershell
> .\scripts\publish-garden.ps1 -SyncOnly
> git add content; git commit -m "Publish"; git push origin v4
> ```
>
> To fix it properly: create a fine-grained PAT with **Contents: read and
> write** on `Push1697/published_quartz_blog`, then add it to the **vault**
> repo as the secret `GARDEN_PUBLISH_TOKEN`.

## ⏱️ Daily routine

You are starting a new job. 2.5–3 h every day will not survive contact with
reality. Target ~15 h/week ≈ 120 h over the 60 days.

**Weekdays — 1.5–2 h**

```text
20 min   revision of yesterday
20 min   new concept
60 min   hands-on lab
20 min   break it, then fix it
```

**Sat/Sun — 3–4 h** — labs almost exclusively. The weekends carry the long labs
and every timed mock.

> [!tip] The 20-minute break-fix block is not optional
> It is the block that produces exam readiness. Skip the concept video before
> you skip this.

## ✅ Month 1 — EX200 topics

- [ ] Linux commands & navigation
- [ ] vim
- [ ] File management
- [ ] Permissions
- [ ] ACLs
- [ ] Users & groups
- [ ] sudo
- [ ] SSH & key auth
- [ ] DNF / RPM / repositories
- [ ] systemd
- [ ] journalctl
- [ ] Processes
- [ ] Networking / nmcli
- [ ] firewalld
- [ ] Partitions
- [ ] LVM
- [ ] XFS / ext4
- [ ] NFS / autofs
- [ ] SELinux
- [ ] Bash scripting
- [ ] **Containers / podman** — rootless, persistent storage, systemd auto-start
- [ ] **tuned profiles**
- [ ] **Kernel management** — grubby, boot targets, kernel arguments

The last three are current EX200 objectives that older 30-day RHCSA plans
routinely omit. They are covered in [03-EX200-Exam-Prep](03-EX200-Exam-Prep.md).

## ✅ Month 2 — EX294 topics

- [ ] Inventories & ansible.cfg
- [ ] Ad-hoc commands & modules
- [ ] Playbooks & YAML
- [ ] Variables, facts, magic vars
- [ ] Loops & conditionals
- [ ] Handlers & failure handling
- [ ] Templates / Jinja2
- [ ] Roles
- [ ] Ansible Vault
- [ ] Collections & content
- [ ] Using only `ansible-doc` for reference

## 🏁 Milestones

- [ ] **Day 30 (Oct 1)** — EX200 sat → RHCSA earned
- [ ] **Day 60 (Oct 31)** — EX294 sat → RHCE earned

## 📝 Log

- **2026-09-02**: Project created. Lab target: 3-node KVM/libvirt on the Linux box, real RHEL via the free developer subscription.
- **2026-09-02**: Restructured into two exam phases — Month 1 certifies EX200, Month 2 certifies EX294. Added container/podman, tuned and kernel-management labs to close current EX200 objective gaps.
- **2026-09-09**: Added offline verification scripts for every lab (`verify/`), including break-fix health checks and scoring mock graders. See [09-Verification-Scripts](09-Verification-Scripts.md).
- **2026-09-09**: Added ten advanced break-fix drills ([10-Advanced-Breakfix-Labs](10-Advanced-Breakfix-Labs.md)) plus the `break-advanced.sh` saboteur and its verifier, for the Day 22–29 evenings and a harder Mock EX200-C.
- **2026-09-11**: Added incident drills ([11-Incident-Drills](11-Incident-Drills.md)) — `incident.sh` opens a severity-graded work order that stages several non-overlapping faults across the estate, fights back at severity 4, and is graded against an SLA by `verify incident`. Every checker also gained `--hard`.
- **2026-09-09**: Curriculum published to the learning garden as 14 standalone articles, with the lab scripts pushed to the public Quartz repo. Every note here now links to its published counterpart.
