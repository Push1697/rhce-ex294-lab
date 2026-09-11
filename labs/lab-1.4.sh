#!/usr/bin/env bash
# Lab 1.4 — sudo and SSH key authentication         (01-Labs-RHCSA-Foundation)
# Run on rhel01, as root.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

sshd_eff() { sshd -T 2>/dev/null; }   # the effective config, not the file

# sudo -l as another user reports exactly what they may run.
sudo_allows() {   # sudo_allows <user> <command line>
  local u="$1"; shift
  runuser -u "$u" -- sudo -n -l -- "$@" >/dev/null 2>&1
}

sudo_nopasswd_for() {   # is this command available WITHOUT a password?
  local u="$1"; shift
  runuser -u "$u" -- sudo -n -l 2>/dev/null | grep -q "NOPASSWD.*$1"
}

listening_on() { ss -tlnH 2>/dev/null | awk '{ print $4 }' | grep -Eq "[:.]$1\$"; }

# ------------------------------------------------------------------------------
lab_init "1.4" "sudo and SSH key authentication" --host rhel01 --root "$@"

section "1. developers may run only the two httpd commands, passwordless"
check "sudoers syntax is valid across all files" visudo -c
if user_exists sara; then
  check "sara may run 'systemctl restart httpd'" sudo_allows sara /usr/bin/systemctl restart httpd
  check "sara may run 'systemctl status httpd'"  sudo_allows sara /usr/bin/systemctl status httpd
  check "it is passwordless for her" sudo_nopasswd_for sara systemctl
  check_not "sara may NOT restart sshd" sudo_allows sara /usr/bin/systemctl restart sshd
  check_not "sara may NOT run an arbitrary command as root" sudo_allows sara /bin/bash
else
  skipped "developers sudo rules" "no user 'sara' on this host — do Lab 1.2 first"
fi
report "what sudo reports for sara" bash -c 'runuser -u sara -- sudo -n -l 2>&1 | tail -5'

section "2. amit may run anything, but must type a password"
if user_exists amit; then
  check_match "sudo -l -U amit shows (ALL) ALL" '\(ALL\)[[:space:]]*(ALL|ALL : ALL)' \
    bash -c 'sudo -l -U amit 2>/dev/null'
  check_nomatch "amit's rule is NOT passwordless" 'NOPASSWD' \
    bash -c 'sudo -l -U amit 2>/dev/null | grep -A5 "may run"'
else
  skipped "amit's sudo rule" "no user 'amit' on this host"
fi

section "3. Password authentication disabled entirely"
check_match -p "sshd's effective PasswordAuthentication is no" \
  '^passwordauthentication no' sshd_eff
check_match -p "KbdInteractiveAuthentication is also off" \
  '^(kbdinteractiveauthentication|challengeresponseauthentication) no' sshd_eff
check_match -p "PubkeyAuthentication is on" '^pubkeyauthentication yes' sshd_eff

section "4. Root cannot log in over SSH"
check_match -p "sshd's effective PermitRootLogin is no" '^permitrootlogin no' sshd_eff

section "5. sshd listens on 2222 as well as 22"
check_match -p "sshd config declares port 2222" '^port 2222' sshd_eff
check_match -p "sshd config still declares port 22" '^port 22$' sshd_eff
check "something is listening on :22" listening_on 22
check "something is listening on :2222" listening_on 2222
check "sshd is running" systemctl is-active --quiet sshd

section "6. The two consequences of moving a port"
if need_cmd "SELinux port label for 2222" semanage; then
  check_match -p "2222 is labelled ssh_port_t" '(^|[^0-9])2222([^0-9]|$)' \
    bash -c 'semanage port -l | grep ^ssh_port_t'
fi
if need_cmd "firewalld rule for 2222" firewall-cmd; then
  check -p "2222/tcp is open in the running firewall" \
    bash -c 'firewall-cmd --list-ports 2>/dev/null | grep -q 2222/tcp'
  check -p "2222/tcp is open permanently, not just at runtime" \
    bash -c 'firewall-cmd --permanent --list-ports 2>/dev/null | grep -q 2222/tcp'
fi

section "7. Key-based login from the control node"
manual "ssh amit@rhel01 from rhel-control succeeds with the key and no prompt" \
  "Run it from rhel-control: ssh -p 2222 amit@rhel01 hostname"
manual "ssh -o PubkeyAuthentication=no amit@rhel01 is refused" \
  "Run it from rhel-control; it must not fall back to a password prompt."
if user_exists amit; then
  ah=$(user_home amit)
  check_sh "amit has an authorized_keys file" "[[ -s '$ah/.ssh/authorized_keys' ]]"
  check_eq "amit's ~/.ssh is mode 700" 700 "$(mode_of "$ah/.ssh")"
  check_sh "amit's authorized_keys is mode 600 or 644" \
    "[[ \$(mode_of '$ah/.ssh/authorized_keys') =~ ^(600|644)$ ]]"
fi

summary
