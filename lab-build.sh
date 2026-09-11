#!/usr/bin/env bash
set -Eeuo pipefail

LAB_DIR="${LAB_DIR:-$HOME/Desktop/projects/rhce-lab}"
BASE="$LAB_DIR/base/rhel-base.qcow2"
IMG_DIR="$LAB_DIR/images"
OS_VARIANT="${OS_VARIANT:-rhel9.4}"        # virt-install --osinfo list
PUBKEY="${PUBKEY:-$HOME/.ssh/id_ed25519.pub}"
LAB_PASS="${LAB_PASS:-redhat}"

[[ -f "$BASE"   ]] || { echo "Missing base image: $BASE" >&2; exit 1; }
[[ -f "$PUBKEY" ]] || { echo "Missing SSH key: $PUBKEY (ssh-keygen -t ed25519)" >&2; exit 1; }
mkdir -p "$IMG_DIR" "$LAB_DIR/seed"

# name:memory:vcpus:ip:extra_disks
NODES=(
  "rhel-control:2048:2:192.168.124.10:0"
  "rhel01:1024:1:192.168.124.11:2"
  "rhel02:1024:1:192.168.124.12:2"
)

for spec in "${NODES[@]}"; do
  IFS=: read -r name mem cpus ip extras <<<"$spec"

  if virsh dominfo "$name" &>/dev/null; then
    echo "== $name already exists, skipping (use lab-destroy.sh first)"
    continue
  fi
  echo "== Building $name ($ip)"

  # Thin overlay on the shared base image, grown to 20G
  qemu-img create -f qcow2 -F qcow2 -b "$BASE" "$IMG_DIR/$name.qcow2" 20G >/dev/null

  # Blank disks for the storage/LVM labs
  disk_args=()
  for ((d=1; d<=extras; d++)); do
    extra="$IMG_DIR/$name-disk$d.qcow2"
    [[ -f "$extra" ]] || qemu-img create -f qcow2 "$extra" 10G >/dev/null
    disk_args+=(--disk "path=$extra,format=qcow2")
  done

  # cloud-init: user, key, static IP, hostname
  seed="$LAB_DIR/seed/$name"
  mkdir -p "$seed"
  cat > "$seed/meta-data" <<EOF
instance-id: $name
local-hostname: $name
EOF
  cat > "$seed/user-data" <<EOF
#cloud-config
preserve_hostname: false
hostname: $name
fqdn: $name.lab.local
users:
  - name: pushpendra
    groups: [wheel]
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    ssh_authorized_keys:
      - $(cat "$PUBKEY")
ssh_pwauth: true
chpasswd:
  expire: false
  list: |
    root:$LAB_PASS
    pushpendra:$LAB_PASS
write_files:
  - path: /etc/hosts
    append: true
    content: |
      192.168.124.10 rhel-control rhel-control.lab.local
      192.168.124.11 rhel01 rhel01.lab.local
      192.168.124.12 rhel02 rhel02.lab.local
EOF
  cloud-localds "$seed/seed.iso" "$seed/user-data" "$seed/meta-data"

  virt-install \
    --name "$name" \
    --memory "$mem" --vcpus "$cpus" \
    --disk "path=$IMG_DIR/$name.qcow2,format=qcow2,bus=virtio" \
    "${disk_args[@]}" \
    --disk "path=$seed/seed.iso,device=cdrom" \
    --osinfo "$OS_VARIANT" \
    --network "network=default,mac=52:54:00:9b:1c:${ip##*.}" \
    --graphics none --import --noautoconsole

  # Pin the address so the inventory never drifts
  virsh net-update default add ip-dhcp-host \
    "<host mac='52:54:00:9b:1c:${ip##*.}' name='$name' ip='$ip'/>" \
    --live --config 2>/dev/null || true
done

echo
echo "Nodes:"; virsh list --all
echo
echo "Next: reboot the nodes once so the pinned DHCP leases apply, then"
echo "  ssh pushpendra@192.168.124.10"
