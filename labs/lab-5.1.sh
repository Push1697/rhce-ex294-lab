#!/usr/bin/env bash
# Lab 5.1 — Make the control node work              (04-Labs-Ansible-Fundamentals)
# Run on rhel-control, as the ordinary user, from anywhere.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

group_tree_ok() {
  local g out bad=0
  out=$(a_groups)
  echo "$out"
  for g in web db prod dev managed; do
    grep -qE "@$g:" <<<"$out" || { echo "group '$g' is missing"; bad=1; }
  done
  return $bad
}

managed_is_a_parent() {
  local out
  out=$(a_groups)
  # web and db must appear nested under managed, not only at the top level
  awk '/@managed:/ { f = 1; next } /^  @/ && f { print; if ($0 ~ /@(web|db):/) n++ }
       /^@/ && !/@managed:/ { f = 0 } END { exit !(n >= 2) }' <<<"$out"
}

# ------------------------------------------------------------------------------
lab_init "5.1" "Make the control node work" --host rhel-control "$@"
a_init

section "1. Ansible reads YOUR ansible.cfg"
check_file "$A_PROJ/ansible.cfg exists" "$A_PROJ/ansible.cfg"
check "ansible --version reports the project's config file" a_cfg_is_mine
check "the project directory is not world-writable (or the cfg is ignored)" \
  a_dir_not_world_writable
info "A world-writable directory makes Ansible skip your ansible.cfg silently."
report "the settings actually in force" \
  bash -c 'ansible-config dump --only-changed 2>/dev/null | head -12'

section "2. The inventory and its group tree"
check "an inventory is configured and readable" bash -c 'ansible-inventory --list >/dev/null 2>&1'
check "groups web, db, prod, dev and managed all exist" group_tree_ok
check "web contains rhel01" a_group_has web rhel01
check "db contains rhel02" a_group_has db rhel02
check "prod contains rhel01" a_group_has prod rhel01
check "dev contains rhel02" a_group_has dev rhel02
check "managed is a parent of web and db" managed_is_a_parent
check_eq "managed resolves to two hosts" 2 "$(a_hosts_in managed | grep -c .)"

section "3. Passwordless SSH and privilege escalation"
check "every host in managed answers a ping" a_all_reachable managed
check "become works without a password prompt" a_become_works managed
report "who Ansible becomes" bash -c 'ansible managed -m command -a id --become 2>&1 | head -6'

section "4. Group membership without reading the file"
check "ansible-inventory --graph shows the tree" bash -c 'ansible-inventory --graph >/dev/null'
check "ansible-inventory --host rhel01 returns its variables" \
  bash -c 'ansible-inventory --host rhel01 >/dev/null 2>&1'
report "rhel01's inventory view" bash -c 'ansible-inventory --host rhel01 2>/dev/null | head -12'

summary
