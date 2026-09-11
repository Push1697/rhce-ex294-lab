#!/usr/bin/env bash
# Lab 5.5 — Loops and conditionals: loops.yml       (04-Labs-Ansible-Fundamentals)
# Run on rhel-control, as the ordinary user.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=loops.yml

# Five users must come from ONE task, not five near-identical ones.
one_user_task_only() {
  local n
  n=$(grep -cE '^[[:space:]]*-?[[:space:]]*(ansible\.builtin\.)?user:' "$PB")
  echo "user-module tasks in $PB: $n"
  [[ ${n:-0} -eq 1 ]]
}

one_package_task_only() {
  local n
  n=$(grep -cE '^[[:space:]]*-?[[:space:]]*(ansible\.builtin\.)?(dnf|yum|package):' "$PB")
  echo "package-module tasks in $PB: $n"
  [[ ${n:-0} -eq 1 ]]
}

loops_over_dicts() {
  grep -q 'loop:' "$PB" && grep -qE '\{\{[[:space:]]*item\.[a-z_]+' "$PB"
}

conditions_use_facts() {
  local bad
  bad=$(grep -nE 'when:.*inventory_hostname[[:space:]]*==' "$PB")
  [[ -z ${bad// /} ]] && return 0
  echo "conditions hardcode a hostname instead of using group membership or facts:"
  echo "$bad"
  return 1
}

five_users_exist() {
  local out n
  out=$(ansible managed -m command -a 'getent passwd' --become 2>&1)
  # count how many of the loop's users landed; the names come from the playbook
  local names
  names=$(grep -oE 'name:[[:space:]]*[a-z][a-z0-9_]*' "$PB" | awk '{print $2}' | sort -u)
  n=0
  for u in $names; do
    grep -q "^$u:" <<<"$out" && n=$((n + 1))
  done
  echo "users declared in the playbook that exist on the nodes: $n"
  [[ ${n:-0} -ge 5 ]]
}

distinct_uids() {
  local out uids
  out=$(ansible rhel01 -m command -a 'getent passwd' --become 2>&1)
  local names
  names=$(grep -oE 'name:[[:space:]]*[a-z][a-z0-9_]*' "$PB" | awk '{print $2}' | sort -u)
  uids=""
  for u in $names; do
    local id
    id=$(grep "^$u:" <<<"$out" | cut -d: -f3)
    [[ -n ${id:-} ]] && uids+="$id"$'\n'
  done
  echo "UIDs: $(tr '\n' ' ' <<<"$uids")"
  [[ $(grep -c . <<<"$uids") -eq $(sort -u <<<"$uids" | grep -c .) ]]
}

skips_cleanly_on_dev() {
  local out
  out=$(ansible-playbook "$PB" --limit dev 2>&1)
  echo "$out" | grep -E '^[^ ]+ +: +ok='
  grep -qE 'failed=[1-9]|fatal:' <<<"$out" && { echo "$out" | tail -8; return 1; }
  grep -q 'skipping:' <<<"$out"
}

# ------------------------------------------------------------------------------
lab_init "5.5" "Loops and conditionals" --host rhel-control "$@"
a_init

section "1. Five users in a single task"
check_file "$PB exists" "$A_PROJ/$PB"
check "it is valid YAML" a_yaml_ok "$PB"
check "syntax-check passes" ansible-playbook --syntax-check "$PB"
check "exactly one user task — not five copies" one_user_task_only
check "it loops over a list of dictionaries" loops_over_dicts
check "the loop sets uid, group and comment per item" \
  bash -c "grep -qE 'item\.(uid|group|comment)' $PB"

section "2. A package list in one task"
check "exactly one package task" one_package_task_only
check "it loops or takes a list" \
  bash -c "grep -A3 -E '(dnf|yum|package):' $PB | grep -qE 'loop:|name:[[:space:]]*\[|\{\{'"

section "3. Conditionals driven by group membership and facts"
check "no condition hardcodes a hostname" conditions_use_facts
check "at least one condition tests group membership" \
  bash -c "grep -qE \"when:.*groups\\[|in groups\" $PB"
check "a condition tests the RHEL major version numerically" \
  bash -c "grep -qE 'distribution_major_version.*\\|[[:space:]]*int' $PB"

section "4. Conditional file deployment"
check "a task uses a stat/register check before deploying" \
  bash -c "grep -qE '(ansible\.builtin\.)?stat:' $PB && grep -qE 'when:.*\.stat\.exists' $PB"

section "5. A task gated on a previous command's success"
check "a registered result gates a later task" \
  bash -c "grep -qE 'when:.*\.(rc|failed|changed|succeeded)' $PB"

section "6. Looping over a dictionary"
check "the playbook loops over a dict (dict2items or .key/.value)" \
  bash -c "grep -qE 'dict2items|item\.key|item\.value' $PB"

section "7. The result on the managed nodes"
check "the playbook runs without failures" a_playbook_ok "$PB"
check "a second run reports changed=0" a_idempotent "$PB"
check "all five users exist on the managed nodes" five_users_exist
check "each has its own distinct UID" distinct_uids
check "limiting to dev skips the web-only tasks instead of failing" skips_cleanly_on_dev
info "Read the recap for skipped= — a wrongly skipped task is a silent zero."

summary
