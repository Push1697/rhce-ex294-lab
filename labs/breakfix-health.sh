#!/usr/bin/env bash
# Break-fix health check — Days 19–21               (02-Labs-Security-and-Breakfix)
# Run on rhel01, as root, after repairing a fault from break.sh.
#
# One section per fault that break.sh can inject, so a repair that fixed the
# symptom but left a second fault behind shows up immediately. Run it BEFORE
# you reboot and again AFTER — a repair that does not survive the reboot is not
# a repair.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

# --- fstab / mount ------------------------------------------------------------
fstab_all_resolves() {
  local u bad=0
  while read -r u; do
    [[ -n ${u// /} ]] || continue
    blkid -U "$u" >/dev/null 2>&1 || { echo "no device carries UUID $u"; bad=1; }
  done < <(awk '$1 ~ /^UUID=/ && $1 !~ /^#/ { sub(/^UUID=/, "", $1); print $1 }' /etc/fstab)
  return $bad
}

expected_mounts_present() {
  local m bad=0
  for m in /data /app /applogs; do
    grep -qE "^[^#].*[[:space:]]$m[[:space:]]" /etc/fstab 2>/dev/null || continue
    findmnt "$m" >/dev/null 2>&1 || { echo "$m is in fstab but not mounted"; bad=1; }
  done
  return $bad
}

commented_out_mounts() {
  local c
  c=$(grep -nE '^#[^#]*[[:space:]](/data|/app|/applogs)[[:space:]]' /etc/fstab 2>/dev/null)
  [[ -z ${c// /} ]] && return 0
  echo "these mounts have been commented out of /etc/fstab:"
  echo "$c"
  return 1
}

# --- SELinux -----------------------------------------------------------------
no_denials() {
  local n
  n=$(ausearch -m AVC -ts recent 2>/dev/null | grep -c denied)
  echo "AVC denials in the recent log: ${n:-0}"
  [[ ${n:-0} -eq 0 ]]
}

web_labels_correct() {
  [[ -d /web ]] || { echo "/web does not exist on this box"; return 2; }
  local out
  out=$(restorecon -Rvn /web 2>&1)
  [[ -z ${out//[[:space:]]/} ]] && return 0
  echo "$out" | head -5
  return 1
}

ssh_port_labelled() {
  local ports p
  ports=$(sshd -T 2>/dev/null | awk '/^port /{print $2}')
  for p in $ports; do
    [[ $p == 22 ]] && continue
    semanage port -l 2>/dev/null | grep '^ssh_port_t' | grep -qE "(^|[^0-9])$p([^0-9]|$)" || {
      echo "sshd listens on $p but $p is not labelled ssh_port_t"; return 1; }
  done
  return 0
}

# --- services / firewall -----------------------------------------------------
httpd_config_valid() { httpd -t; }

listeners_are_reachable() {
  local p bad=0
  for p in $(sshd -T 2>/dev/null | awk '/^port /{print $2}'); do
    firewall-cmd --list-ports 2>/dev/null | grep -q "$p/tcp" ||
      firewall-cmd --list-services 2>/dev/null | grep -qw ssh ||
      { echo "port $p is not open in the firewall"; bad=1; }
  done
  return $bad
}

http_open_if_running() {
  systemctl is-active --quiet httpd || { echo "httpd is not running"; return 2; }
  firewall-cmd --list-services 2>/dev/null | grep -qw http ||
    firewall-cmd --list-ports 2>/dev/null | grep -q '80/tcp'
}

# --- ssh key permissions -----------------------------------------------------
ssh_dir_perms_sane() {
  local h u bad=0
  while IFS=: read -r u _ uid _ _ h _; do
    ((uid >= 1000 && uid < 65534)) || continue
    [[ -d $h/.ssh ]] || continue
    local dm km
    dm=$(mode_of "$h/.ssh")
    [[ $dm == 700 ]] || { echo "$h/.ssh is mode $dm, must be 700"; bad=1; }
    if [[ -f $h/.ssh/authorized_keys ]]; then
      km=$(mode_of "$h/.ssh/authorized_keys")
      [[ $km == 600 || $km == 644 ]] || { echo "$h/.ssh/authorized_keys is mode $km"; bad=1; }
    fi
  done < /etc/passwd
  return $bad
}

# --- dnf ---------------------------------------------------------------------
all_repos_reachable() {
  local out
  out=$(dnf repolist --enabled 2>&1)
  grep -Eqi 'cannot|error|failure|Failed to' <<<"$out" && { echo "$out" | tail -6; return 1; }
  dnf -q makecache --refresh >/dev/null 2>&1 || {
    echo "dnf makecache failed:"; dnf makecache --refresh 2>&1 | tail -5; return 1; }
  return 0
}

# --- dns ---------------------------------------------------------------------
resolution_works() {
  local bad=0 h
  for h in rhel01 rhel02; do
    getent hosts "$h" >/dev/null 2>&1 || { echo "cannot resolve $h"; bad=1; }
  done
  return $bad
}

dns_servers_answer() {
  local s ok=0
  for s in $(awk '/^nameserver/ { print $2 }' /etc/resolv.conf 2>/dev/null); do
    if command -v dig >/dev/null 2>&1; then
      dig +time=2 +tries=1 @"$s" redhat.com >/dev/null 2>&1 && ok=1
    else
      ping -c1 -W2 "$s" >/dev/null 2>&1 && ok=1
    fi
    echo "nameserver $s: $( ((ok)) && echo responds || echo silent)"
  done
  ((ok))
}

# --- sudo --------------------------------------------------------------------
wheel_still_has_sudo() {
  grep -Eq '^[[:space:]]*%wheel' /etc/sudoers /etc/sudoers.d/* 2>/dev/null
}

# ------------------------------------------------------------------------------
lab_init "breakfix" "Break-fix health check" --host rhel01 --root "$@"

section "fstab — the box mounts everything it claims to"
check "findmnt --verify passes" findmnt --verify
check "every UUID in /etc/fstab resolves to a real device" fstab_all_resolves
check "everything listed in fstab is actually mounted" expected_mounts_present
check "no lab mount has been commented out" commented_out_mounts
check "mount -a is silent" bash -c 'out=$(mount -a 2>&1); [[ -z ${out// /} ]]'

section "selinux_ctx — labels are right, and enforcing"
check_eq "SELinux is Enforcing" "Enforcing" "$(getenforce 2>/dev/null)"
check_match "config agrees, so it stays enforcing" '^SELINUX=enforcing' grep '^SELINUX=' /etc/selinux/config
check "no recent AVC denials" no_denials
web_labels_correct; rc=$?
case $rc in
  0) pass "a dry-run relabel of /web changes nothing" ;;
  2) skipped "/web labels" "no /web directory on this box" ;;
  *) fail "a dry-run relabel of /web changes nothing" "chcon was used, or the label is wrong" ;;
esac

section "selinux_port — every sshd port is labelled"
if need_cmd "port label checks" semanage; then
  check "each port sshd listens on is labelled ssh_port_t" ssh_port_labelled
fi
check "sshd is running" systemctl is-active --quiet sshd

section "service — units start and configs parse"
check "no systemd unit is in a failed state" \
  bash -c 'n=$(systemctl list-units --state=failed --no-legend --plain | grep -c .); [[ ${n:-0} -eq 0 ]]'
if rpm -q httpd >/dev/null 2>&1; then
  check "httpd's configuration parses" httpd_config_valid
  check "httpd is running" systemctl is-active --quiet httpd
fi
report "failed units, if any" bash -c 'systemctl --failed --no-legend --plain'

section "firewall — services that run are reachable"
if need_cmd "firewall checks" firewall-cmd; then
  check "firewalld is running" systemctl is-active --quiet firewalld
  check "sshd's ports are open" listeners_are_reachable
  http_open_if_running; rc=$?
  case $rc in
    0) pass "http is open while httpd is running" ;;
    2) skipped "http firewall rule" "httpd is not running" ;;
    *) fail "http is open while httpd is running" "the service is up but nothing can reach it" ;;
  esac
  check "runtime and permanent firewall configs agree" \
    bash -c 'diff <(firewall-cmd --list-all) <(firewall-cmd --permanent --list-all) >/dev/null'
fi

section "perms — SSH key authentication is not silently broken"
check "every user's ~/.ssh permissions are sane" ssh_dir_perms_sane
check_match "sshd still accepts public keys" '^pubkeyauthentication yes' bash -c 'sshd -T'

section "repo — dnf works"
check "every enabled repository is reachable" all_repos_reachable

section "dns — names resolve"
check "rhel01 and rhel02 resolve" resolution_works
check "at least one configured nameserver answers" dns_servers_answer
report "resolver configuration" bash -c 'cat /etc/resolv.conf | grep -v "^#"'

section "sudo — privilege escalation still works"
check "sudoers syntax is valid" visudo -c
check "the wheel group rule has not been commented out" wheel_still_has_sudo
check "root can still be reached via sudo from a wheel member" \
  bash -c 'u=$(getent group wheel | cut -d: -f4 | cut -d, -f1); [[ -z $u ]] && exit 0;
           sudo -n -l -U "$u" 2>/dev/null | grep -q "may run"'

section "The drill itself"
manual "You reproduced the fault before fixing it" \
  "Never fix what you cannot reproduce — that is the rule for this week."
manual "Your first hypothesis was the right one" \
  "Record it in the fault-log table in 02-Labs-Security-and-Breakfix."
manual "Under 10 minutes, closed-book" \
  "That is the Day 21 target. Time yourself honestly."

summary
