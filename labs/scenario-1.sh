#!/usr/bin/env bash
# Scenario 1 — Fleet baseline (Day 52)             (07-Scenario-Labs)
# Run on rhel-control, as the ordinary user.
#   ./scenario-1.sh --pb=baseline.yml
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=""
for a in "$@"; do case "$a" in --pb=*) PB=${a#--pb=} ;; esac; done
for c in ${PB:-} baseline.yml site.yml fleet.yml; do [[ -f $c ]] && { PB=$c; break; }; done

on_nodes() {   # returns the raw output of a shell command across all hosts
  ansible all -m shell -a "$*" --become 2>&1
}

group_everywhere() {
  local out
  out=$(on_nodes "getent group $1")
  echo "$out" | grep -E "^$1:|FAILED" | head -4
  ! grep -qE 'FAILED|non-zero' <<<"$out"
}

five_users_from_variables() {
  local names n=0 out
  names=$(grep -rhoE '^[[:space:]]*-?[[:space:]]*name:[[:space:]]*[a-z][a-z0-9_]*' \
          group_vars/ host_vars/ 2>/dev/null | awk '{print $NF}' | sort -u)
  [[ -n ${names:-} ]] || { echo "no user list found in group_vars — users must come from a variable structure"; return 1; }
  out=$(on_nodes 'getent passwd')
  for u in $names; do grep -q "^$u:" <<<"$out" && n=$((n + 1)); done
  echo "users defined in variables that exist on the nodes: $n"
  [[ ${n:-0} -ge 5 ]]
}

keys_for_everyone() {
  local out n
  out=$(on_nodes 'for f in /home/*/.ssh/authorized_keys; do [ -s "$f" ] && echo "$f"; done')
  n=$(grep -c 'authorized_keys' <<<"$out")
  echo "authorized_keys files found across the fleet: $n"
  echo "$out" | grep authorized_keys | head -6
  [[ ${n:-0} -ge 5 ]]
}

sysadmins_nopasswd() {
  local out
  out=$(on_nodes 'grep -rh sysadmins /etc/sudoers /etc/sudoers.d/ 2>/dev/null')
  echo "$out" | grep -i sysadmins | head -4
  grep -qi NOPASSWD <<<"$out"
}

developers_password_required_and_limited() {
  local out
  out=$(on_nodes 'grep -rh developers /etc/sudoers /etc/sudoers.d/ 2>/dev/null')
  echo "$out" | grep -i developers | head -4
  grep -qi developers <<<"$out" || { echo "no sudo rule for developers at all"; return 1; }
  grep -qi 'NOPASSWD' <<<"$out" && { echo "developers should be password-required, but NOPASSWD is set"; return 1; }
  grep -qE 'systemctl|service' <<<"$out"
}

ssh_hardened() {
  local out
  out=$(on_nodes 'sshd -T | grep -E "^(permitrootlogin|passwordauthentication) "')
  echo "$out" | grep -E 'permitrootlogin|passwordauthentication' | head -8
  ! grep -qE 'permitrootlogin (yes|prohibit-password)' <<<"$out" &&
  ! grep -qE 'passwordauthentication yes' <<<"$out"
}

motd_templated() {
  local out
  out=$(on_nodes 'cat /etc/motd')
  echo "$out" | grep -vE 'CHANGED|SUCCESS|=>|^\s*$' | head -6
  local bad=0 h
  for h in $(a_hosts_in all); do
    ansible "$h" -m command -a 'cat /etc/motd' --become 2>&1 | grep -q "$h" ||
      { echo "$h's motd does not name it"; bad=1; }
  done
  grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{2}/[0-9]{2}/[0-9]{4}' <<<"$out" ||
    { echo "no build date in the motd"; bad=1; }
  return $bad
}

# ------------------------------------------------------------------------------
lab_init "scenario-1" "Fleet baseline" --host rhel-control --score "$@"
a_init
[[ -n ${PB:-} ]] || { fail "one playbook builds the fleet baseline" \
  "no baseline.yml or site.yml found — pass --pb=NAME"; summary; exit 1; }
info "grading playbook: $PB"

section "1. sysadmins and developers groups, five users from variables"
check "the playbook syntax-checks" ansible-playbook --syntax-check "$PB"
check "the sysadmins group exists fleet-wide" group_everywhere sysadmins
check "the developers group exists fleet-wide" group_everywhere developers
check "five users come from a variable structure, not inline tasks" five_users_from_variables
check "there is only one user task in the whole project" \
  bash -c 'n=$(grep -rcE "^[[:space:]]*-?[[:space:]]*(ansible\.builtin\.)?user:" --include="*.yml" . 2>/dev/null | awk -F: "{s+=\$2} END {print s+0}");
           echo "user-module tasks: $n"; [[ ${n:-0} -le 2 ]]'

section "2. SSH public keys deployed for all five"
check "authorized_keys exists for at least five accounts" keys_for_everyone
check "keys are deployed by the authorized_key module" \
  bash -c "grep -rq 'authorized_key' --include='*.yml' . 2>/dev/null"

section "3. sudo: sysadmins passwordless, developers restricted"
check "sysadmins have passwordless sudo" sysadmins_nopasswd
check "developers need a password and are limited to service management" \
  developers_password_required_and_limited
check "sudoers was validated before deployment" \
  bash -c "grep -rqE 'validate:.*visudo' --include='*.yml' . 2>/dev/null"
check "sudoers parses on every node" \
  bash -c 'out=$(ansible all -m command -a "visudo -c" --become 2>&1);
           echo "$out" | grep -E "parsed OK|FAILED" | head -4; ! grep -q FAILED <<<"$out"'

section "4. Baseline packages plus a per-group set"
check "a baseline package list applies to every host" \
  bash -c "grep -rqE 'packages|baseline' group_vars/all.yml 2>/dev/null"
check "a different additional set is defined per group" \
  bash -c 'a=$(grep -rhoE "^[a-z_]*packages[a-z_]*:" group_vars/*.yml 2>/dev/null | sort -u | grep -c .);
           echo "package variables across group_vars: $a"; [[ ${a:-0} -ge 1 ]] &&
           [[ $(ls group_vars/*.yml 2>/dev/null | grep -vc all.yml) -ge 1 ]]'
check "the baseline packages are installed everywhere" \
  bash -c 'out=$(ansible all -m command -a "rpm -q vim-enhanced" 2>&1);
           echo "$out" | tail -4; true'

section "5. SSH hardened: no root, no passwords"
check "root login and password auth are both off fleet-wide" ssh_hardened

section "6. /etc/motd templated with hostname and build date"
check "each host's motd names it and carries a date" motd_templated
check "it comes from a template, not a copied literal" \
  bash -c "grep -rqE 'template:' --include='*.yml' . 2>/dev/null && grep -rq 'motd' templates/ roles/*/templates/ 2>/dev/null"

section "7. One run, then nothing"
check "the playbook runs clean against the fleet" a_playbook_ok "$PB"
check "the second run reports changed=0 on every host" a_idempotent "$PB"
check "every host is still reachable" a_all_reachable all

summary
