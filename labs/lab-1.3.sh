#!/usr/bin/env bash
# Lab 1.3 — Permissions, special bits, ACLs         (01-Labs-RHCSA-Foundation)
# Run on rhel01, as root.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

P=/srv/project

acl_has() {   # acl_has <path> <acl entry regex>
  getfacl -p --absolute-names "$1" 2>/dev/null | grep -Eq "$2"
}

sticky_bit_set()  { sticky_set "$P"; }
sgid_bit_set()    { sgid_set "$P"; }

# raj creates a file; amit — also in developers — must not be able to delete it.
other_users_cannot_delete() {
  local f=$P/verify-sticky-$$ rc=0
  runuser -u raj -- touch "$f" 2>/dev/null || { echo "raj could not create a file in $P"; return 1; }
  if runuser -u amit -- rm -f "$f" 2>/dev/null && [[ ! -e $f ]]; then
    echo "amit deleted a file owned by raj — the sticky bit is not doing its job"
    rc=1
  else
    echo "amit was refused, as required"
  fi
  rm -f "$f" 2>/dev/null
  return $rc
}

# A file created by anyone must land in the developers group.
group_is_inherited() {
  local f=$P/verify-sgid-$$ g rc=0
  runuser -u raj -- touch "$f" 2>/dev/null || { echo "raj could not create a file in $P"; return 1; }
  g=$(stat -c %G "$f")
  echo "a file created by raj is group-owned by '$g'"
  [[ $g == developers ]] || rc=1
  rm -f "$f" 2>/dev/null
  return $rc
}

# New files under reports must pick up sara's access from the default ACL.
new_file_inherits_acl() {
  local f=$P/reports/verify-dacl-$$ rc=0
  touch "$f" 2>/dev/null || { echo "could not create $f"; return 1; }
  if getfacl -p --absolute-names "$f" 2>/dev/null | grep -Eq '^user:sara:rw'; then
    echo "the new file carries user:sara:rw-"
  else
    getfacl -p --absolute-names "$f" 2>/dev/null | grep -E '^user:' || echo "(no named ACL entries at all)"
    rc=1
  fi
  rm -f "$f" 2>/dev/null
  return $rc
}

sara_can_write_reports() {
  local f=$P/reports/verify-sara-$$ rc=0
  runuser -u sara -- touch "$f" 2>/dev/null || rc=1
  [[ -e $f ]] || rc=1
  rm -f "$f" 2>/dev/null
  ((rc)) && echo "sara could not create a file in $P/reports"
  return $rc
}

vendor1_read_only_public() {
  local f=$P/public/verify-vendor-$$ rc=0
  runuser -u vendor1 -s /bin/bash -- -c "ls $P/public" >/dev/null 2>&1 ||
    { echo "vendor1 cannot even read $P/public"; return 1; }
  if runuser -u vendor1 -s /bin/bash -- -c "touch $f" 2>/dev/null; then
    echo "vendor1 was able to write into $P/public — the ACL is not read-only"
    rm -f "$f"; rc=1
  else
    echo "vendor1 can read but not write, as required"
  fi
  return $rc
}

# ------------------------------------------------------------------------------
lab_init "1.3" "Permissions, special bits, ACLs" --host rhel01 --root "$@"

need_cmd "ACL checks" getfacl || { summary; exit 1; }

section "1. Ownership of /srv/project"
check_dir "/srv/project exists" "$P"
check_eq "owned by root, group developers" "root:developers" "$(owner_of "$P")"
report "current mode" stat -c '%A %a %U:%G %n' "$P"

section "2. Sticky bit — nobody deletes another user's files"
check -p "sticky bit is set on /srv/project" sticky_bit_set
if mutating "amit cannot delete a file created by raj"; then
  check "amit cannot delete a file created by raj" other_users_cannot_delete
fi

section "3. SGID — group ownership is inherited"
check -p "SGID bit is set on /srv/project" sgid_bit_set
check "the directory is group-writable" group_writable "$P"
if mutating "new files are group-owned by developers"; then
  check "new files are group-owned by developers" group_is_inherited
fi

section "4. sara's ACL on /srv/project/reports"
check_dir "/srv/project/reports exists" "$P/reports"
check -p "named ACL entry user:sara:rw- on reports" acl_has "$P/reports" '^user:sara:rw'
check "sara is NOT a member of developers (no group was added)" \
  bash -c '! id -nG sara 2>/dev/null | tr " " "\n" | grep -qx developers'
if mutating "sara can genuinely write into reports"; then
  check "sara can genuinely write into reports" sara_can_write_reports
fi

section "5. vendor1's read-only ACL on /srv/project/public"
check_dir "/srv/project/public exists" "$P/public"
check -p "named ACL entry user:vendor1:r-- on public" acl_has "$P/public" '^user:vendor1:r--'
if mutating "vendor1 can read but not write in public"; then
  check "vendor1 can read but not write in public" vendor1_read_only_public
fi

section "6. Default ACL so new files inherit sara's access"
check -p "default ACL for sara exists on reports" acl_has "$P/reports" '^default:user:sara:rw'
if mutating "a newly created file inherits user:sara:rw-"; then
  check "a newly created file inherits user:sara:rw-" new_file_inherits_acl
fi

section "7. The filesystem still supports all of this"
check "the mount holding /srv/project supports ACLs" \
  bash -c 'getfacl -p --absolute-names /srv/project >/dev/null 2>&1'
report "mount options in force" findmnt -no TARGET,FSTYPE,OPTIONS --target /srv/project

summary
