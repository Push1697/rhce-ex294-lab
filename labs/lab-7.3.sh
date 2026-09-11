#!/usr/bin/env bash
# Lab 7.3 — Ansible Vault                           (06-Labs-Advanced-Ansible)
# Run on rhel-control, as the ordinary user.
#
#   ./lab-7.3.sh --secret=S3cret   the plaintext value that must NOT be findable
#   ./lab-7.3.sh --pw=~/.vault_pass
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

VAULTED=group_vars/database.yml
PWFILE=$HOME/.vault_pass
SECRET=""
PB=db.yml
for a in "$@"; do
  case "$a" in
    --secret=*) SECRET=${a#--secret=} ;;
    --pw=*)     PWFILE=${a#--pw=} ;;
    --pb=*)     PB=${a#--pb=} ;;
  esac
done
PWFILE=${PWFILE/#\~/$HOME}

is_ciphertext() {
  head -1 "$1" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT'
}

view_works_unattended() {
  local out
  out=$(ansible-vault view --vault-password-file "$PWFILE" "$VAULTED" 2>&1)
  if grep -qE 'ERROR|Decryption failed' <<<"$out"; then echo "$out" | head -4; return 1; fi
  echo "decrypted cleanly; it defines: $(grep -oE '^[a-z_]+:' <<<"$out" | tr -d ':' | tr '\n' ' ')"
  return 0
}

no_plaintext_in_repo() {
  [[ -n ${SECRET:-} ]] || { echo "no --secret given, so nothing to search for"; return 2; }
  local hits
  hits=$(grep -rIl --exclude-dir=.git -- "$SECRET" . 2>/dev/null)
  [[ -z ${hits// /} ]] && { echo "'$SECRET' appears nowhere in the project"; return 0; }
  echo "the secret is sitting in plaintext in:"
  echo "$hits"
  return 1
}

inline_encrypted_string_exists() {
  local hits
  hits=$(grep -rl '!vault |' --include='*.yml' . 2>/dev/null)
  [[ -n ${hits// /} ]] || { echo "no inline !vault encrypted string anywhere"; return 1; }
  echo "inline encrypted strings in: $(tr '\n' ' ' <<<"$hits")"
  # and the file itself must NOT be wholly encrypted — that is the point
  local f
  for f in $hits; do
    is_ciphertext "$f" || { echo "$f is plaintext with an encrypted value inside — correct"; return 0; }
  done
  echo "every such file is wholly encrypted; the requirement was an inline string"
  return 1
}

playbook_runs_unattended() {
  local out
  out=$(ansible-playbook "$PB" --vault-password-file "$PWFILE" 2>&1)
  echo "$out" | tail -8
  ! grep -qE 'failed=[1-9]|fatal:|vault password' <<<"$out"
}

secret_not_in_output() {
  [[ -n ${SECRET:-} ]] || return 2
  local out
  out=$(ansible-playbook "$PB" --vault-password-file "$PWFILE" -vv 2>&1)
  if grep -qF -- "$SECRET" <<<"$out"; then
    echo "the secret was printed in -vv output:"
    grep -nF -- "$SECRET" <<<"$out" | head -3
    return 1
  fi
  echo "not present in -vv output"
  grep -c 'censored' <<<"$out" | sed 's/^/censored markers: /'
  return 0
}

no_log_used() {
  grep -rqE '^[[:space:]]*no_log:[[:space:]]*(true|yes)' --include='*.yml' . 2>/dev/null
}

# ------------------------------------------------------------------------------
lab_init "7.3" "Ansible Vault" --host rhel-control "$@"
a_init
info "vault password file: $PWFILE"
[[ -z ${SECRET:-} ]] && info "pass --secret=VALUE to have the plaintext search graded"

section "1. group_vars/database.yml is encrypted"
check_file "$VAULTED exists" "$A_PROJ/$VAULTED"
check "cat shows ciphertext, not the password" is_ciphertext "$VAULTED"
check "ansible-vault can view it with the password file" view_works_unattended

section "2. The password comes from a file, not a prompt"
check_file "the vault password file exists" "$PWFILE"
check_eq "it is mode 600 — nobody else can read it" 600 "$(mode_of "$PWFILE")"
check "the playbook runs unattended with --vault-password-file" playbook_runs_unattended
check "no interactive prompt is required" \
  bash -c "! ansible-playbook $PB --vault-password-file '$PWFILE' 2>&1 | grep -qi 'vault password:'"

section "3. An inline encrypted string in a plaintext file"
check "an inline !vault string exists inside an otherwise plaintext file" \
  inline_encrypted_string_exists

section "4. The vault was rekeyed"
manual "You rekeyed the vault and the old password no longer works" \
  "ansible-vault rekey — nothing on disk records that it happened."
check "the file still decrypts with the current password" view_works_unattended

section "5. Viewing and editing without decrypting on disk"
check "no stray decrypted copy left lying around" \
  bash -c 'stray=$(grep -rIl --include="*.yml" -E "^[a-z_]*pass(word)?:[[:space:]]*[^{$]" group_vars/ host_vars/ 2>/dev/null);
           echo "${stray:-none}"; [[ -z ${stray// /} ]]'
check "no .yml.orig / .bak / .decrypted files in the project" \
  bash -c 'f=$(find . -name "*.orig" -o -name "*.bak" -o -name "*decrypt*" 2>/dev/null | grep -v "\.git");
           echo "${f:-none}"; [[ -z ${f// /} ]]'

section "6. The secret never appears in output"
check "tasks handling the secret use no_log: true" no_log_used
info "Vault protects the file at rest; no_log protects it at runtime. You need both."
secret_not_in_output; rc=$?
case $rc in
  0) pass "the secret does not appear even with -vv" ;;
  2) skipped "the secret does not appear in output" "re-run with --secret=VALUE" ;;
  *) fail "the secret does not appear even with -vv" "it was printed — add no_log: true" ;;
esac
no_plaintext_in_repo; rc=$?
case $rc in
  0) pass "grep across the project finds no plaintext secret" ;;
  2) skipped "no plaintext secret in the project" "re-run with --secret=VALUE" ;;
  *) fail "grep across the project finds no plaintext secret" "see the files listed above" ;;
esac

summary
