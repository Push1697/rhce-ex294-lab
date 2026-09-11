#!/usr/bin/env bash
# Lab 7.2 — Decompose into roles                    (06-Labs-Advanced-Ansible)
# Run on rhel-control, as the ordinary user.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=site.yml
ROLES="common apache users security"

role_is_complete() {   # role_is_complete <name>
  local r=roles/$1 bad=0 f
  for f in defaults/main.yml vars/main.yml tasks/main.yml handlers/main.yml meta/main.yml; do
    [[ -f $r/$f ]] || { echo "missing: $r/$f"; bad=1; }
  done
  [[ -d $r/templates ]] || { echo "missing: $r/templates/"; bad=1; }
  return $bad
}

site_is_thin() {
  local inline
  # count task-looking lines that are NOT inside a roles: list
  inline=$(awk '
    /^[[:space:]]*tasks:/ { t = 1; next }
    /^[[:space:]]*(roles|handlers|pre_tasks|post_tasks|vars):/ { t = 0 }
    t && /^[[:space:]]*-[[:space:]]*name:/ { n++ }
    END { print n + 0 }' "$PB")
  echo "inline tasks in $PB: $inline"
  [[ ${inline:-0} -le 3 ]]
}

lists_roles() {
  grep -qE '^[[:space:]]*roles:' "$PB" ||
    grep -qE 'include_role|import_role' "$PB"
}

no_hardcoded_paths_in_tasks() {
  local hits
  hits=$(grep -rnE 'rhel0[12]|/web/site|192\.168\.' roles/*/tasks/ 2>/dev/null)
  [[ -z ${hits// /} ]] && return 0
  echo "hardcoded hostnames or paths inside role tasks:"
  echo "$hits" | head -6
  return 1
}

defaults_are_overridable() {
  # pick a default from the apache role and prove group_vars/-e can change it
  local key val out
  key=$(grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*:' roles/apache/defaults/main.yml 2>/dev/null |
        tr -d ':' | head -1)
  [[ -n ${key:-} ]] || { echo "roles/apache/defaults/main.yml defines nothing"; return 1; }
  val=$(ansible localhost -m debug -a "var=$key" -e "$key=OVERRIDDEN" 2>/dev/null | grep -c OVERRIDDEN)
  echo "overriding $key from the command line: $( ((val)) && echo works || echo ignored)"
  ((val))
}

scaffolded_not_handmade() {
  # ansible-galaxy role init leaves a README and a tests/ or meta with galaxy_info
  local r ok=0
  for r in $ROLES; do
    [[ -f roles/$r/README.md ]] && ok=$((ok + 1))
    grep -q 'galaxy_info' "roles/$r/meta/main.yml" 2>/dev/null && ok=$((ok + 1))
  done
  echo "scaffolding markers found: $ok"
  ((ok >= 2))
}

# ------------------------------------------------------------------------------
lab_init "7.2" "Decompose into roles" --host rhel-control "$@"
a_init

section "1. The four roles exist and are complete"
for r in $ROLES; do
  check_dir "roles/$r exists" "$A_PROJ/roles/$r"
done
for r in $ROLES; do
  check "roles/$r has defaults, vars, tasks, handlers, meta and templates" role_is_complete "$r"
done
check "they were scaffolded with ansible-galaxy role init, not hand-made" scaffolded_not_handmade

section "2. site.yml is thin — plays and role lists"
check_file "$PB exists" "$A_PROJ/$PB"
check "it lists roles rather than inlining tasks" lists_roles
check "almost no inline tasks remain" site_is_thin
check "syntax-check passes" ansible-playbook --syntax-check "$PB"
report "the play/role structure" bash -c "ansible-playbook $PB --list-tasks 2>/dev/null | head -30"

section "3. Roles are portable"
check "no hardcoded hostnames or paths inside roles/*/tasks" no_hardcoded_paths_in_tasks
check "dependencies are declared in meta/main.yml, not assumed" \
  bash -c "grep -rqE 'dependencies:' roles/*/meta/main.yml 2>/dev/null"
check "at least one role declares a real dependency" \
  bash -c "grep -rA3 'dependencies:' roles/*/meta/main.yml 2>/dev/null | grep -qE '^\s*-\s*(role:|[a-z])'"

section "4. defaults vs vars — the precedence point that gets tested"
check "tunables live in defaults/main.yml" \
  bash -c "[[ -s roles/apache/defaults/main.yml ]] && grep -qE '^[a-z_]+:' roles/apache/defaults/main.yml"
check "overriding a default from the command line changes behaviour" defaults_are_overridable
check "group_vars overrides a role default somewhere" \
  bash -c 'ov=$(comm -12 <(grep -hoE "^[a-z_]+:" roles/*/defaults/main.yml 2>/dev/null | tr -d ":" | sort -u) \
                         <(grep -hoE "^[a-z_]+:" group_vars/*.yml 2>/dev/null | tr -d ":" | sort -u));
           echo "overridden defaults: ${ov:-<none>}"; [[ -n ${ov// /} ]]'
manual "You can explain defaults vs vars precedence without looking it up" \
  "defaults is the lowest precedence in all of Ansible; vars is very high."

section "5. Tags let a single role run in isolation"
check "--list-tags shows per-stage tags" \
  bash -c "ansible-playbook $PB --list-tags 2>&1 | grep -qi 'task tags'"
check "running just the apache tag works" \
  bash -c "out=\$(ansible-playbook $PB --tags apache 2>&1); echo \"\$out\" | tail -6;
           ! grep -qE 'failed=[1-9]|fatal:|no hosts matched' <<<\"\$out\""

section "6. Nothing was lost in the conversion"
check "the full playbook runs clean" a_playbook_ok "$PB"
check "and is still idempotent" a_idempotent "$PB"
check "the web tier still serves" \
  bash -c 'bad=0; for h in $(a_hosts_in web); do
             ansible "$h" -m uri -a "url=http://$h/ status_code=200" 2>&1 | grep -q SUCCESS || bad=1
           done; exit $bad'
manual "You can scaffold a role from scratch in under five minutes" \
  "Day 51 gate. Time yourself once."

summary
