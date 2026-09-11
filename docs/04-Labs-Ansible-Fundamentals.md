---
created: 2026-09-02
tags: [rhce, ansible, labs, ex294]
---
# 04 — Ansible Fundamentals (Days 31–37)

**Month 2 — EX294 track.**

Week 5. RHCE properly begins here.

> [!important] The only reference you are allowed
> `ansible-doc`. Not the web, not a cheat sheet. The exam gives you the installed
> documentation and nothing else, so build the habit now:
> ```bash
> ansible-doc -l | grep -i firewall
> ansible-doc ansible.builtin.user
> ansible-doc -s ansible.builtin.dnf      # ready-to-paste snippet
> ```
> `ansible-doc -s` is the single highest-value command in this entire week.

All work happens on `rhel-control` in `~/ansible/`, against `rhel01` and `rhel02`.

> [!tip] Automated checks: `./verify 5.1` … `5.7`, or `./verify week5`
> These run your playbooks, twice, because idempotence is the requirement.
> See [09-Verification-Scripts](09-Verification-Scripts.md).

---

## Day 31 — Inventory, config, connectivity

### Lab 5.1 — Make the control node work (60 min)

**Requirement**

1. `~/ansible/ansible.cfg` used automatically when you run `ansible` from that
   directory — prove Ansible is reading *yours*, not `/etc/ansible/ansible.cfg`.
2. An inventory defining groups `web` (rhel01), `db` (rhel02), `prod` (rhel01),
   `dev` (rhel02), and a parent group `managed` containing web and db.
3. Passwordless SSH and passwordless privilege escalation to both nodes.
4. Prove connectivity with an ad-hoc ping.
5. Show which host belongs to which groups without reading the file.

**Acceptance criteria**

- [ ] `ansible --version` reports your config file path
- [ ] `ansible managed --list-hosts` returns both nodes
- [ ] `ansible all -m ping` returns SUCCESS for both
- [ ] `ansible all -m command -a id --become` returns uid=0
- [ ] `ansible-inventory --graph` shows the group tree

**Verify**

```bash
ansible --version | grep 'config file'
ansible-inventory --graph
ansible-inventory --host rhel01
ansible managed -m ping
ansible managed -m command -a 'id' --become
```

> [!warning] The config-file trap
> Ansible ignores an `ansible.cfg` in a **world-writable** directory, silently.
> If your config seems ignored, check the directory permissions first.

---

## Day 32 — Ad-hoc commands and modules

### Lab 5.2 — Do a full day of admin without a playbook (60 min)

**Requirement**

Using **only** ad-hoc commands (`ansible ... -m ...`), on all managed nodes:

1. Install `httpd` and `firewalld`.
2. Start and enable both.
3. Create user `webadmin` with a specific UID.
4. Copy a file to `/etc/motd` with defined content.
5. Open the http service in the firewall permanently.
6. Gather and display only the `ansible_distribution*` facts.
7. Reboot rhel02 and wait for it to return.

**Acceptance criteria**

- [ ] Every task done ad-hoc, no playbook file
- [ ] Second run of each command reports `ok`, not `changed` (idempotence)
- [ ] You found each module with `ansible-doc`, not from memory

**Verify**

```bash
ansible managed -m dnf -a 'name=httpd state=present' --become
ansible managed -m service -a 'name=httpd state=started enabled=true' --become
ansible managed -m setup -a 'filter=ansible_distribution*'
ansible managed -m command -a 'systemctl is-enabled httpd'
```

> [!tip] Idempotence is the whole idea
> Run every command twice. The second run must be green `ok`, not orange
> `changed`. A task that reports `changed` on every run is a broken task —
> `command` and `shell` are the usual culprits, which is why you avoid them
> whenever a real module exists.

---

## Day 33 — YAML and your first playbooks

### Lab 5.3 — Construct, don't copy (75 min)

**Requirement**

Write `~/ansible/web.yml` that configures the `web` group as a working web
server. Do **not** copy this from anywhere — build it task by task, finding each
module with `ansible-doc`.

It must:

1. Install httpd and firewalld.
2. Deploy `/var/www/html/index.html` containing the host's own hostname and IP,
   sourced from facts.
3. Start and enable httpd.
4. Permit http through the firewall permanently.
5. Be fully idempotent.

**Acceptance criteria**

- [ ] `ansible-playbook --syntax-check web.yml` passes
- [ ] `ansible-playbook --check web.yml` runs clean against a configured host
- [ ] `curl rhel01` returns the correct hostname
- [ ] Second run: **zero** changed tasks
- [ ] No `command` or `shell` module used anywhere

**Verify**

```bash
ansible-playbook --syntax-check web.yml
ansible-playbook web.yml
ansible-playbook web.yml | grep -E 'changed=[1-9]'    # must find nothing
curl -s rhel01
```

> [!tip]- YAML failures that will cost you marks
> Tabs are illegal — spaces only. `become: true` at play level vs task level.
> A colon inside an unquoted value breaks the parse. `state: present` vs
> `state: latest` are not the same answer.

---

## Day 34 — Variables, facts, and precedence

### Lab 5.4 — Same playbook, different results per host (60 min)

**Requirement**

1. `group_vars/web.yml` sets the served port to 80; `group_vars/db.yml` sets
   database-related variables.
2. `host_vars/rhel01.yml` overrides one group variable — prove which wins.
3. A playbook that uses `ansible_facts` to install the correct package name
   depending on the distribution major version.
4. Register the output of a command and use it in a later task.
5. Create a custom fact on rhel01 under `/etc/ansible/facts.d/` and consume it.
6. Prompt for a variable at runtime with a sensible default.

**Acceptance criteria**

- [ ] Host var demonstrably beats group var
- [ ] Custom fact appears under `ansible_local`
- [ ] Registered variable is used, and you can print its `.stdout`
- [ ] You can state the precedence order from memory

**Verify**

```bash
ansible rhel01 -m setup -a 'filter=ansible_local'
ansible-playbook vars.yml -e "extra_var=fromcli"
ansible rhel01 -m debug -a 'var=ansible_facts.distribution_major_version'
```

> [!tip]- Precedence, roughly lowest → highest
> role defaults → group_vars/all → group_vars/group → host_vars → play vars →
> task vars → **`-e` extra vars always win**. Know that `-e` wins; it is a
> frequent exam question shaped as "why is my variable being ignored".

---

## Day 35 — Loops and conditionals

### Lab 5.5 — Stop repeating yourself (60 min)

**Requirement**

1. Create five users from a list of dictionaries, each with their own UID,
   group and comment — in a **single** task.
2. Install a list of packages in one task.
3. Start a service only if the host is in the `web` group.
4. Deploy a config file only when a given file does not already exist.
5. Apply a task only when a registered command succeeded.
6. Loop over a dictionary and print key/value pairs.
7. Skip a task entirely on RHEL 8, run it on RHEL 9+.

**Acceptance criteria**

- [ ] No copy-pasted near-identical tasks anywhere
- [ ] Conditionals use facts, not hardcoded hostnames
- [ ] Skipped tasks report `skipping`, not failure
- [ ] Playbook is idempotent

**Verify**

```bash
ansible-playbook loops.yml
ansible managed -m command -a 'id user3'
ansible-playbook loops.yml --limit dev    # web-only tasks skip cleanly
```

> [!tip]- Hint
> `loop:` with a list of dicts and `{{ item.name }}`. `when:` takes a bare
> expression — no `{{ }}` around the whole condition.
> `when: ansible_facts['distribution_major_version'] | int >= 9`.

---

## Day 36 — Handlers, error handling, idempotence

### Lab 5.6 — Behave correctly when things change or fail (60 min)

**Requirement**

1. Deploy an httpd config file; restart httpd **only when the file changes**,
   via a handler.
2. Validate the config before it is put in place — a broken config must never
   reach the server.
3. A task that is allowed to fail without stopping the play.
4. A task whose failure condition you define yourself, based on its output.
5. A block that runs cleanup even when an earlier task fails.
6. Force handlers to run even if a later task fails.

**Acceptance criteria**

- [ ] Unchanged config → handler does **not** fire
- [ ] Changed config → handler fires exactly once
- [ ] Deliberately broken config is rejected before deployment
- [ ] Play continues past the permitted failure
- [ ] Rescue/always blocks demonstrably execute

**Verify**

```bash
ansible-playbook handlers.yml            # first run: handler fires
ansible-playbook handlers.yml            # second run: no handler, no changes
# now corrupt the template and re-run — deployment must be refused
```

> [!tip]- Hint
> `notify:` + `handlers:`; `validate: 'httpd -t -f %s'` on the template/copy
> module; `ignore_errors: true`; `failed_when:`; `changed_when:`;
> `block/rescue/always`; `--force-handlers`.

---

## Day 37 — Week 5 consolidation

### Lab 5.7 — Timed build (90 min, closed-book except `ansible-doc`)

Revert both managed nodes to `clean`.

**Requirement**

One playbook, run once, that takes both nodes from fresh to:

1. A `sysadmins` group and three users in it, with SSH keys deployed.
2. Passwordless sudo for that group.
3. httpd installed, configured, running and enabled — on `web` only.
4. A templated index page naming the host.
5. firewalld permitting http on web, and nothing extra anywhere.
6. A daily systemd timer running a maintenance script.
7. Handlers restarting services only on real change.
8. Idempotent: a second run reports zero changes.

- [ ] Completed inside 90 minutes
- [ ] `ansible-doc` was the only reference used
- [ ] Second run: `changed=0` on every host

→ Next: [05-Labs-Automate-the-RHCSA-Set](05-Labs-Automate-the-RHCSA-Set.md) — where the two halves join up.
