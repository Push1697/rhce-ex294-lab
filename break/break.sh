#!/usr/bin/env bash
# break.sh — deliberately damage this box so you can practise repairing it.
# ALWAYS snapshot first:  virsh snapshot-create-as rhel01 pre-lab
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }

fault_fstab() {        # boot fails into emergency mode
  printf 'UUID=00000000-dead-beef-0000-000000000000 /data xfs defaults 0 0\n' >> /etc/fstab
}
fault_selinux_ctx() {  # httpd 403s on correctly-permissioned files
  mkdir -p /web/site; echo ok > /web/site/index.html
  chcon -t user_home_t /web/site/index.html 2>/dev/null || true
  sed -i 's#^DocumentRoot.*#DocumentRoot "/web/site"#' /etc/httpd/conf/httpd.conf
  systemctl restart httpd 2>/dev/null || true
}
fault_selinux_port() { # sshd refuses to start on a new port
  sed -i 's/^#\?Port 22$/Port 2222/' /etc/ssh/sshd_config
  semanage port -d -t ssh_port_t -p tcp 2222 2>/dev/null || true
}
fault_firewall() {     # service runs, nothing can reach it
  firewall-cmd --permanent --remove-service=http >/dev/null 2>&1 || true
  firewall-cmd --permanent --remove-port=8080/tcp >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null
}
fault_service() {      # unit fails at start
  printf '\nInvalidDirective yes\n' >> /etc/httpd/conf/httpd.conf
  systemctl restart httpd 2>/dev/null || true
}
fault_perms() {        # ssh key auth silently stops working
  chmod 777 /home/amit/.ssh 2>/dev/null || true
  chmod 666 /home/amit/.ssh/authorized_keys 2>/dev/null || true
}
fault_repo() {         # dnf breaks
  sed -i 's#^baseurl=.*#baseurl=file:///nonexistent#' /etc/yum.repos.d/locallab.repo 2>/dev/null || \
    printf '[broken]\nname=broken\nbaseurl=http://invalid.example.com/repo\nenabled=1\ngpgcheck=0\n' \
      > /etc/yum.repos.d/broken.repo
}
fault_dns() {          # name resolution dies, IPs still work
  nmcli con mod lab-static ipv4.dns "203.0.113.99" 2>/dev/null || true
  nmcli con up lab-static >/dev/null 2>&1 || true
}
fault_sudo() {         # a group loses privilege escalation
  sed -i 's/^%wheel/#%wheel/' /etc/sudoers
}
fault_mount() {        # persistent mount silently absent after reboot
  sed -i '/\/app/s/^/#/' /etc/fstab
  umount /app 2>/dev/null || true
}

FAULTS=(fstab selinux_ctx selinux_port firewall service perms repo dns sudo mount)

case "${1:-random}" in
  random) f="${FAULTS[$RANDOM % ${#FAULTS[@]}]}"; "fault_$f"
          echo "A fault has been applied. Good luck." ;;
  list)   printf '%s\n' "${FAULTS[@]}" ;;
  all)    for f in "${FAULTS[@]}"; do "fault_$f"; done; echo "All faults applied. Brutal mode." ;;
  *)      "fault_$1" && echo "Applied: $1" ;;
esac
