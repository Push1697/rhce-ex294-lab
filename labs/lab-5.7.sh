#!/usr/bin/env bash
# Lab 5.7 — Week 5 consolidation, timed build       (04-Labs-Ansible-Fundamentals)
# Run on rhel-control, as the ordinary user.
#   ./lab-5.7.sh --pb=site.yml     name the playbook if it is not site.yml
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=""
for a in "$@"; do case "$a" in --pb=*) PB=${a#--pb=} ;; esac; done

pick_playbook() {
  local c
  for c in ${PB:-} site.yml consolidation.yml week5.yml build.yml main.yml; do
    [[ -f $c ]] && { echo "$c"; return 0; }
  done
  return 1
}

sudo_nopasswd_for_sysadmins() {
  local out
  out=$(ansible managed -m shell -a 'grep -rh sysadmins /etc/sudoers /etc/sudoers.d/ 2>/dev/null' --become 2>&1)
  echo "$out" | grep -vE 'CHANGED|SUCCESS|=>|rc=' | head -4
  grep -qi 'NOPASSWD' <<<"$out"
}

sudoers_valid_everywhere() {
  local out
  out=$(ansible managed -m command -a 'visudo -c' --become 2>&1)
  echo "$out" | grep -E 'parsed OK|FAILED' | head -4
  ! grep -qE 'FAILED|parse error' <<<"$out"
}

keys_deployed() {
  local out
  out=$(ansible managed -m shell -a 'for h in /home/*/.ssh/authorized_keys; do [ -s "$h" ] && echo "$h"; done' --become 2>&1)
  echo "$out" | grep -c '/authorized_keys' >/dev/null
  echo "$out" | grep '/authorized_keys' | head -5
  [[ $(grep -c '/authorized_keys' <<<"$out") -ge 3 ]]
}

httpd_only_on_web() {
  local out bad=0 h
  for h in $(a_hosts_in web); do
    ansible "$h" -m command -a 'systemctl is-active httpd' 2>&1 | grep -q '^active' ||
      { echo "$h (in web) is not running httpd"; bad=1; }
  done
  for h in $(a_hosts_in db); do
    a_group_has web "$h" && continue
    ansible "$h" -m command -a 'rpm -q httpd' 2>&1 | grep -q 'not installed' ||
      { echo "$h (not in web) has httpd installed — 'on web only' was the requirement"; bad=1; }
  done
  return $bad
}

index_names_each_host() {
  local h bad=0 body
  for h in $(a_hosts_in web); do
    body=$(ansible "$h" -m uri -a "url=http://$h/ return_content=true" 2>&1)
    grep -q "$h" <<<"$body" || { echo "$h's page does not name it"; bad=1; }
  done
  return $bad
}

firewall_http_web_only() {
  local h bad=0 out
  for h in $(a_hosts_in web); do
    out=$(ansible "$h" -m command -a 'firewall-cmd --permanent --list-services' --become 2>&1)
    grep -qw http <<<"$out" || { echo "$h: http is not permanently open"; bad=1; }
  done
  for h in $(a_hosts_in db); do
    a_group_has web "$h" && continue
    out=$(ansible "$h" -m command -a 'firewall-cmd --permanent --list-services' --become 2>&1)
    grep -qw http <<<"$out" && { echo "$h: http is open but this host is not in web"; bad=1; }
  done
  return $bad
}

a_daily_timer_exists() {
  local out
  out=$(ansible managed -m shell -a 'systemctl list-timers --all --no-legend' --become 2>&1)
  echo "$out" | grep -vE 'CHANGED|SUCCESS|=>' | head -6
  grep -qE 'maint|audit|daily|\.timer' <<<"$out"
}

no_handler_on_repeat() {
  a_run "$PB" >/dev/null 2>&1
  a_no_handlers_fired && return 0
  grep -A2 'RUNNING HANDLER' <<<"$A_LAST_RUN" | head -6
  return 1
}

# ------------------------------------------------------------------------------
lab_init "5.7" "Week 5 consolidation (timed)" --host rhel-control "$@"
a_init

PB=$(pick_playbook) || { fail "one playbook that does the whole build" \
  "no site.yml (or similar) found in $A_PROJ — pass --pb=NAME"; summary; exit 1; }
info "grading playbook: $PB"

section "1. sysadmins group and three users with keys"
check "the playbook exists and syntax-checks" ansible-playbook --syntax-check "$PB"
check "sysadmins group exists on every managed node" \
  bash -c 'out=$(ansible managed -m command -a "getent group sysadmins" 2>&1);
           echo "$out" | tail -4; ! grep -qE "FAILED|non-zero" <<<"$out"'
check "at least three users have authorized_keys deployed" keys_deployed

section "2. Passwordless sudo for sysadmins"
check "a NOPASSWD rule exists for sysadmins" sudo_nopasswd_for_sysadmins
check "sudoers parses cleanly on every node" sudoers_valid_everywhere
check "the sudoers file was validated before deployment" \
  bash -c "grep -rqE 'validate:.*visudo' *.yml roles/ 2>/dev/null"

section "3. httpd on the web group only"
check "httpd runs on web and is absent elsewhere" httpd_only_on_web

section "4. A templated index page naming the host"
check "a template is used for the index page" \
  bash -c "grep -rqE '(ansible\.builtin\.)?template:' *.yml roles/ 2>/dev/null"
check "each web host serves a page naming itself" index_names_each_host

section "5. firewalld permits http on web and nothing extra"
check "http is permanently open on web, and only on web" firewall_http_web_only

section "6. A daily maintenance timer"
check "a systemd timer is installed on the managed nodes" a_daily_timer_exists
check "the timer and its service come from the playbook" \
  bash -c "grep -rqE '\.timer' *.yml roles/ templates/ 2>/dev/null"

section "7. Handlers restart services only on real change"
check "the playbook notifies handlers" bash -c "grep -rqE '^[[:space:]]*notify:' *.yml roles/ 2>/dev/null"
check "a repeat run fires no handler at all" no_handler_on_repeat

section "8. Idempotence"
check "the playbook runs clean" a_playbook_ok "$PB"
check "the second run reports changed=0 on every host" a_idempotent "$PB"

section "9. The conditions of the exercise"
manual "Completed inside 90 minutes" "Timed, from reverted 'clean' nodes."
manual "ansible-doc was the only reference used" "No web, no notes, no cheat sheet."

summary
