---
created: 2026-09-02
tags: [rhce, rhcsa, ansible, reference, bridge]
---
# Manual → Ansible Map

The single most important reference in this project. It is what turns RHCSA and
RHCE from two unrelated certifications into one continuous skill.

**The method change:** the old plan said
*watch → understand → do it yourself → break it → troubleshoot → rebuild.*

Replace it with:

> **Learn it manually → automate it with Ansible → break it → troubleshoot it →
> rebuild it automatically.**

Do this on the *same day* for the *same topic*. Once Month 2 starts, Day 38 you
create users by hand and Day 38 you also write the `user` module task. The bridge
is built daily, not saved up for Week 6.

During Month 1 you are certifying EX200, so the manual half comes first and this
map is what you read forward into — not something to attempt in parallel.

---

## ⚠️ Collections: the thing that catches people out

Only some of these modules ship in `ansible.builtin`. Several of the ones you
need most for RHCSA-style work — **firewalld, SELinux, mount, ACL, LVM** — live
in `ansible.posix` or `community.general`.

```bash
ansible-galaxy collection list                    # what you actually have
ansible-doc -l ansible.posix                      # what is inside one
ansible-galaxy collection install ansible.posix community.general
```

Install both on the control node in Week 5 and confirm again before the EX294
mocks on Day 56.
If `ansible-doc firewalld` returns nothing in the exam, you needed the collection
and did not check.

---

## The map

| RHCSA task | Manual command | Ansible module | Collection |
| --- | --- | --- | --- |
| Create user | `useradd` | `user` | builtin |
| Create group | `groupadd` | `group` | builtin |
| Set password | `passwd` | `user` + `password:` (hashed) | builtin |
| Password aging | `chage` | `user` (`password_expire_*`) | builtin |
| Deploy SSH key | `ssh-copy-id` | `authorized_key` | ansible.posix |
| sudo rules | `visudo` | `copy`/`template` + `validate` | builtin |
| Install package | `dnf install` | `dnf` | builtin |
| Package group | `dnf group install` | `dnf` (`name: "@group"`) | builtin |
| Add repository | edit `.repo` | `yum_repository` | builtin |
| Start/enable service | `systemctl` | `service` / `systemd_service` | builtin |
| Custom unit file | write `.service` | `template` + `systemd_service` (daemon_reload) | builtin |
| Firewall port/service | `firewall-cmd` | `firewalld` | **ansible.posix** |
| SELinux mode | `setenforce` | `selinux` | **ansible.posix** |
| SELinux boolean | `setsebool -P` | `seboolean` | **ansible.posix** |
| SELinux context | `semanage fcontext` | `sefcontext` + `command: restorecon` | community.general |
| SELinux port | `semanage port` | `seport` | community.general |
| Copy file | `cp` | `copy` | builtin |
| Templated config | edit by hand | `template` (Jinja2) | builtin |
| Line in a file | `sed -i` | `lineinfile` / `blockinfile` | builtin |
| Permissions/ownership | `chmod`, `chown` | `file` | builtin |
| ACLs | `setfacl` | `acl` | **ansible.posix** |
| Create directory | `mkdir -p` | `file` (`state: directory`) | builtin |
| Archive | `tar` | `archive` / `unarchive` | builtin |
| Cron job | `crontab -e` | `cron` | builtin |
| systemd timer | write `.timer` | `template` + `systemd_service` | builtin |
| Mount + fstab | `mount`, edit fstab | `mount` | **ansible.posix** |
| Partition | `parted`, `fdisk` | `parted` | community.general |
| Filesystem | `mkfs.xfs` | `filesystem` | community.general |
| LVM volume group | `vgcreate` | `lvg` | community.general |
| LVM logical volume | `lvcreate`, `lvextend` | `lvol` | community.general |
| Swap | `mkswap`, `swapon` | `filesystem` + `mount` | mixed |
| Hostname | `hostnamectl` | `hostname` | builtin |
| Network config | `nmcli` | `nmcli` | community.general |
| Kernel parameter | `sysctl` | `sysctl` | ansible.posix |
| Reboot and wait | `reboot` | `reboot` | builtin |
| Gather system info | `uname`, `df` | `setup` (facts) | builtin |
| Run something with no module | — | `command` (never `shell` unless you need a shell) | builtin |

---

## Worked example — the pattern to repeat for every topic

**Day 2 manual:**

```bash
groupadd -g 5000 developers
useradd -g developers -c "Amit" amit
usermod -aG wheel amit
chage -M 30 -W 7 sara
```

**Day 2 automated — same outcome, written the same evening:**

```yaml
- name: Developer accounts exist
  hosts: managed
  become: true

  vars:
    developers:
      - { name: amit, uid: 3001, comment: "Amit" }
      - { name: sara, uid: 3002, comment: "Sara" }

  tasks:
    - name: Developers group exists
      ansible.builtin.group:
        name: developers
        gid: 5000
        state: present

    - name: Developer accounts exist
      ansible.builtin.user:
        name: "{{ item.name }}"
        uid: "{{ item.uid }}"
        group: developers
        comment: "{{ item.comment }}"
        state: present
      loop: "{{ developers }}"
```

Then **break it** (delete a user, change a UID by hand, remove the group) and
**rebuild it by re-running the playbook**. That final step is what the exam
actually measures.

---

## When there is no module

Use `command`, and make it honest about change:

```yaml
- name: Relabel the web content
  ansible.builtin.command: restorecon -Rv /web
  register: relabel
  changed_when: relabel.stdout | length > 0
```

Without `changed_when`, that task reports `changed` on every single run and your
playbook is no longer idempotent. `shell` is only for when you genuinely need
pipes, redirection or globbing — otherwise `command` is safer.

---

## Finding the module in the exam

You will not remember every module. You do not need to. You need this reflex:

```bash
ansible-doc -l | grep -i <thing>          # find it
ansible-doc <module>                      # read the options
ansible-doc -s <module>                   # copy the skeleton
```

Practise it until it is faster than recalling from memory. It is allowed, it is
reliable, and it is the difference between a pass and a blank screen.

Related: [04-Labs-Ansible-Fundamentals](04-Labs-Ansible-Fundamentals.md) · [05-Labs-Automate-the-RHCSA-Set](05-Labs-Automate-the-RHCSA-Set.md)
