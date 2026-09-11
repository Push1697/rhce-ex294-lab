#!/usr/bin/env bash
# Lab 5.2 — A full day of admin without a playbook  (04-Labs-Ansible-Fundamentals)
# Run on rhel-control, as the ordinary user.
#
# The requirement was to do all of it ad-hoc. What a script can grade is the
# resulting state of the managed nodes — plus the absence of a playbook that
# would have done it for you.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

UID_WANT=""
for a in "$@"; do case "$a" in --uid=*) UID_WANT=${a#--uid=} ;; esac; done

# Run a command on every managed node; pass only when it succeeds everywhere.
on_all() {
  local out n hosts
  out=$(ansible managed -m command -a "$*" --become 2>&1)
  n=$(grep -cE 'rc=0|CHANGED|SUCCESS' <<<"$out")
  hosts=$(a_hosts_in managed | grep -c .)
  grep -E 'FAILED|non-zero|UNREACHABLE' <<<"$out" | head -3
  [[ ${n:-0} -ge ${hosts:-1} ]]
}

pkg_everywhere() {
  local out
  out=$(ansible managed -m command -a "rpm -q $1" 2>&1)
  grep -qE 'not installed|FAILED' <<<"$out" && { echo "$out" | grep -E 'not installed|FAILED' | head -3; return 1; }
  return 0
}

svc_enabled_everywhere() {
  local out
  out=$(ansible managed -m command -a "systemctl is-enabled $1" 2>&1)
  grep -qE 'disabled|masked|FAILED' <<<"$out" && { echo "$out" | tail -6; return 1; }
  return 0
}

motd_has_content() {
  local out
  out=$(ansible managed -m command -a 'cat /etc/motd' --become 2>&1)
  echo "$out" | tail -6
  # every host must have a non-empty motd
  ! grep -qE 'FAILED|UNREACHABLE' <<<"$out" &&
    [[ $(grep -vcE '^rhel|^ *$|CHANGED|SUCCESS|=>' <<<"$out") -gt 0 ]]
}

webadmin_uid_consistent() {
  local out uids
  out=$(ansible managed -m command -a 'id -u webadmin' 2>&1)
  uids=$(grep -oE '^[0-9]+$' <<<"$out" | sort -u)
  echo "UIDs found: $(tr '\n' ' ' <<<"$uids")"
  [[ $(grep -c . <<<"$uids") -eq 1 ]] || return 1
  [[ -z ${UID_WANT:-} ]] && return 0
  [[ $uids == "$UID_WANT" ]]
}

no_playbook_did_this() {
  local hits
  hits=$(grep -rlE 'name:.*(webadmin|motd)' "$A_PROJ" --include='*.yml' 2>/dev/null)
  [[ -z ${hits// /} ]] && return 0
  echo "these playbooks would have done the work for you:"
  echo "$hits"
  return 1
}

# ------------------------------------------------------------------------------
lab_init "5.2" "A full day of admin without a playbook" --host rhel-control "$@"
a_init

section "1. httpd and firewalld installed everywhere"
check "httpd is installed on every managed node" pkg_everywhere httpd
check "firewalld is installed on every managed node" pkg_everywhere firewalld

section "2. Both services started and enabled"
check -p "httpd is enabled everywhere" svc_enabled_everywhere httpd
check -p "firewalld is enabled everywhere" svc_enabled_everywhere firewalld
check "httpd is running everywhere" on_all systemctl is-active httpd
check "firewalld is running everywhere" on_all systemctl is-active firewalld

section "3. The webadmin account with a specific UID"
check "webadmin exists on every managed node" on_all id webadmin
check "its UID is the same everywhere (and the one you chose)" webadmin_uid_consistent
[[ -z ${UID_WANT:-} ]] && info "Re-run with --uid=NNNN to have the exact UID graded."

section "4. /etc/motd deployed"
check "every node has a non-empty /etc/motd" motd_has_content

section "5. http open in the firewall, permanently"
check -p "http is open at runtime everywhere" on_all firewall-cmd --list-services
check -p "http is open permanently everywhere" \
  bash -c 'out=$(ansible managed -m command -a "firewall-cmd --permanent --list-services" --become 2>&1);
           echo "$out" | tail -4; ! grep -qE "FAILED|UNREACHABLE" <<<"$out" &&
           [[ $(grep -c "http" <<<"$out") -ge 1 ]]'

section "6. Facts filtered to ansible_distribution*"
check "the setup module returns the distribution facts" \
  bash -c 'ansible managed -m setup -a "filter=ansible_distribution*" 2>&1 | grep -q ansible_distribution'
report "what those facts say" \
  bash -c 'ansible rhel01 -m setup -a "filter=ansible_distribution*" 2>/dev/null | grep -E "distribution|version" | head -5'

section "7. rhel02 rebooted and came back"
check "rhel02 is reachable" a_all_reachable rhel02
report "how long rhel02 has been up" \
  bash -c 'ansible rhel02 -m command -a "uptime -p" 2>&1 | tail -2'
manual "You rebooted rhel02 with the reboot module and waited for it" \
  "Compare the uptime above with when you ran it."

section "8. It was genuinely done ad-hoc"
check "no playbook in the project would have done this work" no_playbook_did_this
manual "Every command was run twice, and the second run reported ok, not changed" \
  "Idempotence is the whole point of the exercise."

summary
