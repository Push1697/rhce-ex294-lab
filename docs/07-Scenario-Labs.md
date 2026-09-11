---
created: 2026-09-02
tags: [rhce, ansible, scenarios, labs, ex294]
---
# 07 — Scenario Labs (Days 52–55)

Week 8. **Stop watching courses.** Almost completely.

Every evening gets one scenario. Read the requirement, build it, verify it,
reboot, verify again. Then break it and repair it.

Restore both managed nodes to `clean` before each scenario. `ansible-doc` is your
only reference.

> [!tip] Automated checks: `./verify s1` … `s5`, or `./verify week8`
> Each scenario is scored per requirement, like a mock.
> See [09-Verification-Scripts](09-Verification-Scripts.md).

---

## Scenario 1 — Fleet baseline (Day 52 — Fri, 90 min)

> Configure 3 RHEL servers with users, SSH keys, sudo and required packages
> using Ansible.

**Requirement**

1. Groups `sysadmins` and `developers`; five users distributed across them from
   a variable structure.
2. SSH public keys deployed for all five.
3. `sysadmins` gets passwordless sudo; `developers` gets password-required sudo
   restricted to service management.
4. Baseline packages installed on every host; a different additional set per
   group.
5. SSH hardened: no root login, no password authentication.
6. `/etc/motd` templated with the hostname and the build date.

**Acceptance criteria**

- [ ] One run against three fresh hosts
- [ ] `changed=0` on the second run
- [ ] sudoers validated before deployment
- [ ] Key-only SSH confirmed for every user
- [ ] Survives reboot

---

## Scenario 2 — Web tier, end to end (Day 53 — Sat, 90 min)

> Deploy Apache to the web group, configure firewall + SELinux, deploy a
> templated configuration and make everything persistent.

**Requirement**

1. Apache installed, enabled, running on the `web` group only.
2. Document root at `/web/site` — **not** the default — with correct SELinux
   file contexts applied via policy, not `chcon`.
3. Templated virtual host, validated before deployment.
4. firewalld permitting http and https permanently.
5. An extra listener on port 8080, with the matching SELinux port definition.
6. A handler restarting Apache only when configuration actually changes.
7. Index page generated from facts, naming the host.

**Acceptance criteria**

- [ ] `curl rhel01` and `curl rhel01:8080` both return the host's own page
- [ ] `restorecon -Rvn /web` outputs nothing
- [ ] SELinux enforcing throughout
- [ ] Reboot changes nothing
- [ ] Second run: zero changes

---

## Scenario 3 — Environment separation (Day 53 — Sat, 75 min)

> Configure different settings for production and development using
> inventory/group variables.

**Requirement**

1. `prod` and `dev` groups, one host each.
2. Identical playbook, different outcomes: different document roots, different
   log levels, different package sets, firewall open widely in dev and narrowly
   in prod.
3. Production hosts additionally get a stricter SSH configuration and audit
   settings.
4. A single variable flips a host between environments with no playbook edit.
5. `group_vars/all.yml` supplies defaults that both environments override.

**Acceptance criteria**

- [ ] Zero environment-specific logic hardcoded in tasks
- [ ] Moving a host between groups changes its build with no other change
- [ ] `ansible-inventory --graph` documents the layout
- [ ] Both environments idempotent

> [!tip] This is the scenario that tests whether you understood variables
> If you find yourself writing `when: inventory_hostname == "rhel01"`, stop.
> That is the wrong answer. Use group membership and variables.

---

## Scenario 4 — Secrets (Day 54 — Sun, 60 min)

> Store sensitive information using Vault and consume it from a playbook.

**Requirement**

1. Database credentials in an encrypted `group_vars/db.yml`.
2. A user account whose password comes from the vault, hashed correctly — a
   plaintext password in `/etc/shadow` is a failure.
3. A templated application config file containing the secret, mode `0600`,
   owned by the service account.
4. The playbook runs unattended via a vault password file.
5. The secret appears nowhere in output, even with `-vv`.
6. A second, separately-encrypted vault file with a **different** password, both
   used in one run.

**Acceptance criteria**

- [ ] `grep -r` across the repo finds no plaintext secret
- [ ] Runs unattended, no prompt
- [ ] Output shows `censored` where the secret would be
- [ ] Two vault IDs used simultaneously

**Verify**

```bash
ansible-playbook db.yml --vault-id dev@~/.vault_dev --vault-id prod@~/.vault_prod
ansible-playbook db.yml -vv | grep -i s3cret || echo "clean"
ansible db -m command -a 'getent shadow appuser' --become
```

---

## Scenario 5 — A role that builds a server from nothing (Day 54 — Sun, 90 min)

> Build an Apache role that can configure a completely fresh RHEL server.

**Requirement**

1. A single role, scaffolded with `ansible-galaxy role init`.
2. Takes a `clean` node to a fully working, firewalled, SELinux-correct web
   server with one play and no external tasks.
3. Every tunable exposed in `defaults/main.yml` — port, document root, server
   name, package list.
4. Handlers for reload vs restart, used correctly.
5. `meta/main.yml` declares its dependency on your `common` role.
6. Documented in the role's own `README.md`.
7. Works unchanged on a host it has never seen.

**Acceptance criteria**

- [ ] `ansible-playbook -e "apache_port=8888"` visibly changes the result
- [ ] Role runs standalone against a clean node
- [ ] Zero hardcoded hostnames or paths in `tasks/`
- [ ] Idempotent, reboot-safe

---

## Day 55 — Break your own automation

This is where a great deal of the learning actually happens.

### The Ansible saboteur

Save as `~/Desktop/projects/rhce-lab/break-ansible.sh` on the **control node**,
run inside your project directory. Then repair without searching.

```bash
#!/usr/bin/env bash
# break-ansible.sh — corrupt the automation project so you can practise repair.
# Commit your work to git first:  git init && git add -A && git commit -m ok
set -Eeuo pipefail
PROJ="${1:-$HOME/ansible}"; cd "$PROJ"

f_yaml()      { sed -i '0,/^    - name:/s//   - name:/' site.yml; }          # indentation
f_inventory() { sed -i 's/^rhel01/rhel99/' inventory; }                       # unreachable host
f_ssh()       { chmod 600 ~/.ssh/id_ed25519.pub; mv ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.bak; }
f_sudo()      { sed -i 's/^become = True/become = False/' ansible.cfg; }
f_undefvar()  { sed -i 's/{{ apache_port }}/{{ apache_prt }}/' roles/apache/templates/*.j2; }
f_collection(){ sed -i 's/ansible.posix.firewalld/ansible.posix.firewalld_typo/' roles/*/tasks/main.yml; }
f_condition() { sed -i 's/when: inventory_hostname in groups\["web"\]/when: inventory_hostname in groups["wb"]/' site.yml; }
f_template()  { printf '{%% if unclosed %%}\n' >> roles/apache/templates/vhost.conf.j2; }
f_handler()   { sed -i 's/notify: restart apache/notify: restart apach/' roles/apache/tasks/main.yml; }

FAULTS=(yaml inventory ssh sudo undefvar collection condition template handler)
case "${2:-random}" in
  list) printf '%s\n' "${FAULTS[@]}" ;;
  random) f="${FAULTS[$RANDOM % ${#FAULTS[@]}]}"; "f_$f"; echo "Fault applied. Find it." ;;
  *) "f_${2}"; echo "Applied: $2" ;;
esac
```

Combine it with `break.sh` from [02-Labs-Security-and-Breakfix](02-Labs-Security-and-Breakfix.md) on the managed
nodes — a fault on the target *and* a fault in the automation at the same time
is the realistic case.

### The full error catalogue to drill

| Fault | Where it shows up | Your first move |
| --- | --- | --- |
| Wrong YAML indentation | Parse error before any task runs | `ansible-playbook --syntax-check` |
| Wrong inventory | `UNREACHABLE` or "skipping: no hosts matched" | `ansible-inventory --graph` |
| SSH failure | `UNREACHABLE`, permission denied | `ansible <host> -m ping -vvv` |
| sudo failure | `sudo: a password is required` | check `become`, `-K`, sudoers |
| Undefined variable | `'x' is undefined` at template time | `--check`, then `| default()` |
| Missing collection | `couldn't resolve module/action` | `ansible-galaxy collection list` |
| Incorrect condition | Task silently skips, nothing happens | `--check -vv`, print the fact |
| Bad template | `TemplateSyntaxError` | render with `--check --diff` |
| Service failure | Task fails on start | `journalctl -xeu` on the target |
| SELinux problem | Service starts, access denied | `ausearch -m AVC -ts recent` |
| Firewall problem | Service up, unreachable | `firewall-cmd --list-all` |

> [!important] "Skipping" is the dangerous one
> A failed task shouts at you. A wrongly-conditioned task **succeeds silently**
> and does nothing. In the exam that is a zero with a green playbook run. Always
> read the recap line: `ok=`, `changed=`, and especially `skipped=`.

### Drill log

| Date | Fault | Time to find | Time to fix | Notes |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

---

## Day 55 gate

- [ ] All five scenarios completed unaided
- [ ] Every fault in both saboteurs diagnosed in under 10 minutes
- [ ] I read the play recap for `skipped=` as a matter of habit
- [ ] I have not used a search engine for a week

→ Next: [08-EX294-Exam-Prep](08-EX294-Exam-Prep.md)
