#!/usr/bin/env bash
# Lab 2.7 — NFS, autofs, Week 2 consolidation       (01-Labs-RHCSA-Foundation)
# Two nodes are involved. Run it on BOTH; it works out which side it is on.
#   on rhel02 (server): sudo ./lab-2.7.sh
#   on rhel01 (client): sudo ./lab-2.7.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

SERVER=rhel02
SHARE=/srv/share
HOMES=/srv/home-dirs

# ---------------------------------------------------------------- server side --
export_is_ro_to_others() {   # /srv/share must be rw to rhel01 and not world-rw
  local line
  line=$(exportfs -v 2>/dev/null | grep -A1 "^$SHARE" | tr '\n' ' ')
  echo "${line:-<not exported>}"
  grep -q 'rhel01\|192\.168\.124\.11' <<<"$line" && grep -q 'rw' <<<"$line" &&
    ! grep -Eq '<world>|\*\(' <<<"$line"
}

firewall_nfs_only() {
  local svcs extra
  svcs=$(firewall-cmd --list-services 2>/dev/null)
  echo "services: $svcs"
  for s in nfs mountd rpc-bind; do
    grep -qw "$s" <<<"$svcs" || { echo "missing: $s"; return 1; }
  done
  extra=$(tr ' ' '\n' <<<"$svcs" | grep -vE '^(nfs|nfs3|mountd|rpc-bind|ssh|dhcpv6-client|)$' | tr '\n' ' ')
  [[ -n ${extra// /} ]] && { echo "unexpected extra services open: $extra"; return 1; }
  return 0
}

run_server_checks() {
  section "S1. The exports exist"
  check_dir "$SHARE exists" "$SHARE"
  check_dir "$HOMES exists" "$HOMES"
  check "nfs-server is running" systemctl is-active --quiet nfs-server
  check -p "nfs-server is enabled at boot" systemctl is-enabled --quiet nfs-server
  check_match -p "$SHARE appears in /etc/exports (or exports.d)" "$SHARE" \
    bash -c 'cat /etc/exports /etc/exports.d/*.exports 2>/dev/null'
  check_match -p "$HOMES appears in /etc/exports (or exports.d)" "$HOMES" \
    bash -c 'cat /etc/exports /etc/exports.d/*.exports 2>/dev/null'

  section "S2. $SHARE is read-write to rhel01 only"
  check "exportfs shows it rw to rhel01 and not to the world" export_is_ro_to_others
  report "active exports" exportfs -v

  section "S3. The firewall permits NFS and nothing extra"
  if need_cmd "firewall checks" firewall-cmd; then
    check -p "nfs, mountd and rpc-bind are open — and nothing unexpected" firewall_nfs_only
    check -p "the permanent config matches the runtime config" \
      bash -c 'diff <(firewall-cmd --list-services | tr " " "\n" | sort) \
                    <(firewall-cmd --permanent --list-services | tr " " "\n" | sort)'
  fi
}

# ---------------------------------------------------------------- client side --
autofs_map_for() {   # find the autofs map file mentioning a path
  grep -rl "$1" /etc/auto.master /etc/auto.master.d/ /etc/auto.* 2>/dev/null | head -1
}

net_data_mounts_on_demand() {
  ls /net/data >/dev/null 2>&1 || { echo "ls /net/data failed"; return 1; }
  findmnt /net/data >/dev/null 2>&1 || { echo "/net/data did not become a mount point"; return 1; }
  echo "the mount appeared on access: $(findmnt -no SOURCE,FSTYPE /net/data)"
}

timeout_is_60() {
  grep -rhE 'timeout[= ]+60|--timeout[= ]?60' \
    /etc/auto.master /etc/auto.master.d/ /etc/autofs.conf 2>/dev/null | head -3 | grep -q .
}

amit_home_over_nfs() {
  local t
  t=$(runuser -u amit -s /bin/bash -- -c 'cd ~ 2>/dev/null && findmnt -no FSTYPE -T . 2>/dev/null')
  echo "amit's home sits on filesystem type: ${t:-<unknown>}"
  [[ $t == nfs* ]]
}

run_client_checks() {
  section "C1. The server's exports are visible"
  check "showmount -e $SERVER works" showmount -e "$SERVER"
  check_match "$SHARE is offered" "$SHARE" showmount -e "$SERVER"
  check_match "$HOMES is offered" "$HOMES" showmount -e "$SERVER"

  section "C2. /mnt/share is mounted persistently"
  check "/mnt/share is mounted" findmnt /mnt/share
  check_match "it is an NFS mount from $SERVER" "$SERVER|192\.168\.124\.12" \
    bash -c 'findmnt -no SOURCE /mnt/share'
  check -p "there is an /etc/fstab entry for it" bash -c 'fstab_line /mnt/share | grep -q .'
  check "it is writable" bash -c 'f=/mnt/share/.verify-$$; touch "$f" && rm -f "$f"'
  check -p "findmnt --verify is happy with /etc/fstab" findmnt --verify

  section "C3. autofs mounts /net/data on demand"
  check "autofs is installed" rpm -q autofs
  check -p "autofs is enabled at boot" systemctl is-enabled --quiet autofs
  check "autofs is running" systemctl is-active --quiet autofs
  check -p "a map file references $SHARE" bash -c "grep -rq '$SHARE' /etc/auto.* 2>/dev/null"
  check "accessing /net/data triggers the mount" net_data_mounts_on_demand
  check -p "a 60-second idle timeout is configured" timeout_is_60
  info "To see it expire: sleep 90; findmnt /net/data   → should be gone."

  section "C4. amit's home comes from the server"
  if user_exists amit; then
    check -p "a wildcard/home map exists for $HOMES" \
      bash -c "grep -rq '$HOMES' /etc/auto.* 2>/dev/null"
    check "amit's home is served over NFS" amit_home_over_nfs
  else
    skipped "amit's NFS home" "no user 'amit' on this host"
  fi
}

# ------------------------------------------------------------------------------
lab_init "2.7" "NFS, autofs, Week 2 consolidation" --root "$@"

case "$(_v_host)" in
  "$SERVER") info "Detected the NFS server side."; run_server_checks ;;
  rhel01)    info "Detected the NFS client side."; run_client_checks ;;
  *)         info "Unknown host — running whichever checks apply."
             command -v exportfs >/dev/null && [[ -d $SHARE ]] && run_server_checks
             command -v showmount >/dev/null && run_client_checks ;;
esac

info "Run this on the OTHER node too — the lab is only complete when both pass."
summary
