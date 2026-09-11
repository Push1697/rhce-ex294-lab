#!/usr/bin/env bash
# break-ansible.sh — corrupt the automation project so you can practise repair.
# Commit your work to git first:  git init && git add -A && git commit -m ok
set -Eeuo pipefail
PROJ="${1:-$HOME/ansible}"; cd "$PROJ"

f_yaml()      { sed -i '0,/^    - name:/s//   - name:/' site.yml; }          # indentation
f_inventory() { sed -i 's/^rhel01/rhel99/' inventory; }                       # unreachable host
f_ssh()       { chmod 600 ~/.ssh/id_ed25519.pub; mv ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.bak; }
f_sudo()      { sed -i 's/^become = True/become = False/' ansible.cfg; }
f_undefvar()  { sed -i 's/{{ apache_port }}/{{ apache_prt }}/' roles/apache/templates/*.j2; }
f_collection(){ sed -i 's/ansible.posix.firewalld/ansible.posix.firewalld_typo/' roles/*/tasks/main.yml; }
f_condition() { sed -i 's/when: inventory_hostname in groups\["web"\]/when: inventory_hostname in groups["wb"]/' site.yml; }
f_template()  { printf '{%% if unclosed %%}\n' >> roles/apache/templates/vhost.conf.j2; }
f_handler()   { sed -i 's/notify: restart apache/notify: restart apach/' roles/apache/tasks/main.yml; }

FAULTS=(yaml inventory ssh sudo undefvar collection condition template handler)
case "${2:-random}" in
  list) printf '%s\n' "${FAULTS[@]}" ;;
  random) f="${FAULTS[$RANDOM % ${#FAULTS[@]}]}"; "f_$f"; echo "Fault applied. Find it." ;;
  *) "f_${2}"; echo "Applied: $2" ;;
esac
