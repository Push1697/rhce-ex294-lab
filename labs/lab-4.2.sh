#!/usr/bin/env bash
# Lab 4.2 — tuned, kernel and boot targets          (03-EX200-Exam-Prep)
# Run on rhel01, as root.
#
# Requirement 5 is "add a kernel command-line parameter persistently" without
# naming one, so pass yours in:  ./lab-4.2.sh --karg=quiet_loglevel=3
# Without it, the script reports what is on the command line and asks you.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

KARG=""
for a in "$@"; do
  case "$a" in --karg=*) KARG=${a#--karg=} ;; esac
done

default_is_not_newest() {
  local def newest
  def=$(grubby --default-kernel 2>/dev/null)
  newest=$(ls -1t /boot/vmlinuz-* 2>/dev/null | head -1)
  echo "default: ${def:-?}"
  echo "newest:  ${newest:-?}"
  [[ -n ${def:-} && -n ${newest:-} && $def != "$newest" ]]
}

karg_live_and_persistent() {
  local live persisted
  grep -qw -- "$KARG" /proc/cmdline || { echo "not on the running command line: $KARG"; return 1; }
  persisted=$(grubby --info=DEFAULT 2>/dev/null | grep '^args=')
  echo "$persisted"
  grep -q -- "$KARG" <<<"$persisted"
}

no_pending_one_shot_boot() {
  local next
  next=$(grub2-editenv list 2>/dev/null | sed -n 's/^next_entry=//p')
  echo "${next:+next_entry is still set to: $next}"
  [[ -z ${next// /} ]]
}

# ------------------------------------------------------------------------------
lab_init "4.2" "tuned, kernel and boot targets" --host rhel01 --root "$@"

section "1. The tuned profile"
if need_cmd "tuned checks" tuned-adm; then
  check "tuned is running" systemctl is-active --quiet tuned
  check -p "tuned is enabled at boot" systemctl is-enabled --quiet tuned
  active=$(tuned-adm active 2>/dev/null | sed 's/.*: //')
  info "active profile: ${active:-<none>}"
  check_eq -p "the active profile is virtual-guest" "virtual-guest" "$active"
  check_sh -p "the choice is recorded on disk, so it survives a reboot" \
    'grep -rqi "virtual-guest" /etc/tuned/ 2>/dev/null'
fi

section "2. tuned's own recommendation"
if command -v tuned-adm >/dev/null; then
  report "what tuned recommends for this machine" tuned-adm recommend
  manual "You can explain why tuned recommends that profile here" \
    "It reads virtualisation and role hints — say which ones."
fi

section "3. A one-time boot of a non-default kernel"
report "installed kernels" bash -c 'ls -1 /boot/vmlinuz-* 2>/dev/null'
if [[ $(ls -1 /boot/vmlinuz-* 2>/dev/null | wc -l) -lt 2 ]]; then
  skipped "one-time and permanent kernel selection" \
    "only one kernel is installed — install a second before doing this lab"
else
  check "no one-time boot entry is still pending" no_pending_one_shot_boot
  manual "You booted a non-default kernel exactly once, and it reverted" \
    "grub2-reboot leaves no trace afterwards — that is the point of the check above."

  section "4. A different kernel set as the permanent default"
  check -p "the default kernel is not simply the newest one" default_is_not_newest
  report "grubby's view" bash -c 'grubby --default-index; grubby --default-kernel'
fi

section "5. A persistent kernel command-line parameter"
if [[ -n ${KARG:-} ]]; then
  check -p "$KARG is live and persisted in the boot loader" karg_live_and_persistent
else
  report "the current kernel command line" cat /proc/cmdline
  report "what grubby has persisted for the default kernel" \
    bash -c 'grubby --info=DEFAULT 2>/dev/null | grep ^args='
  manual "The parameter you added appears in BOTH outputs above" \
    "Re-run with --karg=<your parameter> to have this graded automatically."
fi

section "6. Boot target restored to multi-user"
check_eq -p "default target is multi-user.target" "multi-user.target" "$(systemctl get-default)"
check "the system reached multi-user.target on this boot" \
  systemctl is-active --quiet multi-user.target
manual "You deliberately booted rescue.target and came back" \
  "Transient — but it must have been a real boot, not systemctl isolate."

summary
