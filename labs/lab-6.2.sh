#!/usr/bin/env bash
# Lab 6.2 — Labs 2.1 + 2.3 redone as services.yml   (05-Labs-Automate-the-RHCSA-Set)
# Run on rhel-control, as the ordinary user.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"
. "$_D/../lib/ansible-lib.sh"

PB=services.yml

# Changing the unit file must trigger daemon_reload; an unchanged run must not.
reload_only_on_change() {
  local out
  a_run "$PB" >/dev/null 2>&1
  if grep -qiE 'daemon.reload|systemd.*daemon' <<<"$A_LAST_RUN" &&
     grep -qE 'changed:' <<<"$A_LAST_RUN"; then
    echo "an unchanged run still reloaded systemd"
    return 1
  fi
  echo "unchanged run: no daemon-reload, as required"
  # now disturb the unit on one host and confirm the reload happens
  local h
  h=$(a_hosts_in managed | head -1)
  ansible "$h" -m lineinfile -a \
    'path=/etc/systemd/system/siteguard.service line="# disturbed by the verifier" insertafter=EOF' \
    --become >/dev/null 2>&1 || { echo "could not disturb the unit on $h"; return 2; }
  a_run "$PB" >/dev/null 2>&1
  out=$(a_recap)
  echo "$out"
  grep -qE 'changed=[1-9]' <<<"$out"
}

reboot_survived() {
  local out
  out=$(ansible managed -m command -a 'systemctl is-active siteguard' 2>&1)
  echo "$out" | tail -4
  ! grep -qE 'inactive|failed|FAILED' <<<"$out"
}

# ------------------------------------------------------------------------------
lab_init "6.2" "Packages, repositories and services through Ansible" --host rhel-control "$@"
a_init

section "1. The playbook itself"
check_file "$PB exists" "$A_PROJ/$PB"
check "it is valid YAML" a_yaml_ok "$PB"
check "syntax-check passes" ansible-playbook --syntax-check "$PB"

section "2. The repository is defined by the yum_repository module"
check "yum_repository is used, not a copied .repo file" \
  bash -c "grep -q 'yum_repository' $PB"
check "the repo exists on the managed nodes" \
  bash -c 'out=$(ansible managed -m command -a "dnf repolist enabled" --become 2>&1);
           echo "$out" | tail -6; grep -q locallab <<<"$out"'
check "the .repo file on the node is Ansible-managed, not hand-edited" \
  bash -c 'out=$(ansible managed -m shell -a "cat /etc/yum.repos.d/locallab.repo" --become 2>&1);
           echo "$out" | head -8; grep -qE "baseurl" <<<"$out"'

section "3. A defined package list is installed"
check "the playbook installs a list of packages in one task" \
  bash -c "grep -A4 -E '(dnf|package):' $PB | grep -qE 'loop:|name:[[:space:]]*\[|\{\{'"
check "the packages are present on the nodes" \
  bash -c 'out=$(ansible managed -m command -a "rpm -q httpd" 2>&1);
           echo "$out" | tail -4; ! grep -q "not installed" <<<"$out"'

section "4. siteguard's script and unit come from templates"
check "the playbook deploys them with template or copy" \
  bash -c "grep -qE '(ansible\.builtin\.)?(template|copy):' $PB"
check "the unit file is templated into /etc/systemd/system" \
  bash -c "grep -qE 'dest:.*(systemd/system).*siteguard' $PB"

section "5. daemon_reload happens only when the unit changes"
check "the playbook uses daemon_reload (in a handler or task)" \
  bash -c "grep -qE 'daemon_reload|daemon-reload' $PB"
if mutating "daemon-reload fires on change and not otherwise"; then
  reload_only_on_change; rc=$?
  case $rc in
    0) pass "the reload happened on a real change, and not on an unchanged run" ;;
    2) skipped "reload on change" "could not disturb the unit file on the target" ;;
    *) fail "the reload happened on a real change, and not on an unchanged run" \
         "see the run output above" ;;
  esac
fi

section "6. The unit is enabled and running"
check "siteguard is enabled on the nodes" \
  bash -c 'out=$(ansible managed -m command -a "systemctl is-enabled siteguard" 2>&1);
           echo "$out" | tail -4; ! grep -qE "disabled|masked|FAILED" <<<"$out"'
check "it is active" reboot_survived

section "7. Default target and the masked unit"
check "the default target is multi-user on every node" \
  bash -c 'out=$(ansible managed -m command -a "systemctl get-default" 2>&1);
           echo "$out" | tail -4; [[ $(grep -c "multi-user.target" <<<"$out") -ge 1 ]] &&
           ! grep -q graphical <<<"$out"'
check "debug-shell.service is masked on every node" \
  bash -c 'out=$(ansible managed -m command -a "systemctl is-enabled debug-shell.service" 2>&1);
           echo "$out" | tail -4; grep -q masked <<<"$out"'

section "8. The Lab 2.1 end state, graded on the node"
check "systemd state matches Lab 2.1" a_remote_verify managed lab-2.1.sh

section "9. Idempotence and reboot survival"
check "the playbook runs clean" a_playbook_ok "$PB"
check "a second run reports changed=0" a_idempotent "$PB"
check "the nodes are reachable after the playbook's own reboot" a_all_reachable managed
manual "The playbook itself rebooted the nodes and everything came back" \
  "ansible managed -m reboot --become, then re-run this script."

summary
