#!/usr/bin/env bash
# Lab 3.3 — firewalld zones, services, ports, rich rules  (02-Labs-Security-and-Breakfix)
# Run on rhel01, as root.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

NET=$(lab_net).0/24
BAD=$(lab_net).99

fw()  { firewall-cmd "$@" 2>/dev/null; }

public_ssh_only() {
  local svcs extra
  svcs=$(fw --list-services --zone=public)
  echo "public services: ${svcs:-<none>}"
  grep -qw ssh <<<"$svcs" || { echo "ssh is not permitted in public"; return 1; }
  extra=$(tr ' ' '\n' <<<"$svcs" | grep -vE '^(ssh|dhcpv6-client|)$' | tr '\n' ' ')
  [[ -n ${extra// /} ]] && { echo "public also permits: $extra — the requirement was SSH only"; return 1; }
  return 0
}

internal_has_source() {
  local srcs
  srcs=$(fw --list-sources --zone=internal)
  echo "internal sources: ${srcs:-<none>}"
  grep -q "$NET" <<<"$srcs"
}

internal_services() {
  local svcs bad=0 s
  svcs=$(fw --list-services --zone=internal)
  echo "internal services: ${svcs:-<none>}"
  for s in http https nfs; do
    grep -qw "$s" <<<"$svcs" || { echo "missing from internal: $s"; bad=1; }
  done
  return $bad
}

rich_rule_rejects_and_logs() {
  local rules
  rules=$(fw --list-rich-rules --zone=public; fw --list-rich-rules --zone=internal)
  echo "${rules:-<no rich rules>}"
  grep -q "$BAD" <<<"$rules" && grep -qi 'reject' <<<"$rules" && grep -qi 'log' <<<"$rules"
}

forward_8080_to_80() {
  local fwd
  fwd=$(fw --list-forward-ports --zone=public; fw --list-forward-ports --zone=internal)
  echo "${fwd:-<no forward ports>}"
  grep -Eq 'port=8080.*toport=80($|[^0-9])' <<<"$fwd"
}

runtime_matches_permanent() {
  local d
  d=$(diff <(fw --list-all-zones | grep -vE '^\s*$') \
           <(fw --permanent --list-all-zones | grep -vE '^\s*$'))
  [[ -z ${d// /} ]] && return 0
  echo "runtime and permanent differ:"
  echo "$d" | head -12
  return 1
}

# ------------------------------------------------------------------------------
lab_init "3.3" "firewalld zones, services, ports, rich rules" --host rhel01 --root "$@"
info "lab network $NET · blocked host $BAD · $(lab_platform)"

need_cmd "every check in this lab" firewall-cmd || { summary; exit 1; }
check "firewalld is running" systemctl is-active --quiet firewalld

section "1. Default zone is public, SSH only"
check_eq -p "the default zone is public" "public" "$(fw --get-default-zone)"
check -p "public permits ssh and nothing else" public_ssh_only

section "2. The internal zone"
check -p "the internal zone carries the $NET source" internal_has_source
check -p "it permits http, https and nfs" internal_services

section "3. TCP 8080 open permanently in public"
check -p "8080/tcp is open at runtime" bash -c 'firewall-cmd --list-ports --zone=public 2>/dev/null | grep -q 8080/tcp'
check -p "8080/tcp is open permanently" bash -c 'firewall-cmd --permanent --list-ports --zone=public 2>/dev/null | grep -q 8080/tcp'
if need_cmd "the SELinux half of this requirement" semanage; then
  check -p "8080 is labelled http_port_t so Apache may bind it" \
    bash -c 'semanage port -l | grep "^http_port_t" | grep -qE "(^|[^0-9])8080([^0-9]|$)"'
fi

section "4. The rich rule blocking $BAD"
check -p "a rich rule rejects $BAD and logs it" rich_rule_rejects_and_logs

section "5. Port forwarding 8080 to 80"
check -p "a forward-port rule maps 8080 to 80" forward_8080_to_80

section "6. Nothing is runtime-only"
check -p "the runtime and permanent configurations are identical" runtime_matches_permanent
info "A --permanent rule without --reload, or a runtime rule never committed,"
info "both fail here — and both score zero in the exam."

section "7. Reachability"
check "something is listening on 8080" \
  bash -c 'ss -tlnH | awk "{print \$4}" | grep -Eq "[:.]8080$"'
manual "From rhel02: curl rhel01:8080 succeeds" \
  "Only the other node can prove the firewall lets traffic in."
report "the zones as they stand" bash -c 'firewall-cmd --list-all-zones | grep -A8 -E "^(public|internal)"'

summary
