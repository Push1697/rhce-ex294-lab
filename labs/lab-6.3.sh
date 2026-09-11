#!/usr/bin/env bash
# Lab 6.3 — Labs 2.5 + 2.6 redone as storage.yml    (05-Labs-Automate-the-RHCSA-Set)
# Run on rhel-control, as the ordinary user.
#
# The hardest automation lab of the week. Snapshot the nodes before running
# anything here — a storage playbook mistake costs you the node.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=storage.yml

fstab_uses_uuid_on_nodes() {
  local out
  out=$(ansible managed -m shell -a "grep -E '(/data|/app|/applogs)' /etc/fstab" --become 2>&1)
  echo "$out" | grep -E '^(UUID|/dev|#)' | head -8
  # every lab mount line must start with UUID=
  local bad
  bad=$(grep -E '^\s*/dev/' <<<"$out")
  [[ -n ${bad// /} ]] && { echo "these entries use a device name instead of a UUID:"; echo "$bad"; return 1; }
  grep -q '^UUID=' <<<"$out"
}

mounts_present() {
  local out
  out=$(ansible managed -m command -a 'findmnt -no TARGET,SOURCE,FSTYPE /data /app /applogs' --become 2>&1)
  echo "$out" | grep -vE 'CHANGED|SUCCESS|=>' | head -10
  ! grep -qE 'FAILED|non-zero' <<<"$out"
}

uses_the_right_collections() {
  local bad=0
  grep -qE 'community\.general\.parted|parted:' "$PB" || { echo "no parted task"; bad=1; }
  grep -qE 'community\.general\.lvg|lvg:' "$PB" || { echo "no lvg task"; bad=1; }
  grep -qE 'community\.general\.lvol|lvol:' "$PB" || { echo "no lvol task"; bad=1; }
  grep -qE 'community\.general\.filesystem|filesystem:' "$PB" || { echo "no filesystem task"; bad=1; }
  grep -qE 'ansible\.posix\.mount|mount:' "$PB" || { echo "no mount task"; bad=1; }
  return $bad
}

resizefs_used() {
  grep -qE 'resizefs:[[:space:]]*(true|yes)' "$PB"
}

force_not_enabled() {
  local hits
  hits=$(grep -nE 'force:[[:space:]]*(true|yes)' "$PB")
  [[ -z ${hits// /} ]] && return 0
  echo "force: true on a storage module will reformat a filesystem without asking:"
  echo "$hits"
  return 1
}

check_mode_is_safe() {
  local out
  out=$(ansible-playbook --check "$PB" 2>&1)
  echo "$out" | tail -8
  ! grep -qE 'fatal:' <<<"$out"
}

# ------------------------------------------------------------------------------
lab_init "6.3" "Storage through Ansible" --host rhel-control "$@"
a_init

section "1. The playbook and the modules it uses"
check_file "$PB exists" "$A_PROJ/$PB"
check "it is valid YAML" a_yaml_ok "$PB"
check "syntax-check passes" ansible-playbook --syntax-check "$PB"
check "parted, lvg, lvol, filesystem and mount are all used" uses_the_right_collections
check "no parted/mkfs/lvcreate smuggled in via command or shell" \
  bash -c "! grep -qE '(mkfs|lvcreate|vgcreate|pvcreate|parted /dev)' $PB"
check "force: is not enabled on any destructive module" force_not_enabled
info "force: false is the default for a reason — it stops a reformat."

section "2. --check is safe to run"
check "ansible-playbook --check produces no fatal errors" check_mode_is_safe

section "3. It runs clean and is idempotent"
check "the playbook runs without failures" a_playbook_ok "$PB"
check "a second run with unchanged variables reports changed=0" a_idempotent "$PB"

section "4. The Lab 2.5 end state, graded on the node"
check "partitions, filesystem, swap and fstab match Lab 2.5" \
  a_remote_verify managed lab-2.5.sh

section "5. The Lab 2.6 end state, graded on the node"
check "LVM layout matches Lab 2.6" a_remote_verify managed lab-2.6.sh

section "6. fstab was written by the mount module, using UUIDs"
check "every lab mount in fstab uses UUID=" fstab_uses_uuid_on_nodes
check "/data, /app and /applogs are all mounted" mounts_present
check "the mount module used state: mounted (writes fstab AND mounts)" \
  bash -c "grep -A6 -E 'mount:' $PB | grep -qE 'state:[[:space:]]*mounted'"

section "7. Growing a filesystem by changing a variable"
check "resizefs: true is set so the filesystem follows the LV" resizefs_used
check "the LV size comes from a variable, not a literal" \
  bash -c "grep -A6 -E 'lvol' $PB | grep -qE 'size:[[:space:]]*\{\{'"
manual "Changing the size variable and re-running grew the filesystem safely" \
  "Set the variable to 9g, re-run, then run lab-2.6.sh's checks again."

section "8. Reboot survival"
check "the nodes are reachable" a_all_reachable managed
check "findmnt --verify passes on every node" \
  bash -c 'out=$(ansible managed -m command -a "findmnt --verify" --become 2>&1);
           echo "$out" | tail -6; ! grep -qE "FAILED|non-zero" <<<"$out"'
info "Reboot the nodes, then run this script again — it is the same standard as the exam."

summary
