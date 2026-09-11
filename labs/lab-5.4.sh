#!/usr/bin/env bash
# Lab 5.4 — Variables, facts and precedence         (04-Labs-Ansible-Fundamentals)
# Run on rhel-control, as the ordinary user.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=vars.yml

# The point of the lab: a host_var must visibly beat a group_var.
host_var_beats_group_var() {
  local key gv hv eff
  # find a variable defined in both group_vars/web.yml and host_vars/rhel01.yml
  key=$(comm -12 \
        <(grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*:' group_vars/web.yml 2>/dev/null | tr -d ':' | sort -u) \
        <(grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*:' host_vars/rhel01.yml 2>/dev/null | tr -d ':' | sort -u) |
        head -1)
  [[ -n ${key:-} ]] || { echo "no variable is defined in BOTH group_vars/web.yml and host_vars/rhel01.yml"; return 1; }
  gv=$(grep -E "^$key:" group_vars/web.yml | cut -d: -f2- | tr -d ' "')
  hv=$(grep -E "^$key:" host_vars/rhel01.yml | cut -d: -f2- | tr -d ' "')
  eff=$(ansible rhel01 -m debug -a "var=$key" 2>/dev/null | sed -n 's/.*: *"\?\([^"]*\)"\?$/\1/p' | tail -1)
  echo "$key — group_vars: '$gv', host_vars: '$hv', effective: '$eff'"
  [[ -n ${eff:-} && $eff == "$hv" && $hv != "$gv" ]]
}

extra_var_wins() {
  local key eff
  key=$(grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*:' group_vars/all.yml 2>/dev/null | tr -d ':' | head -1)
  [[ -n ${key:-} ]] || key=$(grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*:' group_vars/web.yml 2>/dev/null | tr -d ':' | head -1)
  [[ -n ${key:-} ]] || { echo "no group variable found to override"; return 1; }
  eff=$(ansible rhel01 -m debug -a "var=$key" -e "$key=OVERRIDDEN_BY_CLI" 2>/dev/null |
        grep -o 'OVERRIDDEN_BY_CLI')
  echo "with -e on the command line, $key became: ${eff:-<unchanged>}"
  [[ $eff == OVERRIDDEN_BY_CLI ]]
}

custom_fact_present() {
  local out
  out=$(ansible rhel01 -m setup -a 'filter=ansible_local' 2>&1)
  echo "$out" | grep -A6 ansible_local | head -8
  grep -q '"ansible_local"' <<<"$out" && ! grep -qE '"ansible_local": \{\}' <<<"$out"
}

fact_file_on_target() {
  local out
  out=$(ansible rhel01 -m command -a 'ls -1 /etc/ansible/facts.d/' --become 2>&1)
  echo "$out" | tail -5
  grep -qE '\.fact' <<<"$out"
}

# ------------------------------------------------------------------------------
lab_init "5.4" "Variables, facts and precedence" --host rhel-control "$@"
a_init

section "1. group_vars for web and db"
check_file "group_vars/web.yml exists" "$A_PROJ/group_vars/web.yml"
check_file "group_vars/db.yml exists" "$A_PROJ/group_vars/db.yml"
check "web's port variable is set to 80" \
  bash -c "grep -qE '^[a-z_]*port[a-z_]*:[[:space:]]*80[[:space:]]*\$' group_vars/web.yml"
check "db.yml defines database-related variables" \
  bash -c "grep -qiE 'db|database|mysql|postgres|maria' group_vars/db.yml"
check "both files are valid YAML" \
  bash -c 'a_yaml_ok group_vars/web.yml && a_yaml_ok group_vars/db.yml'

section "2. A host_var that beats a group_var"
check_file "host_vars/rhel01.yml exists" "$A_PROJ/host_vars/rhel01.yml"
check "a host variable demonstrably overrides the group variable" host_var_beats_group_var
check "an -e extra var beats everything" extra_var_wins
manual "You can recite the precedence order from memory" \
  "role defaults -> group_vars/all -> group_vars/group -> host_vars -> play -> task -> -e"

section "3. Package choice driven by a distribution fact"
check_file "$PB exists" "$A_PROJ/$PB"
check "it is valid YAML" a_yaml_ok "$PB"
check "syntax-check passes" ansible-playbook --syntax-check "$PB"
check "it branches on the distribution version fact" \
  bash -c "grep -qE 'distribution_major_version|ansible_distribution' $PB"
check "the branch is a when: condition, not a hardcoded hostname" \
  bash -c "! grep -qE 'when:.*inventory_hostname[[:space:]]*==' $PB"

section "4. A registered variable used later"
check "the playbook registers something" bash -c "grep -qE '^[[:space:]]*register:' $PB"
check "and consumes it (.stdout, .rc or .changed)" \
  bash -c "grep -qE '\.(stdout|stdout_lines|rc|changed)' $PB"

section "5. A custom fact on rhel01"
check "a .fact file exists under /etc/ansible/facts.d on rhel01" fact_file_on_target
check "it shows up as ansible_local" custom_fact_present
check "the playbook consumes ansible_local" bash -c "grep -q 'ansible_local' $PB"

section "6. A prompted variable with a default"
check "the playbook uses vars_prompt" bash -c "grep -q 'vars_prompt' $PB"
check "the prompt has a default so it can run unattended" \
  bash -c "awk '/vars_prompt/ { f = 1 } f && /default:/ { found = 1 } END { exit !found }' $PB"
check "the playbook runs to completion with -e supplied" \
  bash -c "out=\$(ansible-playbook $PB -e 'extra_var=fromcli' 2>&1); echo \"\$out\" | tail -6;
           ! grep -qE 'failed=[1-9]|fatal:' <<<\"\$out\""

summary
