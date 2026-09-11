#!/usr/bin/env bash
# Runs on rhel-control only: ansible-core, the shared lab key, and the project
# skeleton that Lab 5.1 expects to exist.
set -Eeuo pipefail

LAB_USER=${LAB_USER:-vagrant}
HOME_DIR="/home/$LAB_USER"
PROJ="$HOME_DIR/ansible"

# --- the private half of the lab key -----------------------------------------
install -d -m 0700 -o "$LAB_USER" -g "$LAB_USER" "$HOME_DIR/.ssh"
printf '%s\n' "$LAB_PRIVKEY" > "$HOME_DIR/.ssh/id_ed25519"
chmod 0600 "$HOME_DIR/.ssh/id_ed25519"
chown "$LAB_USER:$LAB_USER" "$HOME_DIR/.ssh/id_ed25519"

# Don't make the student answer a host-key prompt on every single ad-hoc command.
cat > "$HOME_DIR/.ssh/config" <<'SSHCFG'
Host rhel01 rhel02 rhel-control
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts
SSHCFG
chmod 0600 "$HOME_DIR/.ssh/config"
chown "$LAB_USER:$LAB_USER" "$HOME_DIR/.ssh/config"

# --- ansible-core -------------------------------------------------------------
if ! command -v ansible >/dev/null 2>&1; then
  echo "==> installing ansible-core"
  dnf install -y -q ansible-core || {
    echo "!! ansible-core is not in the enabled repositories."
    echo "!! On Rocky/Alma it is in AppStream; on RHEL you need a subscription."
  }
fi
command -v ansible >/dev/null 2>&1 && ansible --version | head -1

# --- the project skeleton Lab 5.1 asks for -----------------------------------
# Written only if absent: re-provisioning must never overwrite your work.
install -d -m 0755 -o "$LAB_USER" -g "$LAB_USER" "$PROJ"

if [[ ! -f "$PROJ/ansible.cfg" ]]; then
  cat > "$PROJ/ansible.cfg" <<CFG
[defaults]
inventory         = ./inventory
remote_user       = $LAB_USER
host_key_checking = False
roles_path        = ./roles
collections_path  = ./collections

[privilege_escalation]
become          = True
become_method   = sudo
become_user     = root
become_ask_pass = False
CFG
  chown "$LAB_USER:$LAB_USER" "$PROJ/ansible.cfg"
fi

if [[ ! -f "$PROJ/inventory" ]]; then
  cat > "$PROJ/inventory" <<'INV'
[web]
rhel01

[db]
rhel02

[prod]
rhel01

[dev]
rhel02

[managed:children]
web
db
INV
  chown "$LAB_USER:$LAB_USER" "$PROJ/inventory"
fi

# Ansible ignores an ansible.cfg in a world-writable directory, silently. That
# is a real trap in Lab 5.1, and a synced folder mounted 777 walks straight into
# it — so check rather than assume.
mode=$(stat -c %a "$PROJ")
if [[ ${mode: -1} =~ [2367] ]]; then
  echo "!! $PROJ is mode $mode — world-writable, so Ansible will IGNORE its ansible.cfg."
  if [[ ${SYNC_ANSIBLE:-0} == 1 ]]; then
    echo "!! The synced folder needs dmode=755,fmode=644 mount options."
  else
    chmod 0755 "$PROJ"
    echo "!! Corrected to 0755."
  fi
fi

echo "==> control node ready: project in $PROJ"
