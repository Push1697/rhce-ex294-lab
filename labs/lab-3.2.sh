#!/usr/bin/env bash
# Lab 3.2 — Reading SELinux denials                 (02-Labs-Security-and-Breakfix)
# Run on rhel01, as root, AFTER you have diagnosed and repaired the fault.
#
# This lab grades the *manner* of the fix, not just the outcome: SELinux must
# still be enforcing, and the repair must not be a blanket audit2allow module.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

BASELINE=/var/tmp/rhce-verify/semodule.baseline

# Modules named like an audit2allow dump are the giveaway.
no_audit2allow_module() {
  local suspects
  suspects=$(semodule -l 2>/dev/null |
             grep -Eiw 'mypol|my-httpd|local|localpol|allowme|fixit|httpd_local|sshd_local')
  [[ -z ${suspects// /} ]] && return 0
  echo "locally built policy modules present:"
  echo "$suspects"
  return 1
}

no_new_modules_since_baseline() {
  [[ -f $BASELINE ]] || { echo "no baseline recorded — see --snapshot below"; return 2; }
  local added
  added=$(comm -13 <(sort "$BASELINE") <(semodule -l 2>/dev/null | sort))
  [[ -z ${added// /} ]] && return 0
  echo "policy modules added since the baseline:"
  echo "$added"
  return 1
}

services_healthy() {
  local bad=0 u
  for u in httpd sshd; do
    systemctl list-unit-files "$u.service" >/dev/null 2>&1 || continue
    rpm -q "$u" >/dev/null 2>&1 || continue
    systemctl is-active --quiet "$u" || { echo "$u is not running"; bad=1; }
  done
  return $bad
}

# ------------------------------------------------------------------------------
# ./lab-3.2.sh --snapshot   records the clean list of policy modules, so a later
# run can tell whether you papered over the fault with audit2allow.
if [[ ${1:-} == --snapshot ]]; then
  mkdir -p "$(dirname "$BASELINE")"
  semodule -l > "$BASELINE" 2>/dev/null &&
    echo "Baseline recorded: $(wc -l < "$BASELINE") policy modules in $BASELINE" ||
    { echo "semodule -l failed — is policycoreutils installed?" >&2; exit 1; }
  exit 0
fi

lab_init "3.2" "Reading SELinux denials" --host rhel01 --root "$@"

section "1. SELinux was never disabled to make it work"
check_eq "getenforce still reports Enforcing" "Enforcing" "$(getenforce 2>/dev/null)"
check_match -p "/etc/selinux/config still says enforcing" '^SELINUX=enforcing' \
  grep '^SELINUX=' /etc/selinux/config
check "no permissive domains were added" \
  bash -c 'out=$(semanage permissive -l 2>/dev/null | grep -c "^[a-z_]*_t$"); [[ ${out:-0} -eq 0 ]]'

section "2. The fix was minimal, not a generated policy module"
if need_cmd "policy module checks" semodule; then
  check "no audit2allow-style module is loaded" no_audit2allow_module
  no_new_modules_since_baseline; rc=$?
  case $rc in
    0) pass "no policy modules added since the recorded baseline" ;;
    2) skipped "policy modules unchanged since baseline" \
         "run './lab-3.2.sh --snapshot' on a clean box first" ;;
    *) fail "no policy modules added since the recorded baseline" \
         "a module was loaded — was semanage fcontext the right answer instead?" ;;
  esac
fi

section "3. The broken service actually works again"
check "httpd and sshd are running" services_healthy
check "the audit log has no fresh denials" \
  bash -c 'n=$(ausearch -m AVC -ts recent 2>/dev/null | grep -c denied); [[ ${n:-0} -eq 0 ]]'
if [[ -d /web ]] && command -v semanage >/dev/null; then
  check "a dry-run relabel of /web changes nothing" \
    bash -c 'out=$(restorecon -Rvn /web 2>&1); [[ -z ${out// /} ]]'
fi

section "4. Your reasoning"
manual "You wrote down which process, which target and which permission was denied" \
  "Before applying the fix, not after. That habit is what the exam rewards."
manual "You can justify why the fix was a context / boolean / port change" \
  "If the honest answer is 'audit2allow suggested it', redo this drill."
report "denials recorded today, for review" \
  bash -c 'ausearch -m AVC -ts today 2>/dev/null | grep denied | tail -5'

summary
