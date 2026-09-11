#!/usr/bin/env bash
# Lab 2.1 — systemd services and targets            (01-Labs-RHCSA-Foundation)
# Run on rhel01, as root.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

LOG=/var/log/siteguard.log

# The whole point of the lab: did the unit run on THIS boot?
ran_since_boot() {
  local boot mt
  boot=$(date -d "$(uptime -s)" +%s 2>/dev/null) || { echo "cannot determine boot time"; return 1; }
  [[ -f $LOG ]] || { echo "$LOG does not exist"; return 1; }
  mt=$(stat -c %Y "$LOG")
  echo "boot at $(date -d "@$boot" '+%F %T'), log last written $(date -d "@$mt" '+%F %T')"
  ((mt >= boot))
}

# ------------------------------------------------------------------------------
lab_init "2.1" "systemd services and targets" --host rhel01 --root "$@"

section "1. httpd installed and starting at boot"
check "httpd is installed" rpm -q httpd
check -p "httpd is enabled" systemctl is-enabled --quiet httpd
check "httpd is active now" systemctl is-active --quiet httpd

section "2. The siteguard script"
check_file "/usr/local/bin/siteguard exists" /usr/local/bin/siteguard
check_sh "it is executable" '[[ -x /usr/local/bin/siteguard ]]'
check "running it by hand exits 0" /usr/local/bin/siteguard

section "3. siteguard.service"
check "the unit exists and systemd can read it" systemctl cat siteguard.service
check -p "it is enabled" systemctl is-enabled --quiet siteguard.service
check_match -p "it starts after the network is online" 'network-online.target' \
  bash -c 'systemctl show -p After --value siteguard.service'
check_match -p "it wants network-online.target (not just After=)" 'network-online.target' \
  bash -c 'systemctl show -p Wants --value siteguard.service'
check_eq -p "Restart=on-failure" "on-failure" "$(unit_prop siteguard.service Restart)"
check_match -p "installed into multi-user.target" 'WantedBy[[:space:]]*=[[:space:]]*multi-user.target' \
  systemctl cat siteguard.service
check "the unit file has no syntax complaints" \
  bash -c 'systemd-analyze verify siteguard.service 2>&1 | grep -qv . || true'

section "4. The log proves it ran this boot"
check_file "$LOG exists" "$LOG"
check -p "it was written on the current boot, not a previous one" ran_since_boot
report "last three lines" bash -c "tail -3 $LOG 2>/dev/null"

section "5. The system boots to multi-user, never graphical"
check_eq -p "default target is multi-user.target" "multi-user.target" "$(systemctl get-default)"

section "6. debug-shell.service is masked"
check_eq -p "is-enabled reports masked" "masked" "$(systemctl is-enabled debug-shell.service 2>&1)"
check_not "starting it fails" systemctl start debug-shell.service

section "7. Boot performance"
report "slowest units at boot" bash -c 'systemd-analyze blame 2>/dev/null | head -5'
manual "You can name the slowest unit to start at boot" \
  "Read the list above; you should be able to answer this without the script."

summary
