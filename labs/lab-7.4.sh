#!/usr/bin/env bash
# Lab 7.4 — Collections and content                 (06-Labs-Advanced-Ansible)
# Run on rhel-control, as the ordinary user.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

collections_path_is_local() {
  local p
  p=$(ansible-config dump 2>/dev/null | grep -i 'COLLECTIONS_PATHS' | cut -d= -f2- | tr -d ' ')
  echo "collections path: ${p:-<default>}"
  grep -qE "$A_PROJ|\./collections|collections" <<<"$p" &&
    grep -q "$A_PROJ" <<<"$p"
}

collection_installed() {
  ansible-galaxy collection list 2>/dev/null | grep -q "^$1"
}

installed_under_project() {
  local d
  d=$(find "$A_PROJ" -maxdepth 4 -type d -name 'ansible_collections' 2>/dev/null | head -1)
  echo "${d:-<no ansible_collections directory inside the project>}"
  [[ -n ${d:-} ]]
}

fqcn_used() {
  local hits
  hits=$(grep -rhoE '(ansible\.posix|community\.general|ansible\.builtin)\.[a-z_]+:' \
         --include='*.yml' . 2>/dev/null | sort -u)
  [[ -z ${hits// /} ]] && { echo "no fully-qualified module names anywhere"; return 1; }
  echo "FQCNs in use:"; echo "$hits" | head -8
  return 0
}

requirements_installs() {
  local out
  out=$(ansible-galaxy collection install -r requirements.yml 2>&1)
  echo "$out" | tail -6
  ! grep -qiE 'error|failed' <<<"$out"
}

doc_offline() {
  local out
  out=$(ansible-doc -l ansible.posix 2>&1 | head -5)
  echo "$out"
  [[ $(grep -c . <<<"$out") -ge 2 ]]
}

# ------------------------------------------------------------------------------
lab_init "7.4" "Collections and content" --host rhel-control "$@"
a_init

section "1. What is installed, and where"
check "ansible-galaxy collection list works" bash -c 'ansible-galaxy collection list >/dev/null 2>&1'
report "installed collections" bash -c 'ansible-galaxy collection list 2>/dev/null | head -15'
check "collections are installed inside the project, not only system-wide" installed_under_project

section "2. collections_path points at the project"
check_file "ansible.cfg exists" "$A_PROJ/ansible.cfg"
check "ansible.cfg sets collections_path (or collections_paths)" \
  bash -c "grep -qiE '^[[:space:]]*collections_paths?[[:space:]]*=' ansible.cfg"
check "the effective path is inside the project directory" collections_path_is_local

section "3. The two collections these labs need"
check "ansible.posix is installed" collection_installed ansible.posix
check "community.general is installed" collection_installed community.general

section "4. requirements.yml"
check_file "requirements.yml exists" "$A_PROJ/requirements.yml"
check "it is valid YAML" a_yaml_ok requirements.yml
check "it names the collections rather than roles only" \
  bash -c "grep -qE '^[[:space:]]*collections:' requirements.yml"
check "installing from it succeeds" requirements_installs

section "5. FQCN versus short name"
check "modules are referenced by fully-qualified name somewhere" fqcn_used
manual "You can explain when the short name works and when it does not" \
  "Short names resolve only via the collections: keyword or the builtin namespace."
manual "You can name the collection any module you used belongs to" \
  "firewalld, selinux, mount -> ansible.posix. parted, lvg, lvol -> community.general."

section "6. Documentation, entirely offline"
check "ansible-doc lists modules from a collection" doc_offline
check "ansible-doc -s produces a paste-ready snippet" \
  bash -c "ansible-doc -s ansible.posix.firewalld 2>/dev/null | grep -q 'firewalld'"
info "ansible-doc -s is the highest-value command in the whole exam."

summary
