#!/usr/bin/env bash
# Lab 6.5 — Ten servers, zero SSH sessions          (05-Labs-Automate-the-RHCSA-Set)
# Run on rhel-control, as the ordinary user.
#
#   ./lab-6.5.sh                 grade site.yml
#   ./lab-6.5.sh --sabotage      additionally break a host and prove the
#                                verify stage fails loudly (needs break.sh
#                                already on the target as /root/break.sh)
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=site.yml
SABOTAGE=0
for a in "$@"; do
  case "$a" in
    --sabotage) SABOTAGE=1 ;;
    --pb=*)     PB=${a#--pb=} ;;
  esac
done

host_count() { a_hosts_in all | grep -c .; }

no_hardcoded_hosts() {
  local hits
  hits=$(grep -rnE 'inventory_hostname[[:space:]]*==[[:space:]]*["'"'"']rhel' \
         "$PB" roles/ group_vars/ 2>/dev/null)
  [[ -z ${hits// /} ]] && return 0
  echo "per-host behaviour is hardcoded instead of coming from variables:"
  echo "$hits" | head -6
  return 1
}

per_host_values_from_facts() {
  grep -rqE 'ansible_facts|ansible_default_ipv4|inventory_hostname|hostvars' "$PB" roles/ templates/ 2>/dev/null
}

verify_stage_exists() {
  local out
  out=$(ansible-playbook "$PB" --list-tags 2>&1)
  echo "$out" | grep -i 'task tags' | head -3
  grep -qi 'verify' <<<"$out"
}

verification_is_real() {
  # a debug message saying "done" is not verification
  local real
  real=$(grep -rlE '(ansible\.builtin\.)?(assert|uri|wait_for):' "$PB" roles/ 2>/dev/null)
  [[ -n ${real// /} ]] || { echo "no assert, uri or wait_for anywhere — nothing is actually verified"; return 1; }
  echo "verification modules found in: $(tr '\n' ' ' <<<"$real")"
  grep -rqE 'failed_when:|assert:' "$PB" roles/ 2>/dev/null
}

all_web_serve() {
  local h bad=0 out
  for h in $(a_hosts_in web); do
    out=$(ansible "$h" -m uri -a "url=http://$h/ status_code=200" 2>&1)
    grep -qE 'SUCCESS|status.*200' <<<"$out" || { echo "$h did not answer 200"; bad=1; }
  done
  return $bad
}

sabotage_then_verify_must_fail() {
  local h out
  h=$(a_hosts_in web | head -1)
  echo "breaking the firewall on $h"
  out=$(ansible "$h" -m command -a '/root/break.sh firewall' --become 2>&1)
  grep -qE 'No such file|FAILED' <<<"$out" && {
    echo "break.sh is not at /root/break.sh on $h — copy it there first"; return 2; }
  out=$(ansible-playbook "$PB" --tags verify 2>&1)
  echo "$out" | tail -10
  if grep -qE 'failed=[1-9]|fatal:' <<<"$out"; then
    echo "the verify stage failed loudly, as it must"
    return 0
  fi
  echo "the verify stage passed on a sabotaged host — it is not verifying anything"
  return 1
}

# ------------------------------------------------------------------------------
lab_init "6.5" "Ten servers, zero SSH sessions" --host rhel-control "$@"
a_init
info "hosts in the inventory: $(host_count)"

section "1. One playbook runs the whole pipeline"
check_file "$PB exists" "$A_PROJ/$PB"
check "it is valid YAML" a_yaml_ok "$PB"
check "syntax-check passes" ansible-playbook --syntax-check "$PB"
report "the stages it will run" bash -c "ansible-playbook $PB --list-tasks 2>/dev/null | head -25"

section "2. The playbook does not care how many hosts there are"
check_sh "the inventory holds more than the two real nodes" '[[ $(a_hosts_in all | grep -c .) -ge 3 ]]'
info "Eight extra entries pointing at the two real hosts is a legitimate simulation."
check "no per-host behaviour is hardcoded" no_hardcoded_hosts
check "per-host values come from facts or inventory variables" per_host_values_from_facts

section "3. The pipeline covers every stage"
for want in user ssh package template firewalld selinux service; do
  check "the pipeline handles: $want" \
    bash -c "grep -rqE '$want' $PB roles/ 2>/dev/null"
done

section "4. The verify stage genuinely verifies"
check "a 'verify' tag exists" verify_stage_exists
check "verification uses assert, uri or wait_for — not a debug message" verification_is_real
check "the verify stage passes on a healthy estate" \
  bash -c "out=\$(ansible-playbook $PB --tags verify 2>&1); echo \"\$out\" | tail -6;
           ! grep -qE 'failed=[1-9]|fatal:' <<<\"\$out\""

section "5. The estate is genuinely configured"
check "every host answers a ping" a_all_reachable all
check "every web host serves a page over HTTP" all_web_serve

section "6. Safe to run repeatedly"
check "a full run completes without failures" a_playbook_ok "$PB"
check "the second run reports changed=0 across every host" a_idempotent "$PB"

section "7. Verification fails when a host is sabotaged"
if ((SABOTAGE)); then
  if mutating "the verify stage catches a sabotaged host"; then
    sabotage_then_verify_must_fail; rc=$?
    case $rc in
      0) pass "the verify stage failed loudly on a sabotaged host" ;;
      2) skipped "sabotage test" "break.sh is not at /root/break.sh on the target" ;;
      *) fail "the verify stage failed loudly on a sabotaged host" \
           "it reported success on a broken host — that is a green run worth zero marks" ;;
    esac
    info "Now re-run the full playbook to repair the host you just broke."
  fi
else
  skipped "the verify stage catches a sabotaged host" "re-run with --sabotage to test this"
fi

section "8. The rule for the week"
manual "You did not SSH into a managed node to fix anything all week" \
  "Logging in to verify is fine. Logging in to repair is not."

summary
