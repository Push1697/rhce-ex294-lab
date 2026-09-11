#!/usr/bin/env bash
# Mock EX200-B — grader                             (03-EX200-Exam-Prep, Day 27)
# Run on rhel01, as root, AFTER the reboot.
#
#   ./mock-ex200-b.sh --spec              print the exam paper (pinned values)
#   sudo ./mock-ex200-b.sh                grade it
#   sudo ./mock-ex200-b.sh --labuser=amit which user owns the rootless container
#
# Mock EX200-C is this same paper run on a box you have first wrecked with
# `break.sh all` — grade it with this script plus breakfix-health.sh.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

if [[ ${1:-} == --spec ]]; then
  cat <<'SPEC'
Mock EX200-B — 2.5 hours, closed book, rhel01 reverted to `clean` first.
Graded after a reboot. The grader pins the values below, so build exactly these.

 1. A repository named `locallab` from the local directory /repo, gpgcheck off,
    and a package installed from it.
 2. Three users: `ops1` with UID 3101, `ops2`, and `svc1` with UID 3199 and no
    interactive shell.
 3. /srv/shared — every new file created there is group-owned by `developers`
    automatically.
 4. A default ACL on /srv/shared giving user `qa1` write access to new files.
 5. Volume group `vgdata` on a blank disk; logical volume `lvapp`, XFS, mounted
    at /app; extended by 2 GB to 6 GB with the filesystem grown online.
 6. Logical volume `lvlogs`, ext4, mounted at /applogs, reduced to 1 GB safely.
 7. rhel02 exports /srv/share; rhel01 mounts it persistently at /mnt/share.
 8. autofs mounts rhel02:/srv/share at /net/data on demand, 60-second timeout.
 9. A rootless container serving a page on port 8080 from /opt/webdata,
    auto-started at boot via a systemd --user unit with lingering enabled.
10. sshd moved to port 2222, with SELinux enforcing and the firewall open.
11. Every SUID file on the system listed in /root/reports/suid.txt.
12. /usr/local/bin/unitcheck — exits non-zero when any systemd unit has failed.
13. The tuned profile `virtual-guest`, set persistently.
14. A non-default kernel set as the permanent default.
15. /etc/fstab arranged so a failed mount does not prevent the machine booting.
SPEC
  exit 0
fi

LABUSER=""
for a in "$@"; do case "$a" in --labuser=*) LABUSER=${a#--labuser=} ;; esac; done
if [[ -z ${LABUSER:-} ]]; then
  LABUSER=$(awk -F: '$3 >= 1000 && $3 < 65534 && $6 ~ /^\/home\// { print $1; exit }' /etc/passwd)
fi

# ------------------------------------------------------------------ helpers ---
local_repo_used() {
  local rpm name
  rpm=$(find /repo -maxdepth 2 -name '*.rpm' -print -quit 2>/dev/null)
  [[ -n ${rpm:-} ]] || { echo "no .rpm under /repo"; return 1; }
  name=$(rpm -qp --qf '%{NAME}\n' "$rpm" 2>/dev/null)
  echo "package in /repo: ${name:-?}"
  rpm -q "$name" >/dev/null 2>&1
}

group_inherited_in() {
  local d="$1" g="$2" f="$d/.verify-sgid-$$" got
  touch "$f" 2>/dev/null || { echo "could not create a file in $d"; return 1; }
  got=$(stat -c %G "$f"); rm -f "$f"
  echo "a new file in $d is group-owned by '$got'"
  [[ $got == "$g" ]]
}

default_acl_write_for() {
  local d="$1" u="$2" f="$d/.verify-acl-$$" rc=0
  getfacl -p --absolute-names "$d" 2>/dev/null | grep -Eq "^default:user:$u:rw" ||
    { echo "no default ACL giving $u write access on $d"; rc=1; }
  if ((V_MUTATE)); then
    touch "$f" 2>/dev/null || return 1
    getfacl -p --absolute-names "$f" 2>/dev/null | grep -Eq "^user:$u:rw" ||
      { echo "a new file did not inherit write access for $u"; rc=1; }
    rm -f "$f"
  fi
  return $rc
}

fs_fills_lv() {
  local mnt="$1" src lvb fsb
  src=$(mount_src "$mnt")
  lvb=$(lvs --noheadings --units b --nosuffix -o lv_size "$src" 2>/dev/null | tr -d ' ')
  fsb=$(df -B1 --output=size "$mnt" 2>/dev/null | tail -1 | tr -d ' ')
  echo "LV ${lvb:-?} bytes, filesystem ${fsb:-?} bytes"
  [[ -n ${lvb:-} && -n ${fsb:-} ]] && awk -v l="$lvb" -v f="$fsb" 'BEGIN { exit !(f > l * 0.9) }'
}

rootless_container_running() {
  local out
  out=$(runuser -u "$LABUSER" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$LABUSER")" \
        podman ps --format '{{.Names}} {{.Ports}}' 2>&1)
  echo "${out:-<nothing>}"
  grep -q '8080' <<<"$out"
}

linger_on() {
  local l
  l=$(loginctl show-user "$LABUSER" -p Linger --value 2>/dev/null)
  echo "Linger=${l:-<unknown>} for $LABUSER"
  [[ $l == yes ]]
}

user_unit_enabled() {
  local out
  out=$(runuser -u "$LABUSER" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$LABUSER")" \
        systemctl --user list-unit-files --no-legend 2>&1 | grep -E 'container|podman')
  echo "${out:-<no container user units>}"
  grep -q 'enabled' <<<"$out"
}

suid_list_correct() {
  local f=/root/reports/suid.txt p bad=0 n
  [[ -s $f ]] || { echo "$f is missing or empty"; return 1; }
  grep -qx '/usr/bin/passwd' "$f" || { echo "/usr/bin/passwd is not listed"; bad=1; }
  grep -qx '/usr/bin/sudo' "$f" || { echo "/usr/bin/sudo is not listed"; bad=1; }
  while read -r p; do
    [[ -n ${p// /} ]] || continue
    [[ -u $p ]] || { echo "listed but not SUID: $p"; bad=1; }
  done < "$f"
  n=$(grep -c . "$f"); echo "$n entries"
  return $bad
}

unitcheck_detects_failure() {
  local u=verify-mockb-fail.service rc
  cat > "/etc/systemd/system/$u" <<'UNIT'
[Unit]
Description=deliberately failing unit, created by the mock grader
[Service]
Type=oneshot
ExecStart=/bin/false
UNIT
  systemctl daemon-reload
  systemctl start "$u" >/dev/null 2>&1
  /usr/local/bin/unitcheck >/dev/null 2>&1; rc=$?
  echo "unitcheck exited $rc with a failed unit present"
  systemctl reset-failed "$u" >/dev/null 2>&1
  rm -f "/etc/systemd/system/$u"; systemctl daemon-reload
  ((rc != 0))
}

default_kernel_not_newest() {
  local def newest
  def=$(grubby --default-kernel 2>/dev/null)
  newest=$(ls -1t /boot/vmlinuz-* 2>/dev/null | head -1)
  echo "default: ${def:-?} / newest: ${newest:-?}"
  [[ -n ${def:-} && $def != "$newest" ]]
}

nofail_present() {
  local line
  line=$(awk '$1 !~ /^#/ && $4 ~ /nofail/ { print }' /etc/fstab)
  echo "${line:-<no entry carries nofail>}"
  [[ -n ${line// /} ]]
}

# ------------------------------------------------------------------------------
lab_init "ex200-b" "Mock EX200-B" --host rhel01 --root --score "$@"
info "rootless-container tasks are graded against user: ${LABUSER:-<none found>}"

section "1. The local repository"
check -p "locallab is enabled" bash -c 'dnf repolist enabled 2>/dev/null | grep -q locallab'
check "its baseurl is file:///repo" bash -c "grep -rq 'baseurl[[:space:]]*=[[:space:]]*file:///repo' /etc/yum.repos.d/"
check "a package from /repo is installed" local_repo_used

section "2. Three users from a spec"
check "ops1 exists" user_exists ops1
check_eq "ops1 has UID 3101" 3101 "$(user_uid ops1)"
check "ops2 exists" user_exists ops2
check "svc1 exists" user_exists svc1
check_eq "svc1 has UID 3199" 3199 "$(user_uid svc1)"
s=$(user_shell svc1)
check_sh "svc1 has no interactive shell (${s:-none})" "[[ '$s' == */nologin || '$s' == */false ]]"

section "3. Automatic group ownership in /srv/shared"
check_dir "/srv/shared exists" /srv/shared
check -p "SGID is set" sgid_set /srv/shared
check_match "group-owned by developers" '^developers$' stat -c %G /srv/shared
if mutating "new files are group-owned by developers"; then
  check "new files are group-owned by developers" group_inherited_in /srv/shared developers
fi

section "4. Default ACL giving qa1 write access"
if need_cmd "ACL checks" getfacl; then
  check "qa1 exists" user_exists qa1
  check -p "a default ACL grants qa1 write access to new files" default_acl_write_for /srv/shared qa1
fi

section "5. lvapp extended to 6 GB, grown online"
check "volume group vgdata exists" vgs vgdata
check "logical volume lvapp exists" lvs vgdata/lvapp
check "/app is mounted" findmnt /app
check_eq "/app is XFS" "xfs" "$(mount_fstype /app)"
check_sh "/app is about 6 GB" "approx '$(df_gib /app)' 6 0.5"
check "the filesystem was grown to match the LV" fs_fills_lv /app
check -p "/app has an /etc/fstab entry" bash -c 'fstab_line /app | grep -q .'

section "6. lvlogs reduced to 1 GB"
check "logical volume lvlogs exists" lvs vgdata/lvlogs
check "/applogs is still mounted" findmnt /applogs
check_eq "/applogs is ext4" "ext4" "$(mount_fstype /applogs)"
check_sh "/applogs is about 1 GB" "approx '$(df_gib /applogs)' 1 0.3"
check "the filesystem was resized too, not just the LV" fs_fills_lv /applogs
check -p "/applogs has an /etc/fstab entry" bash -c 'fstab_line /applogs | grep -q .'

section "7. NFS mount from rhel02"
check "rhel02 offers /srv/share" bash -c 'showmount -e rhel02 2>/dev/null | grep -q /srv/share'
check "/mnt/share is mounted" findmnt /mnt/share
check_match "it is an NFS mount" '^nfs' bash -c 'findmnt -no FSTYPE /mnt/share'
check -p "there is an /etc/fstab entry for it" bash -c 'fstab_line /mnt/share | grep -q .'

section "8. autofs at /net/data with a 60-second timeout"
check -p "autofs is enabled" systemctl is-enabled --quiet autofs
check "autofs is running" systemctl is-active --quiet autofs
check -p "a map references /srv/share" bash -c "grep -rq '/srv/share' /etc/auto.* 2>/dev/null"
check "accessing /net/data triggers a mount" \
  bash -c 'ls /net/data >/dev/null 2>&1 && findmnt /net/data >/dev/null'
check -p "a 60-second timeout is configured" \
  bash -c "grep -rhE 'timeout[= ]+60|--timeout[= ]?60' /etc/auto.master /etc/auto.master.d/ /etc/autofs.conf 2>/dev/null | grep -q ."

section "9. Rootless container on 8080, auto-started at boot"
if [[ -n ${LABUSER:-} ]]; then
  check_dir "/opt/webdata exists" /opt/webdata
  check "a rootless container publishes 8080" rootless_container_running
  check "curl localhost:8080 answers" bash -c 'curl -sf --max-time 5 http://localhost:8080/ >/dev/null'
  check -p "lingering is enabled for $LABUSER" linger_on
  check -p "an enabled systemd --user unit runs it" user_unit_enabled
  check -p "/opt/webdata carries container_file_t" \
    bash -c '[[ $(selinux_type /opt/webdata) == container_file_t ]]'
else
  fail "rootless container tasks" "no ordinary user found — pass --labuser=NAME"
fi

section "10. sshd on 2222 with SELinux and the firewall"
check_match -p "sshd is configured for port 2222" '^port 2222' bash -c 'sshd -T'
check "something is listening on 2222" bash -c 'ss -tlnH | awk "{print \$4}" | grep -Eq "[:.]2222$"'
check_eq "SELinux is Enforcing" "Enforcing" "$(getenforce)"
if command -v semanage >/dev/null; then
  check -p "2222 is labelled ssh_port_t" \
    bash -c 'semanage port -l | grep "^ssh_port_t" | grep -qE "(^|[^0-9])2222([^0-9]|$)"'
fi
check -p "2222/tcp is open permanently" \
  bash -c 'firewall-cmd --permanent --list-ports 2>/dev/null | grep -q 2222/tcp'

section "11. The SUID inventory"
check "/root/reports/suid.txt is correct and complete" suid_list_correct

section "12. /usr/local/bin/unitcheck"
check_file "the script exists" /usr/local/bin/unitcheck
check_sh "it is executable" '[[ -x /usr/local/bin/unitcheck ]]'
check "it exits 0 on a healthy box" \
  bash -c 'n=$(systemctl list-units --state=failed --no-legend --plain | grep -c .);
           if [[ ${n:-0} -eq 0 ]]; then /usr/local/bin/unitcheck >/dev/null 2>&1; else true; fi'
if mutating "it exits non-zero when a unit has failed"; then
  check "it exits non-zero when a unit has failed" unitcheck_detects_failure
fi

section "13. tuned profile set persistently"
if need_cmd "tuned checks" tuned-adm; then
  check_eq -p "the active profile is virtual-guest" "virtual-guest" \
    "$(tuned-adm active 2>/dev/null | sed 's/.*: //')"
  check -p "tuned is enabled at boot" systemctl is-enabled --quiet tuned
fi

section "14. A non-default kernel made permanent"
if [[ $(ls -1 /boot/vmlinuz-* 2>/dev/null | wc -l) -lt 2 ]]; then
  fail "a non-default kernel is the permanent default" "only one kernel is installed"
else
  check -p "the default kernel is not the newest installed one" default_kernel_not_newest
  check "the machine booted the kernel grubby calls the default" \
    bash -c 'grubby --default-kernel 2>/dev/null | grep -q "$(uname -r)"'
fi

section "15. A failed mount must not prevent boot"
check -p "at least one fstab entry carries nofail" nofail_present
check "findmnt --verify still passes" findmnt --verify
check "the system booted cleanly this time" \
  bash -c '[[ $(systemctl is-system-running 2>/dev/null) =~ ^(running|degraded)$ ]]'

summary
