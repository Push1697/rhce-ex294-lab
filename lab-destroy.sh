#!/usr/bin/env bash
set -Eeuo pipefail
for n in rhel-control rhel01 rhel02; do
  virsh destroy "$n" 2>/dev/null || true
  virsh undefine "$n" --remove-all-storage --nvram 2>/dev/null || true
done
echo "Lab destroyed. Re-run lab-build.sh for a clean set."
