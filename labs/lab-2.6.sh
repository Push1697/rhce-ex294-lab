#!/usr/bin/env bash
# Lab 2.6 — LVM                                     (01-Labs-RHCSA-Foundation)
# Run on rhel01, as root. Uses the second blank lab disk (vdc on KVM,
# sdc on VirtualBox) — detected, not assumed.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

VG=vgdata
DISK=$(lab_disk 2)

lv_size_gib() { lvs --noheadings --units g -o lv_size "$VG/$1" 2>/dev/null | tr -d ' g'; }

pe_size_is_16m() {
  local pe
  pe=$(vgs --noheadings --units m -o vg_extent_size "$VG" 2>/dev/null | tr -d ' m')
  echo "extent size: ${pe:-?} MiB"
  approx "${pe:-0}" 16 0.5
}

vg_on_lab_disk() {
  local pvs
  pvs=$(vgs --noheadings -o pv_name "$VG" 2>/dev/null | tr -d ' ' | tr '\n' ' ')
  echo "physical volumes in $VG: ${pvs:-<none>}"
  echo "expected the second lab disk: $DISK"
  grep -q "$DISK" <<<"$pvs"
}

no_snapshot_left() {
  local snaps
  snaps=$(lvs --noheadings -o lv_name,origin "$VG" 2>/dev/null | awk 'NF == 2 { print $1 }')
  echo "${snaps:+snapshots still present: $snaps}"
  [[ -z ${snaps// /} ]]
}

fs_fills_lv() {   # the filesystem must have been grown, not just the LV
  local lv="$1" mnt="$2" lvb fsb
  lvb=$(lvs --noheadings --units b -o lv_size --nosuffix "$VG/$lv" 2>/dev/null | tr -d ' ')
  fsb=$(df -B1 --output=size "$mnt" 2>/dev/null | tail -1 | tr -d ' ')
  echo "LV is $lvb bytes, filesystem reports $fsb bytes"
  [[ -n ${lvb:-} && -n ${fsb:-} ]] &&
    awk -v l="$lvb" -v f="$fsb" 'BEGIN { exit !(f > l * 0.9) }'
}

# ------------------------------------------------------------------------------
lab_init "2.6" "LVM" --host rhel01 --root "$@"

if [[ -z ${DISK:-} ]]; then
  fail "a second blank lab disk is attached"     "only one non-root disk was found — the LVM lab needs two"
  summary; exit 1
fi
info "using lab disk: $DISK ($(lab_platform))"

section "1. The volume group"
check "$DISK is a physical volume" pvs "$DISK"
check "volume group $VG exists" vgs "$VG"
check "it is built on $DISK" vg_on_lab_disk
check "the extent size is 16 MiB" pe_size_is_16m
report "the current layout" bash -c 'pvs; vgs; lvs'

section "2. lvapp — XFS at /app, extended to 9 GB"
check "logical volume lvapp exists" lvs "$VG/lvapp"
check_sh "lvapp is about 9 GiB after the extension" "approx '$(lv_size_gib lvapp)' 9 0.4"
check_eq "it holds an XFS filesystem" "xfs" "$(mount_fstype /app)"
check "/app is mounted" findmnt /app
check_match "and it is the lvapp device that is mounted" 'lvapp' bash -c 'findmnt -no SOURCE /app'
check -p "/app has an entry in /etc/fstab" bash -c 'fstab_line /app | grep -q .'
check "the filesystem was grown to match the LV, not just the LV extended" \
  fs_fills_lv lvapp /app

section "3. lvlogs — ext4 at /applogs, reduced to 1 GB"
check "logical volume lvlogs exists" lvs "$VG/lvlogs"
check_sh "lvlogs is about 1 GiB after the reduction" "approx '$(lv_size_gib lvlogs)' 1 0.3"
check_eq "it holds an ext4 filesystem" "ext4" "$(mount_fstype /applogs)"
check "/applogs is still mounted after the shrink" findmnt /applogs
check -p "/applogs has an entry in /etc/fstab" bash -c 'fstab_line /applogs | grep -q .'
check "the ext4 filesystem itself was resized, not just the LV" \
  fs_fills_lv lvlogs /applogs

section "4. The snapshot was created and then removed"
check "no leftover snapshot volumes in $VG" no_snapshot_left
manual "You created a 500 MB snapshot of lvapp before removing it" \
  "Nothing left to grade — but you should be able to do it from memory."

section "5. Reboot safety"
check -p "findmnt --verify is happy with /etc/fstab" findmnt --verify
check "mount -a is silent (both mounts already correct)" \
  bash -c 'out=$(mount -a 2>&1); [[ -z ${out// /} ]]'

section "6. The thing you must be able to explain"
manual "You can explain why XFS can never be shrunk" \
  "If you cannot say it out loud in one sentence, revisit it now, not in Week 4."

summary
