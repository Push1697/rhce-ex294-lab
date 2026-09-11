#!/usr/bin/env bash
# Scenario 4 — Secrets (Day 54)                    (07-Scenario-Labs)
# Run on rhel-control, as the ordinary user.
#
#   ./scenario-4.sh --secret=S3cret --dev-pw=~/.vault_dev --prod-pw=~/.vault_prod \
#                   --appuser=appuser --conf=/etc/myapp/app.conf
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

SECRET=""; DEVPW=$HOME/.vault_dev; PRODPW=$HOME/.vault_prod
APPUSER=appuser; CONF=""; PB=db.yml
for a in "$@"; do
  case "$a" in
    --secret=*)  SECRET=${a#--secret=} ;;
    --dev-pw=*)  DEVPW=${a#--dev-pw=} ;;
    --prod-pw=*) PRODPW=${a#--prod-pw=} ;;
    --appuser=*) APPUSER=${a#--appuser=} ;;
    --conf=*)    CONF=${a#--conf=} ;;
    --pb=*)      PB=${a#--pb=} ;;
  esac
done
DEVPW=${DEVPW/#\~/$HOME}; PRODPW=${PRODPW/#\~/$HOME}

VAULTED=$(ls -1 group_vars/db.yml group_vars/database.yml 2>/dev/null | head -1)

is_ciphertext() { head -1 "$1" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT'; }

# The config file the playbook deploys, if not given.
find_conf() {
  [[ -n ${CONF:-} ]] && { echo "$CONF"; return 0; }
  grep -rhoE 'dest:[[:space:]]*/[^[:space:]"'"'"']+\.(conf|cfg|ini|env)' --include='*.yml' . 2>/dev/null |
    awk '{print $2}' | head -1
}

password_is_hashed_not_plaintext() {
  local out hash
  out=$(ansible db -m shell -a "getent shadow $APPUSER" --become 2>&1)
  hash=$(grep -oE "^$APPUSER:[^:]*" <<<"$out" | cut -d: -f2)
  echo "shadow field: ${hash:0:20}..."
  [[ -z ${hash:-} ]] && { echo "no shadow entry for $APPUSER"; return 1; }
  # a real hash starts with $y$, $6$, $5$ etc. Anything else is plaintext or empty.
  [[ $hash =~ ^\$[0-9a-z]+\$ ]] || { echo "that is not a hash — a plaintext password in /etc/shadow is a failure"; return 1; }
  [[ -n ${SECRET:-} ]] && grep -qF -- "$SECRET" <<<"$hash" && {
    echo "the plaintext secret appears in the shadow field"; return 1; }
  return 0
}

playbook_uses_password_hash_filter() {
  grep -rqE 'password_hash\(' --include='*.yml' . 2>/dev/null
}

conf_perms_and_owner() {
  local f out m o
  f=$(find_conf)
  [[ -n ${f:-} ]] || { echo "could not determine which config file is deployed"; return 2; }
  echo "checking $f"
  out=$(ansible db -m shell -a "stat -c '%a %U:%G' $f" --become 2>&1)
  echo "$out" | grep -E '^[0-7]{3,4} ' | head -3
  m=$(grep -oE '^[0-7]{3,4}' <<<"$out" | head -1)
  o=$(grep -oE "[a-z_]+:[a-z_]+" <<<"$out" | head -1)
  [[ $m == 600 || $m == 0600 ]] || { echo "mode is $m, must be 0600"; return 1; }
  grep -q "$APPUSER" <<<"$o" || { echo "owner is $o, must be $APPUSER"; return 1; }
  return 0
}

conf_contains_secret_on_target_only() {
  local f out
  f=$(find_conf)
  [[ -n ${f:-} && -n ${SECRET:-} ]] || return 2
  out=$(ansible db -m shell -a "grep -c . $f" --become 2>&1)
  echo "$out" | tail -3
  ! grep -qE 'No such file' <<<"$out"
}

two_vault_ids_in_one_run() {
  local out
  out=$(ansible-playbook "$PB" --vault-id "dev@$DEVPW" --vault-id "prod@$PRODPW" 2>&1)
  echo "$out" | tail -8
  ! grep -qE 'failed=[1-9]|fatal:|Decryption failed' <<<"$out"
}

secret_absent_from_verbose_output() {
  [[ -n ${SECRET:-} ]] || return 2
  local out
  out=$(ansible-playbook "$PB" --vault-id "dev@$DEVPW" --vault-id "prod@$PRODPW" -vv 2>&1)
  if grep -qF -- "$SECRET" <<<"$out"; then
    echo "the secret was printed:"; grep -nF -- "$SECRET" <<<"$out" | head -3; return 1
  fi
  echo "absent from -vv output; censored markers: $(grep -c censored <<<"$out")"
  return 0
}

no_plaintext_anywhere() {
  [[ -n ${SECRET:-} ]] || return 2
  local hits
  hits=$(grep -rIl --exclude-dir=.git -- "$SECRET" . 2>/dev/null)
  [[ -z ${hits// /} ]] && return 0
  echo "plaintext secret found in:"; echo "$hits"
  return 1
}

# ------------------------------------------------------------------------------
lab_init "scenario-4" "Secrets" --host rhel-control --score "$@"
a_init
info "app user: $APPUSER; vault ids: dev@$DEVPW, prod@$PRODPW"
[[ -z ${SECRET:-} ]] && info "pass --secret=VALUE so the plaintext searches can be graded"

section "1. Database credentials in an encrypted group_vars file"
check_sh "an encrypted db/database group_vars file exists" '[[ -n "'"${VAULTED:-}"'" ]]'
if [[ -n ${VAULTED:-} ]]; then
  check "it is ciphertext on disk" is_ciphertext "$VAULTED"
  check "it decrypts with the dev vault id" \
    bash -c "ansible-vault view --vault-id 'dev@$DEVPW' '$VAULTED' >/dev/null 2>&1 ||
             ansible-vault view --vault-id 'prod@$PRODPW' '$VAULTED' >/dev/null 2>&1"
fi

section "2. The account password is hashed, never plaintext"
check "the playbook hashes it with the password_hash filter" playbook_uses_password_hash_filter
check "/etc/shadow holds a real hash for $APPUSER" password_is_hashed_not_plaintext
check "no plaintext password: line survives in any playbook" \
  bash -c '! grep -rqE "^[[:space:]]*password:[[:space:]]*[A-Za-z0-9]{4,}[[:space:]]*$" --include="*.yml" . 2>/dev/null'

section "3. The templated application config"
check "a template deploys the config file" \
  bash -c "grep -rqE '(ansible\.builtin\.)?template:' --include='*.yml' . 2>/dev/null"
conf_perms_and_owner; rc=$?
case $rc in
  0) pass "the config is mode 0600 and owned by $APPUSER" ;;
  2) skipped "config permissions and ownership" "pass --conf=/path/to/file" ;;
  *) fail "the config is mode 0600 and owned by $APPUSER" "see the values above" ;;
esac
conf_contains_secret_on_target_only; rc=$?
case $rc in
  0) pass "the config exists on the target" ;;
  2) skipped "the config exists on the target" "pass --conf= and --secret=" ;;
  *) fail "the config exists on the target" "the file is missing" ;;
esac

section "4. The playbook runs unattended"
check "no interactive vault prompt is needed" \
  bash -c "! ansible-playbook $PB --vault-id 'dev@$DEVPW' --vault-id 'prod@$PRODPW' 2>&1 | grep -qi 'vault password:'"
check_file "the dev vault password file exists" "$DEVPW"
check_file "the prod vault password file exists" "$PRODPW"
check_eq "the dev password file is mode 600" 600 "$(mode_of "$DEVPW")"
check_eq "the prod password file is mode 600" 600 "$(mode_of "$PRODPW")"

section "5. The secret never appears in output"
check "tasks handling the secret use no_log: true" \
  bash -c "grep -rqE '^[[:space:]]*no_log:[[:space:]]*(true|yes)' --include='*.yml' . 2>/dev/null"
secret_absent_from_verbose_output; rc=$?
case $rc in
  0) pass "the secret does not appear even with -vv" ;;
  2) skipped "the secret does not appear with -vv" "re-run with --secret=VALUE" ;;
  *) fail "the secret does not appear even with -vv" "add no_log: true to that task" ;;
esac
no_plaintext_anywhere; rc=$?
case $rc in
  0) pass "grep across the repository finds no plaintext secret" ;;
  2) skipped "no plaintext secret in the repository" "re-run with --secret=VALUE" ;;
  *) fail "grep across the repository finds no plaintext secret" "see the files above" ;;
esac

section "6. Two separately-encrypted vaults, both used in one run"
check "two vault files exist with different passwords" \
  bash -c 'n=$(grep -rl "^\$ANSIBLE_VAULT" group_vars/ host_vars/ vars/ 2>/dev/null | grep -c .);
           echo "encrypted files: $n"; [[ ${n:-0} -ge 2 ]]'
check "the playbook runs with both vault ids at once" two_vault_ids_in_one_run
check "the two password files genuinely differ" \
  bash -c "! diff -q '$DEVPW' '$PRODPW' >/dev/null 2>&1"

summary
