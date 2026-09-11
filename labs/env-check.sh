#!/usr/bin/env bash
# Environment acceptance test                       (00-Lab-Environment)
#
# Run it inside the lab, on any node — it works out which node it is and what
# hypervisor it is on:
#
#   vagrant ssh rhel-control -c 'sudo /opt/rhce-labs/verify env'
#   vagrant ssh rhel01       -c 'sudo /opt/rhce-labs/verify env'
#
# On a KVM host it also checks the libvirt side. The Windows/VirtualBox host is
# checked by vagrant/lab.ps1 doctor instead, since bash cannot see VBoxManage.
#
# Do not start Week 1 until every line passes on every node.
_D=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
. "$_D/../lib/verify-lib.sh"

NODES="rhel-control rhel01 rhel02"
LABUSER=${LAB_USER:-}
for a in "$@"; do case "$a" in --labuser=*) LABUSER=${a#--labuser=} ;; esac; done
# the ordinary lab account: SUDO_USER when invoked via sudo, else the first real user
[[ -n ${LABUSER:-} ]] || LABUSER=${SUDO_USER:-}
[[ -n ${LABUSER:-} ]] || LABUSER=$(awk -F: '$3 >= 1000 && $3 < 65534 && $6 ~ /^\/home\// { print $1; exit }' /etc/passwd)

as_user() {   # run as the lab account, whoever we currently are
  if [[ $(id -un) == "$LABUSER" ]]; then "$@"; else runuser -u "$LABUSER" -- "$@"; fi
}

# ------------------------------------------------------------ every node ------
two_lab_disks() {
  local d1 d2
  d1=$(lab_disk 1); d2=$(lab_disk 2)
  echo "root disk: /dev/$(root_disk 2>/dev/null || echo '?')"
  echo "lab disks: ${d1:-<none>} ${d2:-<none>}"
  lsblk -dno NAME,SIZE,TYPE | sed 's/^/    /'
  [[ -n ${d1:-} && -n ${d2:-} ]]
}

lab_network_up() {
  local net ip
  net=$(lab_net)
  ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | grep "^$net\." | head -1)
  echo "an address on $net.0/24: ${ip:-<none>}"
  [[ -n ${ip:-} ]]
}

all_nodes_resolve() {
  local bad=0 n
  for n in $NODES; do
    getent hosts "$n" >/dev/null 2>&1 || { echo "cannot resolve $n"; bad=1; }
  done
  ((bad)) || echo "all three names resolve"
  return $bad
}

all_nodes_reachable() {
  local bad=0 n
  for n in $NODES; do
    [[ $n == "$(_v_host)" ]] && continue
    ping -c1 -W2 "$n" >/dev/null 2>&1 || { echo "cannot ping $n"; bad=1; }
  done
  ((bad)) || echo "the other nodes answer"
  return $bad
}

kit_mounted() {
  # On Vagrant the kit is a read-only share; on KVM it was copied in.
  [[ -x $_D/../verify ]] || { echo "the kit is not where this script expected it"; return 1; }
  echo "kit at $(readlink -f "$_D/..")"
  findmnt -no TARGET,FSTYPE,OPTIONS --target "$_D/.." 2>/dev/null | sed 's/^/    /'
  return 0
}

passwordless_sudo() {
  as_user sudo -n true 2>/dev/null
}

repos_available() {
  local n
  n=$(dnf repolist --enabled 2>/dev/null | grep -cE '^[a-zA-Z0-9]')
  echo "enabled repositories: $n"
  [[ ${n:-0} -ge 2 ]]
}

# ------------------------------------------------------ rhel01 extras ---------
spare_nic_present() {
  # The nmcli lab needs an interface that exists and has no address on it.
  local spare addrs
  spare=$(spare_iface || true)
  echo "interfaces: $(ip -o link show | awk -F': ' '$2 !~ /^lo/ { printf "%s ", $2 }')"
  echo "set aside for the nmcli lab: ${spare:-<none>}"
  [[ -n ${spare:-} ]] || return 1
  addrs=$(ip -4 -o addr show dev "$spare" 2>/dev/null | awk '{print $4}')
  if [[ -n ${addrs:-} ]]; then
    echo "but it already carries $addrs — the lab needs it empty"
    echo "(VirtualBox runs DHCP on the host-only net; re-run 'lab.ps1 provision')"
    return 1
  fi
  echo "and it has no address, as the lab needs"
  return 0
}

# ------------------------------------------------ control node only ----------
ssh_to_nodes() {
  local bad=0 n out
  for n in rhel01 rhel02; do
    out=$(as_user ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
          "$n" 'hostname -s' 2>&1)
    if [[ $out == "$n" ]]; then echo "$n -> $out"
    else echo "$n -> ${out:-<no reply>}"; bad=1; fi
  done
  return $bad
}

sudo_on_nodes() {
  local bad=0 n out
  for n in rhel01 rhel02; do
    out=$(as_user ssh -o BatchMode=yes -o ConnectTimeout=5 "$n" 'sudo -n whoami' 2>&1)
    [[ $out == root ]] || { echo "$n: sudo -n did not return root ($out)"; bad=1; }
  done
  ((bad)) || echo "passwordless sudo works on both managed nodes"
  return $bad
}

ansible_ping() {
  local out n
  out=$(as_user bash -lc 'cd ~/ansible 2>/dev/null && ansible managed -m ping' 2>&1)
  n=$(grep -c SUCCESS <<<"$out")
  echo "$n of 2 managed nodes answered"
  [[ ${n:-0} -eq 2 ]] || echo "$out" | tail -6
  [[ ${n:-0} -eq 2 ]]
}

ansible_become() {
  local out
  out=$(as_user bash -lc 'cd ~/ansible 2>/dev/null && ansible managed -m command -a "id -u" --become' 2>&1)
  echo "$out" | grep -E '^[0-9]+$|rc=|password' | head -4
  ! grep -q 'password is required' <<<"$out" && grep -q '^0$' <<<"$out"
}

project_not_world_writable() {
  local m
  m=$(mode_of "/home/$LABUSER/ansible")
  echo "~/ansible is mode ${m:-<missing>}"
  [[ -n ${m:-} ]] || return 1
  ! other_writable "/home/$LABUSER/ansible"
}

# ------------------------------------------------------------- KVM host ------
run_kvm_host_checks() {
  section "H. The KVM host"
  check "libvirtd is running" systemctl is-active --quiet libvirtd
  check "the default network is active" bash -c "virsh net-list 2>/dev/null | grep -q default"
  check "all three domains are running" \
    bash -c 'bad=0; for n in rhel-control rhel01 rhel02; do
               virsh domstate "$n" 2>/dev/null | grep -q running || { echo "$n is not running"; bad=1; }
             done; exit $bad'
  check "every node has a clean snapshot" \
    bash -c 'bad=0; for n in rhel-control rhel01 rhel02; do
               virsh snapshot-list "$n" 2>/dev/null | grep -q clean || { echo "$n has no clean snapshot"; bad=1; }
             done; exit $bad'
}

# ------------------------------------------------------------------------------
lab_init "env" "Lab environment acceptance test" --root "$@"
HOSTSHORT=$(_v_host)
info "node $HOSTSHORT · $(lab_platform) · lab account ${LABUSER:-<none found>}"

section "1. This node is sound"
check "the lab kit is available on this node" kit_mounted
check "all three node names resolve" all_nodes_resolve
check "the lab network is up on this node" lab_network_up
check "the other nodes answer a ping" all_nodes_reachable
check "the lab account has passwordless sudo" passwordless_sudo
check "package repositories are usable" repos_available

if [[ $HOSTSHORT == rhel01 || $HOSTSHORT == rhel02 ]]; then
  section "2. The blank disks the storage labs need"
  check "two lab disks are attached and detected" two_lab_disks
  if [[ $HOSTSHORT == rhel01 ]]; then
    check "an unconfigured interface exists for the nmcli lab" spare_nic_present
  fi
fi

if [[ $HOSTSHORT == rhel-control ]]; then
  section "2. Reaching the managed nodes"
  check "SSH to rhel01 and rhel02 works with the key, no password" ssh_to_nodes
  check "passwordless sudo works on both" sudo_on_nodes

  section "3. Ansible"
  if need_cmd "the Ansible checks" ansible; then
    check "ansible managed -m ping succeeds for both" ansible_ping
    check "become returns uid 0" ansible_become
    check "~/ansible is not world-writable (or ansible.cfg is ignored)" project_not_world_writable
    info "Ansible silently ignores an ansible.cfg in a world-writable directory."
    report "config file in use" bash -c "cd /home/$LABUSER/ansible 2>/dev/null && ansible --version | head -2"
  fi
fi

if command -v virsh >/dev/null 2>&1; then
  run_kvm_host_checks
else
  section "H. The hypervisor host"
  skipped "host-side checks" "run them on the host: vagrant/lab.ps1 doctor"
  info "This node cannot see VirtualBox from inside the guest, by design."
fi

section "The gate"
info "Run this on all three nodes. Every line must pass before Week 1."
manual "A 'clean' snapshot exists for all three nodes" \
  "lab.ps1 snap clean  (Vagrant)  ·  virsh snapshot-create-as (KVM)"

summary
