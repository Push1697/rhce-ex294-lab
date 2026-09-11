#!/usr/bin/env bash
# Incident grading                                   (11-Incident-Drills)
# Run on rhel01, as root, when you believe the estate is restored.
#
#   sudo ./verify incident --blind    am I there yet? pass/fail only
#   sudo ./verify incident            what is still wrong
#
# It does three things the individual checkers do not:
#   - aggregates the whole-estate health sweeps into one verdict
#   - checks the clock against the work order's target
#   - checks you did not buy the fix with a security control, or leave the thing
#     that was undoing your repairs in place
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"

STATE=/var/tmp/rhce-verify
TICKET=$STATE/incident.json
KIT=$(readlink -f "$_D/..")

ticket() { [[ -s $TICKET ]] && base64 -d < "$TICKET" 2>/dev/null; }
field()  { ticket | awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print }'; }

# --- run another checker and report its tally as one result ------------------
sweep() {   # sweep <checker> [baseline field]
  # Graded against where the estate started, not against perfection. A lab that
  # has not reached the web labs yet has httpd uninstalled and fails three
  # checks on a completely clean box; requiring an outright pass made every
  # incident ungradeable. The work order breaks things on top of whatever was
  # already true, so that is what gets measured.
  local name=$1 key=${2:-} out rc tally now base
  out=$(bash "$_D/$name" --no-color --no-mutate 2>&1); rc=$?
  tally=$(grep -E '^ +[0-9]+ passed' <<<"$out" | head -1 | tr -s ' ')
  now=$(grep -Eo '[0-9]+ failed' <<<"$out" | head -1 | tr -dc '0-9')
  [[ -n ${key:-} ]] && base=$(field "$key")
  echo "${tally:-<no tally>}"

  if [[ -n ${base:-} ]]; then
    echo "this sweep had $base failing when the incident opened"
    if (( ${now:-0} <= base )); then
      (( ${now:-0} > 0 )) &&
        echo "what is left was already failing then — labs not yet done, not faults"
      return 0
    fi
    grep -A40 'Not yet met' <<<"$out" | sed -n '2,12p'
    return 1
  fi

  echo "(no baseline recorded, so this has to pass outright)"
  ((rc == 0)) || grep -A40 'Not yet met' <<<"$out" | sed -n '2,12p'
  return $rc
}

# --- the clock ----------------------------------------------------------------
within_target() {
  local opened sla mins
  opened=$(field opened); sla=$(field sla)
  [[ -n ${opened:-} && -n ${sla:-} ]] || { echo "no work order on this host"; return 2; }
  mins=$(( ($(date +%s) - opened) / 60 ))

  # One of the faults moves the clock. Until that is repaired, wall time on this
  # host is fiction, and reading an elapsed time off it would either flatter you
  # or condemn you by months. Say so instead of pronouncing on the target.
  if (( mins < 0 || mins > 1440 )); then
    echo "the clock on this host says $mins minute(s) have elapsed, which cannot be right"
    echo "fix the clock first — the elapsed time is unreadable until you do"
    return 2
  fi
  echo "$mins minute(s) elapsed against a $sla-minute target"
  ((mins <= sla))
}

# --- did you buy the fix with a security control? -----------------------------
selinux_never_disabled() {
  local ge cfg cl
  ge=$(getenforce 2>/dev/null)
  cfg=$(grep -E '^SELINUX=' /etc/selinux/config 2>/dev/null)
  cl=$(cat /proc/cmdline)
  echo "getenforce=$ge · $cfg"
  [[ $ge == Enforcing ]] || { echo "SELinux is not enforcing"; return 1; }
  grep -qE '^SELINUX=enforcing' <<<"$cfg" || { echo "the config file would not keep it enforcing"; return 1; }
  grep -qwE 'selinux=0|enforcing=0' <<<"$cl" && { echo "the kernel command line still disables it"; return 1; }
  return 0
}

no_permission_widening() {
  local bad=0 hits
  hits=$(find /etc /srv /web /var/www -xdev -maxdepth 3 -type d -perm -0002 ! -perm -1000 2>/dev/null | head -5)
  [[ -n ${hits// /} ]] && { echo "world-writable directories without the sticky bit:"; echo "$hits"; bad=1; }
  hits=$(find /etc -xdev -maxdepth 2 -type f -perm -0002 2>/dev/null | head -5)
  [[ -n ${hits// /} ]] && { echo "world-writable files under /etc:"; echo "$hits"; bad=1; }
  ((bad)) || echo "nothing was made world-writable to force it to work"
  return $bad
}

no_blanket_policy_module() {
  command -v semodule >/dev/null 2>&1 || return 2
  local sus
  sus=$(semodule -l 2>/dev/null | grep -Eiw 'mypol|my-httpd|local|localpol|allowme|fixit|httpd_local|sshd_local')
  [[ -z ${sus// /} ]] && { echo "no generated policy module was loaded"; return 0; }
  echo "locally built policy modules present:"; echo "$sus"
  return 1
}

sudo_still_works() {
  local u
  u=$(getent group wheel | cut -d: -f4 | cut -d, -f1)
  visudo -c >/dev/null 2>&1 || { echo "sudoers does not parse"; return 1; }
  grep -Eq '^[[:space:]]*%wheel' /etc/sudoers /etc/sudoers.d/* 2>/dev/null ||
    { echo "the wheel rule is gone"; return 1; }
  echo "sudoers parses and the wheel rule is intact"
  return 0
}

# --- was the thing that undid your repairs removed? ---------------------------
no_persistence_left() {
  local found=()
  systemctl list-unit-files 2>/dev/null | grep -q 'sysstat-collect-aux' && found+=("the systemd units")
  [[ -e /usr/local/sbin/sysstat-collect-aux ]] && found+=("/usr/local/sbin/sysstat-collect-aux")
  systemctl is-enabled sysstat-collect-aux.timer >/dev/null 2>&1 && found+=("the timer, still enabled")
  if ((${#found[@]})); then
    # ${found[*]} joins on the first character of IFS only, so ", " gave "a,b"
    echo "still present: $(printf '%s, ' "${found[@]}" | sed 's/, $//')"
    echo "a repair that lasts only until the next timer firing is not a repair"
    return 1
  fi
  echo "nothing is scheduled to undo your work"
  return 0
}

# Nothing else should be quietly re-breaking things either.
no_unexpected_timers() {
  local out
  out=$(systemctl list-timers --all --no-legend 2>/dev/null |
        awk '{print $NF}' | sed -E 's/[.](service|timer)$//' |
        grep -vE '^(logrotate|dnf-makecache|unbound-anchor|systemd-tmpfiles-clean|fstrim|mlocate-updatedb|raid-check|sysstat-collect|sysstat-summary|man-db-cache-update|NEXT|)$')
  # No apostrophe in the default: bash treats a single quote inside ${x:-...}
  # inside double quotes as an opening quote, and the file stops parsing.
  echo "${out:-<only the distribution timers>}"
  # informational: a lab timer of your own is fine, so this never fails
  return 0
}

# --- reboot proof -------------------------------------------------------------
rebooted_since_open() {
  # By boot id, not by clock. One of the faults moves the clock months, which
  # made a boot from *before* the incident opened compare as later than it and
  # pass this check while nothing had been rebooted at all.
  local was now
  was=$(field boot)
  now=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
  [[ -n ${was:-} && -n ${now:-} ]] || return 2
  echo "boot at open: ${was:0:8} · this boot: ${now:0:8}"
  [[ $was != "$now" ]]
}

# ------------------------------------------------------------------------------
lab_init "incident" "Incident resolution" --host rhel01 --root "$@"

if ! ticket >/dev/null 2>&1; then
  warn "no incident is open on this host" \
    "open one with: sudo $KIT/break/incident.sh open 2 --yes"
  info "Grading the estate anyway, as a plain health sweep."
else
  info "severity $(field level) · target $(field sla) min · $(field faults | wc -w) fault(s) staged"
fi

section "1. The estate is healthy"
check "the single-cause health sweep is back to where it started"   sweep breakfix-health.sh base_bf
check "the advanced health sweep is back to where it started"   sweep breakfix-advanced.sh base_adv

section "2. Inside the target time"
within_target; rc=$?
case $rc in
  0) pass "resolved inside the work order's target" ;;
  2) skipped "inside the target time" \
       "either there is no work order here, or the clock is still wrong" ;;
  *) fail "resolved inside the work order's target" \
       "over target — finish anyway, and record the real number" ;;
esac

section "3. You did not buy it with a security control"
check "SELinux was never left off, in any of the three places it can be" selinux_never_disabled
check "nothing was made world-writable to force it to work" no_permission_widening
no_blanket_policy_module; rc=$?
case $rc in
  0) pass "no generated SELinux policy module was loaded" ;;
  2) skipped "no generated policy module" "semodule is not installed" ;;
  *) fail "no generated SELinux policy module was loaded" \
       "audit2allow papers over a mislabelled file" ;;
esac
check "sudo still works for the group that should have it" sudo_still_works

section "4. Nothing is undoing your repairs"
check "the persistence mechanism is gone, not merely stopped" no_persistence_left
report "timers on this box that are not the distribution's" no_unexpected_timers

section "5. It survived a restart"
rebooted_since_open; rc=$?
case $rc in
  0) pass "this node has rebooted since the incident was opened" ;;
  2) skipped "rebooted since the incident opened" "no work order recorded a boot id" ;;
  *) fail "this node has rebooted since the incident was opened" \
       "several of these faults only reappear after a restart — reboot, then grade again" ;;
esac

section "6. The other node"
manual "rhel02 is healthy too" \
  "At severity 3 and above the fault may be there: sudo $KIT/verify breakfix on rhel02."
manual "You reached the service from the other node, not just from localhost" \
  "curl from rhel02, mount from rhel01 — localhost proves nothing about a firewall."

section "7. The write-up"
manual "You can name, for each report, what actually caused it" \
  "Then run: sudo $KIT/break/incident.sh reveal"
manual "You know which report misled you longest, and why" \
  "That is the entry worth putting in the drill log."

summary
