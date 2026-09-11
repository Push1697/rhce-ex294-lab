#!/usr/bin/env bash
# Lab 1.5 — Find, archives, compression             (01-Labs-RHCSA-Foundation)
# Run on rhel01, as root.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

B=/root/backup
ETC_TAR=$(ls -1t "$B"/etc-*.tar.gz 2>/dev/null | head -1)
LOG_TAR=$B/logs.tar.bz2
SUID=/root/reports/suid.txt

etc_archive_named_by_date() {
  local base
  base=$(basename "${ETC_TAR:-}")
  echo "found: ${base:-<nothing>}"
  [[ $base =~ ^etc-[0-9]{4}-[0-9]{2}-[0-9]{2}\.tar\.gz$ ]]
}

# If the archive really carries SELinux contexts, a file extracted from it keeps
# its original label rather than picking up the destination's default.
contexts_preserved() {
  local d want got
  command -v getfattr >/dev/null 2>&1 || { echo "getfattr not installed"; return 2; }
  d=$(mktemp -d /root/.verify-tar-XXXXXX) || return 1
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" RETURN
  tar --selinux --acls --xattrs --xattrs-include='*' \
      -xzf "$ETC_TAR" -C "$d" etc/hostname 2>/dev/null ||
    tar -xzf "$ETC_TAR" -C "$d" ./etc/hostname 2>/dev/null || {
      echo "could not extract etc/hostname from the archive"; return 1; }
  got=$(getfattr -n security.selinux --only-values "$d/etc/hostname" 2>/dev/null | tr -d '\0')
  want=$(getfattr -n security.selinux --only-values /etc/hostname 2>/dev/null | tr -d '\0')
  echo "archive: ${got:-<none>}"
  echo "on disk: ${want:-<none>}"
  [[ -n ${got:-} && $got == "$want" ]]
}

only_log_files() {
  local bad
  bad=$(tar tjf "$LOG_TAR" 2>/dev/null | grep -v '/$' | grep -cv '\.log$')
  echo "non-.log members: $bad"
  [[ $bad == 0 ]]
}

logs_are_recent() {
  local cutoff bad
  cutoff=$(date -d '-8 days' +%Y-%m-%d)
  bad=$(tar tvjf "$LOG_TAR" 2>/dev/null |
        awk -v c="$cutoff" '$4 != "" && $4 < c { print $4, $6 }')
  [[ -z $bad ]] && return 0
  echo "members older than 7 days:"; echo "$bad" | head -5
  return 1
}

restore_has_only_hostname() {
  local n
  n=$(find /tmp/restore -type f 2>/dev/null | wc -l)
  echo "regular files under /tmp/restore: $n"
  [[ -f /tmp/restore/etc/hostname && $n -eq 1 ]]
}

every_listed_file_is_suid() {
  local p bad=0
  while read -r p; do
    [[ -n ${p// /} ]] || continue
    [[ -e $p ]] || { echo "listed but missing: $p"; bad=1; continue; }
    [[ -u $p ]] || { echo "listed but not SUID: $p"; bad=1; }
  done < "$SUID"
  return $bad
}

# ------------------------------------------------------------------------------
lab_init "1.5" "Find, archives, compression" --host rhel01 --root "$@"

section "1. The /etc archive"
check_dir "/root/backup exists" "$B"
check "an etc-YYYY-MM-DD.tar.gz archive exists" etc_archive_named_by_date
if [[ -n ${ETC_TAR:-} ]]; then
  check_match "it really is gzip-compressed" 'gzip compressed' file -b "$ETC_TAR"
  check "it contains /etc content" bash -c "tar tzf '$ETC_TAR' | grep -q 'etc/hostname'"
  check_match "permissions and ownership are recorded" '^[-d][rwxsSt-]{9}' \
    bash -c "tar tvzf '$ETC_TAR' | head -1"
  contexts_preserved; rc=$?
  case $rc in
    0) pass "SELinux contexts were preserved in the archive" ;;
    2) skipped "SELinux contexts preserved" "getfattr (attr package) is not installed" ;;
    *) fail "SELinux contexts were preserved in the archive"             "the label from the archive does not match the label on disk" ;;
  esac
fi

section "2. The recent-logs archive"
check_file "/root/backup/logs.tar.bz2 exists" "$LOG_TAR"
if [[ -s $LOG_TAR ]]; then
  check_match "it really is bzip2-compressed" 'bzip2 compressed' file -b "$LOG_TAR"
  check "it contains only *.log files" only_log_files
  check "every member was modified in the last 7 days" logs_are_recent
  check_sh "it is not empty" "[[ \$(tar tjf '$LOG_TAR' | wc -l) -gt 0 ]]"
fi

section "3. Files owned by amit outside /home"
manual "You listed every file owned by amit outside /home" \
  "Nothing to grade — but you should be able to re-run that find from memory."
if user_exists amit; then
  report "what such a find returns now" \
    bash -c 'find / -xdev -user amit -not -path "/home/*" -not -path "/proc/*" 2>/dev/null | head -10'
fi

section "4. The SUID list"
check_file "/root/reports/suid.txt exists" "$SUID"
if [[ -s $SUID ]]; then
  check "it includes /usr/bin/passwd" grep -qx '/usr/bin/passwd' "$SUID"
  check "it includes /usr/bin/sudo"   grep -qx '/usr/bin/sudo' "$SUID"
  check "every path listed really carries the SUID bit" every_listed_file_is_suid
  report "entries" wc -l "$SUID"
fi

section "5. Selective extraction into /tmp/restore"
check_file "/tmp/restore/etc/hostname exists" /tmp/restore/etc/hostname
check "and nothing else was extracted" restore_has_only_hostname

summary
