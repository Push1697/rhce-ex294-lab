#!/usr/bin/env bash
#
# incident.sh — open an incident against this estate.       (11-Incident-Drills)
#
#   DO NOT READ THE REST OF THIS FILE.
#
# It contains the causes. `reveal` prints them once you are finished, along with
# how long you took. Reading it now spends the only chance you get to meet these
# faults cold.
#
# Unlike break.sh and break-advanced.sh, this does not hand you a drill — it
# hands you a **work order**. Several things are wrong at once, on more than one
# host, some of them invisible until a reboot, and at level 4 something on the
# box is actively undoing your repairs until you find it.
#
#   ./incident.sh open 3 --yes     open a level-3 incident
#   ./incident.sh objective        re-print the work order
#   ./incident.sh status           how long it has been open
#   ./incident.sh reveal           the causes, and your elapsed time
#   ./incident.sh abandon --yes    give up: reveal, and undo the persistence
#
# ALWAYS snapshot first. There is no undo besides the snapshot:
#   lab.ps1 snap pre-incident            (Vagrant)
#   virsh snapshot-create-as rhel01 ...  (KVM)
set -uo pipefail

STATE=/var/tmp/rhce-verify
TICKET=$STATE/incident.json
ORDER=/root/INCIDENT.md
KIT=${KIT:-/opt/rhce-labs}
HERE=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")

# Time targets per level, in minutes. Deliberately tight.
declare -A SLA=([1]=15 [2]=40 [3]=75 [4]=120)

# What the reporter noticed. Symptoms only — never a cause.
declare -A SYMPTOM=(
  [fstab]="a filesystem that should be mounted is not, and the box may drop to emergency mode on restart"
  [selinux_ctx]="the web server returns 403 on files whose permissions are plainly correct"
  [selinux_port]="sshd will not come up on the port it was moved to"
  [firewall]="a service is listening but nothing off-box can reach it"
  [service]="a unit refuses to start and complains about its own configuration"
  [perms]="key-based SSH stopped working for a user, with no message worth reading"
  [repo]="dnf fails before it downloads anything"
  [dns]="names do not resolve, though addresses still work"
  [sudo]="a whole group lost the ability to escalate"
  [mount]="a mount is present now and absent after a restart"
  [f1]="names stop resolving, and /etc/hosts is demonstrably correct"
  [f2]="a service will not start on a config error you cannot correct"
  [f3]="the site is unreachable, and fixing one thing is not enough"
  [f4]="a unit starts by hand but never at boot, citing something that does not exist"
  [f5]="the filesystem is full and du cannot account for it"
  [f6]="everything time-sensitive misbehaves at once"
  [f7]="sudo works for some commands and refuses others"
  [f8]="SELinux is off after a reboot, and the config file says enforcing"
  [f9]="DNS works now and breaks on every reboot"
  [xnfs]="an NFS mount that worked yesterday now times out, and the client looks fine"
  [xweb]="rhel01 serves its page locally but nothing else on the network can fetch it"
  [persist]="repairs do not stick — something you fixed comes back broken a few minutes later"
  [decoy]="a unit is stopped and disabled, and the journal carries a warning about it"
)

# The answers. Printed by `reveal` only.
declare -A CAUSE=(
  [fstab]="a bogus UUID was appended to /etc/fstab"
  [selinux_ctx]="the document root was relabelled with chcon, so the label is wrong and would not survive a relabel"
  [selinux_port]="sshd was moved to 2222 but the port label was removed"
  [firewall]="http and 8080/tcp were removed from the permanent firewall configuration"
  [service]="an invalid directive was appended to httpd.conf"
  [perms]="~/.ssh and authorized_keys were made group- and world-writable, so sshd refuses them"
  [repo]="a repository baseurl was pointed at somewhere that does not exist"
  [dns]="the connection profile's DNS server was set to a black hole"
  [sudo]="the %wheel rule in /etc/sudoers was commented out"
  [mount]="a lab mount was commented out of /etc/fstab and unmounted"
  [f1]="the hosts: line in nsswitch.conf lost its 'files' source"
  [f2]="the config file was corrupted and then made immutable with chattr +i"
  [f3]="three independent causes behind one symptom: a chcon relabel, a move to an unlabelled port, and http removed from the firewall"
  [f4]="a systemd drop-in added RequiresMountsFor for a mount unit that does not exist"
  [f5]="a large file was opened by a background process and then deleted, so the space is allocated but unreachable"
  [f6]="four separate time faults: the time service disabled, the timezone moved to Pacific/Kiritimati, /etc/adjtime switched to LOCAL so a reboot shifts the clock, and files under /etc dated forty days ahead"
  [f7]="Defaults secure_path lost its sbin directories, and a sudoers.d file was made world-writable"
  [f8]="selinux=0 was added to the kernel command line, which beats /etc/selinux/config"
  [f9]="the NetworkManager profile carries a bogus DNS server, so the generated resolv.conf reverts on every boot"
  [xnfs]="the fault is on rhel02, not rhel01: nfs was removed from the server's firewall"
  [xweb]="the fault is on rhel02's side of the conversation: a rich rule there rejects rhel01"
  [persist]="a systemd timer named sysstat-collect-aux re-applies a fault every three minutes — the firewall where firewalld exists, otherwise the hosts: line in nsswitch.conf. The unit and its script both carry a lab marker, but you have to find them"
  [decoy]="a decoy. rngd was stopped and a warning logged. Nothing depended on it, and nothing in the acceptance criteria mentions it — the exercise was to not waste time on it"
)

# Which host each fault belongs on.
declare -A ON=([xnfs]=rhel02 [xweb]=rhel02)

LOCAL_L1=(fstab selinux_ctx firewall service perms repo dns sudo mount)
LOCAL_L2=(f1 f2 f4 f5 f7 f9)
LOCAL_L3=(f6 f8)
XNODE=(xnfs xweb)

# Faults that must not be staged together, because they act on the same thing.
# Two faults with one mechanism are not a harder drill: fixing either fixes
# both, and `reveal` then reads as though it repeated itself. Layered faults
# that merely share a *symptom* are fair game and stay in — f8 hiding
# selinux_ctx behind a disabled SELinux is the point of the exercise.
declare -A CONFLICT=(
  [dns]="f9"                                   # both point the NM profile at a black hole
  [f9]="dns"
  [firewall]="f3 persist"                      # persist re-removes http on a timer
  [persist]="firewall f3"
  [f3]="firewall selinux_ctx selinux_port persist"
  [selinux_ctx]="f3"
  [selinux_port]="f3"
  [sudo]="f7"                                  # both land in sudoers
  [f7]="sudo"
  [service]="f2"                               # both corrupt the same httpd.conf
  [f2]="service"
  [fstab]="mount"                              # both edit /etc/fstab
  [mount]="fstab"
)

die()  { echo "incident: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
now()  { date +%s; }

# ------------------------------------------------------------------ faults ----
apply_break_sh() {   # reuse the single-cause saboteur
  local f=$1
  [[ -x $HERE/break.sh ]] || { echo "  (break.sh missing, skipping $f)" >&2; return 1; }
  "$HERE/break.sh" "$f" >/dev/null 2>&1
}

apply_advanced() {   # reuse the harder saboteur, without its own bookkeeping
  local f=$1
  [[ -x $HERE/break-advanced.sh ]] || { echo "  (break-advanced.sh missing, skipping $f)" >&2; return 1; }
  "$HERE/break-advanced.sh" "$f" --yes >/dev/null 2>&1
}

# The adversarial one: a timer that undoes a repair until it is found.
#
# Whatever it re-applies has to be something this host can actually have done to
# it. A drill that reports "repairs do not stick" on a box where the mechanism
# is absent is not a hard drill, it is a lie — so pick a payload that works
# here, and refuse to stage if none does.
persist_payload() {
  if have firewall-cmd; then
    cat <<'SCRIPT'
# It re-applies a firewall fault, so a repair that was not made permanent — or
# a cause that was never removed — comes back.
firewall-cmd --permanent --remove-service=http  >/dev/null 2>&1 || true
firewall-cmd --permanent --remove-port=8080/tcp >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true
SCRIPT
    return 0
  fi
  if [[ -f /etc/nsswitch.conf ]]; then
    cat <<'SCRIPT'
# It re-applies a name-resolution fault: the hosts: line loses its files source,
# so /etc/hosts stops being consulted a few minutes after you repair it.
sed -i -E 's/^([[:space:]]*hosts:.*)\<files\>[[:space:]]*/\1/' /etc/nsswitch.conf 2>/dev/null || true
SCRIPT
    return 0
  fi
  return 1
}

apply_persist() {
  local payload
  payload=$(persist_payload) || {
    echo "  (nothing on this host can be re-broken on a timer)" >&2
    return 1
  }

  {
    cat <<'HEAD'
#!/usr/bin/env bash
# rhce-lab artifact: part of an incident drill. Safe to delete once found.
HEAD
    printf '%s\n' "$payload"
  } > /usr/local/sbin/sysstat-collect-aux
  chmod 0755 /usr/local/sbin/sysstat-collect-aux

  cat > /etc/systemd/system/sysstat-collect-aux.service <<'UNIT'
[Unit]
Description=Auxiliary metrics collection
# rhce-lab artifact: part of an incident drill.

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sysstat-collect-aux
UNIT

  cat > /etc/systemd/system/sysstat-collect-aux.timer <<'UNIT'
[Unit]
Description=Auxiliary metrics collection schedule
# rhce-lab artifact: part of an incident drill.

[Timer]
OnBootSec=2min
OnUnitActiveSec=3min
AccuracySec=15s

[Install]
WantedBy=timers.target
UNIT

  systemctl daemon-reload
  systemctl enable --now sysstat-collect-aux.timer >/dev/null 2>&1 || {
    echo "  (the timer would not enable)" >&2
    return 1
  }
  # and break it once immediately, so the symptom is there from the start
  /usr/local/sbin/sysstat-collect-aux
  # Prove the payload actually did something. If it did not, the report would
  # promise a symptom that never appears, so back the whole fault out.
  if ! persist_took_effect; then
    echo "  (the persistence payload had no effect here)" >&2
    remove_persistence
    return 1
  fi
  return 0
}

persist_took_effect() {
  if have firewall-cmd; then
    ! firewall-cmd --permanent --query-service=http >/dev/null 2>&1
  else
    ! grep -Eq '^[[:space:]]*hosts:.*\<files\>' /etc/nsswitch.conf
  fi
}

remove_persistence() {
  systemctl disable --now sysstat-collect-aux.timer >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/sysstat-collect-aux.timer \
        /etc/systemd/system/sysstat-collect-aux.service \
        /usr/local/sbin/sysstat-collect-aux
  systemctl daemon-reload >/dev/null 2>&1 || true
}

# A decoy: alarming, and irrelevant.
apply_decoy() {
  systemctl disable --now rngd >/dev/null 2>&1 ||
    systemctl disable --now chronyd-restricted >/dev/null 2>&1 || true
  logger -p daemon.err -t rngd "entropy source unavailable, degraded mode" 2>/dev/null || true
}

# Faults that live on the other node. Reached over SSH as the lab user, which is
# how you would reach it anyway.
apply_xnode() {
  local f=$1 host=${ON[$1]} cmd
  case "$f" in
    xnfs) cmd='sudo firewall-cmd --permanent --remove-service=nfs; sudo firewall-cmd --permanent --remove-service=mountd; sudo firewall-cmd --permanent --remove-service=rpc-bind; sudo firewall-cmd --reload' ;;
    xweb) local me; me=$(my_lab_ip)
          [[ -n ${me:-} ]] || return 1
          cmd="sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=$me reject'; sudo firewall-cmd --reload" ;;
    *) return 1 ;;
  esac
  peer_ssh "$host" "$cmd" >/dev/null 2>&1
}

apply_fault() {
  local f=$1
  case "$f" in
    persist) apply_persist ;;
    decoy)   apply_decoy ;;
    xnfs|xweb) apply_xnode "$f" ;;
    f[0-9]|f10) apply_advanced "$f" ;;
    *)       apply_break_sh "$f" ;;
  esac
}

# --------------------------------------------------------------- baseline -----
# How many checks were already failing *before* anything was staged.
#
# The grader used to require both health sweeps to pass outright. On a lab where
# the web labs have not been done yet, httpd is not installed and three checks
# fail on a completely clean estate — so no incident could ever be graded green.
# Recording the starting point means the drill grades what you broke, not what
# was never built.
fail_count() {   # fail_count <checker file name>
  local out
  out=$(bash "$HERE/../labs/$1" --no-color --no-mutate 2>&1) || true
  grep -Eo '[0-9]+ failed' <<<"$out" | head -1 | tr -dc '0-9'
}

# ------------------------------------------------------------------ ticket ----
pick() {   # pick <n> from a list, without repeats
  local n=$1; shift
  printf '%s\n' "$@" | shuf | head -n "$n"
}

# Is the other node up and reachable as the lab user? Only then is it fair to
# put a fault on it. If it is not, the estate is single-node and the drill
# stays single-node, rather than listing a symptom nothing could stage.
# Root's copy of the lab key, written by the provisioner. The lab user is
# deliberately not given the private half on the managed nodes — distributing it
# is a Month 2 Ansible lab — so the saboteur uses root's copy and logs in *as*
# the lab user, which grants nobody access they did not already have.
PEER_KEY=${PEER_KEY:-/etc/rhce-lab/peer_key}

# The provisioner records what this node actually is, so nothing here has to
# guess at interface ordering. Only fills in what is not already set.
if [[ -r /etc/rhce-lab.env ]]; then
  while IFS='=' read -r _k _v; do
    [[ $_k =~ ^LAB_[A-Z_]+$ ]] || continue
    [[ -n ${!_k:-} ]] && continue
    eval "$_k=\$_v"
  done < /etc/rhce-lab.env
  unset _k _v
fi

# This node's address on the lab network — not the NAT interface Vagrant uses.
my_lab_ip() {
  if [[ -n ${LAB_PRIMARY_IP:-} ]]; then echo "$LAB_PRIMARY_IP"; return 0; fi
  local pfx=${LAB_NET:-192.168.56}
  ip -4 -o addr show 2>/dev/null | awk -v p="$pfx." '$4 ~ "^" p { split($4, a, "/"); print a[1]; exit }'
}

peer_ssh() {   # peer_ssh <host> <command...>
  local host=$1; shift
  local -a opt=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8)
  [[ -r $PEER_KEY ]] && opt+=(-i "$PEER_KEY" -o IdentitiesOnly=yes)
  ssh "${opt[@]}" -l "${LAB_USER:-vagrant}" "$host" "$@"
}

xnode_reachable() {
  peer_ssh "${1:-rhel02}" 'sudo -n true' >/dev/null 2>&1
}

CHOSEN=()

conflicts_with_chosen() {   # conflicts_with_chosen <fault>
  local cand=$1 c
  for c in ${CHOSEN[@]+"${CHOSEN[@]}"}; do
    [[ $cand == "$c" ]] && return 0
    [[ " ${CONFLICT[$c]:-} "    == *" $cand "* ]] && return 0
    [[ " ${CONFLICT[$cand]:-} " == *" $c "*    ]] && return 0
  done
  return 1
}

take() {   # take <n> <pool...> — add up to n non-conflicting faults to CHOSEN
  local n=$1; shift
  local f
  while read -r f; do
    ((n)) || break
    conflicts_with_chosen "$f" && continue
    CHOSEN+=("$f"); n=$((n - 1))
  done < <(printf '%s
' "$@" | shuf)
}

compose() {   # compose <level> -> the fault list, one per line
  local lvl=$1
  CHOSEN=()
  case "$lvl" in
    1) take 1 "${LOCAL_L1[@]}" ;;
    2) take 1 "${LOCAL_L1[@]}"; take 2 "${LOCAL_L2[@]}" ;;
    3) take 2 "${LOCAL_L1[@]}"; take 2 "${LOCAL_L2[@]}"; take 1 "${LOCAL_L3[@]}"
       xnode_reachable && take 1 "${XNODE[@]}" ;;
    # persist is chosen first so the pools below cannot pick the fault it owns
    4) CHOSEN+=(persist)
       take 2 "${LOCAL_L1[@]}"; take 2 "${LOCAL_L2[@]}"; take 1 "${LOCAL_L3[@]}"
       xnode_reachable && take 1 "${XNODE[@]}"
       CHOSEN+=(decoy) ;;
    *) die "level must be 1, 2, 3 or 4" ;;
  esac
  printf '%s
' ${CHOSEN[@]+"${CHOSEN[@]}"}
}

write_ticket() {   # write_ticket <level> <opened> <faults...>
  local lvl=$1 opened=$2; shift 2
  mkdir -p "$STATE"
  {
    printf 'level=%s\n' "$lvl"
    printf 'opened=%s\n' "$opened"
    printf 'sla=%s\n' "${SLA[$lvl]}"
    # The boot this incident was opened on. Comparing timestamps cannot prove
    # a reboot here: one of the faults moves the clock, which makes a boot
    # from *before* the incident look like it happened after it. A boot id is
    # exact, and does not care what the clock says.
    printf 'boot=%s\n' "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
    printf 'base_bf=%s\n' "${BASE_BF:-}"
    printf 'base_adv=%s\n' "${BASE_ADV:-}"
    printf 'faults=%s\n' "$*"
  } | base64 > "$TICKET"
  chmod 0600 "$TICKET"
}

read_ticket() {
  [[ -s $TICKET ]] || return 1
  base64 -d < "$TICKET" 2>/dev/null
}

field() { read_ticket | awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print }'; }

# ------------------------------------------------------------- work order -----
# Timestamps here are UTC on purpose: one of the faults moves the timezone, so
# a local-time work order would be stamped fourteen hours from anywhere.
write_order() {
  local lvl=$1 opened=$2; shift 2
  local -a faults=("$@")
  local hosts="rhel01"
  for f in "${faults[@]}"; do [[ -n ${ON[$f]:-} ]] && hosts="rhel01, ${ON[$f]}"; done

  {
    cat <<EOF
# INCIDENT $(date -u -d "@$opened" '+%Y%m%d-%H%M') — severity $lvl

**Opened:** $(date -u -d "@$opened" '+%Y-%m-%d %H:%M:%S') UTC
**Target:** restore service within **${SLA[$lvl]} minutes**
**Scope:** $hosts

## What was reported

EOF
    printf '%s\n' "${faults[@]}" | shuf | while read -r f; do
      printf -- '- %s\n' "${SYMPTOM[$f]:-something is wrong and nobody wrote down what}"
    done
    cat <<EOF

There are **${#faults[@]}** reports. They may or may not share a cause, and one
report may turn out to be several faults wearing a single symptom.

## What "resolved" means

- Every service that should be running is running, and is **enabled**.
- Everything a client needs to reach is reachable **from the other node**, not
  just from localhost.
- SELinux is **enforcing**, and every label survives a relabel.
- The firewall's runtime and permanent configurations are identical.
- \`findmnt --verify\` is clean and \`mount -a\` is silent.
- **It all still holds after a reboot.** Reboot before you declare it fixed.

## Rules of engagement

- No \`setenforce 0\`. Not even briefly. Not even to test a theory.
- No \`chmod 777\`, no widening a permission to make something work.
- No rebuilding the node, and no restoring a snapshot — that is a surrender.
- No reading the saboteurs in \`$KIT/break/\`.
- Searching, \`man\`, and the machine's own logs are all fair game.

## When you think it is done

\`\`\`bash
sudo $KIT/verify incident --blind    # am I there yet? pass/fail only
sudo $KIT/verify incident            # what is still wrong
sudo $KIT/break/incident.sh reveal   # the causes, and your time
\`\`\`
EOF
  } > "$ORDER"
  chmod 0644 "$ORDER"
}

# --------------------------------------------------------------------- cmds ---
cmd_open() {
  local lvl=${1:-2}
  [[ -n ${SLA[$lvl]:-} ]] || die "level must be 1, 2, 3 or 4"
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "opening an incident needs root"

  if [[ -s $TICKET ]] && [[ ${FORCE:-0} != 1 ]]; then
    echo "An incident is already open. Close it with 'reveal', or pass --force." >&2
    cmd_status
    exit 1
  fi

  echo "Taking a baseline of the estate first, so the grade measures what the"
  echo "incident breaks rather than what has not been built yet. One minute."
  BASE_BF=$(fail_count breakfix-health.sh)
  BASE_ADV=$(fail_count breakfix-advanced.sh)
  echo "  baseline: ${BASE_BF:-?} failing in the single-cause sweep, ${BASE_ADV:-?} in the advanced one"
  echo

  local opened; opened=$(now)
  local -a faults=()
  while read -r f; do [[ -n ${f// /} ]] && faults+=("$f"); done < <(compose "$lvl")
  # compose ran in a process substitution, so its CHOSEN did not survive either
  CHOSEN=(${faults[@]+"${faults[@]}"})

  echo "Opening a severity-$lvl incident against $(hostname -s)..."

  # A fault that will not stage here — a package this node does not have, a
  # peer that is down — is replaced by another from the same estate rather than
  # dropped, so a severity-4 order really does carry a severity-4 workload.
  local -a pool=("${LOCAL_L1[@]}" "${LOCAL_L2[@]}" "${LOCAL_L3[@]}")
  # STAGED is a global on purpose: a command substitution would run stage_one in
  # a subshell, and its addition to CHOSEN would not survive, so the next
  # substitution could pick a fault that conflicts with this one.
  STAGED=""
  stage_one() {   # stage_one <fault> -> sets STAGED to whatever got staged
    local f=$1 sub tries=0
    STAGED=""
    apply_fault "$f" && { STAGED=$f; return 0; }
    while read -r sub; do
      (( tries++ >= 4 )) && break
      conflicts_with_chosen "$sub" && continue
      if apply_fault "$sub"; then CHOSEN+=("$sub"); STAGED=$sub; return 0; fi
    done < <(printf '%s
' "${pool[@]}" | shuf)
    return 1
  }

  local applied=()
  for f in "${faults[@]}"; do
    if stage_one "$f"; then applied+=("$STAGED")
    else echo "  (one report could not be staged on this estate; continuing)" >&2; fi
  done
  ((${#applied[@]})) || die "nothing could be staged — is this a fresh lab node?"

  write_ticket "$lvl" "$opened" "${applied[@]}"
  write_order  "$lvl" "$opened" "${applied[@]}"

  cat <<EOF

  ${#applied[@]} fault(s) staged. Your work order is at $ORDER

      cat $ORDER

  Some of this is invisible until you reboot. Reboot before you start, and
  again before you declare it fixed.

  Clock is running: ${SLA[$lvl]} minutes.

EOF
}

cmd_objective() {
  [[ -s $ORDER ]] || die "no work order on this host — open an incident first"
  cat "$ORDER"
}

cmd_status() {
  read_ticket >/dev/null 2>&1 || { echo "No incident open on $(hostname -s)."; return 0; }
  local opened sla lvl mins
  opened=$(field opened); sla=$(field sla); lvl=$(field level)
  mins=$(( ($(now) - opened) / 60 ))
  echo "Severity-$lvl incident, open for $mins minute(s) of a $sla-minute target."
  local n; n=$(field faults | wc -w)
  echo "$n fault(s) were staged. Work order: $ORDER"
  (( mins > sla )) && echo "You are over the target. Keep going — record the real time."
  return 0
}

cmd_reveal() {
  read_ticket >/dev/null 2>&1 || die "no incident recorded on this host"
  local opened sla lvl mins
  opened=$(field opened); sla=$(field sla); lvl=$(field level)
  mins=$(( ($(now) - opened) / 60 ))

  echo "Severity-$lvl incident, opened $(date -u -d "@$opened" '+%Y-%m-%d %H:%M') UTC"
  echo "Elapsed: $mins minute(s) against a $sla-minute target — $( ((mins <= sla)) && echo "inside" || echo "OVER" )"
  echo
  echo "What was done to this estate:"
  echo
  for f in $(field faults); do
    printf '  %-12s %s\n' "$f" "${SYMPTOM[$f]:-?}"
    printf '  %-12s cause: %s\n\n' "" "${CAUSE[$f]:-?}"
  done
  cat <<EOF
Write the time, and which report misled you longest, into the drill log in
11-Incident-Drills. Then restore the clean snapshot.
EOF
}

cmd_abandon() {
  read_ticket >/dev/null 2>&1 || die "no incident recorded on this host"
  echo "Abandoning. Removing the persistence mechanism if it is present, so the"
  echo "estate stops fighting you — everything else is left for the snapshot."
  remove_persistence
  echo
  cmd_reveal
}

cmd_help() {
  cat <<EOF
incident.sh — open an incident against this estate

  open <1-4> --yes     stage an incident and write the work order
  objective            re-print the work order
  status               how long it has been open
  reveal               the causes, and your elapsed time
  abandon --yes        give up: stop the persistence, then reveal

Severity levels

  1   one fault, one host                          target ${SLA[1]} min
  2   three faults, some invisible until a reboot   target ${SLA[2]} min
  3   five faults across two hosts                  target ${SLA[3]} min
  4   level 3, plus something that undoes your
      repairs until you find it, plus one decoy     target ${SLA[4]} min

Grade it with:  sudo $KIT/verify incident
EOF
}

# --------------------------------------------------------------------- main ---
YES=0; FORCE=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --yes|-y) YES=1 ;;
    --force)  FORCE=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}
export FORCE

case "${1:-help}" in
  objective) cmd_objective ;;
  status)    cmd_status ;;
  reveal)    cmd_reveal ;;
  abandon)
    ((YES)) || die "abandoning is a surrender; pass --yes if you mean it"
    cmd_abandon ;;
  open)
    if ((YES == 0)); then
      cat <<EOF
This deliberately breaks $(hostname -s) — and at severity 3 and above, rhel02 too.
Several faults at once, some only visible after a reboot, and at severity 4
something that undoes your repairs until you find it.

Snapshot first. There is no undo but the snapshot:

    lab.ps1 snap pre-incident

Then re-run with --yes.
EOF
      exit 1
    fi
    cmd_open "${2:-2}" ;;
  help|-h|--help) cmd_help ;;
  *) die "unknown command: ${1}. Try: open, objective, status, reveal, abandon" ;;
esac
