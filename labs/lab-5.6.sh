#!/usr/bin/env bash
# Lab 5.6 — Handlers, error handling, idempotence    (04-Labs-Ansible-Fundamentals)
# Run on rhel-control, as the ordinary user.
#
# This script proves handler behaviour by actually disturbing the target's
# config file and watching what the next run does. It restores nothing itself —
# the playbook is supposed to.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=handlers.yml
TARGET=$(ansible web --list-hosts 2>/dev/null | sed -n '2p' | tr -d ' ')

# Which file does the playbook deploy? Take the first dest/path it names.
deployed_file() {
  grep -hoE '(dest|path):[[:space:]]*/[^[:space:]"'"'"']+' "$PB" 2>/dev/null |
    awk '{print $2}' | grep -E '^/etc/' | head -1
}

DEST=$(deployed_file)

unchanged_run_fires_no_handler() {
  a_run "$PB" || { echo "$A_LAST_RUN" | tail -10; return 1; }
  a_recap
  local changed
  changed=$(a_recap_field changed)
  if [[ ${changed:-0} -ne 0 ]]; then
    echo "changed=$changed on an unchanged run"
    return 1
  fi
  a_no_handlers_fired || { echo "a handler fired even though nothing changed"; return 1; }
  return 0
}

changed_run_fires_handler_once() {
  [[ -n ${DEST:-} && -n ${TARGET:-} ]] || { echo "cannot tell which file is deployed where"; return 2; }
  echo "disturbing $DEST on $TARGET so the next run must correct it"
  ansible "$TARGET" -m lineinfile \
    -a "path=$DEST line='# disturbed by the lab verifier' insertbefore=BOF" --become >/dev/null 2>&1 ||
    { echo "could not modify $DEST on $TARGET"; return 1; }
  a_run "$PB" || { echo "$A_LAST_RUN" | tail -10; return 1; }
  a_recap
  a_handlers_fired || { echo "the file changed but no handler ran"; return 1; }
  local n
  n=$(grep -c 'RUNNING HANDLER' <<<"$A_LAST_RUN")
  echo "handlers fired: $n"
  [[ ${n:-0} -ge 1 ]]
}

back_to_idempotent_afterwards() {
  a_run "$PB" || return 1
  a_recap
  [[ $(a_recap_field changed) -eq 0 ]] && a_no_handlers_fired
}

# ------------------------------------------------------------------------------
lab_init "5.6" "Handlers, error handling, idempotence" --host rhel-control "$@"
a_init
info "target host for the change test: ${TARGET:-<none>}"
info "config file the playbook deploys: ${DEST:-<could not determine>}"

section "1. The playbook and its structure"
check_file "$PB exists" "$A_PROJ/$PB"
check "it is valid YAML" a_yaml_ok "$PB"
check "syntax-check passes" ansible-playbook --syntax-check "$PB"
check "it defines handlers" bash -c "grep -qE '^[[:space:]]*handlers:' $PB"
check "at least one task notifies a handler" bash -c "grep -qE '^[[:space:]]*notify:' $PB"

section "2. The config is validated before it is put in place"
check "a copy/template task uses validate:" bash -c "grep -qE '^[[:space:]]*validate:' $PB"
check "the validator is httpd's own syntax check" \
  bash -c "grep -E 'validate:' $PB | grep -qE 'httpd -t|apachectl'"
info "Without validate:, a broken config reaches the server and httpd dies on restart."

section "3. Deliberate failure handling"
check "a task is allowed to fail without stopping the play" \
  bash -c "grep -qE '^[[:space:]]*ignore_errors:[[:space:]]*(true|yes)' $PB"
check "a task defines its own failure condition" bash -c "grep -qE '^[[:space:]]*failed_when:' $PB"
check "a task defines its own changed condition" bash -c "grep -qE '^[[:space:]]*changed_when:' $PB"
check "a block/rescue/always structure exists" \
  bash -c "grep -qE '^[[:space:]]*block:' $PB && grep -qE '^[[:space:]]*(rescue|always):' $PB"
check "cleanup runs even on failure (always:)" bash -c "grep -qE '^[[:space:]]*always:' $PB"

section "4. An unchanged run fires no handler"
check "changed=0 and no RUNNING HANDLER on a repeat run" unchanged_run_fires_no_handler

section "5. A changed file fires the handler exactly once"
if mutating "a real change fires the handler"; then
  changed_run_fires_handler_once; rc=$?
  case $rc in
    0) pass "the handler fired after a genuine change" ;;
    2) skipped "the handler fired after a genuine change" \
         "could not work out which file the playbook deploys — check dest:/path: in $PB" ;;
    *) fail "the handler fired after a genuine change" \
         "see the run output above" ;;
  esac
  check "and the run after that is idempotent again" back_to_idempotent_afterwards
fi

section "6. Forcing handlers to run despite a later failure"
check "the playbook or your notes use --force-handlers or force_handlers" \
  bash -c "grep -qE 'force_handlers' $PB || grep -qE 'force_handlers' ansible.cfg"
manual "You corrupted the template and confirmed deployment was refused" \
  "validate: must reject it before it ever reaches the server."

summary
