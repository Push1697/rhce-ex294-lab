#!/usr/bin/env bash
# Scenario 5 — A role that builds a server from nothing (Day 54)  (07-Scenario-Labs)
# Run on rhel-control, as the ordinary user.
#   ./scenario-5.sh --role=apache --play=apache-only.yml --target=rhel01
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

ROLE=apache; PLAY=""; TARGET=""
for a in "$@"; do
  case "$a" in
    --role=*)   ROLE=${a#--role=} ;;
    --play=*)   PLAY=${a#--play=} ;;
    --target=*) TARGET=${a#--target=} ;;
  esac
done
R=roles/$ROLE
for c in ${PLAY:-} apache-only.yml apache.yml web.yml site.yml; do [[ -f $c ]] && { PLAY=$c; break; }; done
[[ -n ${TARGET:-} ]] || TARGET=$(a_hosts_in web | head -1)

scaffolded() {
  local ok=0
  [[ -f $R/README.md ]] && ok=$((ok + 1))
  grep -q 'galaxy_info' "$R/meta/main.yml" 2>/dev/null && ok=$((ok + 1))
  [[ -d $R/tasks && -d $R/handlers && -d $R/defaults ]] && ok=$((ok + 1))
  echo "scaffolding markers: $ok/3"
  ((ok >= 2))
}

tunables_in_defaults() {
  local bad=0 k
  for k in port document_root server_name packages; do
    grep -qE "^[a-z_]*${k}[a-z_]*:" "$R/defaults/main.yml" 2>/dev/null ||
      { echo "no default exposed for: $k"; bad=1; }
  done
  return $bad
}

no_hardcoded_values_in_tasks() {
  local hits
  hits=$(grep -rnE 'rhel0[12]|192\.168\.|/var/www/html|:80\b' "$R/tasks/" 2>/dev/null)
  [[ -z ${hits// /} ]] && return 0
  echo "hardcoded hostnames, addresses or paths inside $R/tasks:"
  echo "$hits" | head -6
  return 1
}

handlers_reload_and_restart() {
  local h
  h=$(cat "$R/handlers/main.yml" 2>/dev/null)
  echo "$h" | grep -E 'name:|state:' | head -8
  grep -qE 'state:[[:space:]]*reloaded' <<<"$h" && grep -qE 'state:[[:space:]]*restarted' <<<"$h"
}

meta_declares_common() {
  local m
  m=$(cat "$R/meta/main.yml" 2>/dev/null)
  grep -qE 'dependencies:' <<<"$m" || { echo "no dependencies: block"; return 1; }
  grep -A5 'dependencies:' <<<"$m" | grep -qE 'common'
}

port_override_takes_effect() {
  local out
  out=$(ansible-playbook "$PLAY" --limit "$TARGET" -e "${ROLE}_port=8888" --check --diff 2>&1)
  echo "$out" | grep -E '8888|changed=' | head -8
  grep -q '8888' <<<"$out"
}

role_standalone() {
  local out
  out=$(ansible-playbook "$PLAY" --limit "$TARGET" 2>&1)
  V_LAST_OUT="$out"
  echo "$out" | grep -E '^[^ ]+ +: +ok='
  ! grep -qE 'failed=[1-9]|fatal:' <<<"$out"
}

server_actually_works() {
  local bad=0 out
  out=$(ansible "$TARGET" -m uri -a "url=http://$TARGET/ status_code=200" 2>&1)
  grep -qE 'SUCCESS|status.*200' <<<"$out" || { echo "$TARGET did not answer 200"; bad=1; }
  out=$(ansible "$TARGET" -m command -a getenforce 2>&1)
  grep -qi enforcing <<<"$out" || { echo "SELinux is not enforcing on $TARGET"; bad=1; }
  out=$(ansible "$TARGET" -m command -a 'firewall-cmd --list-services' --become 2>&1)
  grep -qw http <<<"$out" || { echo "http is not open in the firewall on $TARGET"; bad=1; }
  return $bad
}

readme_documents_it() {
  local n
  n=$(grep -c . "$R/README.md" 2>/dev/null)
  echo "README.md lines: ${n:-0}"
  [[ ${n:-0} -ge 10 ]] &&
    grep -qiE 'variable|default|role variables' "$R/README.md"
}

# ------------------------------------------------------------------------------
lab_init "scenario-5" "A role that builds a server from nothing" --host rhel-control --score "$@"
a_init
info "role: $R; play: ${PLAY:-<none found>}; target: ${TARGET:-<none>}"
[[ -n ${PLAY:-} ]] || { fail "a play that applies the role alone" \
  "no apache-only.yml or similar — pass --play=NAME"; summary; exit 1; }

section "1. Scaffolded with ansible-galaxy role init"
check_dir "$R exists" "$A_PROJ/$R"
check "it carries the scaffolding, not hand-made directories" scaffolded

section "2. It takes a clean node to a working web server in one play"
check "the play syntax-checks" ansible-playbook --syntax-check "$PLAY"
check "the play is just this role, with no external tasks" \
  bash -c "n=\$(awk '/^[[:space:]]*tasks:/ { t = 1 } t && /^[[:space:]]*-[[:space:]]*name:/ { n++ } END { print n + 0 }' $PLAY);
           echo \"inline tasks: \$n\"; [[ \${n:-0} -eq 0 ]]"
check "applying it to the target succeeds" role_standalone
check "the result is a genuinely working, firewalled, enforcing web server" server_actually_works

section "3. Every tunable exposed in defaults/main.yml"
check_file "$R/defaults/main.yml is not empty" "$A_PROJ/$R/defaults/main.yml"
check "port, document root, server name and packages are all defaults" tunables_in_defaults
check "nothing tunable hides in vars/main.yml" \
  bash -c "! grep -qE '^[a-z_]*(port|document_root|packages):' $R/vars/main.yml 2>/dev/null"
check "overriding the port with -e visibly changes the result" port_override_takes_effect

section "4. Handlers for reload versus restart"
check "both a reload and a restart handler exist" handlers_reload_and_restart
check "tasks notify them" bash -c "grep -qE '^[[:space:]]*notify:' $R/tasks/main.yml"

section "5. meta/main.yml declares the dependency on common"
check "the role depends on the common role" meta_declares_common
check_dir "and that dependency actually exists" "$A_PROJ/roles/common"

section "6. Documented in the role's own README"
check "README.md documents the role and its variables" readme_documents_it

section "7. Portable and idempotent"
check "no hardcoded hostnames or paths in tasks/" no_hardcoded_values_in_tasks
check "re-applying it reports changed=0" a_idempotent "$PLAY"
manual "It works unchanged on a host it has never seen" \
  "Rebuild a node with lab-build.sh and apply just this role to it."

summary
