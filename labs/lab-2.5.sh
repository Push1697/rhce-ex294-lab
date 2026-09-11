#!/usr/bin/env bash
# Lab 2.5 — Partitions, filesystems, swap, fstab    (01-Labs-RHCSA-Foundation)
# Run on rhel01, as root. Uses the first blank lab disk (vdb on KVM,
# sdb on VirtualBox) — detected, not assumed.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

DISK=$(lab_disk 1)
P1=${DISK}1
P2=${DISK}2

fstab_uses_uuid() {
  local line uuid
  line=$(fstab_line /data)
  [[ -n ${line:-} ]] || { echo "no /data entry in /etc/fstab"; return 1; }
  echo "$line"
  [[ $line == UUID=* ]] || { echo "the entry does not start with UUID="; return 1; }
  uuid=$(dev_uuid "$P1")
  [[ -n ${uuid:-} ]] || { echo "cannot read the UUID of $P1"; return 1; }
  grep -q "$uuid" <<<"$line"
}

data_is_about_4g() {
  local g
  g=$(df_gib /data)
  echo "/data is ${g:-?} GiB"
  approx "${g:-0}" 4 0.6
}

swap_priority_10() {
  local line
  line=$(swapon --show=NAME,TYPE,SIZE,PRIO --noheadings 2>/dev/null | grep "$P2")
  echo "${line:-<$P2 is not an active swap device>}"
  [[ -n ${line:-} ]] && [[ $(awk '{print $NF}' <<<"$line") == 10 ]]
}

swap_persistent() {
  local line
  line=$(awk '$1 !~ /^#/ && $3 == "swap" { print }' /etc/fstab)
  echo "${line:-<no swap entry in /etc/fstab>}"
  [[ -n ${line:-} ]] && grep -Eq 'pri=10' <<<"$line"
}

# The filesystem must have been grown, not just the partition.
fs_fills_partition() {
  local pb fb
  pb=$(lsblk -bno SIZE "$P1" 2>/dev/null | head -1)
  fb=$(df -B1 --output=size /data 2>/dev/null | tail -1 | tr -d ' ')
  echo "partition $pb bytes, filesystem $fb bytes"
  [[ -n ${pb:-} && -n ${fb:-} ]] && awk -v p="$pb" -v f="$fb" 'BEGIN { exit !(f > p * 0.9) }'
}

noexec_enforced() {
  local f=/data/verify-noexec-$$.sh rc=0
  printf '#!/bin/bash\necho hi\n' > "$f" 2>/dev/null || { echo "could not write to /data"; return 1; }
  chmod +x "$f"
  if "$f" >/dev/null 2>&1; then
    echo "a script under /data executed — noexec is not in force"
    rc=1
  else
    echo "execution was refused, as required"
  fi
  rm -f "$f"
  return $rc
}

# ------------------------------------------------------------------------------
lab_init "2.5" "Partitions, filesystems, swap, fstab" --host rhel01 --root "$@"

if [[ -z ${DISK:-} ]]; then
  fail "a blank lab disk is attached"     "no disk other than the root disk was found — check the lab VM has its extra disks"
  summary; exit 1
fi
info "using lab disk: $DISK ($(lab_platform))"

section "1. Partition layout on $DISK"
check_sh "$DISK exists" "[[ -b $DISK ]]"
check_sh "$P1 exists" "[[ -b $P1 ]]"
check_sh "$P2 exists" "[[ -b $P2 ]]"
info "sizes: $P1 = $(size_gib "$P1") GiB, $P2 = $(size_gib "$P2") GiB"
check_sh "$P1 is around 4 GiB after the grow" "approx '$(size_gib "$P1")' 4 0.6"
check_sh "$P2 is around 1 GiB" "approx '$(size_gib "$P2")' 1 0.3"
check "free space was left on the disk" \
  bash -c "parted -s $DISK print free 2>/dev/null | grep -qi 'free space'"

section "2. XFS on the first partition, labelled DATA"
check_eq "$P1 holds an XFS filesystem" "xfs" "$(lsblk -no FSTYPE "$P1" 2>/dev/null | head -1)"
check_eq "its label is DATA" "DATA" "$(lsblk -no LABEL "$P1" 2>/dev/null | head -1)"

section "3. /data is mounted by UUID, persistently"
check "/data is mounted right now" findmnt /data
check_eq "and it is $P1 that is mounted there" "$P1" "$(mount_src /data)"
check -p "the fstab entry uses UUID=, not $P1" fstab_uses_uuid
check -p "findmnt --verify is happy with /etc/fstab" findmnt --verify

section "4. Mount options: noexec and nodev"
check_match -p "noexec is in the live mount options" '(^|,)noexec(,|$)' bash -c 'findmnt -no OPTIONS /data'
check_match -p "nodev is in the live mount options" '(^|,)nodev(,|$)' bash -c 'findmnt -no OPTIONS /data'
check_match -p "both appear in the fstab entry" 'noexec' bash -c 'awk "\$2 == \"/data\"" /etc/fstab'
if mutating "a script under /data genuinely cannot execute"; then
  check "a script under /data genuinely cannot execute" noexec_enforced
fi

section "5. Swap on the second partition, priority 10"
check_eq "$P2 is formatted as swap" "swap" "$(lsblk -no FSTYPE "$P2" 2>/dev/null | head -1)"
check "it is active with priority 10" swap_priority_10
check -p "it is activated by /etc/fstab with pri=10" swap_persistent
report "all swap in use" bash -c 'swapon --show'

section "6. The filesystem was grown after the partition"
check "/data reports about 4 GiB" data_is_about_4g
check "the filesystem fills the partition (no wasted space)" \
  fs_fills_partition

summary
