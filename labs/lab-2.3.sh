#!/usr/bin/env bash
# Lab 2.3 — dnf, rpm, repositories                  (01-Labs-RHCSA-Foundation)
# Run on rhel01, as root.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

# The package sitting in /repo should also be installed.
local_pkg_installed() {
  local rpm name
  rpm=$(find /repo -maxdepth 2 -name '*.rpm' -print -quit 2>/dev/null)
  [[ -n ${rpm:-} ]] || { echo "no .rpm file found under /repo"; return 1; }
  name=$(rpm -qp --qf '%{NAME}\n' "$rpm" 2>/dev/null)
  echo "package in /repo: ${name:-?} (from $(basename "$rpm"))"
  rpm -q "$name" >/dev/null 2>&1
}

repo_installed_from_locallab() {
  # dnf records which repo a package came from.
  dnf repoquery --installed --qf '%{from_repo}\n' 2>/dev/null | grep -qx locallab
}

history_has_undo() {
  dnf history list 2>/dev/null | grep -Eqi '\b(undo|rollback)\b'
}

# ------------------------------------------------------------------------------
lab_init "2.3" "dnf, rpm, repositories" --host rhel01 --root "$@"

section "1. The local repository"
check_dir "/repo exists" /repo
check_dir "/repo/repodata exists — createrepo has been run" /repo/repodata
check "a .repo file defines a baseurl of file:///repo" \
  bash -c "grep -rlq 'baseurl[[:space:]]*=[[:space:]]*file:///repo' /etc/yum.repos.d/"
check "the repository is named locallab" \
  bash -c "grep -rq '^\[locallab\]' /etc/yum.repos.d/"
check "gpgcheck is disabled for it" \
  bash -c "awk '/^\[locallab\]/ { f = 1; next } /^\[/ { f = 0 } f && /^gpgcheck/ { print; if (\$0 ~ /0/) ok = 1 } END { exit !ok }' /etc/yum.repos.d/*.repo"
check -p "dnf lists locallab among the enabled repositories" \
  bash -c "dnf repolist enabled 2>/dev/null | grep -q locallab"

section "2. A package installed from it"
check "the RPM you placed in /repo is installed" local_pkg_installed
check "dnf agrees it came from locallab" repo_installed_from_locallab

section "3. Querying package ownership"
check_match "rpm -qf /etc/hosts resolves to a package" '^setup' rpm -qf /etc/hosts
manual "You can name the package that owns /etc/hosts without guessing" \
  "It is shown above. You should have known it before running this."
report "files installed by setup" bash -c 'rpm -ql setup | head -5'

section "4. The container-tools content"
check "podman is installed" rpm -q podman
check "buildah or skopeo came with it" bash -c 'rpm -q buildah || rpm -q skopeo'
report "how dnf recorded the group/module" \
  bash -c 'dnf group list --installed 2>/dev/null | head -10; dnf module list --installed 2>/dev/null | head -5'

section "5. Downgrade and rollback via dnf history"
check "dnf history shows an undo or rollback transaction" history_has_undo
report "recent transactions" bash -c 'dnf history list 2>/dev/null | head -8'
manual "The downgrade was genuinely reversed, not reinstalled by hand" \
  "dnf history info <ID> on the undo transaction should show it."

section "6. Packages installed in the last 24 hours"
report "most recent installs" bash -c "rpm -qa --last 2>/dev/null | head -8"
manual "You can list every package installed in the last 24 hours" \
  "rpm -qa --last, or dnf history — either is acceptable."

summary
