#!/usr/bin/env bash
# Mock EX200-A — grader                             (03-EX200-Exam-Prep, Day 26)
# Run on rhel01, as root, AFTER the reboot. One section per exam task; the
# score is tasks fully correct, scaled to 300 with a 210 pass mark.
#
#   ./mock-ex200-a.sh --spec     print the exam paper (pinned values)
#   sudo ./mock-ex200-a.sh       grade it
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

if [[ ${1:-} == --spec ]]; then
  cat <<'SPEC'
Mock EX200-A — 2.5 hours, closed book, rhel01 reverted to `clean` first.
Graded after a reboot. The grader pins the values below, so build exactly these.

 1. Set the hostname to server-a.lab.local, permanently.
 2. Configure a static IP with two DNS servers and the search domain lab.local,
    on a spare interface — never the one your session arrives on. It must
    survive a reboot, and must not claim the default route.
 3. Group `finance`, GID 6000. Users `fin1` and `fin2` in it. `fin2` must not be
    able to log in interactively.
 4. fin1's password expires in 45 days, with a 10-day warning.
 5. /srv/finance — group-owned by finance, group-writable, users cannot delete
    each other's files, new files inherit the group.
 6. Read-only ACL for user `auditor` on /srv/finance, inherited by new files,
    with no change to group membership.
 7. A 3 GB XFS filesystem from the blank disk, mounted at /finance by UUID,
    with nodev.
 8. 1 GB of swap, persistent.
 9. Volume group `vgapp` with 32 MB extents; a 2 GB logical volume mounted at
    /appdata; then extend it to 5 GB with the filesystem grown.
10. httpd installed and enabled, serving from /finance/www, SELinux enforcing.
11. http open in the firewall, permanently.
12. A systemd timer running /usr/local/bin/audit.sh daily at 03:00, persistent.
13. The journal persistent and capped at 300 MB.
14. fin2 denied the use of cron.
15. Reset the root password from GRUB (simulate the lockout).
SPEC
  exit 0
fi

# ---------------------------------------------------------------- task helpers --
sticky_and_sgid() {
  local p="$1"
  echo "mode: $(perms_of "$p") ($(mode_of "$p"))"
  sgid_set "$p" || { echo "SGID is not set"; return 1; }
  sticky_set "$p" || { echo "the sticky bit is not set"; return 1; }
  return 0
}

acl_inherits_for() {   # acl_inherits_for <dir> <user> <perm-regex>
  local d="$1" u="$2" re="$3" f="$1/.verify-acl-$$" rc=0
  getfacl -p --absolute-names "$d" 2>/dev/null | grep -Eq "^user:$u:$re" ||
    { echo "no named ACL entry for $u on $d"; rc=1; }
  getfacl -p --absolute-names "$d" 2>/dev/null | grep -Eq "^default:user:$u:$re" ||
    { echo "no default ACL entry for $u on $d"; rc=1; }
  if ((V_MUTATE)); then
    touch "$f" 2>/dev/null || { echo "could not create a test file in $d"; return 1; }
    getfacl -p --absolute-names "$f" 2>/dev/null | grep -Eq "^user:$u:$re" ||
      { echo "a new file did not inherit $u's entry"; rc=1; }
    rm -f "$f"
  fi
  return $rc
}

fstab_by_uuid() {   # fstab_by_uuid <mountpoint>
  local line uuid src
  line=$(fstab_line "$1")
  [[ -n ${line:-} ]] || { echo "no /etc/fstab entry for $1"; return 1; }
  echo "$line"
  [[ $line == UUID=* ]] || { echo "the entry does not use UUID="; return 1; }
  src=$(mount_src "$1")
  uuid=$(dev_uuid "$src")
  [[ -n ${uuid:-} ]] && grep -q "$uuid" <<<"$line"
}

swap_1g_persistent() {
  local sz line
  sz=$(swapon --show=SIZE --noheadings --bytes 2>/dev/null | head -1)
  line=$(awk '$1 !~ /^#/ && $3 == "swap" { print }' /etc/fstab)
  echo "active swap: ${sz:-0} bytes"
  echo "fstab: ${line:-<none>}"
  [[ -n ${line:-} ]] || return 1
  approx "$(awk -v b="${sz:-0}" 'BEGIN { printf "%.1f", b / 1073741824 }')" 1 0.3
}

vg_extent_32m() {
  local pe
  pe=$(vgs --noheadings --units m -o vg_extent_size vgapp 2>/dev/null | tr -d ' m')
  echo "extent size: ${pe:-?} MiB"
  approx "${pe:-0}" 32 0.5
}

appdata_is_5g() {
  local g
  g=$(df_gib /appdata)
  echo "/appdata is ${g:-?} GiB"
  approx "${g:-0}" 5 0.5
}

fs_grown_to_lv() {
  local lvb fsb src
  src=$(mount_src /appdata)
  lvb=$(lvs --noheadings --units b --nosuffix -o lv_size "$src" 2>/dev/null | tr -d ' ')
  fsb=$(df -B1 --output=size /appdata 2>/dev/null | tail -1 | tr -d ' ')
  echo "LV ${lvb:-?} bytes, filesystem ${fsb:-?} bytes"
  [[ -n ${lvb:-} && -n ${fsb:-} ]] && awk -v l="$lvb" -v f="$fsb" 'BEGIN { exit !(f > l * 0.9) }'
}

httpd_serves_finance_www() {
  local root body
  root=$(grep -hE '^[[:space:]]*DocumentRoot' /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/*.conf 2>/dev/null |
         tail -1 | awk '{ gsub(/"/, "", $2); print $2 }')
  echo "DocumentRoot: ${root:-<default>}"
  [[ $root == /finance/www ]] || return 1
  body=$(curl -s --max-time 5 http://localhost/ 2>&1)
  echo "curl returned: ${body:0:60}"
  [[ -n ${body// /} ]]
}

find_audit_timer() {
  local t
  for t in $(systemctl list-unit-files --type=timer --no-legend 2>/dev/null | awk '{print $1}'); do
    systemctl cat "$t" "${t%.timer}.service" 2>/dev/null | grep -q 'audit\.sh' && { echo "$t"; return 0; }
  done
  return 1
}

jconf() {
  grep -rhiE "^[[:space:]]*$1[[:space:]]*=" \
    /etc/systemd/journald.conf /etc/systemd/journald.conf.d/*.conf 2>/dev/null |
    tail -1 | cut -d= -f2 | tr -d ' '
}

cron_denied() {
  local o
  o=$(runuser -u "$1" -- crontab -l 2>&1)
  echo "${o:0:120}"
  grep -Eqi 'not allowed|denied|permission' <<<"$o"
}

# ------------------------------------------------------------------------------
lab_init "ex200-a" "Mock EX200-A" --host server-a --root --score "$@"

section "1. Hostname"
check_eq -p "static hostname is server-a.lab.local" "server-a.lab.local" "$(hostnamectl --static)"

section "2. Static addressing"
if need_cmd "network checks" nmcli; then
  active=$(nmcli -t -f NAME con show --active 2>/dev/null | head -1)
  info "active profile: ${active:-<none>}"
  check_eq -p "ipv4.method is manual" "manual" "$(nmcli -g ipv4.method con show "$active" 2>/dev/null)"
  check_sh -p "two DNS servers are configured" \
    "[[ \$(nmcli -g ipv4.dns con show '$active' 2>/dev/null | tr ',' '\n' | grep -c .) -ge 2 ]]"
  check_match -p "the search domain is lab.local" 'lab\.local' \
    bash -c "nmcli -g ipv4.dns-search con show '$active'"
  check_eq -p "the profile autoconnects" "yes" "$(nmcli -g connection.autoconnect con show "$active" 2>/dev/null)"
fi

section "3. finance group and its users"
check_eq "finance has GID 6000" 6000 "$(group_gid finance)"
check "fin1 exists" user_exists fin1
check "fin2 exists" user_exists fin2
check "fin1 is in finance" in_group fin1 finance
check "fin2 is in finance" in_group fin2 finance
s=$(user_shell fin2)
check_sh "fin2 cannot log in interactively (shell: ${s:-none})" \
  "[[ '$s' == */nologin || '$s' == */false ]]"

section "4. fin1's password ageing"
check_eq -p "maximum age is 45 days" "45" \
  "$(chage -l fin1 2>/dev/null | grep -i 'maximum number' | cut -d: -f2 | tr -d ' ')"
check_eq -p "warning period is 10 days" "10" \
  "$(chage -l fin1 2>/dev/null | grep -i 'number of days of warning' | cut -d: -f2 | tr -d ' ')"

section "5. /srv/finance shared directory"
check_dir "/srv/finance exists" /srv/finance
check_match "group-owned by finance" '^finance$' stat -c %G /srv/finance
check -p "SGID and sticky bits are both set" sticky_and_sgid /srv/finance
check "group-writable" group_writable /srv/finance

section "6. auditor's read-only ACL"
if need_cmd "ACL checks" getfacl; then
  check "auditor exists" user_exists auditor
  check -p "read-only ACL for auditor, inherited by new files" \
    acl_inherits_for /srv/finance auditor 'r--'
  check "auditor was NOT added to the finance group" \
    bash -c '! id -nG auditor 2>/dev/null | tr " " "\n" | grep -qx finance'
fi

section "7. /finance — 3 GB XFS, by UUID, nodev"
check "/finance is mounted" findmnt /finance
check_eq "it is XFS" "xfs" "$(mount_fstype /finance)"
check_sh "it is about 3 GB" "approx '$(df_gib /finance)' 3 0.4"
check -p "mounted from a UUID entry in /etc/fstab" fstab_by_uuid /finance
check_match -p "nodev is in force" '(^|,)nodev(,|$)' bash -c 'findmnt -no OPTIONS /finance'

section "8. 1 GB of persistent swap"
check -p "1 GB of swap is active and in /etc/fstab" swap_1g_persistent

section "9. vgapp, /appdata extended to 5 GB"
check "volume group vgapp exists" vgs vgapp
check "its extent size is 32 MB" vg_extent_32m
check "/appdata is mounted" findmnt /appdata
check "/appdata is about 5 GB after the extension" appdata_is_5g
check "the filesystem was grown, not just the LV" fs_grown_to_lv
check -p "/appdata has an /etc/fstab entry" bash -c 'fstab_line /appdata | grep -q .'

section "10. httpd serving /finance/www with SELinux enforcing"
check "httpd is installed" rpm -q httpd
check -p "httpd is enabled" systemctl is-enabled --quiet httpd
check "httpd is active" systemctl is-active --quiet httpd
check_eq "SELinux is Enforcing" "Enforcing" "$(getenforce)"
check "it serves from /finance/www" httpd_serves_finance_www
if command -v semanage >/dev/null; then
  check -p "the label survives a relabel (policy, not chcon)" \
    bash -c 'out=$(restorecon -Rvn /finance/www 2>&1); [[ -z ${out// /} ]]'
fi

section "11. http open in the firewall"
if need_cmd "firewall checks" firewall-cmd; then
  check -p "http is open at runtime" bash -c 'firewall-cmd --list-services | grep -qw http'
  check -p "http is open permanently" bash -c 'firewall-cmd --permanent --list-services | grep -qw http'
fi

section "12. A daily 03:00 timer for audit.sh"
check_file "/usr/local/bin/audit.sh exists" /usr/local/bin/audit.sh
T=$(find_audit_timer || true)
if [[ -n ${T:-} ]]; then
  info "timer: $T"
  check -p "the timer is enabled" systemctl is-enabled --quiet "$T"
  check_match -p "OnCalendar fires at 03:00" '03:00' bash -c "systemctl cat $T"
  check_match -p "Persistent=true" 'Persistent[[:space:]]*=[[:space:]]*(true|yes|1)' bash -c "systemctl cat $T"
else
  fail "a timer runs /usr/local/bin/audit.sh daily" "no .timer unit references audit.sh"
fi

section "13. Journal persistent and capped at 300 MB"
check_dir -p "/var/log/journal exists" /var/log/journal
check_eq -p "Storage=persistent" "persistent" "$(jconf Storage)"
check_eq -p "SystemMaxUse=300M" "300M" "$(jconf SystemMaxUse)"

section "14. fin2 denied cron"
check -p "fin2 is refused by cron" cron_denied fin2

section "15. Root password reset from GRUB"
check "no relabel is left pending" bash -c '[[ ! -f /.autorelabel ]]'
check "SELinux labels under /etc are correct afterwards" \
  bash -c 'out=$(restorecon -Rvn /etc 2>&1 | head -3); [[ -z ${out// /} ]]'
manual "You reset the root password from the GRUB prompt" \
  "The two checks above catch the classic follow-on mistake."

summary
