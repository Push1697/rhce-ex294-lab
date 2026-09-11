#!/usr/bin/env bash
# Lab 1.7 — Week 1 consolidation, timed             (01-Labs-RHCSA-Foundation)
# Run on rhel01, as root. Graded per requirement, so you can see which of the
# eight items you actually completed.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

O=/srv/ops
K=/usr/local/bin/opscheck
ARCH=/root/ssh-backup.tar.gz

sudo_allows_all_nopasswd() {
  runuser -u dev1 -- sudo -n -l 2>/dev/null | grep -Eq 'NOPASSWD.*(ALL|/)'
}

dev2_has_no_sudo() {
  local o
  o=$(sudo -l -U dev2 2>&1)
  echo "${o:0:200}"
  ! grep -Eq '\(ALL\)|NOPASSWD|may run' <<<"$o"
}

acl_inherited_for_svcacct() {
  local f=$O/verify-acl-$$ rc=0
  touch "$f" 2>/dev/null || { echo "could not create $f"; return 1; }
  getfacl -p --absolute-names "$f" 2>/dev/null | grep -Eq '^user:svcacct:r--' || {
    getfacl -p --absolute-names "$f" 2>/dev/null | grep -E '^user:' || echo "(no named ACL entries)"
    rc=1; }
  rm -f "$f"
  return $rc
}

opscheck_fails_on_failed_unit() {
  local u=verify-opscheck-fail.service rc
  cat > "/etc/systemd/system/$u" <<'UNIT'
[Unit]
Description=deliberately failing unit, created by the lab verifier
[Service]
Type=oneshot
ExecStart=/bin/false
UNIT
  systemctl daemon-reload
  systemctl start "$u" >/dev/null 2>&1
  "$K" >/dev/null 2>&1; rc=$?
  echo "opscheck exited $rc while a unit was failed (must be 1)"
  systemctl reset-failed "$u" >/dev/null 2>&1
  rm -f "/etc/systemd/system/$u"; systemctl daemon-reload
  ((rc == 1))
}

archive_keeps_contexts() {
  local d got want
  command -v getfattr >/dev/null 2>&1 || { echo "getfattr not installed"; return 2; }
  d=$(mktemp -d /root/.verify-ssh-XXXXXX) || return 1
  trap "rm -rf '$d'" RETURN
  tar --selinux --acls --xattrs --xattrs-include='*' -xzf "$ARCH" -C "$d" 2>/dev/null ||
    tar -xzf "$ARCH" -C "$d" 2>/dev/null || { echo "extraction failed"; return 1; }
  local f
  f=$(find "$d" -name sshd_config -print -quit)
  [[ -n ${f:-} ]] || { echo "sshd_config is not in the archive"; return 1; }
  got=$(getfattr -n security.selinux --only-values "$f" 2>/dev/null | tr -d '\0')
  want=$(getfattr -n security.selinux --only-values /etc/ssh/sshd_config 2>/dev/null | tr -d '\0')
  echo "archive: ${got:-<none>} / on disk: ${want:-<none>}"
  [[ -n ${got:-} && $got == "$want" ]]
}

# ------------------------------------------------------------------------------
lab_init "1.7" "Week 1 consolidation (timed)" --host rhel01 --root "$@"

section "1. ops group, dev1, dev2, svcacct"
check "group ops exists" group_exists ops
check_eq "ops has GID 4000" 4000 "$(group_gid ops)"
check "dev1 exists" user_exists dev1
check "dev2 exists" user_exists dev2
check "dev1 is in ops" in_group dev1 ops
check "dev2 is in ops" in_group dev2 ops
check "svcacct exists" user_exists svcacct
s=$(user_shell svcacct)
check_sh "svcacct has no interactive shell (got '$s')" \
  "[[ '$s' == */nologin || '$s' == */false ]]"

section "2. /srv/ops permissions"
check_dir "/srv/ops exists" "$O"
check_match "group-owned by ops" '(^| )ops( |$)' stat -c %G "$O"
check -p "SGID is set" sgid_set "$O"
check -p "sticky bit is set" sticky_set "$O"
check "group-writable" group_writable "$O"

section "3. sudo: dev1 passwordless everything, dev2 nothing"
check "sudoers syntax is valid" visudo -c
check "dev1 may run anything without a password" sudo_allows_all_nopasswd
check "dev2 has no sudo access at all" dev2_has_no_sudo

section "4. ACL: svcacct read-only on /srv/ops, inherited"
if need_cmd "ACL checks" getfacl; then
  check -p "named ACL user:svcacct:r-- on /srv/ops" \
    bash -c "getfacl -p --absolute-names $O 2>/dev/null | grep -Eq '^user:svcacct:r--'"
  check -p "default ACL for svcacct on /srv/ops" \
    bash -c "getfacl -p --absolute-names $O 2>/dev/null | grep -Eq '^default:user:svcacct:r--'"
  if mutating "a new file inherits svcacct's read-only entry"; then
    check "a new file inherits svcacct's read-only entry" acl_inherited_for_svcacct
  fi
fi

section "5. SSH: key-only, root denied"
check_match -p "PasswordAuthentication no" '^passwordauthentication no' bash -c 'sshd -T'
check_match -p "PermitRootLogin no" '^permitrootlogin no' bash -c 'sshd -T'
check "sshd is running" systemctl is-active --quiet sshd

section "6. /usr/local/bin/opscheck"
check_file "opscheck exists" "$K"
check_sh "opscheck is executable" "[[ -x $K ]]"
if [[ -x $K ]]; then
  check_match "it reports on failed units" 'failed|unit|OK' bash -c "$K 2>&1"
  if mutating "it exits 1 when a unit has failed"; then
    check "it exits 1 when a unit has failed" opscheck_fails_on_failed_unit
  fi
fi

section "7. /root/ssh-backup.tar.gz"
check_file "the archive exists" "$ARCH"
if [[ -s $ARCH ]]; then
  check_match "it is gzip-compressed" 'gzip compressed' file -b "$ARCH"
  check "it contains /etc/ssh content" bash -c "tar tzf '$ARCH' | grep -q 'ssh'"
  archive_keeps_contexts; rc=$?
  case $rc in
    0) pass "SELinux contexts were preserved" ;;
    2) skipped "SELinux contexts preserved" "getfattr (attr package) is not installed" ;;
    *) fail "SELinux contexts were preserved" "the archived label does not match the on-disk label" ;;
  esac
fi

section "8. Everything survives a reboot"
check "no fstab entry is broken (findmnt --verify)" findmnt --verify
info "The [P] checks above are the ones that classically vanish on restart."
info "Reboot, run this script again, and the summary will say 'reboot-proven'."

summary
