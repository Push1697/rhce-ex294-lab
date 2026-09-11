#!/usr/bin/env bash
# Lab 7.1 — Templates and Jinja2                    (06-Labs-Advanced-Ansible)
# Run on rhel-control, as the ordinary user.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

TPL=templates/vhost.conf.j2
PB=vhost.yml

grep_tpl() { grep -qE "$1" "$TPL" 2>/dev/null; }

output_differs_per_host() {
  local a b h1 h2
  h1=$(a_hosts_in all | sed -n 1p)
  h2=$(a_hosts_in all | sed -n 2p)
  [[ -n ${h1:-} && -n ${h2:-} ]] || { echo "need two hosts to compare"; return 2; }
  a=$(ansible "$h1" -m command -a 'cat /etc/httpd/conf.d/vhost.conf' --become 2>&1 |
      grep -vE 'CHANGED|SUCCESS|=>')
  b=$(ansible "$h2" -m command -a 'cat /etc/httpd/conf.d/vhost.conf' --become 2>&1 |
      grep -vE 'CHANGED|SUCCESS|=>')
  [[ -z ${a// /} || -z ${b// /} ]] && { echo "the vhost file is missing on at least one host"; return 1; }
  if [[ "$a" == "$b" ]]; then
    echo "$h1 and $h2 produced byte-identical output — nothing is host-specific"
    return 1
  fi
  echo "$h1 and $h2 produced genuinely different output, as required"
  diff <(printf '%s' "$a") <(printf '%s' "$b") | head -8
  return 0
}

undefined_var_does_not_crash() {
  local out
  out=$(ansible-playbook "$PB" --check -e 'apache_document_root=' 2>&1)
  echo "$out" | tail -6
  ! grep -qi 'undefined' <<<"$out"
}

httpd_config_valid_everywhere() {
  local out
  out=$(ansible all -m command -a 'httpd -t' --become 2>&1)
  echo "$out" | grep -viE 'CHANGED|SUCCESS|=>' | head -6
  ! grep -qE 'FAILED|Syntax error|non-zero' <<<"$out"
}

# ------------------------------------------------------------------------------
lab_init "7.1" "Templates and Jinja2" --host rhel-control "$@"
a_init

section "1. The template exists and is used"
check_file "$TPL exists" "$A_PROJ/$TPL"
check_file "$PB exists" "$A_PROJ/$PB"
check "the playbook deploys it with the template module" \
  bash -c "grep -qE '(ansible\.builtin\.)?template:' $PB"
check "syntax-check passes" ansible-playbook --syntax-check "$PB"

section "2. It uses the host's own facts"
check "the FQDN comes from facts" grep_tpl 'ansible_(facts\[.fqdn.\]|fqdn)'
check "the primary IP comes from facts" grep_tpl 'ansible_(facts\[.default_ipv4.\]|default_ipv4)'
check "no hardcoded IP address anywhere in the template" \
  bash -c "! grep -qE '[0-9]{1,3}(\.[0-9]{1,3}){3}' $TPL"

section "3. A loop over aliases from a group variable"
check "the template contains a for loop" grep_tpl '\{%-?[[:space:]]*for '
check "the loop is closed" grep_tpl '\{%-?[[:space:]]*endfor'
check "the aliases come from a variable, not a literal list" \
  bash -c "grep -E '\{%-?\s*for ' $TPL | grep -qE 'in[[:space:]]+[a-z_]+'"
check "an aliases variable is defined in group_vars" \
  bash -c "grep -rqiE 'alias' group_vars/ 2>/dev/null"

section "4. A conditional block for prod hosts only"
check "the template contains an if block" grep_tpl '\{%-?[[:space:]]*if '
check "it is closed" grep_tpl '\{%-?[[:space:]]*endif'
check "the condition refers to group membership, not a hostname" \
  bash -c "grep -E '\{%-?\s*if ' $TPL | grep -qE \"groups|prod\""

section "5. Document root from a variable with a default"
check "the document root uses a | default() filter" grep_tpl '\|[[:space:]]*default\('
check "an undefined variable does not crash the run" undefined_var_does_not_crash

section "6. The Ansible-managed header"
check "the template carries a warning header" \
  bash -c "head -5 $TPL | grep -qiE 'ansible|managed|do not edit'"
check "it names its own source path" \
  bash -c "head -8 $TPL | grep -qE 'ansible_managed|vhost\.conf\.j2|template_path'"
check "the header reaches the deployed file on the nodes" \
  bash -c 'out=$(ansible all -m shell -a "head -5 /etc/httpd/conf.d/vhost.conf" --become 2>&1);
           echo "$out" | head -8; grep -qiE "ansible|managed|do not edit" <<<"$out"'

section "7. Validation before deployment"
check "the template task uses validate:" bash -c "grep -A6 -E 'template:' $PB | grep -q 'validate:'"
check "the validator is httpd's own check" \
  bash -c "grep -E 'validate:' $PB | grep -qE 'httpd -t|apachectl'"
check "httpd's configuration is valid on every node" httpd_config_valid_everywhere

section "8. Different hosts, different valid output"
check "two hosts render genuinely different files" output_differs_per_host
check "--check --diff shows exactly what would change" \
  bash -c "out=\$(ansible-playbook $PB --check --diff 2>&1); echo \"\$out\" | tail -8;
           ! grep -qE 'fatal:' <<<\"\$out\""
check "a real run is idempotent" a_idempotent "$PB"

summary
