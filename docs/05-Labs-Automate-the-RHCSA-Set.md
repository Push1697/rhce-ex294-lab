---
created: 2026-09-02
tags: [rhce, ansible, labs, ex294]
---
# 05 — Automate the Entire RHCSA Set (Days 38–44)

Week 6. Stop treating Ansible as a separate subject.

Everything you did by hand in Weeks 1–3, you now do again — through Ansible.
Nothing new to learn conceptually; everything to gain in fluency.

Use [Manual-to-Ansible-Map](Manual-to-Ansible-Map.md) as your lookup. Revert both managed nodes to
`clean` before each lab so you are always automating from a genuinely fresh box.

> [!tip] Automated checks: `./verify 6.1` … `6.5`, or `./verify week6`
> These ship the Week 1–3 check scripts to the managed nodes and run them there,
> from the control node — so the same criteria grade the automated build.
> Snapshot before `6.3`. See [09-Verification-Scripts](09-Verification-Scripts.md).

> [!important] The one rule this week
> **You may not SSH into a managed node to fix anything.** If something is wrong,
> fix the playbook and re-run it. Log in only to *verify*, never to repair.
> This rule is the entire point of the week.

---

## Day 38 — Users, groups, sudo, SSH

### Lab 6.1 — Re-do Labs 1.2 and 1.4 as a playbook (75 min)

**Requirement**

`users.yml` that takes a fresh node to the exact state of Labs 1.2 + 1.4:

1. Groups `developers` (GID 5000) and `contractors`.
2. Users amit, sara, raj with correct primary groups; vendor1 with no shell.
3. sara's password aging: 30 day max, 7 day warning.
4. raj locked.
5. SSH public keys deployed for amit and sara.
6. Passwordless sudo for `developers`, limited to the two httpd commands, with
   the sudoers file **validated before deployment**.
7. sshd: key-only, root denied, port 2222 added — including the SELinux and
   firewall consequences.

**Acceptance criteria**

- [ ] Runs against a `clean` node and produces the Lab 1.2/1.4 end state exactly
- [ ] Second run: `changed=0`
- [ ] An invalid sudoers template is **rejected**, not deployed
- [ ] You never logged into the node to fix anything

**Verify** — from the control node only:

```bash
ansible managed -m command -a 'getent group developers' --become
ansible managed -m command -a 'chage -l sara' --become
ansible managed -m command -a 'semanage port -l' --become | grep 2222
ansible-playbook users.yml   # changed=0
ssh -p 2222 amit@rhel01 hostname
```

> [!tip]- The sudoers validate trap
> `validate: 'visudo -cf %s'` on the `copy`/`template` module. Deploying a broken
> sudoers file with no validation locks you out of root entirely — a genuinely
> unrecoverable mistake in an exam without console access.

---

## Day 39 — Packages, repositories, services

### Lab 6.2 — Re-do Labs 2.1 and 2.3 as a playbook (60 min)

**Requirement**

1. Define a custom repository via `yum_repository`.
2. Install a defined package list.
3. Deploy the `siteguard` script and its unit file from templates.
4. `daemon_reload` when the unit changes, and only then.
5. Enable and start it.
6. Set the default systemd target to multi-user.
7. Mask `debug-shell.service`.

**Acceptance criteria**

- [ ] Repo file managed by Ansible, not hand-edited
- [ ] Unit changes trigger a reload; unchanged runs do not
- [ ] Idempotent
- [ ] Survives a reboot triggered *by the playbook itself*

**Verify**

```bash
ansible-playbook services.yml
ansible managed -m systemd_service -a 'name=siteguard state=started' --become
ansible managed -m command -a 'systemctl is-enabled siteguard'
ansible managed -m reboot --become
ansible managed -m command -a 'systemctl is-active siteguard'
```

---

## Day 40 — Storage: partitions, LVM, filesystems, mounts

### Lab 6.3 — Re-do Labs 2.5 and 2.6 as a playbook (90 min)

Hardest automation lab of the week. Storage modules live outside `ansible.builtin`.

**Requirement**

Against a `clean` node with blank `/dev/sdb` and `/dev/sdc`:

1. Partition `/dev/sdb` — 2 GB and 1 GB.
2. XFS on the 2 GB partition, mounted persistently at `/data` **by UUID**, with
   `noexec,nodev`.
3. Swap on the 1 GB partition, enabled persistently.
4. Volume group `vgdata` on `/dev/sdc`, 16 MB extents.
5. `lvapp` 4 GB XFS at `/app`; `lvlogs` 2 GB ext4 at `/applogs`.
6. Re-running the playbook with `lvapp` set to 9 GB extends the LV **and** grows
   the filesystem.

**Acceptance criteria**

- [ ] Everything created from a blank disk in one run
- [ ] fstab entries use UUIDs, written by the `mount` module
- [ ] Changing the size variable and re-running grows the filesystem safely
- [ ] Second run with unchanged variables: `changed=0`
- [ ] Survives reboot

**Verify**

```bash
ansible managed -m command -a 'lsblk -f' --become
ansible managed -m command -a 'vgdisplay vgdata' --become | grep 'PE Size'
ansible managed -m command -a 'findmnt /data /app /applogs' --become
ansible managed -m reboot --become
ansible managed -m command -a 'df -h /app' --become
```

> [!tip]- Hint
> `community.general.parted`, `community.general.filesystem` (with `resizefs: true`),
> `community.general.lvg`, `community.general.lvol` (`size: 9g`, `resizefs: true`),
> `ansible.posix.mount` (`state: mounted` writes fstab **and** mounts;
> `state: present` writes fstab only).

> [!warning] Idempotence and destructive modules
> `filesystem` will happily reformat if you let it — `force: false` is the
> default for a reason. Test with `--check` first. This is the one lab where a
> mistake costs you the node, so snapshot before every run.

---

## Day 41 — Networking, firewall, SELinux

### Lab 6.4 — Re-do Labs 2.4 and 3.1–3.3 as a playbook (75 min)

**Requirement**

1. Set hostnames via Ansible.
2. Manage the static IP profile with `nmcli`.
3. SELinux enforcing, and enforce it persistently.
4. The `/web(/.*)?` file context, applied and relabelled.
5. `httpd_can_network_connect` boolean on, persistently.
6. Port 2222 added to `ssh_port_t`.
7. firewalld: zones, services, ports, and the rich rule from Lab 3.3.
8. Everything permanent, everything idempotent.

**Acceptance criteria**

- [ ] `restorecon -Rvn /web` reports nothing after the run
- [ ] Booleans persist across reboot
- [ ] Firewall runtime and permanent config match
- [ ] Re-running changes nothing

**Verify**

```bash
ansible-playbook security.yml
ansible managed -m command -a 'getenforce' --become
ansible managed -m command -a 'restorecon -Rvn /web' --become   # empty output
ansible managed -m command -a 'firewall-cmd --list-all' --become
ansible-playbook security.yml | grep 'changed=0'
```

---

## Days 42–44 — The week's real test

### Lab 6.5 — Ten servers, zero SSH sessions (3–4 h across the weekend)

> **Configure 10 new RHEL web servers without manually SSHing into any of them.**

You have two VMs, so simulate the rest: add 8 more entries to the inventory
pointing at the two real hosts with `ansible_host`, or clone two more nodes with
`lab-build.sh`. The point is that the playbook must not care how many there are.

**The pipeline your playbook must implement**

```text
Create admin users
        ↓
Configure SSH (keys, hardening)
        ↓
Install packages
        ↓
Deploy configuration (templated per host)
        ↓
Configure firewall
        ↓
Configure SELinux
        ↓
Start services
        ↓
Enable at boot
        ↓
Verify
```

**Requirement**

1. `site.yml` runs the whole pipeline end to end on a fresh node.
2. Per-host values (hostname, IP, site name) come from inventory variables and
   facts — never hardcoded.
3. The final *Verify* stage genuinely verifies: it checks the service responds,
   the port is open, and the config survives — and **fails the play** if not.
4. The playbook is safe to run repeatedly.
5. It works on a node you have never logged into.

**Acceptance criteria**

- [ ] One command takes N fresh nodes to fully configured
- [ ] `changed=0` on the second run across every host
- [ ] Verification stage fails loudly when you sabotage a host with `break.sh`
- [ ] You did not SSH in to fix anything all week

**Verify**

```bash
ansible-playbook site.yml
ansible-playbook site.yml | grep -E 'changed=[1-9]'    # nothing
ansible web -m uri -a 'url=http://{{ ansible_host }} status_code=200'
# then sabotage and prove the verification catches it:
ansible rhel01 -m command -a '/root/break.sh firewall' --become
ansible-playbook site.yml --tags verify                # must FAIL
```

> [!tip] Verification that actually verifies
> A `debug` message saying "done" is not verification. Use `uri`, `wait_for`,
> `command` + `failed_when`, or `assert`. `assert` is the exam-friendly one:
> ```yaml
> - name: Web service is genuinely serving
>   ansible.builtin.assert:
>     that:
>       - result.status == 200
>     fail_msg: "Site not responding on {{ inventory_hostname }}"
> ```

---

## Day 44 gate

- [ ] Every RHCSA topic from Weeks 1–3 now exists as working automation
- [ ] I did not log into a managed node to repair anything all week
- [ ] My playbooks are idempotent, verified by a second run
- [ ] I know which modules need `ansible.posix` / `community.general`
- [ ] Storage automation works from blank disks

→ Next: [06-Labs-Advanced-Ansible](06-Labs-Advanced-Ansible.md)
