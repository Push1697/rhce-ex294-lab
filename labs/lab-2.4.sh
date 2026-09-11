#!/usr/bin/env bash
# Lab 2.4 — Networking with nmcli                   (01-Labs-RHCSA-Foundation)
# Run on rhel01, as root.
#
# The lab configures a *spare* interface, never the one your session arrives on.
# On Vagrant/VirtualBox that is the third NIC, which the Vagrantfile creates and
# deliberately leaves unconfigured; on KVM it is whichever interface has no
# address. Reconfiguring the management interface would cut you off mid-lab, and
# on a VirtualBox host-only network there is no router to be a gateway.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

CON=lab-static
NET=$(lab_net)
IP1=$NET.31/24
IP2=$NET.51/24
FQDN=rhel01.lab.local
MGMT=$(mgmt_iface)
SPARE=$(spare_iface || true)
PRIMARY=$(primary_lab_ip)

cfield() { nmcli -g "$1" con show "$CON" 2>/dev/null; }

profile_is_active() {
  local dev
  dev=$(nmcli -g GENERAL.DEVICES con show "$CON" 2>/dev/null)
  echo "profile is bound to device: ${dev:-<none>}"
  nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | grep -q "^$CON:"
}

# The one mistake that ends the lab early: taking over the interface your SSH
# session is using, or the one the lab network already runs on.
leaves_management_alone() {
  local dev
  dev=$(nmcli -g GENERAL.DEVICES con show "$CON" 2>/dev/null)
  echo "lab-static is on '${dev:-none}'"
  echo "hands off: '${MGMT:-?}' (management)${SPARE:+ ; expected '$SPARE' (the spare NIC)}"
  [[ -n ${dev:-} ]] || { echo "the profile is not bound to any device"; return 1; }
  [[ -n ${MGMT:-} && $dev == "$MGMT" ]] && {
    echo "that is the management interface — configure the spare NIC instead"; return 1; }
  [[ -n ${SPARE:-} && $dev != "$SPARE" ]] && {
    echo "the environment set aside '$SPARE' for this lab"; return 1; }
  return 0
}

# Taking the address the environment already gave this node would break every
# other node's route to it.
primary_ip_untouched() {
  [[ -n ${PRIMARY:-} ]] || { echo "the environment did not record a primary address"; return 2; }
  local live
  live=$(ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -Fx "$PRIMARY")
  echo "the node's original lab address $PRIMARY is ${live:+still }${live:-NO LONGER }live"
  [[ -n ${live:-} ]]
}

both_addresses_live() {
  local missing=0 a
  for a in "${IP1%%/*}" "${IP2%%/*}"; do
    ip -4 -o addr show 2>/dev/null | grep -q "$a" || { echo "not on any interface: $a"; missing=1; }
  done
  return $missing
}

no_handwritten_ifcfg() {
  local n
  n=$(find /etc/sysconfig/network-scripts -maxdepth 1 -name 'ifcfg-*' 2>/dev/null | wc -l)
  echo "ifcfg-* files present: $n"
  ((n == 0))
}

dns_configured() {
  local d
  d=$(cfield ipv4.dns)
  echo "ipv4.dns = ${d:-<empty>}"
  [[ $(tr ',' '\n' <<<"$d" | grep -c .) -ge 2 ]]
}

# A host-only network has no router, so this profile must not claim the default
# route or it will blackhole everything the NAT interface was carrying.
never_default() {
  local nd
  nd=$(cfield ipv4.never-default)
  echo "ipv4.never-default = ${nd:-no}"
  [[ $nd == yes ]]
}

still_reachable() {
  local bad=0 h
  for h in rhel02 rhel-control; do
    getent hosts "$h" >/dev/null 2>&1 || { echo "cannot resolve $h"; bad=1; }
  done
  ping -c1 -W2 rhel02 >/dev/null 2>&1 || { echo "cannot reach rhel02"; bad=1; }
  ((bad)) || echo "the other nodes are still reachable"
  return $bad
}

# ------------------------------------------------------------------------------
lab_init "2.4" "Networking with nmcli" --host rhel01 --root "$@"

need_cmd "every check in this lab" nmcli || { summary; exit 1; }
info "lab network $NET.0/24 · management ${MGMT:-none} · spare ${SPARE:-none} · $(lab_platform)"

section "1. The lab-static profile"
check "a connection profile named lab-static exists" nmcli con show "$CON"
check -p "it is the active profile on its device" profile_is_active
check "it is on a spare interface, not the management one" leaves_management_alone
check_eq -p "ipv4.method is manual, not auto" "manual" "$(cfield ipv4.method)"
check_match -p "the static address $IP1 is configured" "${IP1//./\\.}" \
  bash -c "nmcli -g ipv4.addresses con show $CON"
check -p "two DNS servers are configured" dns_configured
check_match -p "the search domain is lab.local" 'lab\.local' \
  bash -c "nmcli -g ipv4.dns-search con show $CON"

section "2. The hostname is permanent"
check_eq -p "static hostname is $FQDN" "$FQDN" "$(hostnamectl --static 2>/dev/null)"
check_match "hostnamectl reports the FQDN" 'rhel01\.lab\.local' hostnamectl

section "3. The second address on the same profile"
check_match -p "$IP2 is on the lab-static profile" "${IP2//./\\.}" \
  bash -c "nmcli -g ipv4.addresses con show $CON"
check "both addresses are live on an interface" both_addresses_live
report "live addresses" bash -c 'ip -4 -o addr show | grep -v " lo "'

section "4. Autoconnect at boot"
check_eq -p "autoconnect is yes" "yes" "$(cfield connection.autoconnect)"

section "5. It does not break what already worked"
check -p "the profile does not claim the default route" never_default
primary_ip_untouched; rc=$?
case $rc in
  0) pass "the node's original lab address is untouched" ;;
  2) skipped "the node's original lab address is untouched" "not recorded by this environment" ;;
  *) fail "the node's original lab address is untouched"        "you reconfigured the interface the lab network runs on" ;;
esac
check "the other nodes are still reachable" still_reachable
check_match "resolv.conf carries a nameserver" '^nameserver' cat /etc/resolv.conf

section "6. It was all done with nmcli"
check "no hand-written ifcfg-* files in network-scripts" no_handwritten_ifcfg
info "The requirement was to never edit those files by hand — this proves it."

summary
