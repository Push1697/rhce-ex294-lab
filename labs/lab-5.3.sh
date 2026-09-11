#!/usr/bin/env bash
# Lab 5.3 — Your first playbook: web.yml            (04-Labs-Ansible-Fundamentals)
# Run on rhel-control, as the ordinary user.
# This one RUNS your playbook, twice, because idempotence is the requirement.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=web.yml

index_names_the_host() {
  local h ip body bad=0
  for h in $(a_hosts_in web); do
    body=$(ansible "$h" -m command -a 'cat /var/www/html/index.html' --become 2>&1)
    ip=$(ansible "$h" -m debug -a 'var=ansible_default_ipv4.address' 2>/dev/null |
         sed -n 's/.*"\(.*\)"$/\1/p' | tail -1)
    echo "--- $h (ip $ip)"
    echo "$body" | grep -vE 'CHANGED|SUCCESS|=>|^\}|^\{|rc=' | head -3
    grep -q "$h" <<<"$body" || { echo "$h: the page does not name the host"; bad=1; }
    [[ -n ${ip:-} ]] && { grep -q "$ip" <<<"$body" || { echo "$h: the page does not carry its IP"; bad=1; }; }
  done
  return $bad
}

serves_over_http() {
  local h bad=0 body
  for h in $(a_hosts_in web); do
    body=$(ansible "$h" -m uri -a "url=http://$h/ return_content=true status_code=200" 2>&1)
    grep -q 'status.*200\|SUCCESS' <<<"$body" || { echo "$h did not answer with 200"; bad=1; }
    grep -q "$h" <<<"$body" || { echo "$h served a page that does not name it"; bad=1; }
  done
  return $bad
}

# ------------------------------------------------------------------------------
lab_init "5.3" "Your first playbook — web.yml" --host rhel-control "$@"
a_init

section "1. The playbook exists and parses"
check_file "$PB exists" "$A_PROJ/$PB"
check "it is valid YAML" a_yaml_ok "$PB"
check "ansible-playbook --syntax-check passes" ansible-playbook --syntax-check "$PB"

section "2. It uses real modules, not command/shell"
check "no command, shell or raw module anywhere in it" a_uses_no_shell "$PB"
check "it installs packages with the dnf/package module" \
  bash -c "grep -qE '(dnf|package|yum):' $PB"
check "it manages services with the service/systemd module" \
  bash -c "grep -qE '(service|systemd|systemd_service):' $PB"
check "it manages the firewall with the firewalld module" \
  bash -c "grep -q 'firewalld' $PB"

section "3. --check runs clean against a configured host"
check "ansible-playbook --check reports no failures" \
  bash -c "out=\$(ansible-playbook --check $PB 2>&1); echo \"\$out\" | tail -6;
           ! grep -qE 'failed=[1-9]|fatal:' <<<\"\$out\""

section "4. A real run succeeds"
check "the playbook runs without failures" a_playbook_ok "$PB"

section "5. The second run changes nothing"
check "a repeat run reports changed=0 on every host" a_idempotent "$PB"
info "This is the single most-tested property in EX294."

section "6. The result on the web group"
check "httpd is enabled on every host in web" \
  bash -c 'out=$(ansible web -m command -a "systemctl is-enabled httpd" 2>&1); echo "$out" | tail -4;
           ! grep -qE "disabled|FAILED" <<<"$out"'
check "the index page names the host and carries its IP, from facts" index_names_the_host
check "each host answers over HTTP with its own page" serves_over_http
check "http is permitted through the firewall" \
  bash -c 'out=$(ansible web -m command -a "firewall-cmd --list-services" --become 2>&1);
           echo "$out" | tail -4; grep -q http <<<"$out"'

summary
