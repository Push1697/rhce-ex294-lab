#!/usr/bin/env bash
# Lab 2.2 — Processes, journald, scheduled tasks    (01-Labs-RHCSA-Foundation)
# Run on rhel01, as root.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

jconf() {   # the effective value of a journald setting, drop-ins included
  local key="$1"
  grep -rhiE "^[[:space:]]*$key[[:space:]]*=" \
    /etc/systemd/journald.conf /etc/systemd/journald.conf.d/*.conf 2>/dev/null |
    tail -1 | cut -d= -f2 | tr -d ' '
}

journal_under_cap() {
  local used
  used=$(journalctl --disk-usage 2>/dev/null)
  echo "$used"
  # 200M cap: anything reported in G is a failure, as is >200M
  ! grep -Eqi '[0-9.]+G' <<<"$used"
}

# Find the timer that runs sysreport, whatever the user called it.
find_timer() {
  local t
  for t in $(systemctl list-unit-files --type=timer --no-legend 2>/dev/null | awk '{print $1}'); do
    if systemctl cat "$t" "${t%.timer}.service" 2>/dev/null | grep -q 'sysreport'; then
      echo "$t"; return 0
    fi
  done
  return 1
}

TIMER=$(find_timer || true)

timer_at_0230()   { systemctl cat "$TIMER" 2>/dev/null | grep -Eq 'OnCalendar[[:space:]]*=.*02:30'; }
timer_persistent(){ systemctl cat "$TIMER" 2>/dev/null | grep -Eq 'Persistent[[:space:]]*=[[:space:]]*(true|yes|1)'; }

cron_denied_for_dev2() {
  local o rc
  o=$(runuser -u dev2 -- crontab -l 2>&1); rc=$?
  echo "${o:0:150}"
  # "no crontab for dev2" is not a denial — we need an explicit refusal.
  grep -Eqi 'not allowed|denied|permission' <<<"$o"
}

# ------------------------------------------------------------------------------
lab_init "2.2" "Processes, journald, scheduled tasks" --host rhel01 --root "$@"

section "1. The journal is persistent"
check_dir -p "/var/log/journal exists" /var/log/journal
check_eq -p "journald Storage=persistent" "persistent" "$(jconf Storage)"
check -p "the journal really holds more than the current boot" \
  bash -c 'journalctl --list-boots 2>/dev/null | wc -l | grep -qvx 1'

section "2. The journal is capped at 200 MB"
check_eq -p "SystemMaxUse is set to 200M" "200M" "$(jconf SystemMaxUse)"
check "actual disk usage respects the cap" journal_under_cap

section "3. The previous boot is readable"
check -p "journalctl -b -1 returns something" \
  bash -c 'journalctl -b -1 --no-pager -n 3 >/dev/null 2>&1'

section "4. Terminating a user's processes / renice"
manual "You can kill every process owned by a user with one command" \
  "pkill -u <user> — nothing persistent to grade here."
report "processes by nice value" bash -c 'ps -eo pid,ni,comm --sort=-ni | head -5'
manual "You reniced a long-running process to 10 and proved it" \
  "Transient by nature; the script cannot see it after the fact."

section "5. amit's hourly cron job"
if user_exists amit; then
  check "amit has a crontab" bash -c 'crontab -l -u amit >/dev/null 2>&1'
  check_match -p "it runs sysreport -o /tmp/hourly.txt" 'sysreport.*-o[[:space:]]+/tmp/hourly.txt' \
    bash -c 'crontab -l -u amit 2>/dev/null'
  check_match -p "it fires at the top of every hour" '^0[[:space:]]+\*' \
    bash -c 'crontab -l -u amit 2>/dev/null | grep -v "^#" | grep sysreport'
else
  skipped "amit's cron job" "no user 'amit' on this host"
fi

section "6. A systemd timer at 02:30, persistent"
if [[ -n ${TIMER:-} ]]; then
  info "found timer: $TIMER"
  check -p "the timer is enabled" systemctl is-enabled --quiet "$TIMER"
  check -p "OnCalendar is 02:30" timer_at_0230
  check -p "Persistent=true, so a missed run catches up" timer_persistent
  check "it appears in systemctl list-timers" \
    bash -c "systemctl list-timers --all --no-legend 2>/dev/null | grep -q '$TIMER'"
  report "next scheduled run" \
    bash -c "systemctl list-timers --all --no-legend 2>/dev/null | grep '$TIMER'"
else
  fail "a systemd timer runs sysreport daily" \
    "no .timer unit on this system references sysreport"
fi

section "7. dev2 may not use cron"
if user_exists dev2; then
  check -p "dev2 is denied cron" cron_denied_for_dev2
  check_sh -p "the denial is configured in /etc/cron.deny or cron.allow" \
    '[[ -f /etc/cron.deny && $(grep -cx dev2 /etc/cron.deny) -gt 0 ]] || { [[ -f /etc/cron.allow ]] && ! grep -qx dev2 /etc/cron.allow; }'
else
  skipped "dev2 cron denial" "no user 'dev2' on this host"
fi

summary
