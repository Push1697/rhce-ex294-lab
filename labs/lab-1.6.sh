#!/usr/bin/env bash
# Lab 1.6 — Bash scripting: /usr/local/bin/sysreport  (01-Labs-RHCSA-Foundation)
# Run on rhel01, as root.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

S=/usr/local/bin/sysreport
OUT=""

grab() { OUT=$("$S" 2>&1); return $?; }

executable_by_root_only() {
  local m u
  m=$(mode_of "$S"); u=$(stat -c %U "$S" 2>/dev/null)
  echo "mode ${m:-?}, owner ${u:-?}"
  [[ -n ${m:-} ]] || { echo "cannot stat $S"; return 1; }
  [[ $u == root ]] || return 1
  owner_exec "$S" || { echo "root cannot execute it"; return 1; }
  group_exec "$S" && { echo "the group can execute it too"; return 1; }
  other_exec "$S" && { echo "everyone can execute it"; return 1; }
  return 0
}

reports_hostname()  { grep -qF "$(hostname)" <<<"$OUT"; }
reports_kernel()    { grep -qF "$(uname -r)" <<<"$OUT"; }
reports_uptime()    { grep -Eqi 'up |uptime|load average' <<<"$OUT"; }
reports_release()   { grep -Eqi 'release|rhel|red hat' <<<"$OUT"; }
reports_memory_top(){ grep -Eqi '%mem|memory|rss' <<<"$OUT"; }
reports_fs()        { grep -Eqi '%|filesystem|mounted on|^OK$|\bOK\b' <<<"$OUT"; }
reports_units()     { grep -Eqi 'failed|unit|^OK$|\bOK\b' <<<"$OUT"; }

quiet_with_o() {
  local f=/tmp/verify-sysreport-$$ so
  so=$("$S" -o "$f" 2>/dev/null)
  local rc=$?
  echo "stdout was: '${so:0:80}'"
  [[ -s $f ]] || { echo "no file was written to $f"; rm -f "$f"; return 1; }
  rm -f "$f"
  [[ -z ${so//[[:space:]]/} ]]
}

unknown_flag_rejected() {
  local o rc
  o=$("$S" --bogus 2>&1); rc=$?
  echo "exit $rc; output: ${o:0:120}"
  ((rc != 0)) && grep -qi 'usage' <<<"$o"
}

exit_code_matches_health() {
  local rc failed over
  "$S" >/dev/null 2>&1; rc=$?
  failed=$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | grep -c .)
  over=$(df -P --output=pcent 2>/dev/null | tr -d ' %' | awk 'NR>1 && $1+0 > 80 { c++ } END { print c+0 }')
  echo "exit $rc with $failed failed unit(s) and $over filesystem(s) over 80%"
  if ((failed > 0 || over > 0)); then ((rc == 1)); else ((rc == 0)); fi
}

# Force the unhealthy path with a unit that is guaranteed to fail.
detects_a_failed_unit() {
  local u=verify-sysreport-fail.service rc
  cat > "/etc/systemd/system/$u" <<'UNIT'
[Unit]
Description=deliberately failing unit, created by the lab verifier
[Service]
Type=oneshot
ExecStart=/bin/false
UNIT
  systemctl daemon-reload
  systemctl start "$u" >/dev/null 2>&1
  "$S" >/dev/null 2>&1; rc=$?
  echo "with a failed unit present, sysreport exited $rc (must be 1)"
  systemctl reset-failed "$u" >/dev/null 2>&1
  rm -f "/etc/systemd/system/$u"
  systemctl daemon-reload
  ((rc == 1))
}

# ------------------------------------------------------------------------------
lab_init "1.6" "Bash scripting — sysreport" --host rhel01 --root "$@"

section "1. The script exists and is callable from anywhere"
check_file "/usr/local/bin/sysreport exists and is not empty" "$S"
check "it is executable by root only" executable_by_root_only
check "'sysreport' resolves on PATH without a path prefix" command -v sysreport

if [[ ! -x $S ]]; then summary; exit 1; fi

section "2. Script hygiene"
check_match "it starts with a shebang" '^#!.*(bash|sh)' head -1 "$S"
check "it uses set -euo pipefail" grep -Eq '^[[:space:]]*set -[a-z]*e[a-z]*uo? pipefail|set -euo pipefail' "$S"

section "3. Default output goes to stdout"
grab || true
check_sh "plain 'sysreport' produces output" "[[ -n \"\${OUT// /}\" ]]"
check "it reports the hostname" reports_hostname
check "it reports the kernel version" reports_kernel
check "it reports uptime" reports_uptime
check "it reports the RHEL version" reports_release
check "it has a top-processes-by-memory section" reports_memory_top
check "it reports filesystem fullness (or OK)" reports_fs
check "it reports failed units (or OK)" reports_units

section "4. -o FILE writes the file and prints nothing"
check "sysreport -o FILE is silent and writes the file" quiet_with_o

section "5. An unknown flag prints usage and exits non-zero"
check "sysreport --bogus prints usage and fails" unknown_flag_rejected

section "6. Exit status reflects the health of the box"
check "exit status matches the machine's current state" exit_code_matches_health
if mutating "exit 1 when a unit has genuinely failed"; then
  check "exit 1 when a unit has genuinely failed" detects_a_failed_unit
fi

summary
