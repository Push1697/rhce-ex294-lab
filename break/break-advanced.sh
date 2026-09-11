#!/usr/bin/env bash
#
# break-advanced.sh — the advanced saboteur.        (10-Advanced-Breakfix-Labs)
#
#   DO NOT READ THE REST OF THIS FILE.
#
# It contains the answers to ten drills you are supposed to diagnose from the
# machine itself. Reading it once costs you the only chance you get to practise
# that fault cold. Use `reveal` afterwards instead — it tells you what was done
# and how long you took.
#
# Run it on rhel01 unless a drill says otherwise. ALWAYS snapshot first:
#   virsh snapshot-create-as rhel01 pre-lab
#
#   ./break-advanced.sh list            what the drills are called (no spoilers)
#   ./break-advanced.sh random --yes    one unknown fault — the honest version
#   ./break-advanced.sh f4 --yes        a specific drill
#   ./break-advanced.sh combo --yes     three distinct faults at once
#   ./break-advanced.sh chaos 5 --yes   five faults, exam-day-from-hell mode
#   ./break-advanced.sh status          how many are pending, and since when
#   ./break-advanced.sh reveal          what was applied, and your elapsed time
#   ./break-advanced.sh clear           forget the log (does NOT repair anything)
#
# Nothing here needs network access. Nothing here writes a backup of what it
# changed — your snapshot is the safety net, deliberately.
set -uo pipefail

STATE=/var/tmp/rhce-verify
LOG=$STATE/advanced.applied
FAULTS=(f1 f2 f3 f4 f5 f6 f7 f8 f9 f10)

# What each drill looks like from the outside. Safe to print — it is the symptom
# you would observe anyway, not the cause.
declare -A SYMPTOM=(
  [f1]="names stop resolving, and /etc/hosts is demonstrably correct"
  [f2]="a service will not start on a config error you cannot correct"
  [f3]="the website is unreachable, and fixing one thing is not enough"
  [f4]="a unit starts by hand but never at boot, citing something that does not exist"
  [f5]="the filesystem is full and du cannot account for it"
  [f6]="everything time-sensitive misbehaves at once"
  [f7]="sudo works for some commands and refuses others"
  [f8]="SELinux is off after a reboot, and the config file says enforcing"
  [f9]="DNS works now and breaks on every reboot"
  [f10]="the NFS mount succeeds and writes fail"
)

# The answers. Printed only by `reveal`.
declare -A CAUSE=(
  [f1]="the hosts: line in nsswitch.conf lost its 'files' source, so /etc/hosts is never consulted (and on RHEL 9 that file is managed by authselect)"
  [f2]="the config file was corrupted and then given the immutable attribute with chattr +i, so even root gets EPERM and there is no SELinux denial to find"
  [f3]="three independent faults behind one symptom: the document root was relabelled with chcon, Listen was moved to an unlabelled port 8099, and http was removed from the permanent firewall configuration"
  [f4]="a systemd drop-in added RequiresMountsFor=/srv/data-vol, so the unit hard-depends on a mount unit (srv-data\\x2dvol.mount) that does not exist"
  [f5]="a large file was created, opened by a background process, and then deleted — the space stays allocated until the file descriptor closes, and du cannot see it"
  [f6]="NTP was disabled and the clock pushed months into the future, so certificates, timers, log ordering and password ageing all misbehave"
  [f7]="Defaults secure_path lost its sbin directories, and a file in /etc/sudoers.d was made world-writable so sudo refuses to read it and silently drops those rules"
  [f8]="selinux=0 was added persistently to the kernel command line, which disables SELinux entirely regardless of /etc/selinux/config — and re-enabling it needs a relabel"
  [f9]="the NetworkManager connection profile carries a bogus DNS server; /etc/resolv.conf is generated, so hand-editing it works until the connection next comes up"
  [f10]="the NFS export was flipped to read-only with root_squash, so the mount still succeeds and only writes fail"
)

declare -A NODE=(
  [f10]="run this one on rhel02 (the NFS server) — or on rhel01 to get the client-side variant"
)

# ---------------------------------------------------------------- plumbing ----
die()  { echo "break-advanced: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
YES=0

record() {
  mkdir -p "$STATE"
  printf '%s %s\n' "$(date +%s)" "$1" | base64 >> "$LOG"
}

# ------------------------------------------------------- can we stage this? ---
# `random` and `combo` only pick faults whose prerequisites are actually present,
# so a drill never half-applies and leaves you chasing a fault that is not there.
httpd_conf() { echo /etc/httpd/conf/httpd.conf; }

docroot() {
  local d
  d=$(grep -hE '^[[:space:]]*DocumentRoot' /etc/httpd/conf/httpd.conf \
      /etc/httpd/conf.d/*.conf 2>/dev/null | tail -1 | awk '{ gsub(/"/, "", $2); print $2 }')
  [[ -n ${d:-} && -d $d ]] && { echo "$d"; return 0; }
  [[ -d /web/site ]] && { echo /web/site; return 0; }
  [[ -d /var/www/html ]] && { echo /var/www/html; return 0; }
  return 1
}

target_unit() {
  local u
  for u in httpd siteguard chronyd; do
    systemctl list-unit-files "$u.service" >/dev/null 2>&1 &&
      systemctl cat "$u.service" >/dev/null 2>&1 && { echo "$u"; return 0; }
  done
  return 1
}

immutable_target() {
  local f
  for f in /etc/httpd/conf/httpd.conf /etc/chrony.conf /etc/systemd/journald.conf; do
    [[ -f $f ]] && { echo "$f"; return 0; }
  done
  return 1
}

nfs_export_file() {
  local f
  for f in /etc/exports /etc/exports.d/*.exports; do
    [[ -f $f ]] && grep -qE '^[[:space:]]*/' "$f" && { echo "$f"; return 0; }
  done
  return 1
}

nfs_client_mount() {
  awk '$1 !~ /^#/ && $3 ~ /^nfs/ { print $2; exit }' /etc/fstab 2>/dev/null
}

active_con() { nmcli -t -f NAME con show --active 2>/dev/null | head -1; }

can() {
  case "$1" in
    f1)  [[ -f /etc/nsswitch.conf ]] ;;
    f2)  immutable_target >/dev/null && have chattr ;;
    f3)  [[ -f $(httpd_conf) ]] && docroot >/dev/null && have firewall-cmd ;;
    f4)  target_unit >/dev/null ;;
    f5)  have lsof || true ;;    # the fault stages fine either way
    f6)  have timedatectl ;;
    f7)  [[ -f /etc/sudoers ]] ;;
    f8)  have grubby && [[ -d /sys/firmware ]] ;;
    f9)  have nmcli && [[ -n $(active_con) ]] ;;
    f10) nfs_export_file >/dev/null || [[ -n $(nfs_client_mount) ]] ;;
    *)   return 1 ;;
  esac
}

# ------------------------------------------------------------------ faults ----
fault_f1() {
  # /etc/nsswitch.conf may be an authselect-managed symlink; edit the target in
  # place so the symlink itself survives.
  sed --follow-symlinks -i -E \
    's/^([[:space:]]*hosts:[[:space:]]*).*/\1dns myhostname/' /etc/nsswitch.conf
}

fault_f2() {
  local f
  f=$(immutable_target) || return 1
  case "$f" in
    *httpd.conf) printf '\n# staged by the lab\nServerRoot "/etc/httpd"\nInvalidDirective on\n' >> "$f" ;;
    *chrony.conf) printf '\nbogusdirective yes\n' >> "$f" ;;
    *) printf '\nNotASetting=1\n' >> "$f" ;;
  esac
  chattr +i "$f" 2>/dev/null
  systemctl restart "$(basename "${f%%.conf}")" >/dev/null 2>&1 || true
  systemctl restart httpd >/dev/null 2>&1 || true
}

fault_f3() {
  local root
  root=$(docroot) || return 1
  chcon -R -t var_t "$root" >/dev/null 2>&1 || true
  sed -i -E 's/^[[:space:]]*Listen[[:space:]]+80[[:space:]]*$/Listen 8099/' "$(httpd_conf)"
  firewall-cmd --permanent --remove-service=http  >/dev/null 2>&1 || true
  firewall-cmd --permanent --remove-service=https >/dev/null 2>&1 || true
  firewall-cmd --permanent --remove-port=8099/tcp >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
  systemctl restart httpd >/dev/null 2>&1 || true
}

fault_f4() {
  local u d
  u=$(target_unit) || return 1
  d=/etc/systemd/system/$u.service.d
  mkdir -p "$d"
  cat > "$d/20-storage.conf" <<'DROPIN'
[Unit]
RequiresMountsFor=/srv/data-vol
DROPIN
  systemctl daemon-reload
  systemctl restart "$u" >/dev/null 2>&1 || true
}

fault_f5() {
  local avail total keep want ghost
  avail=$(df -BM --output=avail /var 2>/dev/null | tail -1 | tr -dc '0-9')
  total=$(df -BM --output=size  /var 2>/dev/null | tail -1 | tr -dc '0-9')
  [[ -n ${avail:-} && -n ${total:-} ]] || return 1

  # Fill it until df genuinely reads full. A fixed 2 GB ceiling left a 19 GB
  # root at 19% used, so the reported symptom — a full filesystem — was simply
  # not there, and the checker's own "over 90% full" test never fired.
  # Keep a working margin so the box stays diagnosable: the repair is to find
  # and kill the process holding the descriptor, which needs no free space.
  keep=$((total / 33)); ((keep < 500)) && keep=500
  want=$((avail - keep))
  ((want < 64)) && { echo "  (not enough free space to stage this one safely)" >&2; return 1; }

  ghost=$(mktemp /var/tmp/.stage-XXXXXX) || return 1
  # fallocate reserves the extents without writing them: instant, and it does
  # not inflate the hypervisor's dynamically-allocated disk image with several
  # gigabytes of zeros the way dd would.
  fallocate -l "${want}M" "$ghost" 2>/dev/null ||
    dd if=/dev/zero of="$ghost" bs=1M count="$want" status=none 2>/dev/null ||
    { rm -f "$ghost"; return 1; }
  # Hold the descriptor open, then unlink. The blocks stay allocated.
  setsid nohup bash -c 'exec 3<"$1"; rm -f -- "$1"; exec sleep 86400' _ "$ghost" \
    >/dev/null 2>&1 &
  disown 2>/dev/null || true
  sleep 1
}

fault_f6() {
  # Four independent time faults, none of which the hypervisor can undo.
  #
  # An earlier version simply pushed the wall clock forward. On VirtualBox the
  # guest additions resynchronise the clock from the host within seconds, so
  # the fault was gone before it could be looked at; and stopping them makes
  # VBoxService log a timesync error to the console every ten seconds, which is
  # a permanent red herring on a box meant for troubleshooting practice.
  # These four persist on any hypervisor and on bare metal, and every one of
  # them is a knob RHEL actually gives you.
  local did=0

  # 1. the time service, off and staying off
  timedatectl set-ntp false >/dev/null 2>&1 && did=1
  systemctl disable --now chronyd >/dev/null 2>&1 && did=1

  # 2. a timezone half a world away — every log timestamp and every timer that
  #    fires on a wall-clock time is now wrong, and `date` looks fine locally
  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-timezone Pacific/Kiritimati >/dev/null 2>&1 && did=1
  fi

  # 3. tell the system the hardware clock holds local time, not UTC. The
  #    running clock is untouched, so this is invisible until the next boot,
  #    when it shifts by the timezone offset.
  if [[ -f /etc/adjtime ]]; then
    sed -i 's/^UTC$/LOCAL/' /etc/adjtime 2>/dev/null && did=1
  else
    printf '0.0 0 0.0\n0\nLOCAL\n' > /etc/adjtime 2>/dev/null && did=1
  fi

  # 4. files dated in the future, which is what makes this hard to unsee: make,
  #    dnf and anything using `find -newer` now disagree with reality.
  local f
  for f in /etc/hosts /etc/motd; do
    [[ -e $f ]] && touch -d '+40 days' "$f" 2>/dev/null && did=1
  done

  ((did))
}

fault_f7() {
  sed -i -E 's|^([[:space:]]*Defaults[[:space:]]+secure_path[[:space:]]*=[[:space:]]*).*|\1/usr/local/bin:/usr/bin|' \
    /etc/sudoers

  # Make a sudoers.d file world-writable so sudo refuses to read it — but never
  # the file that grants the lab account its own access. On a Vagrant box that
  # is /etc/sudoers.d/vagrant, and breaking it would lock you out of root with
  # no way back except the snapshot. A drill should be hard, not unrecoverable.
  local me groups f target=""
  me=${SUDO_USER:-$(awk -F: '$3 >= 1000 && $3 < 65534 && $6 ~ /^\/home\// { print $1; exit }' /etc/passwd)}
  groups=$(id -nG "$me" 2>/dev/null | tr ' ' '|')
  for f in /etc/sudoers.d/*; do
    [[ -f $f ]] || continue
    [[ $(basename "$f") == README ]] && continue
    grep -qE "(^|[[:space:]%])(${me}|${groups:-__none__})([[:space:]]|$)" "$f" && continue
    target=$f
    break
  done

  # Nothing safe to break? Then create the rule the labs create anyway, and
  # break that instead.
  if [[ -z ${target:-} ]]; then
    getent group developers >/dev/null 2>&1 || groupadd developers 2>/dev/null
    printf '%%developers ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart httpd, /usr/bin/systemctl status httpd\n' \
      > /etc/sudoers.d/developers
    chmod 0440 /etc/sudoers.d/developers
    target=/etc/sudoers.d/developers
  fi
  chmod 0666 "$target"
  return 0
}

fault_f8() {
  grubby --update-kernel=ALL --args="selinux=0" >/dev/null 2>&1 || return 1
}

fault_f9() {
  local con gw
  con=$(active_con) || return 1
  [[ -n ${con:-} ]] || return 1
  gw=$(ip -4 route show default 2>/dev/null | awk '{ print $3; exit }')
  nmcli con mod "$con" ipv4.ignore-auto-dns yes ipv4.dns "203.0.113.99" >/dev/null 2>&1 || return 1
  # Leave the live file looking right, so nothing breaks until the profile reloads.
  {
    echo "search lab.local"
    [[ -n ${gw:-} ]] && echo "nameserver $gw"
  } > /etc/resolv.conf
  return 0
}

fault_f10() {
  local f m
  if f=$(nfs_export_file); then
    sed -i -E 's/\(([^)]*)\brw\b([^)]*)\)/(\1ro\2)/g; s/\bno_root_squash\b/root_squash/g' "$f"
    grep -q 'root_squash' "$f" || sed -i -E 's/\(([^)]*)\)/(\1,root_squash)/' "$f"
    exportfs -ra >/dev/null 2>&1 || true
  else
    m=$(nfs_client_mount)
    [[ -n ${m:-} ]] || return 1
    awk -v m="$m" 'BEGIN { OFS = "\t" }
      $1 !~ /^#/ && $2 == m { $4 = ($4 == "defaults" ? "ro" : $4 ",ro") } { print }' \
      /etc/fstab > /etc/fstab.staged && mv -f /etc/fstab.staged /etc/fstab
    mount -o remount,ro "$m" >/dev/null 2>&1 || true
  fi
  return 0
}

apply() {
  local f=$1
  if ! can "$f"; then
    echo "  $f cannot be staged on this host (its prerequisites are missing)" >&2
    return 1
  fi
  "fault_$f" || { echo "  $f failed to stage cleanly" >&2; return 1; }
  record "$f"
  [[ -n ${NODE[$f]:-} ]] && echo "  note: ${NODE[$f]}"
  return 0
}

banner() {
  cat <<'EOF'

A fault has been staged. Nothing below tells you what it was.

  Some faults only show themselves after a restart. Reboot before you start,
  and remember that a repair which does not survive the next reboot is not a
  repair.

  Diagnose from the machine: journalctl -xe, systemctl status, ausearch,
  ss, findmnt, lsattr, /proc/cmdline. When you believe it is fixed:

      sudo ./verify advanced

  Then, and only then:  ./break-advanced.sh reveal

EOF
}

# ------------------------------------------------------------------- reveal ---
do_reveal() {
  [[ -s $LOG ]] || { echo "Nothing has been staged on this machine yet."; return 0; }
  local line ts f now
  now=$(date +%s)
  echo "What was done to this machine"
  echo
  while read -r line; do
    [[ -n ${line// /} ]] || continue
    set -- $(base64 -d <<<"$line" 2>/dev/null)
    ts=${1:-0}; f=${2:-?}
    printf '  %s   staged %s\n' "$f" "$(date -d "@$ts" '+%Y-%m-%d %H:%M' 2>/dev/null)"
    printf '       elapsed: %d min\n' $(( (now - ts) / 60 ))
    printf '       symptom: %s\n' "${SYMPTOM[$f]:-unknown}"
    printf '       cause:   %s\n\n' "${CAUSE[$f]:-unknown}"
  done < "$LOG"
  echo "Write the time and your first hypothesis into the drill log in"
  echo "10-Advanced-Breakfix-Labs, then revert to the clean snapshot."
}

do_status() {
  [[ -s $LOG ]] || { echo "No faults staged on this machine."; return 0; }
  local n first
  n=$(grep -c . "$LOG")
  first=$(head -1 "$LOG" | base64 -d 2>/dev/null | awk '{print $1}')
  echo "$n fault(s) staged; the first was staged $(( ($(date +%s) - ${first:-0}) / 60 )) minutes ago."
  echo "Run 'reveal' only after you have finished repairing and verifying."
}

do_list() {
  echo "Advanced break-fix drills — what each one looks like from the outside:"
  echo
  local f
  for f in "${FAULTS[@]}"; do
    printf '  %-4s %s\n' "$f" "${SYMPTOM[$f]}"
    [[ -n ${NODE[$f]:-} ]] && printf '       %s\n' "${NODE[$f]}"
    can "$f" || printf '       (cannot be staged here: prerequisites missing)\n'
  done
  echo
  echo "Full requirements and acceptance criteria: 10-Advanced-Breakfix-Labs."
}

# --------------------------------------------------------------------- main ---
ARGS=()
for a in "$@"; do
  case "$a" in
    --yes|-y) YES=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}
cmd=${1:-list}

case "$cmd" in
  list)   do_list; exit 0 ;;
  reveal) do_reveal; exit 0 ;;
  status) do_status; exit 0 ;;
  clear)  rm -f "$LOG"; echo "Log cleared. Nothing was repaired."; exit 0 ;;
esac

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "staging a fault needs root"

if ((YES == 0)); then
  cat <<EOF
This will deliberately damage $(hostname). Some faults fill a filesystem, move
the clock, or disable SELinux until you repair them by hand.

Take a snapshot first:

    virsh snapshot-create-as $(hostname -s 2>/dev/null || hostname) pre-lab

Then re-run with --yes.
EOF
  exit 1
fi

case "$cmd" in
  random)
    avail=()
    for f in "${FAULTS[@]}"; do can "$f" && avail+=("$f"); done
    ((${#avail[@]})) || die "no fault can be staged on this host"
    apply "${avail[$RANDOM % ${#avail[@]}]}" && banner
    ;;
  combo|chaos)
    n=3
    [[ $cmd == chaos ]] && n=${2:-5}
    [[ $n =~ ^[0-9]+$ ]] || die "chaos takes a number"
    avail=()
    for f in "${FAULTS[@]}"; do can "$f" && avail+=("$f"); done
    ((${#avail[@]})) || die "no fault can be staged on this host"
    # shuffle, then take the first n
    picked=$(printf '%s\n' "${avail[@]}" | shuf | head -n "$n")
    applied=0
    for f in $picked; do apply "$f" && applied=$((applied + 1)); done
    ((applied)) || die "nothing could be staged"
    echo "  $applied fault(s) staged."
    banner
    ;;
  f[0-9]|f10)
    printf '%s\n' "${FAULTS[@]}" | grep -qx "$cmd" || die "unknown drill: $cmd"
    apply "$cmd" && banner
    ;;
  *) die "unknown command: $cmd (try: list, random, combo, chaos N, f1..f10, status, reveal)" ;;
esac
