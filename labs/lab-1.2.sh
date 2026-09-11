#!/usr/bin/env bash
# Lab 1.2 — Users, groups and password policy       (01-Labs-RHCSA-Foundation)
# Run on rhel01, as root.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

chage_field() {   # chage_field <user> <regex>  → the value after the colon
  chage -l "$1" 2>/dev/null | grep -i "$2" | head -1 | cut -d: -f2- | tr -d ' \t'
}

new_user_gets_high_uid() {
  local u=verifyuid$$ uid
  useradd "$u" >/dev/null 2>&1 || { echo "useradd $u failed"; return 1; }
  uid=$(id -u "$u" 2>/dev/null)
  userdel -r "$u" >/dev/null 2>&1
  echo "a brand new account was given UID $uid"
  [[ -n ${uid:-} ]] && ((uid >= 3000))
}

# ------------------------------------------------------------------------------
lab_init "1.2" "Users, groups and password policy" --host rhel01 --root "$@"

section "1. Groups"
check "developers group exists" group_exists developers
check_eq "developers has GID exactly 5000" 5000 "$(group_gid developers)"
check "contractors group exists" group_exists contractors

section "2. amit, sara, raj"
for u in amit sara raj; do
  check "$u exists" user_exists "$u"
done
for u in amit sara raj; do
  check_eq "$u's primary group is developers" "$(group_gid developers)" "$(user_gid "$u")"
done
for u in amit sara raj; do
  h=$(user_home "$u")
  check_sh "$u's home is under /home and exists" "[[ '$h' == /home/* && -d '$h' ]]"
done

section "3. vendor1 — account without an interactive shell"
check "vendor1 exists" user_exists vendor1
check "vendor1 is a member of contractors" in_group vendor1 contractors
sh1=$(user_shell vendor1)
check_sh "vendor1's shell prevents interactive login (got '$sh1')" \
  "[[ '$sh1' == */nologin || '$sh1' == */false ]]"
check_eq "vendor1's home is /opt/vendor1" /opt/vendor1 "$(user_home vendor1)"
check_dir "/opt/vendor1 exists" /opt/vendor1

section "4. sara — password ageing"
check_eq -p "sara: maximum password age is 30 days" 30 "$(chage_field sara 'maximum number of days')"
check_eq -p "sara: warning period is 7 days" 7 "$(chage_field sara 'number of days of warning')"

section "5. raj — locked, not deleted"
check_match -p "raj is locked (passwd -S reports LK)" '^raj +LK?' passwd -S raj
check "raj's account still exists" user_exists raj
check_sh "raj's shadow hash carries the lock prefix" \
  "getent shadow raj | cut -d: -f2 | grep -q '^!'"

section "6. amit — forced password change at first login"
check_match -p "amit must change their password at next login" \
  'must be changed|password change.*:.*(never|1970)' chage -l amit

section "7. New accounts get UID 3000 or above"
check_match -p "UID_MIN in /etc/login.defs is 3000 or above" \
  '^UID_MIN[[:space:]]+([3-9][0-9]{3}|[0-9]{5,})' grep -E '^UID_MIN' /etc/login.defs
if mutating "a brand new account really is given UID >= 3000"; then
  check "a brand new account really is given UID >= 3000" new_user_gets_high_uid
fi

summary
