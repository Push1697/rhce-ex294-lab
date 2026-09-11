#!/usr/bin/env bash
# Scenario 3 — Environment separation (Day 53)     (07-Scenario-Labs)
# Run on rhel-control, as the ordinary user.
#
# This is the scenario that tests whether variables were understood. The
# harshest check here is structural: any `when: inventory_hostname == ...`
# is a failure, however well the estate happens to be configured.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=""
for a in "$@"; do case "$a" in --pb=*) PB=${a#--pb=} ;; esac; done
for c in ${PB:-} site.yml env.yml environments.yml; do [[ -f $c ]] && { PB=$c; break; }; done

PRODH=$(a_hosts_in prod | head -1)
DEVH=$(a_hosts_in dev | head -1)

no_hostname_conditionals() {
  local hits
  hits=$(grep -rnE 'when:.*inventory_hostname[[:space:]]*(==|!=)' --include='*.yml' . 2>/dev/null)
  [[ -z ${hits// /} ]] && return 0
  echo "environment logic is hardcoded per host instead of driven by groups:"
  echo "$hits" | head -6
  return 1
}

no_env_literals_in_tasks() {
  local hits
  hits=$(grep -rnE "(==|!=)[[:space:]]*[\"']?(prod|production|dev|development)[\"']?" \
         roles/*/tasks/ *.yml 2>/dev/null | grep -v 'group_names')
  [[ -z ${hits// /} ]] && return 0
  echo "tasks compare against environment names directly — use group membership or a variable:"
  echo "$hits" | head -6
  return 1
}

group_vars_layered() {
  local bad=0
  [[ -f group_vars/all.yml ]] || { echo "no group_vars/all.yml supplying defaults"; bad=1; }
  [[ -f group_vars/prod.yml ]] || { echo "no group_vars/prod.yml"; bad=1; }
  [[ -f group_vars/dev.yml ]] || { echo "no group_vars/dev.yml"; bad=1; }
  return $bad
}

both_override_all() {
  local base prod dev common
  base=$(grep -oE '^[a-z_]+:' group_vars/all.yml 2>/dev/null | tr -d ':' | sort -u)
  prod=$(grep -oE '^[a-z_]+:' group_vars/prod.yml 2>/dev/null | tr -d ':' | sort -u)
  dev=$(grep -oE '^[a-z_]+:' group_vars/dev.yml 2>/dev/null | tr -d ':' | sort -u)
  common=$(comm -12 <(echo "$base") <(echo "$prod") | grep -c .)
  local common2
  common2=$(comm -12 <(echo "$base") <(echo "$dev") | grep -c .)
  echo "all.yml keys overridden by prod: $common, by dev: $common2"
  [[ ${common:-0} -ge 1 && ${common2:-0} -ge 1 ]]
}

differs_between_environments() {
  local bad=0 key pv dv
  for key in $(grep -oE '^[a-z_]+:' group_vars/prod.yml 2>/dev/null | tr -d ':'); do
    grep -qE "^$key:" group_vars/dev.yml 2>/dev/null || continue
    pv=$(ansible "$PRODH" -m debug -a "var=$key" 2>/dev/null | sed -n 's/.*: *"\?\([^"]*\)"\?$/\1/p' | tail -1)
    dv=$(ansible "$DEVH" -m debug -a "var=$key" 2>/dev/null | sed -n 's/.*: *"\?\([^"]*\)"\?$/\1/p' | tail -1)
    echo "$key — prod: '$pv' / dev: '$dv'"
    [[ $pv != "$dv" ]] && return 0
  done
  echo "no variable resolves differently between the prod and dev hosts"
  return 1
}

docroots_differ() {
  local p d
  p=$(ansible "$PRODH" -m shell -a 'grep -rhE "^\s*DocumentRoot" /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/ 2>/dev/null | tail -1' --become 2>&1 | grep -i documentroot)
  d=$(ansible "$DEVH" -m shell -a 'grep -rhE "^\s*DocumentRoot" /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/ 2>/dev/null | tail -1' --become 2>&1 | grep -i documentroot)
  echo "prod: ${p:-<none>}"
  echo "dev:  ${d:-<none>}"
  [[ -n ${p// /} && -n ${d// /} && $p != "$d" ]]
}

loglevels_differ() {
  local p d
  p=$(ansible "$PRODH" -m shell -a 'grep -rhiE "^\s*LogLevel" /etc/httpd/ 2>/dev/null | tail -1' --become 2>&1 | grep -i loglevel)
  d=$(ansible "$DEVH" -m shell -a 'grep -rhiE "^\s*LogLevel" /etc/httpd/ 2>/dev/null | tail -1' --become 2>&1 | grep -i loglevel)
  echo "prod: ${p:-<none>} / dev: ${d:-<none>}"
  [[ -n ${p// /} && -n ${d// /} && $p != "$d" ]]
}

firewall_narrower_in_prod() {
  local p d np nd
  p=$(ansible "$PRODH" -m command -a 'firewall-cmd --list-all' --become 2>&1)
  d=$(ansible "$DEVH" -m command -a 'firewall-cmd --list-all' --become 2>&1)
  np=$(grep -oE 'services:.*' <<<"$p" | tr ' ' '\n' | grep -c .)
  nd=$(grep -oE 'services:.*' <<<"$d" | tr ' ' '\n' | grep -c .)
  echo "prod permits $np entries, dev permits $nd"
  [[ ${np:-0} -lt ${nd:-0} ]]
}

prod_ssh_stricter() {
  local p d
  p=$(ansible "$PRODH" -m shell -a 'sshd -T | grep -cE "^(permitrootlogin no|passwordauthentication no|maxauthtries|logingracetime|allowtcpforwarding no|x11forwarding no)"' --become 2>&1 | grep -oE '^[0-9]+$' | head -1)
  d=$(ansible "$DEVH" -m shell -a 'sshd -T | grep -cE "^(permitrootlogin no|passwordauthentication no|maxauthtries|logingracetime|allowtcpforwarding no|x11forwarding no)"' --become 2>&1 | grep -oE '^[0-9]+$' | head -1)
  echo "hardening directives — prod: ${p:-?}, dev: ${d:-?}"
  [[ -n ${p:-} && -n ${d:-} ]] && ((p >= d))
}

flip_changes_the_build() {
  local out
  out=$(ansible-playbook "$PB" --check --limit "$DEVH" -e 'env_name=prod' --diff 2>&1)
  echo "$out" | tail -8
  grep -qE 'changed=[1-9]|would be changed|\+\+\+|---' <<<"$out"
}

# ------------------------------------------------------------------------------
lab_init "scenario-3" "Environment separation" --host rhel-control --score "$@"
a_init
[[ -n ${PB:-} ]] || { fail "one playbook builds both environments" \
  "no site.yml found — pass --pb=NAME"; summary; exit 1; }
info "grading playbook: $PB — prod host: ${PRODH:-none}, dev host: ${DEVH:-none}"

section "1. prod and dev groups with one host each"
check "the prod group has exactly one host" \
  bash -c '[[ $(a_hosts_in prod | grep -c .) -eq 1 ]]'
check "the dev group has exactly one host" \
  bash -c '[[ $(a_hosts_in dev | grep -c .) -eq 1 ]]'
check "ansible-inventory --graph documents the layout" \
  bash -c "ansible-inventory --graph 2>/dev/null | grep -qE '@(prod|dev):'"
report "the inventory layout" bash -c 'ansible-inventory --graph 2>/dev/null'

section "2. No environment logic hardcoded in tasks"
check "no 'when: inventory_hostname ==' anywhere" no_hostname_conditionals
check "no task compares against 'prod' or 'dev' literals" no_env_literals_in_tasks
check "conditions use group_names or variables" \
  bash -c "grep -rqE 'group_names|groups\[' --include='*.yml' . 2>/dev/null"

section "3. group_vars/all.yml defaults, overridden by both environments"
check "all.yml, prod.yml and dev.yml all exist" group_vars_layered
check "both environments override at least one default from all.yml" both_override_all
check "at least one variable genuinely resolves differently per host" differs_between_environments

section "4. The same playbook, different outcomes"
check "document roots differ between prod and dev" docroots_differ
check "log levels differ between prod and dev" loglevels_differ
check "the firewall is narrower in prod than in dev" firewall_narrower_in_prod
check "package sets differ between the environments" \
  bash -c 'p=$(grep -c . <(grep -A20 -E "packages" group_vars/prod.yml 2>/dev/null));
           d=$(grep -c . <(grep -A20 -E "packages" group_vars/dev.yml 2>/dev/null));
           echo "package lines — prod: $p, dev: $d"; [[ $p -ne $d ]]'

section "5. Production is additionally hardened"
check "prod has at least as many SSH hardening directives as dev" prod_ssh_stricter
check "audit settings are configured for prod" \
  bash -c "grep -rqiE 'audit|auditd' group_vars/prod.yml roles/ 2>/dev/null"

section "6. One variable flips a host between environments"
check "the environment is selected by a variable, not by editing the playbook" \
  bash -c "grep -rqE '(env|environment)[a-z_]*:' group_vars/ 2>/dev/null"
check "flipping it visibly changes what would be built" flip_changes_the_build
manual "Moving a host between groups changes its build with no other edit" \
  "Move it in the inventory, re-run, and confirm."

section "7. Both environments idempotent"
check "the playbook runs clean across both" a_playbook_ok "$PB"
check "the second run reports changed=0" a_idempotent "$PB"

summary
