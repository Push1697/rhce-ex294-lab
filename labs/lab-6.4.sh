#!/usr/bin/env bash
# Lab 6.4 — Labs 2.4 + 3.1–3.3 as security.yml      (05-Labs-Automate-the-RHCSA-Set)
# Run on rhel-control, as the ordinary user.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=security.yml

on_nodes() {   # run a command on all managed nodes, show the tail, pass if clean
  local out
  out=$(ansible managed -m shell -a "$*" --become 2>&1)
  echo "$out" | grep -vE 'CHANGED|SUCCESS|=>|^\s*$' | head -8
  ! grep -qE 'FAILED|UNREACHABLE|non-zero' <<<"$out"
}

relabel_is_noop_everywhere() {
  local out
  out=$(ansible managed -m command -a 'restorecon -Rvn /web' --become 2>&1)
  # any "Relabeled" line means the policy is wrong somewhere
  local rel
  rel=$(grep -i 'relabel' <<<"$out")
  [[ -z ${rel// /} ]] && { echo "no relabelling needed on any node"; return 0; }
  echo "$rel" | head -5
  return 1
}

booleans_persistent() {
  local out
  out=$(ansible managed -m shell -a "semanage boolean -l | grep httpd_can_network_connect" --become 2>&1)
  echo "$out" | grep httpd | head -4
  # the persisted column must also read on
  [[ $(grep -c 'on.*on' <<<"$out") -ge 1 ]]
}

firewall_runtime_matches_permanent() {
  local out
  out=$(ansible managed -m shell \
        -a 'diff <(firewall-cmd --list-all) <(firewall-cmd --permanent --list-all) && echo IDENTICAL' \
        --become 2>&1)
  echo "$out" | tail -8
  [[ $(grep -c IDENTICAL <<<"$out") -ge 1 ]] && ! grep -qE 'FAILED|non-zero' <<<"$out"
}

# ------------------------------------------------------------------------------
lab_init "6.4" "Networking, firewall and SELinux through Ansible" --host rhel-control "$@"
a_init

section "1. The playbook and its modules"
check_file "$PB exists" "$A_PROJ/$PB"
check "it is valid YAML" a_yaml_ok "$PB"
check "syntax-check passes" ansible-playbook --syntax-check "$PB"
check "hostname is set with the hostname module" bash -c "grep -qE '(ansible\.builtin\.)?hostname:' $PB"
check "the static IP is managed with the nmcli module" bash -c "grep -q 'nmcli' $PB"
check "SELinux state is managed with the selinux module" \
  bash -c "grep -qE 'ansible\.posix\.selinux|^\s*-?\s*selinux:' $PB"
check "file contexts are managed with sefcontext" bash -c "grep -q 'sefcontext' $PB"
check "booleans are managed with seboolean" bash -c "grep -q 'seboolean' $PB"
check "ports are managed with seport" bash -c "grep -q 'seport' $PB"
check "the firewall is managed with the firewalld module" bash -c "grep -q 'firewalld' $PB"
check "no semanage/firewall-cmd smuggled in via shell" \
  bash -c "! grep -qE '(semanage |firewall-cmd |setsebool )' $PB"

section "2. It runs clean and is idempotent"
check "the playbook runs without failures" a_playbook_ok "$PB"
check "a second run reports changed=0" a_idempotent "$PB"
info "seboolean and firewalld tasks that report changed every run are the usual culprits."

section "3. SELinux is enforcing and persistently so"
check "getenforce says Enforcing on every node" \
  bash -c 'out=$(ansible managed -m command -a getenforce 2>&1); echo "$out" | tail -4;
           ! grep -qiE "permissive|disabled" <<<"$out"'
check "the config file agrees on every node" \
  bash -c 'out=$(ansible managed -m shell -a "grep ^SELINUX= /etc/selinux/config" --become 2>&1);
           echo "$out" | tail -4; ! grep -qE "permissive|disabled" <<<"$out"'

section "4. The /web file context is applied and relabelled"
check "an fcontext rule exists for /web on the nodes" \
  bash -c 'out=$(ansible managed -m shell -a "semanage fcontext -l | grep \"^/web\"" --become 2>&1);
           echo "$out" | tail -4; grep -q httpd_sys_content_t <<<"$out"'
check "restorecon -Rvn /web is a no-op on every node" relabel_is_noop_everywhere
check "the playbook triggers a relabel after setting the context" \
  bash -c "grep -qE 'restorecon|setype|state:[[:space:]]*present' $PB"

section "5. httpd_can_network_connect on, persistently"
check "the boolean is on and persisted on every node" booleans_persistent
check "the playbook sets persistent: true (or equivalent)" \
  bash -c "grep -A4 seboolean $PB | grep -qE 'persistent:[[:space:]]*(true|yes)'"
info "A boolean without persistence disappears on reboot — a zero-mark answer."

section "6. Port 2222 added to ssh_port_t"
check "2222 is labelled ssh_port_t on every node" \
  bash -c 'out=$(ansible managed -m shell -a "semanage port -l | grep ^ssh_port_t" --become 2>&1);
           echo "$out" | tail -4; grep -q 2222 <<<"$out"'

section "7. firewalld zones, services, ports and the rich rule"
check "the rich rule from Lab 3.3 is present" \
  bash -c 'out=$(ansible managed -m shell -a "firewall-cmd --list-rich-rules" --become 2>&1);
           echo "$out" | tail -6; grep -q "$(lab_net).99" <<<"$out"'
check "8080/tcp is open" \
  bash -c 'out=$(ansible managed -m shell -a "firewall-cmd --list-ports" --become 2>&1);
           echo "$out" | tail -4; grep -q 8080 <<<"$out"'
check "runtime and permanent configurations are identical on every node" \
  firewall_runtime_matches_permanent
check "the playbook sets permanent: true on firewalld tasks" \
  bash -c "grep -A5 firewalld $PB | grep -qE 'permanent:[[:space:]]*(true|yes)'"
check "and immediate: true, so the change also applies now" \
  bash -c "grep -A5 firewalld $PB | grep -qE 'immediate:[[:space:]]*(true|yes)'"

section "8. The Lab 3.1 and 3.3 end states, graded on the node"
check "SELinux state matches Lab 3.1" a_remote_verify managed lab-3.1.sh
check "firewall state matches Lab 3.3" a_remote_verify managed lab-3.3.sh

section "9. Hostnames and addressing"
check "each node reports the FQDN the playbook set" \
  bash -c 'out=$(ansible managed -m command -a "hostnamectl --static" 2>&1);
           echo "$out" | tail -4; grep -qE "lab\.local" <<<"$out"'
check "the nodes are still reachable after the network changes" a_all_reachable managed
info "A network playbook that cuts you off is the one mistake that needs console access."

summary
