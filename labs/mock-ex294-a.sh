#!/usr/bin/env bash
# Mock EX294-A — grader                             (08-EX294-Exam-Prep, Day 56)
# Run on rhel-control, as the ordinary user, AFTER rebooting every managed node.
#
#   ./mock-ex294-a.sh --spec                    print the exam paper
#   ./mock-ex294-a.sh --proj=~/ansible-exam     grade it
#   ./mock-ex294-a.sh --proj=~/ansible-exam --secret=S3cret --pw=~/.vault_pass
#
# Mock EX294-B is this same paper on a wrecked estate: run break.sh all on
# rhel01 and break-ansible.sh random first, then grade with this script.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"

if [[ ${1:-} == --spec ]]; then
  cat <<'SPEC'
Mock EX294-A — 4 hours, closed book (ansible-doc, man, /usr/share/doc only).
All three nodes reverted to `clean`. Work only from rhel-control. You may not
SSH into a managed node except to verify. Graded after a reboot of every node.

 1. /home/<you>/ansible-exam/ with an ansible.cfg setting inventory, roles path,
    collections path, remote user and privilege escalation.
 2. An inventory with groups webservers, databases, prod, dev and a parent group
    all_managed.
 3. ansible.posix and community.general installed into a project-local path from
    a requirements.yml.
 4. packages.yml — install a defined package list on all managed hosts, plus one
    extra package only on hosts with more than 1 GB of RAM, decided by a fact.
 5. users.yml — create users from a vault-encrypted variable file; the web list
    gets accounts on webservers only, the db list on databases only. Passwords
    hashed, never plaintext. SSH keys deployed.
 6. webserver.yml — httpd installed and enabled on webservers, a templated
    index.html naming the host and its IP from facts, the firewall open, and
    correct SELinux contexts for a non-default document root.
 7. storage.yml — on databases, a VG and LV from a blank disk, XFS, mounted
    persistently at /dbdata. If the disk is absent the play must fail with a
    clear message rather than crash.
 8. roles/apache/ — a role fully configuring a web server, all tunables in
    defaults/, with handlers.
 9. site.yml — runs everything in the right order, with a tag per stage.
10. report.yml — generates /root/report.txt on every managed host containing
    hostname, IP, kernel, memory and free disk, from a template.
11. A rolling update across webservers, two at a time, aborting above 25%
    failure.
12. Every playbook idempotent: a second run reports changed=0.
SPEC
  exit 0
fi

. "$_D/../lib/ansible-lib.sh"

SECRET=""; PWFILE=""
for a in "$@"; do
  case "$a" in
    --secret=*) SECRET=${a#--secret=} ;;
    --pw=*)     PWFILE=${a#--pw=} ;;
  esac
done
PWFILE=${PWFILE/#\~/$HOME}
VAULT_ARGS=()
[[ -n ${PWFILE:-} && -f ${PWFILE:-} ]] && VAULT_ARGS=(--vault-password-file "$PWFILE")

cfgv() { ansible-config dump 2>/dev/null | grep -i "^$1" | cut -d= -f2- | tr -d ' '; }

sets_inventory() {
  local v
  v=$(cfgv DEFAULT_HOST_LIST)
  echo "inventory in force: ${v:-<none>}"
  [[ -n ${v// /} ]] || grep -qiE '^[[:space:]]*inventory[[:space:]]*=' ansible.cfg
}

run_pb() {   # run a playbook with the vault password if one was given
  local pb="$1"; shift
  [[ -f $pb ]] || { echo "$pb does not exist"; return 1; }
  A_LAST_RUN=$(ansible-playbook "$pb" ${VAULT_ARGS[@]+"${VAULT_ARGS[@]}"} "$@" 2>&1)
  local rc=$?
  V_LAST_OUT="$A_LAST_RUN"
  a_recap
  ((rc == 0)) && [[ $(a_recap_field failed) -eq 0 && $(a_recap_field unreachable) -eq 0 ]]
}

idem_pb() {
  run_pb "$1" >/dev/null 2>&1
  local changed
  changed=$(a_recap_field changed)
  a_recap
  [[ ${changed:-0} -eq 0 ]] || {
    echo "changed=$changed on a repeat run"
    grep -B2 'changed:' <<<"$A_LAST_RUN" | grep '^TASK' | head -6
    return 1; }
}

extra_pkg_by_ram_fact() {
  grep -qE 'ansible_memtotal_mb|memtotal' packages.yml 2>/dev/null &&
    grep -qE 'when:.*(memtotal|memfree)' packages.yml 2>/dev/null
}

users_split_by_group() {
  local bad=0 out
  out=$(ansible webservers -m shell -a 'getent passwd | cut -d: -f1,3' 2>&1)
  local dbout
  dbout=$(ansible databases -m shell -a 'getent passwd | cut -d: -f1,3' 2>&1)
  # the two host groups must NOT have identical user sets
  local wu du
  wu=$(grep -oE '^[a-z_]+:[0-9]{4}' <<<"$out" | sort -u | md5sum | cut -c1-8)
  du=$(grep -oE '^[a-z_]+:[0-9]{4}' <<<"$dbout" | sort -u | md5sum | cut -c1-8)
  echo "user-set fingerprints — webservers: $wu, databases: $du"
  [[ $wu == "$du" ]] && { echo "both groups got the same accounts — the split did not happen"; bad=1; }
  return $bad
}

passwords_hashed() {
  local out bad=0
  out=$(ansible all_managed -m shell -a "awk -F: '\$3>=1000 && \$3<65534 {print \$1}' /etc/passwd | while read u; do getent shadow \$u | cut -d: -f1,2; done" --become 2>&1)
  echo "$out" | grep -E '^[a-z_]+:' | head -8
  while read -r line; do
    [[ $line =~ ^[a-z_]+: ]] || continue
    local h=${line#*:}
    [[ -z ${h:-} || $h == '!!' || $h == '*' || $h == '!'* ]] && continue
    [[ $h =~ ^\$[0-9a-z]+\$ ]] || { echo "not a hash: $line"; bad=1; }
  done <<<"$out"
  [[ -n ${SECRET:-} ]] && grep -qF -- "$SECRET" <<<"$out" && {
    echo "a plaintext secret is in /etc/shadow"; bad=1; }
  return $bad
}

storage_fails_clearly_without_disk() {
  local out
  out=$(ansible-playbook storage.yml ${VAULT_ARGS[@]+"${VAULT_ARGS[@]}"} \
        -e 'db_disk=/dev/doesnotexist' 2>&1)
  echo "$out" | grep -iE 'msg|fail' | head -5
  # it must fail, and with a message, not a traceback
  grep -qE 'failed=[1-9]|fatal:' <<<"$out" || { echo "it did not fail on a missing disk"; return 1; }
  grep -qiE '"msg"|assertion|not present|does not exist' <<<"$out"
}

dbdata_mounted() {
  local out
  out=$(ansible databases -m command -a 'findmnt -no TARGET,SOURCE,FSTYPE /dbdata' --become 2>&1)
  echo "$out" | grep -vE 'CHANGED|SUCCESS|=>' | head -4
  grep -q '/dbdata' <<<"$out" && grep -q xfs <<<"$out"
}

report_file_complete() {
  local out bad=0 want
  out=$(ansible all_managed -m command -a 'cat /root/report.txt' --become 2>&1)
  echo "$out" | grep -vE 'CHANGED|SUCCESS|=>' | head -12
  for want in kernel mem; do
    grep -qi "$want" <<<"$out" || { echo "the report does not mention: $want"; bad=1; }
  done
  local h
  for h in $(a_hosts_in all_managed); do
    ansible "$h" -m command -a 'cat /root/report.txt' --become 2>&1 | grep -q "$h" ||
      { echo "$h's report does not name it"; bad=1; }
  done
  return $bad
}

rolling_two_at_a_time() {
  local f
  f=$(grep -rln 'serial' --include='*.yml' . 2>/dev/null | head -1)
  [[ -n ${f:-} ]] || { echo "no playbook sets serial"; return 1; }
  echo "rolling config in: $f"
  grep -E 'serial|max_fail_percentage' "$f" | head -4
  grep -qE 'serial:[[:space:]]*2' "$f" && grep -qE 'max_fail_percentage:[[:space:]]*25' "$f"
}

no_plaintext_passwords() {
  local hits
  hits=$(grep -rn 'password' --include='*.yml' . 2>/dev/null |
         grep -vE '\$ANSIBLE_VAULT|!vault|password_hash|no_log|vault_|_password:[[:space:]]*\{\{')
  [[ -z ${hits// /} ]] && return 0
  echo "possible plaintext password references:"
  echo "$hits" | head -6
  return 1
}

# ------------------------------------------------------------------------------
lab_init "ex294-a" "Mock EX294-A" --host rhel-control --score "$@"
a_init
[[ ${#VAULT_ARGS[@]} -eq 0 ]] && info "no --pw given: vault-dependent playbooks may prompt and fail"

section "1. The project and its ansible.cfg"
check_file "ansible.cfg exists in the project" "$A_PROJ/ansible.cfg"
check "ansible is reading it, not /etc/ansible/ansible.cfg" a_cfg_is_mine
check "it sets the inventory" sets_inventory
check "it sets roles_path" bash -c "grep -qiE '^[[:space:]]*roles_path[[:space:]]*=' ansible.cfg"
check "it sets collections_path" bash -c "grep -qiE '^[[:space:]]*collections_paths?[[:space:]]*=' ansible.cfg"
check "it sets remote_user" bash -c "grep -qiE '^[[:space:]]*remote_user[[:space:]]*=' ansible.cfg"
check "it configures privilege escalation" \
  bash -c "grep -qiE '^[[:space:]]*become[[:space:]]*=[[:space:]]*(true|yes|True)' ansible.cfg"

section "2. The inventory groups"
for g in webservers databases prod dev all_managed; do
  check "group $g exists and resolves to at least one host" \
    bash -c "[[ \$(a_hosts_in $g | grep -c .) -ge 1 ]]"
done
check "all_managed is a parent group, not a flat list" \
  bash -c "ansible-inventory --graph 2>/dev/null | awk '/@all_managed:/ { f = 1; next } /^  @/ && f { n++ } END { exit !(n >= 2) }'"
check "every host in all_managed answers a ping" a_all_reachable all_managed
check "become works everywhere without a password" a_become_works all_managed

section "3. Collections from requirements.yml, project-local"
check_file "requirements.yml exists" "$A_PROJ/requirements.yml"
check "ansible.posix is installed" bash -c "ansible-galaxy collection list 2>/dev/null | grep -q '^ansible.posix'"
check "community.general is installed" bash -c "ansible-galaxy collection list 2>/dev/null | grep -q '^community.general'"
check "they live inside the project directory" \
  bash -c "d=\$(find '$A_PROJ' -maxdepth 4 -type d -name ansible_collections | head -1); echo \"\${d:-none}\"; [[ -n \${d:-} ]]"

section "4. packages.yml"
check_file "packages.yml exists" "$A_PROJ/packages.yml"
check "syntax-check passes" ansible-playbook --syntax-check packages.yml
check "the extra package is gated on a memory fact" extra_pkg_by_ram_fact
check "it runs clean" run_pb packages.yml
check "and is idempotent" idem_pb packages.yml

section "5. users.yml from a vault-encrypted variable file"
check_file "users.yml exists" "$A_PROJ/users.yml"
check "a vault-encrypted variable file exists" \
  bash -c "n=\$(grep -rl '^\\\$ANSIBLE_VAULT' group_vars/ host_vars/ vars/ 2>/dev/null | grep -c .);
           echo \"encrypted files: \$n\"; [[ \${n:-0} -ge 1 ]]"
check "web users land on webservers and db users on databases, not both" users_split_by_group
check "every account password in /etc/shadow is a hash" passwords_hashed
check "the playbook uses the password_hash filter" \
  bash -c "grep -q 'password_hash' users.yml"
check "SSH keys are deployed" bash -c "grep -qE 'authorized_key|ssh_key' users.yml"
check "it runs clean" run_pb users.yml
check "and is idempotent" idem_pb users.yml

section "6. webserver.yml"
check_file "webserver.yml exists" "$A_PROJ/webserver.yml"
check "httpd is enabled on every webserver" \
  bash -c 'out=$(ansible webservers -m command -a "systemctl is-enabled httpd" 2>&1);
           echo "$out" | tail -4; ! grep -qE "disabled|FAILED" <<<"$out"'
check "each webserver serves a page naming itself" \
  bash -c 'bad=0; for h in $(a_hosts_in webservers); do
             ansible "$h" -m uri -a "url=http://$h/ return_content=true" 2>&1 | grep -q "$h" || bad=1
           done; exit $bad'
check "the page carries the host IP from facts" \
  bash -c "grep -qE 'ansible_default_ipv4|ansible_facts' webserver.yml templates/*.j2 2>/dev/null"
check "the firewall is open for http" \
  bash -c 'out=$(ansible webservers -m command -a "firewall-cmd --list-services" --become 2>&1);
           echo "$out" | tail -4; grep -q http <<<"$out"'
check "the non-default document root has the right SELinux context" \
  bash -c 'out=$(ansible webservers -m shell -a "semanage fcontext -l | grep httpd_sys_content_t | grep -v /var/www" --become 2>&1);
           echo "$out" | head -4; grep -q httpd_sys_content_t <<<"$out"'
check "SELinux is enforcing everywhere" \
  bash -c 'out=$(ansible all_managed -m command -a getenforce 2>&1); echo "$out" | tail -4;
           ! grep -qiE "permissive|disabled" <<<"$out"'
check "it runs clean" run_pb webserver.yml
check "and is idempotent" idem_pb webserver.yml

section "7. storage.yml"
check_file "storage.yml exists" "$A_PROJ/storage.yml"
check "/dbdata is an XFS mount on the databases group" dbdata_mounted
check -p "it is persistent in /etc/fstab" \
  bash -c 'out=$(ansible databases -m shell -a "grep dbdata /etc/fstab" --become 2>&1);
           echo "$out" | grep -E "dbdata" | head -3; grep -q dbdata <<<"$out"'
check "a missing disk makes the play fail with a clear message, not a crash" \
  storage_fails_clearly_without_disk
check "it is idempotent" idem_pb storage.yml

section "8. roles/apache"
check_dir "roles/apache exists" "$A_PROJ/roles/apache"
check "it has defaults, tasks, handlers, templates and meta" \
  bash -c 'bad=0; for f in defaults/main.yml tasks/main.yml handlers/main.yml meta/main.yml; do
             [[ -f roles/apache/$f ]] || { echo "missing: roles/apache/$f"; bad=1; }; done
           [[ -d roles/apache/templates ]] || { echo "missing: roles/apache/templates/"; bad=1; }
           exit $bad'
check "all tunables are in defaults, not vars" \
  bash -c "[[ -s roles/apache/defaults/main.yml ]] && ! grep -qE '^[a-z_]*(port|document_root):' roles/apache/vars/main.yml 2>/dev/null"
check "tasks notify handlers" bash -c "grep -qE '^[[:space:]]*notify:' roles/apache/tasks/main.yml"

section "9. site.yml with a tag per stage"
check_file "site.yml exists" "$A_PROJ/site.yml"
check "syntax-check passes" ansible-playbook --syntax-check site.yml
check "it lists roles or imports the other playbooks" \
  bash -c "grep -qE '^[[:space:]]*roles:|import_playbook|include_role' site.yml"
check "--list-tags shows per-stage tags" \
  bash -c "ansible-playbook site.yml --list-tags 2>&1 | grep -qi 'task tags'"
report "the tags it defines" bash -c "ansible-playbook site.yml --list-tags 2>/dev/null | tail -6"
check "it runs the whole estate clean" run_pb site.yml
check "and the second run reports changed=0" idem_pb site.yml

section "10. report.yml"
check_file "report.yml exists" "$A_PROJ/report.yml"
check "it uses a template" bash -c "grep -qE '(ansible\.builtin\.)?template:' report.yml"
check "/root/report.txt exists on every managed host and is complete" report_file_complete
check "it is idempotent" idem_pb report.yml

section "11. The rolling update"
check "serial: 2 and max_fail_percentage: 25 are configured" rolling_two_at_a_time
check "the rolling play targets webservers" \
  bash -c "grep -rlE 'serial' --include='*.yml' . | head -1 | xargs grep -qE 'hosts:.*webserver'"

section "12. No plaintext secrets anywhere"
check "no plaintext password references in any playbook" no_plaintext_passwords
if [[ -n ${SECRET:-} ]]; then
  check "the secret appears nowhere in the project" \
    bash -c "h=\$(grep -rIl --exclude-dir=.git -- '$SECRET' . 2>/dev/null); echo \"\${h:-none}\"; [[ -z \${h// /} ]]"
else
  skipped "the secret appears nowhere in the project" "re-run with --secret=VALUE"
fi

summary
