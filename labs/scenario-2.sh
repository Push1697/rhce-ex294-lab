#!/usr/bin/env bash
# Scenario 2 — Web tier, end to end (Day 53)       (07-Scenario-Labs)
# Run on rhel-control, as the ordinary user.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=""
for a in "$@"; do case "$a" in --pb=*) PB=${a#--pb=} ;; esac; done
for c in ${PB:-} web.yml site.yml webserver.yml; do [[ -f $c ]] && { PB=$c; break; }; done

web_hosts() { a_hosts_in web; }

on_web() { ansible web -m shell -a "$*" --become 2>&1; }

apache_on_web_only() {
  local bad=0 h
  for h in $(web_hosts); do
    ansible "$h" -m command -a 'systemctl is-active httpd' 2>&1 | grep -q '^active' ||
      { echo "$h: httpd is not active"; bad=1; }
    ansible "$h" -m command -a 'systemctl is-enabled httpd' 2>&1 | grep -q '^enabled' ||
      { echo "$h: httpd is not enabled"; bad=1; }
  done
  for h in $(a_hosts_in all); do
    a_group_has web "$h" && continue
    ansible "$h" -m command -a 'rpm -q httpd' 2>&1 | grep -q 'not installed' ||
      { echo "$h is not in web but has httpd installed"; bad=1; }
  done
  return $bad
}

docroot_is_web_site() {
  local out
  out=$(on_web 'httpd -S 2>/dev/null | grep -i "root\|port" ; grep -rhE "^\s*DocumentRoot" /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/*.conf 2>/dev/null')
  echo "$out" | grep -iE 'documentroot|port' | head -8
  grep -q '/web/site' <<<"$out"
}

relabel_noop() {
  local out
  out=$(on_web 'restorecon -Rvn /web')
  local rel
  rel=$(grep -i relabel <<<"$out")
  [[ -z ${rel// /} ]] && { echo "no relabelling needed — the policy is right"; return 0; }
  echo "$rel" | head -5
  return 1
}

context_from_policy_not_chcon() {
  local out
  out=$(on_web 'semanage fcontext -l | grep "^/web"')
  echo "$out" | grep '/web' | head -4
  grep -q 'httpd_sys_content_t' <<<"$out"
}

serves_on_both_ports() {
  local bad=0 h b80 b8080
  for h in $(web_hosts); do
    b80=$(ansible "$h" -m uri -a "url=http://$h/ return_content=true status_code=200" 2>&1)
    b8080=$(ansible "$h" -m uri -a "url=http://$h:8080/ return_content=true status_code=200" 2>&1)
    grep -q "$h" <<<"$b80" || { echo "$h: port 80 does not serve a page naming the host"; bad=1; }
    grep -qE 'SUCCESS|status.*200' <<<"$b8080" || { echo "$h: port 8080 did not answer 200"; bad=1; }
  done
  return $bad
}

selinux_port_8080() {
  local out
  out=$(on_web 'semanage port -l | grep ^http_port_t')
  echo "$out" | grep http_port_t | head -3
  grep -qE '(^|[^0-9])8080([^0-9]|$)' <<<"$out"
}

firewall_http_https_permanent() {
  local out bad=0
  out=$(on_web 'firewall-cmd --permanent --list-services')
  echo "$out" | grep -vE 'CHANGED|SUCCESS|=>' | head -6
  grep -qw http <<<"$out" || { echo "http is not permanently open"; bad=1; }
  grep -qw https <<<"$out" || { echo "https is not permanently open"; bad=1; }
  return $bad
}

handler_only_on_change() {
  a_run "$PB" >/dev/null 2>&1
  a_no_handlers_fired || { grep -A2 'RUNNING HANDLER' <<<"$A_LAST_RUN" | head -5; return 1; }
  echo "no handler fired on an unchanged run"
  return 0
}

index_from_facts() {
  local bad=0 h ip body
  for h in $(web_hosts); do
    ip=$(ansible "$h" -m debug -a 'var=ansible_default_ipv4.address' 2>/dev/null |
         sed -n 's/.*"\(.*\)"$/\1/p' | tail -1)
    body=$(ansible "$h" -m command -a 'cat /web/site/index.html' --become 2>&1)
    grep -q "$h" <<<"$body" || { echo "$h: the page does not name the host"; bad=1; }
    [[ -n ${ip:-} ]] && { grep -q "$ip" <<<"$body" || { echo "$h: the page lacks its own IP"; bad=1; }; }
  done
  return $bad
}

# ------------------------------------------------------------------------------
lab_init "scenario-2" "Web tier, end to end" --host rhel-control --score "$@"
a_init
[[ -n ${PB:-} ]] || { fail "one playbook builds the web tier" \
  "no web.yml or site.yml found — pass --pb=NAME"; summary; exit 1; }
info "grading playbook: $PB"

section "1. Apache on the web group only"
check "the playbook syntax-checks" ansible-playbook --syntax-check "$PB"
check "httpd is enabled and running on web, absent elsewhere" apache_on_web_only

section "2. Document root at /web/site with the right SELinux context"
check "DocumentRoot is /web/site, not the default" docroot_is_web_site
check "the context comes from policy (semanage fcontext), not chcon" context_from_policy_not_chcon
check "restorecon -Rvn /web outputs nothing" relabel_noop
check "no chcon anywhere in the project" \
  bash -c "! grep -rq 'chcon' --include='*.yml' . 2>/dev/null"

section "3. A templated virtual host, validated before deployment"
check "a template is deployed into conf.d" \
  bash -c "grep -rqE 'dest:.*conf\.d' --include='*.yml' . 2>/dev/null"
check "the template task uses validate:" \
  bash -c "grep -rqE 'validate:.*(httpd -t|apachectl)' --include='*.yml' . 2>/dev/null"
check "httpd's config parses on every web host" \
  bash -c 'out=$(ansible web -m command -a "httpd -t" --become 2>&1);
           echo "$out" | grep -viE "CHANGED|SUCCESS|=>" | head -4; ! grep -qE "FAILED|Syntax" <<<"$out"'

section "4. firewalld permits http and https, permanently"
check "both services are permanently open" firewall_http_https_permanent
check "runtime matches permanent" \
  bash -c 'out=$(ansible web -m shell -a "diff <(firewall-cmd --list-services | tr \" \" \"\n\" | sort) <(firewall-cmd --permanent --list-services | tr \" \" \"\n\" | sort) && echo SAME" --become 2>&1);
           echo "$out" | tail -6; grep -q SAME <<<"$out"'

section "5. An extra listener on 8080 with its SELinux port"
check "8080 is labelled http_port_t" selinux_port_8080
check "8080/tcp is open in the firewall" \
  bash -c 'out=$(ansible web -m shell -a "firewall-cmd --permanent --list-ports" --become 2>&1);
           echo "$out" | tail -4; grep -q 8080 <<<"$out"'
check "httpd is configured to listen on 8080" \
  bash -c 'out=$(ansible web -m shell -a "grep -rh \"^Listen\" /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/" --become 2>&1);
           echo "$out" | grep Listen | head -4; grep -q 8080 <<<"$out"'

section "6. A handler that fires only on real change"
check "the playbook notifies a handler" bash -c "grep -rqE '^[[:space:]]*notify:' --include='*.yml' . 2>/dev/null"
check "an unchanged run fires no handler" handler_only_on_change

section "7. The index page generated from facts"
check "each host's page names it and carries its IP" index_from_facts
check "both ports serve that page" serves_on_both_ports

section "8. Enforcing, idempotent, reboot-safe"
check "SELinux is Enforcing on every web host" \
  bash -c 'out=$(ansible web -m command -a getenforce 2>&1); echo "$out" | tail -4;
           ! grep -qiE "permissive|disabled" <<<"$out"'
check "the playbook runs clean" a_playbook_ok "$PB"
check "the second run reports changed=0" a_idempotent "$PB"
info "Reboot both nodes and run this again — that is how it will be graded."

summary
