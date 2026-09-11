#!/usr/bin/env bash
# Lab 6.1 — Labs 1.2 + 1.4 redone as users.yml      (05-Labs-Automate-the-RHCSA-Set)
# Run on rhel-control, as the ordinary user. Never log into a managed node.
#
# The end state is the same as Labs 1.2 and 1.4, so the Month 1 checks grade it:
# they are shipped to the target and run there, from here.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=users.yml

# A deliberately invalid sudoers template must be refused, not deployed.
bad_sudoers_is_refused() {
  local tmpl out
  tmpl=$(grep -rhoE 'src:[[:space:]]*[^[:space:]]+sudoers[^[:space:]]*' "$PB" 2>/dev/null |
         awk '{print $2}' | head -1)
  [[ -n ${tmpl:-} ]] || { echo "cannot find the sudoers template referenced in $PB"; return 2; }
  [[ -f $tmpl ]] || tmpl="templates/$(basename "$tmpl")"
  [[ -f $tmpl ]] || { echo "template file not found: $tmpl"; return 2; }
  cp -a "$tmpl" "$tmpl.verify-backup" || return 1
  printf '\nthis is not valid sudoers syntax at all\n' >> "$tmpl"
  out=$(ansible-playbook "$PB" 2>&1)
  mv -f "$tmpl.verify-backup" "$tmpl"
  echo "$out" | grep -iE 'validat|visudo|failed' | head -4
  # The play must fail, and sudoers on the node must still parse.
  if ! grep -qE 'failed=[1-9]|fatal:' <<<"$out"; then
    echo "the broken template was accepted — validate: is missing or wrong"
    return 1
  fi
  ansible managed -m command -a 'visudo -c' --become 2>&1 | grep -q 'parsed OK'
}

# ------------------------------------------------------------------------------
lab_init "6.1" "Users, sudo and SSH through Ansible" --host rhel-control "$@"
a_init

section "1. The playbook itself"
check_file "$PB exists" "$A_PROJ/$PB"
check "it is valid YAML" a_yaml_ok "$PB"
check "syntax-check passes" ansible-playbook --syntax-check "$PB"
check "it uses the user and group modules, not shell" \
  bash -c "grep -qE '(ansible\.builtin\.)?user:' $PB && grep -qE '(ansible\.builtin\.)?group:' $PB"
check "no useradd/groupadd smuggled in via command or shell" \
  bash -c "! grep -qE '(useradd|groupadd|usermod|chage)' $PB"

section "2. It runs clean and is idempotent"
check "the playbook runs without failures" a_playbook_ok "$PB"
check "a second run reports changed=0" a_idempotent "$PB"

section "3. The Lab 1.2 end state, graded on the node"
check "users, groups and password policy match Lab 1.2 exactly" \
  a_remote_verify managed lab-1.2.sh
info "That was Lab 1.2's own check script, run on the target from here."

section "4. The Lab 1.4 end state, graded on the node"
check "sudo and SSH match Lab 1.4 exactly" \
  a_remote_verify managed lab-1.4.sh

section "5. SSH keys deployed by Ansible"
check "the playbook deploys keys with authorized_key or the user module" \
  bash -c "grep -qE 'authorized_key|ssh_key' $PB"
check "amit and sara have authorized_keys on the nodes" \
  bash -c 'out=$(ansible managed -m shell -a "ls -s /home/amit/.ssh/authorized_keys /home/sara/.ssh/authorized_keys" --become 2>&1);
           echo "$out" | tail -6; ! grep -qE "No such file" <<<"$out"'

section "6. The sudoers file is validated before deployment"
check "validate: visudo -cf appears on the sudoers task" \
  bash -c "grep -E 'validate:' $PB | grep -q 'visudo'"
if mutating "a broken sudoers template is refused, not deployed"; then
  bad_sudoers_is_refused; rc=$?
  case $rc in
    0) pass "a deliberately broken sudoers template was refused" ;;
    2) skipped "broken sudoers template is refused" \
         "could not locate the sudoers template referenced by $PB" ;;
    *) fail "a deliberately broken sudoers template was refused" \
         "it was deployed anyway — that locks root out of a real machine" ;;
  esac
fi

section "7. Port 2222 and its consequences"
check "the playbook handles the SELinux port too" \
  bash -c "grep -qE 'seport|selinux' $PB"
check "and the firewall" bash -c "grep -q 'firewalld' $PB"
check "2222 is labelled ssh_port_t on the nodes" \
  bash -c 'out=$(ansible managed -m shell -a "semanage port -l | grep ^ssh_port_t" --become 2>&1);
           echo "$out" | tail -4; grep -q 2222 <<<"$out"'

section "8. The rule for this week"
manual "You never logged into a managed node to fix anything" \
  "If you did, the playbook is not finished. Fix the playbook and re-run."

summary
