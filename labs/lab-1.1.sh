#!/usr/bin/env bash
# Lab 1.1 — Navigation, vim, text processing        (01-Labs-RHCSA-Foundation)
# Run on rhel01, as root.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

R=/root/reports
LL=$R/large-logs.txt
BE=$R/boot-errors.txt
UC=$R/users.csv

# --- checks for large-logs.txt ------------------------------------------------
paths_under_var_log() {
  awk '{ p = $NF; if (p !~ /^\/?var\/log\//) { print "not under /var/log: " $0; bad = 1 } }
       END { exit (bad > 0) }' "$LL"
}

all_over_100k() {
  local line p sz bad=0
  while read -r line; do
    p=${line##* }
    [[ $p == /* ]] || p=/$p
    [[ -f $p ]] || continue
    sz=$(stat -c %s "$p" 2>/dev/null || echo 0)
    ((sz > 102400)) || { echo "only $sz bytes: $p"; bad=1; }
  done < "$LL"
  return $bad
}

sorted_by_real_size() {
  # Accepts raw bytes or human units. The size column must never increase.
  awk '{
         s = $1; n = s + 0
         if (s ~ /[kK]$/)      n *= 1024
         else if (s ~ /[mM]$/) n *= 1048576
         else if (s ~ /[gG]$/) n *= 1073741824
         if (NR > 1 && n > prev) { print "out of order at line " NR ": " $0; bad = 1 }
         prev = n
       }
       END { exit (bad > 0) }' "$LL"
}

two_fields_only() {
  awk 'NF != 2 { print "line " NR " has " NF " fields: " $0; bad = 1 }
       END { exit (bad > 0) }' "$LL"
}

# --- checks for boot-errors.txt -----------------------------------------------
line_numbers_present() {
  awk '!/^[[:space:]]*[0-9]+[:[:space:]]/ { print "no line number: " $0; bad = 1 }
       END { exit (bad > 0) }' "$BE"
}

every_line_matches() {
  local off
  off=$(grep -viE 'error|fail' "$BE" | head -3)
  [[ -z $off ]] && return 0
  echo "these lines mention neither error nor fail:"
  echo "$off"
  return 1
}

# A case-insensitive grep over the same source should yield the same number of
# lines. The source is ambiguous (messages vs the journal), so a mismatch is a
# prompt to look, not an automatic failure.
cross_check_count() {
  local want got
  [[ -f /var/log/messages ]] || { echo "no /var/log/messages — journal was probably the source"; return 2; }
  want=$(grep -icE 'error|fail' /var/log/messages)
  got=$(grep -c . "$BE")
  echo "independent count from /var/log/messages: $want ; your file: $got"
  [[ $want == "$got" ]]
}

# --- checks for users.csv -----------------------------------------------------
three_fields() {
  awk -F, 'NF != 3 { print "BAD: " $0; bad = 1 } END { exit (bad > 0) }' "$UC"
}

no_system_accounts() {
  awk -F, '$2 + 0 < 1000 { print "BAD: " $0; bad = 1 } END { exit (bad > 0) }' "$UC"
}

third_field_is_shell() {
  awk -F, '$3 !~ /^\// { print "BAD: " $0; bad = 1 } END { exit (bad > 0) }' "$UC"
}

users_all_real() {
  local u rest bad=0
  while IFS=, read -r u rest; do
    [[ -z ${u// /} ]] && continue
    getent passwd "$u" >/dev/null || { echo "no such user: $u"; bad=1; }
  done < "$UC"
  return $bad
}

# ------------------------------------------------------------------------------
lab_init "1.1" "Navigation, vim, text processing" --host rhel01 --root "$@"

section "1. /root/reports/large-logs.txt"
check_file "large-logs.txt exists and is not empty" "$LL"
if [[ -s $LL ]]; then
  check "shows size and path only — two fields per line" two_fields_only
  check "every line refers to a path under /var/log" paths_under_var_log
  check "every listed file is genuinely larger than 100 KB" all_over_100k
  check "sorted by real size, largest first — not lexically" sorted_by_real_size
fi

section "2. /root/reports/boot-errors.txt"
check_file "boot-errors.txt exists and is not empty" "$BE"
if [[ -s $BE ]]; then
  check "line numbers preserved on every line" line_numbers_present
  check "every line actually mentions error or fail" every_line_matches
  if grep -qE 'Error|ERROR|Fail|FAIL|Failed|failed' "$BE"; then
    pass "the match was case-insensitive — uppercase variants are present"
  else
    warn "no uppercase Error/FAIL lines in the file"       "That is fine if the source genuinely had none. If it did not, your grep was case-sensitive."
  fi
  cross_check_count; rc=$?
  if ((rc == 2)); then
    skipped "line count cross-checked against the source" "the journal, not /var/log/messages, was the source"
  elif ((rc == 0)); then
    pass "line count matches an independent case-insensitive grep of the source"
  else
    warn "line count differs from an independent grep of /var/log/messages"       "$(cross_check_count 2>&1 | head -1). Fine if you used the journal; suspicious otherwise."
  fi
  report "lines captured" wc -l "$BE"
fi

section "3. /root/reports/users.csv"
check_file "users.csv exists and is not empty" "$UC"
if [[ -s $UC ]]; then
  check "exactly three comma-separated fields per line" three_fields
  check "nothing with a UID below 1000 — so no root" no_system_accounts
  check "third field is a shell path" third_field_is_shell
  check "every username in the file exists on the system" users_all_real
  want=$(awk -F: '$3 >= 1000 && $3 < 65534 { c++ } END { print c + 0 }' /etc/passwd)
  got=$(grep -c . "$UC")
  check_eq "one line per UID>=1000 account in /etc/passwd" "$want" "$got"
fi

section "4. Editor discipline"
manual "All editing was done in vim — no nano, no desktop editor" \
  "A script cannot see which editor you used."
if [[ -f /root/.viminfo ]]; then
  info "/root/.viminfo exists, so vim has been used as root at least once."
else
  warn "no /root/.viminfo — vim may not have been used as root at all"
fi

summary
