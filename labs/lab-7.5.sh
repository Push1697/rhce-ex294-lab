#!/usr/bin/env bash
# Lab 7.5 — Failure handling and structure at scale (06-Labs-Advanced-Ansible)
# Run on rhel-control, as the ordinary user.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

ROLL=rolling.yml
PB=site.yml
for a in "$@"; do
  case "$a" in --rolling=*) ROLL=${a#--rolling=} ;; --pb=*) PB=${a#--pb=} ;; esac
done

batching_visible() {
  local out n
  out=$(ansible-playbook "$ROLL" 2>&1)
  V_LAST_OUT="$out"
  # serial batching shows the play header repeated, once per batch
  n=$(grep -c '^PLAY \[' <<<"$out")
  echo "PLAY headers in the run: $n"
  grep -E '^PLAY (RECAP|\[)' <<<"$out" | head -6
  [[ ${n:-0} -ge 2 ]]
}

rescue_runs_on_failure() {
  local out
  out=$(ansible-playbook "$PB" --tags rescue-test 2>&1)
  V_LAST_OUT="$out"
  grep -qiE 'no hosts matched|tag.*not found|skipping' <<<"$out" && {
    echo "no rescue-test tag — cannot trigger the rescue path automatically"; return 2; }
  grep -qi 'rescue' <<<"$out"
}

run_once_exactly_once() {
  local out n
  out=$(ansible-playbook "$PB" --tags once 2>&1)
  V_LAST_OUT="$out"
  grep -qiE 'no hosts matched|tag.*not found' <<<"$out" && { echo "no 'once' tag to test"; return 2; }
  n=$(grep -cE '^(ok|changed): \[' <<<"$out")
  echo "task ran on $n host(s)"
  [[ ${n:-0} -eq 1 ]]
}

skip_tags_works() {
  local a b
  a=$(ansible-playbook "$PB" --list-tasks 2>/dev/null | grep -c .)
  b=$(ansible-playbook "$PB" --list-tasks --skip-tags storage 2>/dev/null | grep -c .)
  echo "tasks listed: $a, with storage skipped: $b"
  [[ ${b:-0} -lt ${a:-0} ]]
}

# ------------------------------------------------------------------------------
lab_init "7.5" "Failure handling and structure at scale" --host rhel-control "$@"
a_init

section "1. One host fails, the others continue — and the opposite"
check_file "$ROLL exists" "$A_PROJ/$ROLL"
check "it is valid YAML" a_yaml_ok "$ROLL"
check "syntax-check passes" ansible-playbook --syntax-check "$ROLL"
check "max_fail_percentage is set" bash -c "grep -qE '^[[:space:]]*max_fail_percentage:' $ROLL"
check "any_errors_fatal is used somewhere for the opposite behaviour" \
  bash -c "grep -rqE 'any_errors_fatal' *.yml roles/ 2>/dev/null"

section "2. block / rescue / always doing real cleanup"
check "a block/rescue/always structure exists" \
  bash -c "grep -rqE '^[[:space:]]*block:' *.yml roles/ && grep -rqE '^[[:space:]]*rescue:' *.yml roles/"
check "an always: section performs cleanup" \
  bash -c "grep -rqE '^[[:space:]]*always:' *.yml roles/ 2>/dev/null"
rescue_runs_on_failure; rc=$?
case $rc in
  0) pass "the rescue path demonstrably executes on failure" ;;
  2) skipped "the rescue path executes on failure" \
       "tag the failure-injecting play 'rescue-test' to have this graded" ;;
  *) fail "the rescue path demonstrably executes on failure" "no rescue output in the run" ;;
esac

section "3. Rolling update, two hosts at a time"
check "serial is set to 2" bash -c "grep -qE '^[[:space:]]*serial:[[:space:]]*2[[:space:]]*$' $ROLL"
check "the run visibly proceeds in batches" batching_visible
check "the rolling play targets the web group" bash -c "grep -qE 'hosts:.*web' $ROLL"

section "4. pre_tasks and post_tasks around the roles"
check "pre_tasks exists" bash -c "grep -rqE '^[[:space:]]*pre_tasks:' *.yml 2>/dev/null"
check "post_tasks exists" bash -c "grep -rqE '^[[:space:]]*post_tasks:' *.yml 2>/dev/null"
report "the resulting order" bash -c "ansible-playbook $PB --list-tasks 2>/dev/null | head -20"

section "5. delegate_to on the control node"
check "delegate_to is used" bash -c "grep -rqE '^[[:space:]]*delegate_to:' *.yml roles/ 2>/dev/null"
check "at least one task is delegated to localhost or the control node" \
  bash -c "grep -rhE 'delegate_to:' *.yml roles/ 2>/dev/null | grep -qE 'localhost|127\.0\.0\.1|rhel-control'"

section "6. run_once"
check "run_once is used" bash -c "grep -rqE '^[[:space:]]*run_once:[[:space:]]*(true|yes)' *.yml roles/ 2>/dev/null"
run_once_exactly_once; rc=$?
case $rc in
  0) pass "the run_once task executed exactly once" ;;
  2) skipped "the run_once task executed exactly once" \
       "tag it 'once' to have this graded automatically" ;;
  *) fail "the run_once task executed exactly once" "it ran on more than one host" ;;
esac

section "7. Tags isolate any single stage"
check "--list-tags reports the stage tags" \
  bash -c "ansible-playbook $PB --list-tags 2>&1 | grep -qi 'task tags'"
report "the tags defined" bash -c "ansible-playbook $PB --list-tags 2>/dev/null | tail -5"
check "--tags security --check runs cleanly" \
  bash -c "out=\$(ansible-playbook $PB --tags security --check 2>&1); echo \"\$out\" | tail -6;
           ! grep -qE 'fatal:|no hosts matched' <<<\"\$out\""
check "--skip-tags genuinely removes tasks" skip_tags_works

section "8. Read the recap, always"
manual "You check the recap for skipped= as a matter of habit" \
  "A failed task shouts. A wrongly-conditioned task succeeds silently and does nothing."

summary
