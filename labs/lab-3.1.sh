#!/usr/bin/env bash
# Lab 3.1 — SELinux contexts, booleans, ports       (02-Labs-Security-and-Breakfix)
# Run on rhel01, as root.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

WEB=/web/site

# The decisive test: a dry-run relabel must find nothing to change. If it wants
# to change something, the policy is wrong and chcon was used instead.
relabel_is_a_no_op() {
  local out
  out=$(restorecon -Rvn /web 2>&1)
  [[ -z ${out//[[:space:]]/} ]] && return 0
  echo "restorecon -Rvn wants to change:"
  echo "$out" | head -5
  return 1
}

fcontext_rule_exists() {
  semanage fcontext -l 2>/dev/null | grep -E '^/web' | grep -q 'httpd_sys_content_t'
}

curl_serves_from_web() {
  local body file
  body=$(curl -s --max-time 5 http://localhost/ 2>&1)
  file=$(find "$WEB" -maxdepth 1 -name 'index.htm*' -print -quit 2>/dev/null)
  [[ -n ${file:-} ]] || { echo "no index file under $WEB"; return 1; }
  echo "served: ${body:0:80}"
  echo "on disk: $(head -c 80 "$file")"
  [[ -n ${body// /} ]] && diff <(printf '%s' "$body") <(cat "$file") >/dev/null 2>&1
}

boolean_on_persistently() {   # boolean_on_persistently <name>
  local runtime persisted
  runtime=$(getsebool "$1" 2>/dev/null | awk '{print $3}')
  persisted=$(bool_persist "$1")
  echo "$1: runtime=$runtime persisted=${persisted:-?}"
  [[ $runtime == on && $persisted == on ]]
}

# ------------------------------------------------------------------------------
lab_init "3.1" "SELinux contexts, booleans, ports" --host rhel01 --root "$@"

section "1. SELinux is enforcing, now and after reboot"
check_eq "getenforce reports Enforcing" "Enforcing" "$(getenforce 2>/dev/null)"
check_match -p "/etc/selinux/config also says enforcing" '^SELINUX=enforcing' \
  grep '^SELINUX=' /etc/selinux/config

section "2. Apache serves /web/site with SELinux enforcing"
check_dir "$WEB exists" "$WEB"
check "httpd is running" systemctl is-active --quiet httpd
check_match "DocumentRoot points at $WEB" "$WEB" \
  bash -c 'httpd -S 2>/dev/null | grep -i "root"; grep -hE "^[[:space:]]*DocumentRoot" /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/*.conf 2>/dev/null'
check "curl http://localhost returns the file from $WEB" curl_serves_from_web
check_eq "$WEB is labelled httpd_sys_content_t" "httpd_sys_content_t" "$(selinux_type "$WEB")"

section "3. The fix is policy, not chcon"
if need_cmd "policy checks" semanage; then
  check -p "an fcontext rule exists for /web(/.*)?" fcontext_rule_exists
  check -p "restorecon -Rvn /web is a no-op — the label survives a relabel" relabel_is_a_no_op
  info "This is the check that separates semanage fcontext from chcon."
fi

section "4. Apache may connect out to a database"
check -p "httpd_can_network_connect is on, persistently" \
  boolean_on_persistently httpd_can_network_connect

section "5. Apache may serve content from NFS"
check -p "httpd_use_nfs is on, persistently" boolean_on_persistently httpd_use_nfs

section "6. sshd on port 2222 with SELinux enforcing"
if need_cmd "port label checks" semanage; then
  check_match -p "2222 is labelled ssh_port_t" '(^|[^0-9])2222([^0-9]|$)' \
    bash -c 'semanage port -l | grep "^ssh_port_t"'
fi
check_match "sshd is actually configured for 2222" '^port 2222' bash -c 'sshd -T'
check "sshd is running" systemctl is-active --quiet sshd

section "7. No denials are being generated right now"
if need_cmd "audit log search" ausearch; then
  check "no AVC denials in the recent audit log" \
    bash -c 'out=$(ausearch -m AVC -ts recent 2>/dev/null | grep -c "denied"); [[ ${out:-0} -eq 0 ]]'
  report "most recent denials, if any" \
    bash -c 'ausearch -m AVC -ts today 2>/dev/null | grep denied | tail -3'
fi

summary
