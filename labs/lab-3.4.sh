#!/usr/bin/env bash
# Lab 3.4 — The four boot failures                  (02-Labs-Security-and-Breakfix)
# Run on rhel01, as root, after recovering the box.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

every_fstab_uuid_resolves() {
  local u bad=0
  while read -r u; do
    [[ -n ${u// /} ]] || continue
    blkid -U "$u" >/dev/null 2>&1 || { echo "no device has UUID $u"; bad=1; }
  done < <(awk '$1 ~ /^UUID=/ && $1 !~ /^#/ { sub(/^UUID=/, "", $1); print $1 }' /etc/fstab)
  return $bad
}

mount_a_is_silent() {
  local out
  out=$(mount -a 2>&1)
  [[ -z ${out//[[:space:]]/} ]] && return 0
  echo "$out"
  return 1
}

grub_config_present() {
  if [[ -d /sys/firmware/efi ]]; then
    echo "this machine booted UEFI"
    ls /boot/efi/EFI/*/grub.cfg >/dev/null 2>&1 || ls /boot/grub2/grub.cfg >/dev/null 2>&1
  else
    echo "this machine booted BIOS"
    [[ -f /boot/grub2/grub.cfg ]]
  fi
}

grub_config_is_fresh() {
  local cfg mt kt
  cfg=$( { ls /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null; } | head -1)
  [[ -n ${cfg:-} ]] || return 1
  mt=$(stat -c %Y "$cfg")
  kt=$(stat -c %Y "$(ls -1t /boot/vmlinuz-* 2>/dev/null | head -1)" 2>/dev/null || echo 0)
  echo "grub.cfg written $(date -d "@$mt" '+%F %T'), newest kernel $(date -d "@$kt" '+%F %T')"
  ((mt >= kt))
}

no_pending_relabel() {
  [[ ! -f /.autorelabel ]]
}

contexts_are_sane() {
  local out
  out=$(restorecon -Rvn /etc 2>&1 | head -5)
  [[ -z ${out//[[:space:]]/} ]] && return 0
  echo "files under /etc are mislabelled:"
  echo "$out"
  return 1
}

# ------------------------------------------------------------------------------
lab_init "3.4" "The four boot failures" --host rhel01 --root "$@"

section "1. Root password reset from GRUB"
manual "You reset the root password from the GRUB prompt, with no prior access" \
  "Nothing on the box records this. If you needed the hint, do it again."
check "no relabel is still pending from /.autorelabel" no_pending_relabel
check "SELinux labels under /etc are correct after the reset" contexts_are_sane
manual "You can explain why /.autorelabel matters after a password reset" \
  "One sentence. If you cannot, this drill has not landed."

section "2. Recovery from a broken /etc/fstab"
check -p "findmnt --verify passes" findmnt --verify
check -p "every UUID= in /etc/fstab resolves to a real device" every_fstab_uuid_resolves
check "mount -a is completely silent" mount_a_is_silent
check "the machine is in a normal running state, not emergency mode" \
  bash -c '[[ $(systemctl is-system-running 2>/dev/null) =~ ^(running|degraded)$ ]]'
report "systemd's own verdict on this boot" bash -c 'systemctl is-system-running; systemctl --failed --no-legend'

section "3. Default target restored to multi-user"
check_eq -p "default target is multi-user.target" "multi-user.target" "$(systemctl get-default)"
check "the current boot actually reached multi-user.target" \
  systemctl is-active --quiet multi-user.target

section "4. GRUB configuration regenerated"
check "grub.cfg exists at the right path for this boot mode" grub_config_present
check "it is at least as new as the newest installed kernel" grub_config_is_fresh
check "the running kernel has a boot entry" \
  bash -c 'grubby --info=ALL 2>/dev/null | grep -q "$(uname -r)"'
report "installed kernels and the default" \
  bash -c 'grubby --default-kernel 2>/dev/null; ls -1 /boot/vmlinuz-* 2>/dev/null'

section "5. The habit this week is supposed to build"
check "findmnt --verify runs clean — do this before every reboot from now on" \
  findmnt --verify
info "The drill is: change fstab, run findmnt --verify, then reboot. Never the reverse."

summary
