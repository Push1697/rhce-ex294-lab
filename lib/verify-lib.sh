#!/usr/bin/env bash
# verify-lib.sh — shared harness for the RHCSA/RHCE lab verification scripts.
#
# Offline by design: bash + coreutils only. Nothing is downloaded and nothing
# leaves the machine. Source it from a lab script:
#
#   . "$(dirname "${BASH_SOURCE[0]}")/../lib/verify-lib.sh"
#   lab_init "1.2" "Users, groups and password policy" --host rhel01 --root
#   section "Groups"
#   check_eq "developers has GID 5000" 5000 "$(group_gid developers)"
#   summary
#
# It never tells you HOW to fix a failure — that is the lab's job. It tells you
# what is wrong and what the machine actually reports.

# Deliberately NOT set -e: a failing check must never abort the run.
set -uo pipefail

# ---------------------------------------------------------------- appearance --
if [[ -t 1 && "${NO_COLOR:-}" == "" && "${TERM:-dumb}" != dumb ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
  C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN=
fi

# ------------------------------------------------------------------ counters --
V_PASS=0; V_FAIL=0; V_WARN=0; V_SKIP=0; V_MANUAL=0
V_PERSIST_PASS=0
V_LAB=""; V_TITLE=""; V_SCORE_MODE=0
V_SECTION=""; V_SECTION_FAIL=0; V_SECTION_STARTED=0
V_VERBOSE=${VERIFY_VERBOSE:-0}
V_MUTATE=${VERIFY_MUTATE:-1}
V_AFTER_REBOOT=0
V_BLIND=${VERIFY_BLIND:-0}
V_HARD=${VERIFY_HARD:-0}; export V_HARD
V_CHECK_N=0
V_LAST_OUT=""
V_STATE_DIR=""; V_BOOT_ID=""; V_LAST_PASS_BOOT=""
_P=0
declare -a V_FAILED_SECTIONS=()
declare -a V_SECTIONS_TOTAL=()
declare -a V_FAILED_LINES=()
declare -a V_CLEANUP=()
declare -a V_ARGS=()

# --------------------------------------------------------------- option parse --
# Consumes the harness's own flags; anything else is left in V_ARGS for the
# calling script (the mock graders use it for --spec).
_v_parse_args() {
  while (($#)); do
    case "$1" in
      -v|--verbose)   V_VERBOSE=1 ;;
      -q|--quiet)     V_VERBOSE=0 ;;
      --no-mutate)    V_MUTATE=0 ;;
      --mutate)       V_MUTATE=1 ;;
      --after-reboot) V_AFTER_REBOOT=1 ;;
      --blind)        V_BLIND=1 ;;
      --hard)         V_HARD=1; export V_HARD ;;
      --no-color)     C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN= ;;
      -h|--help)      _v_usage; exit 0 ;;
      *)              V_ARGS+=("$1") ;;
    esac
    shift
  done
}

_v_usage() {
  echo "$(basename "$0") — verification for lab ${V_LAB:-?}"
  echo
  echo "  -v, --verbose       show command output for passing checks too"
  echo "      --no-mutate     skip checks that create or delete anything"
  echo "      --after-reboot  refuse to run unless the machine booted recently"
  echo "      --blind         report pass/fail only, without saying what was checked"
  echo "      --hard          exam conditions: no diagnostics on failure, warnings"
  echo "                      count as failures, tighter tolerances, and a pass"
  echo "                      requires proof it survived a reboot"
  echo "      --no-color      plain output (also honoured via NO_COLOR=1)"
  echo "  -h, --help          this text"
  echo
  echo "Exit status: 0 = every automated check passed, 1 = at least one failed."
  echo "Checks marked [P] are the ones that classically vanish on reboot."
}

# ------------------------------------------------------------------- plumbing --
_v_state_dir() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    printf '/var/tmp/rhce-verify'
  else
    printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/rhce-verify"
  fi
}

_v_boot_id() { cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown; }

_v_host() { hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown; }

_v_uptime_human() {
  local s
  s=$(cut -d. -f1 /proc/uptime 2>/dev/null) || { echo unknown; return; }
  printf '%dd %02dh %02dm' $((s / 86400)) $((s % 86400 / 3600)) $((s % 3600 / 60))
}

lab_init() {
  V_LAB="$1"; V_TITLE="$2"; shift 2
  local want_host="" want_root=0 want_user=0
  local -a rest=()
  while (($#)); do
    case "$1" in
      --host)  want_host="$2"; shift ;;
      --root)  want_root=1 ;;
      --user)  want_user=1 ;;
      --score) V_SCORE_MODE=1 ;;
      *)       rest+=("$1") ;;
    esac
    shift
  done
  _v_parse_args ${rest[@]+"${rest[@]}"}

  V_STATE_DIR=$(_v_state_dir); mkdir -p "$V_STATE_DIR" 2>/dev/null || true
  V_BOOT_ID=$(_v_boot_id)
  V_LAST_PASS_BOOT=$(cat "$V_STATE_DIR/lab-$V_LAB.boot" 2>/dev/null || echo "")

  echo "${C_BOLD}${C_BLUE}== Lab $V_LAB — $V_TITLE${C_RESET}"
  echo "${C_DIM}   $(hostname) · up $(_v_uptime_human) · $(date '+%Y-%m-%d %H:%M:%S')${C_RESET}"

  if ((V_AFTER_REBOOT)); then
    local up
    up=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 999999)
    if ((up > 1800)); then
      echo "${C_RED}   --after-reboot given, but this machine has been up $(_v_uptime_human).${C_RESET}"
      echo "${C_RED}   Reboot, then run this again. Nothing was checked.${C_RESET}"
      exit 2
    fi
  fi
  if ((want_root)) && [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "${C_RED}   This lab must be verified as root:  sudo $0${C_RESET}"; exit 2
  fi
  if ((want_user)) && [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo "${C_RED}   This lab must be verified as the ordinary user, NOT root.${C_RESET}"; exit 2
  fi
  if [[ -n $want_host && $(_v_host) != "$want_host" ]]; then
    echo "${C_YELLOW}   Note: written for '$want_host', running on '$(_v_host)'.${C_RESET}"
  fi
  ((V_MUTATE)) || echo "${C_DIM}   --no-mutate: checks that touch the system will be skipped.${C_RESET}"
  ((V_HARD)) && echo "${C_RED}   HARD MODE: no diagnostics, warnings fail, and a pass needs a reboot.${C_RESET}"
  echo
  trap _v_run_cleanup EXIT
}

section() {
  _v_close_section
  V_SECTION="$1"; V_SECTION_FAIL=0; V_SECTION_STARTED=1
  V_SECTIONS_TOTAL+=("$1")
  echo "${C_BOLD}$1${C_RESET}"
}

_v_close_section() {
  ((V_SECTION_STARTED)) || return 0
  ((V_SECTION_FAIL)) && V_FAILED_SECTIONS+=("$V_SECTION")
  V_SECTION_STARTED=0
  echo
  return 0
}

# Render the captured output of the last command, indented, for diagnosis.
_v_show_out() {
  local out="$1" max="${2:-6}" n=0 line
  if [[ -z ${out//[[:space:]]/} ]]; then
    echo "        ${C_DIM}(no output)${C_RESET}"; return 0
  fi
  while IFS= read -r line; do
    n=$((n + 1))
    if ((n > max)); then echo "        ${C_DIM}...${C_RESET}"; break; fi
    echo "        ${C_DIM}${line:0:150}${C_RESET}"
  done <<<"$out"
  return 0
}

_v_result() {   # _v_result PASS|FAIL|WARN|SKIP|MANUAL persist desc [detail]
  local kind="$1" persist="$2" desc="$3" detail="${4:-}" tag mark
  case "$kind" in
    PASS)   tag="${C_GREEN}PASS${C_RESET}";  V_PASS=$((V_PASS + 1))
            ((persist)) && V_PERSIST_PASS=$((V_PERSIST_PASS + 1)) ;;
    FAIL)   tag="${C_RED}FAIL${C_RESET}";    V_FAIL=$((V_FAIL + 1)); V_SECTION_FAIL=1
            V_FAILED_LINES+=("$desc") ;;
    WARN)   tag="${C_YELLOW}WARN${C_RESET}"; V_WARN=$((V_WARN + 1)) ;;
    SKIP)   tag="${C_DIM}SKIP${C_RESET}";    V_SKIP=$((V_SKIP + 1)) ;;
    MANUAL) tag="${C_CYAN}CHECK${C_RESET}";  V_MANUAL=$((V_MANUAL + 1)) ;;
  esac
  # Hard mode: a warning is a failure, and you get the verdict without the
  # evidence — same as an exam, where nothing tells you which way it went wrong.
  if ((V_HARD)) && [[ $kind == WARN ]]; then
    kind=FAIL; tag="${C_RED}FAIL${C_RESET}"
    V_WARN=$((V_WARN - 1)); V_FAIL=$((V_FAIL + 1)); V_SECTION_FAIL=1
    V_FAILED_LINES+=("$desc")
  fi
  if ((V_HARD)); then detail=""; fi
  if ((persist)); then mark=" ${C_CYAN}[P]${C_RESET}"; else mark=""; fi
  if ((V_BLIND)); then
    # Blind mode: say whether it passed, never what was examined. For the
    # break-fix drills, where the check description would hand you the answer.
    V_CHECK_N=$((V_CHECK_N + 1))
    echo "  [$tag] check ${V_CHECK_N}${mark}"
    return 0
  fi
  echo "  [$tag] ${desc}${mark}"
  [[ -n $detail ]] && echo "        ${C_DIM}${detail}${C_RESET}"
  if ((V_HARD)); then
    return 0
  elif [[ $kind == FAIL && -n ${V_LAST_OUT//[[:space:]]/} ]]; then
    _v_show_out "$V_LAST_OUT"
  elif ((V_VERBOSE)) && [[ $kind == PASS && -n ${V_LAST_OUT//[[:space:]]/} ]]; then
    _v_show_out "$V_LAST_OUT" 3
  fi
  return 0
}

_v_take_persist_flag() {
  _P=0
  [[ ${1:-} == -p ]] && _P=1
  return 0
}

_v_run() {   # run a command, capture combined output into V_LAST_OUT, return rc
  V_LAST_OUT=$("$@" 2>&1)
  return $?
}

# ---------------------------------------------------------------- check verbs --

# check [-p] "desc" cmd...           pass when cmd exits 0
check() {
  _v_take_persist_flag "$@"; ((_P)) && shift
  local desc="$1"; shift
  if _v_run "$@"; then _v_result PASS "$_P" "$desc"; else _v_result FAIL "$_P" "$desc"; fi
}

# check_not [-p] "desc" cmd...       pass when cmd exits non-zero
check_not() {
  _v_take_persist_flag "$@"; ((_P)) && shift
  local desc="$1"; shift
  if _v_run "$@"; then
    _v_result FAIL "$_P" "$desc" "the command succeeded when it had to fail"
  else
    _v_result PASS "$_P" "$desc"
  fi
}

# check_sh [-p] "desc" 'shell code'  pass when the snippet exits 0
check_sh() {
  _v_take_persist_flag "$@"; ((_P)) && shift
  local desc="$1" code="$2"
  if _v_run bash -c "$code"; then _v_result PASS "$_P" "$desc"; else _v_result FAIL "$_P" "$desc"; fi
}

# check_not_sh [-p] "desc" 'shell code'
check_not_sh() {
  _v_take_persist_flag "$@"; ((_P)) && shift
  local desc="$1" code="$2"
  if _v_run bash -c "$code"; then
    _v_result FAIL "$_P" "$desc" "the command succeeded when it had to fail"
  else
    _v_result PASS "$_P" "$desc"
  fi
}

# check_eq [-p] "desc" expected actual
check_eq() {
  _v_take_persist_flag "$@"; ((_P)) && shift
  local desc="$1" want="$2" got="${3:-}"
  V_LAST_OUT=""
  if [[ "$got" == "$want" ]]; then
    _v_result PASS "$_P" "$desc"
  else
    _v_result FAIL "$_P" "$desc" "expected '$want', got '${got:-<empty>}'"
  fi
}

# check_match [-p] "desc" regex cmd...     stdout must match (ERE, case-insensitive)
check_match() {
  _v_take_persist_flag "$@"; ((_P)) && shift
  local desc="$1" re="$2"; shift 2
  _v_run "$@" || true
  if grep -Eqi -- "$re" <<<"$V_LAST_OUT"; then
    _v_result PASS "$_P" "$desc"
  else
    _v_result FAIL "$_P" "$desc" "nothing in the output matched /$re/"
  fi
}

# check_nomatch [-p] "desc" regex cmd...   stdout must NOT match
check_nomatch() {
  _v_take_persist_flag "$@"; ((_P)) && shift
  local desc="$1" re="$2"; shift 2
  _v_run "$@" || true
  if grep -Eqi -- "$re" <<<"$V_LAST_OUT"; then
    _v_result FAIL "$_P" "$desc" "the output still matches /$re/"
  else
    _v_result PASS "$_P" "$desc"
  fi
}

# check_empty [-p] "desc" cmd...     pass when the command produces no output
check_empty() {
  _v_take_persist_flag "$@"; ((_P)) && shift
  local desc="$1"; shift
  _v_run "$@" || true
  if [[ -z ${V_LAST_OUT//[[:space:]]/} ]]; then
    _v_result PASS "$_P" "$desc"
  else
    _v_result FAIL "$_P" "$desc" "expected no output at all"
  fi
}

# check_file [-p] "desc" path        exists, regular, non-empty
check_file() {
  _v_take_persist_flag "$@"; ((_P)) && shift
  local desc="$1" path="$2"
  V_LAST_OUT=$(ls -ld -- "$path" 2>&1)
  if [[ -f $path && -s $path ]]; then _v_result PASS "$_P" "$desc"
  elif [[ -f $path ]]; then _v_result FAIL "$_P" "$desc" "$path exists but is empty"
  else _v_result FAIL "$_P" "$desc" "$path does not exist"; fi
}

# check_dir [-p] "desc" path
check_dir() {
  _v_take_persist_flag "$@"; ((_P)) && shift
  local desc="$1" path="$2"
  V_LAST_OUT=$(ls -ld -- "$path" 2>&1)
  if [[ -d $path ]]; then _v_result PASS "$_P" "$desc"
  else _v_result FAIL "$_P" "$desc" "$path is not a directory"; fi
}

# pass/fail — for the odd check whose logic has to live in the lab script itself
pass()    { V_LAST_OUT=""; _v_result PASS 0 "$1" "${2:-}"; }
fail()    { V_LAST_OUT=""; _v_result FAIL 0 "$1" "${2:-}"; }

# --------------------------------------------------------- non-verdict verbs --
manual()  { V_LAST_OUT=""; _v_result MANUAL 0 "$1" "${2:-}"; }
warn()    { V_LAST_OUT=""; _v_result WARN   0 "$1" "${2:-}"; }
skipped() { V_LAST_OUT=""; _v_result SKIP   0 "$1" "${2:-}"; }
info()    { ((V_BLIND)) && return 0; echo "        ${C_DIM}$1${C_RESET}"; }

# report "desc" cmd...   informational: always shows output, never a verdict
report() {
  local desc="$1"; shift
  ((V_BLIND)) && return 0
  _v_run "$@" || true
  echo "  [${C_DIM}INFO${C_RESET}] $desc"
  _v_show_out "$V_LAST_OUT" 8
}

# --------------------------------------------------------------- conveniences --
# need_cmd "what it was for" cmd    0 if present, else records a SKIP and returns 1
need_cmd() {
  local ctx="$1" cmd="$2"
  command -v "$cmd" >/dev/null 2>&1 && return 0
  skipped "$ctx" "'$cmd' is not installed on this host"
  return 1
}

# mutating "desc"    0 when destructive checks are allowed
mutating() {
  ((V_MUTATE)) && return 0
  skipped "$1" "--no-mutate"
  return 1
}

# defer 'shell code'   run at exit whatever happens — clean up test artefacts
defer() { V_CLEANUP+=("$1"); }
_v_run_cleanup() {
  local c
  for c in ${V_CLEANUP[@]+"${V_CLEANUP[@]}"}; do bash -c "$c" >/dev/null 2>&1 || true; done
  return 0
}

# Small accessors the RHCSA labs use constantly.
user_exists()  { getent passwd "$1" >/dev/null 2>&1; }
group_exists() { getent group "$1" >/dev/null 2>&1; }
group_gid()    { getent group "$1" 2>/dev/null | cut -d: -f3; }
user_shell()   { getent passwd "$1" 2>/dev/null | cut -d: -f7; }
user_home()    { getent passwd "$1" 2>/dev/null | cut -d: -f6; }
user_gid()     { getent passwd "$1" 2>/dev/null | cut -d: -f4; }
user_uid()     { id -u "$1" 2>/dev/null; }
in_group()     { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }
mode_of()      { stat -c %a -- "$1" 2>/dev/null; }
perms_of()     { stat -c %A -- "$1" 2>/dev/null; }
# Permission bits, tested properly. A regex over the octal mode gets this wrong.
mode_bit()     { local m; m=$(stat -c %a -- "$1" 2>/dev/null) || return 2
                 [[ -n ${m:-} ]] || return 2
                 (( (8#$m & $2) != 0 )); }
group_writable() { mode_bit "$1" 020; }
other_writable() { mode_bit "$1" 002; }
owner_exec()     { mode_bit "$1" 0100; }
group_exec()     { mode_bit "$1" 010; }
other_exec()     { mode_bit "$1" 001; }
sgid_set()       { mode_bit "$1" 02000; }
suid_set()       { mode_bit "$1" 04000; }
sticky_set()     { mode_bit "$1" 01000; }
owner_of()     { stat -c %U:%G -- "$1" 2>/dev/null; }
selinux_type() { ls -Zd -- "$1" 2>/dev/null | awk '{print $1}' | awk -F: '{print $3}'; }
fstab_line()   { awk -v m="$1" '$1 !~ /^#/ && $2 == m {print; exit}' /etc/fstab 2>/dev/null; }
mount_opts()   { findmnt -no OPTIONS --target "$1" 2>/dev/null; }
mount_src()    { findmnt -no SOURCE --target "$1" 2>/dev/null; }
mount_fstype() { findmnt -no FSTYPE --target "$1" 2>/dev/null; }
dev_uuid()     { blkid -s UUID -o value "$1" 2>/dev/null; }
size_gib()     { local b; b=$(lsblk -bno SIZE "$1" 2>/dev/null | head -1)
                 [[ -n ${b:-} ]] && awk -v b="$b" 'BEGIN { printf "%.1f", b / 1073741824 }'; }
df_gib()       { df -B1 --output=size "$1" 2>/dev/null | tail -1 |
                 awk '{ printf "%.1f", $1 / 1073741824 }'; }
approx()       { # approx <value> <target> <tolerance>   → 0 when |value-target| <= tol
                 # Hard mode halves the tolerance: "about 4 GiB" stops meaning 3.4.
                 local d="$3"
                 ((${V_HARD:-0})) && d=$(awk -v x="$3" 'BEGIN { printf "%.3f", x / 2 }')
                 awk -v v="${1:-0}" -v t="$2" -v d="$d" 'BEGIN { exit !(v >= t - d && v <= t + d) }'; }

# bool_persist <name>  → the persisted (not merely runtime) value of an SELinux boolean
bool_persist() {
  command -v semanage >/dev/null 2>&1 || return 1
  semanage boolean -l 2>/dev/null | awk -v b="$1" '$1 == b { gsub(/[(),]/, "", $0); print $3 }'
}

# --------------------------------------------- where is this lab running? ----
# Where the lab environment made a deliberate choice it records it, so the
# checkers read a fact instead of inferring one. Anything already set in the
# environment wins, so a one-off override on the command line still works.
if [[ -r /etc/rhce-lab.env ]]; then
  while IFS='=' read -r _k _v; do
    [[ $_k =~ ^LAB_[A-Z_]+$ ]] || continue
    [[ -n ${!_k:-} ]] && continue
    eval "$_k=\$_v"
  done < /etc/rhce-lab.env
  unset _k _v
fi
# The same labs run on KVM/libvirt (virtio disks: vdb, vdc; a routed lab network
# with a real gateway) and on Vagrant/VirtualBox (SATA disks: sdb, sdc; a
# host-only network with no router). Nothing below assumes either.

lab_platform() {   # kvm | virtualbox | unknown
  [[ -n ${LAB_PLATFORM:-} ]] && { echo "$LAB_PLATFORM"; return 0; }
  local v
  v=$(systemd-detect-virt 2>/dev/null || true)
  case "$v" in
    kvm|qemu) echo kvm ;;
    oracle)   echo virtualbox ;;
    *)        [[ -d /vagrant || -d /opt/rhce-labs ]] && echo virtualbox || echo unknown ;;
  esac
}

# The whole disk that carries /. Everything else is a blank lab disk.
root_disk() {
  local d
  for d in $(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2 == "disk" { print $1 }'); do
    if lsblk -no MOUNTPOINTS "/dev/$d" 2>/dev/null | grep -qx '/'; then echo "$d"; return 0; fi
    if lsblk -no MOUNTPOINT  "/dev/$d" 2>/dev/null | grep -qx '/'; then echo "$d"; return 0; fi
  done
  return 1
}

# lab_disk 1|2 — the Nth blank lab disk, whatever the hypervisor calls it.
# Override with LAB_DISK1=/dev/sdb LAB_DISK2=/dev/sdc if detection ever misfires.
lab_disk() {
  local n=${1:-1} override rd
  override=$(eval "printf '%s' \"\${LAB_DISK$n:-}\"")
  [[ -n ${override:-} ]] && { printf '%s' "$override"; return 0; }
  rd=$(root_disk || true)
  lsblk -dno NAME,TYPE 2>/dev/null |
    awk -v skip="${rd:-__none__}" '$2 == "disk" && $1 != skip { print "/dev/" $1 }' |
    sed -n "${n}p"
}

# The lab network prefix, e.g. 192.168.56. Override with LAB_NET.
lab_net() {
  [[ -n ${LAB_NET:-} ]] && { printf '%s' "$LAB_NET"; return 0; }
  local ip
  # the first RFC1918 address that is not the NAT interface a hypervisor hands out
  ip=$(ip -4 -o addr show scope global 2>/dev/null |
       awk '{ print $4 }' | cut -d/ -f1 |
       grep -vE '^(10\.0\.2\.|127\.)' | head -1)
  [[ -n ${ip:-} ]] && { printf '%s' "${ip%.*}"; return 0; }
  printf '%s' "192.168.56"
}

# The interface Vagrant/libvirt uses for its own management access. The
# networking lab must not reconfigure it, or you cut off your own session.
mgmt_iface() {
  ip -4 -o addr show 2>/dev/null | awk '$4 ~ /^10\.0\.2\./ { print $2; exit }'
}

# The interface the environment set aside for the networking lab: present, and
# deliberately left with no address. Recorded by the provisioner where possible,
# otherwise the first interface that has no IPv4 address at all.
spare_iface() {
  [[ -n ${LAB_SPARE_IFACE:-} ]] && { printf '%s' "$LAB_SPARE_IFACE"; return 0; }
  local i
  for i in $(ls /sys/class/net 2>/dev/null | grep -Ev '^(lo|virbr|docker)'); do
    [[ -z $(ip -4 -o addr show dev "$i" 2>/dev/null) ]] && { printf '%s' "$i"; return 0; }
  done
  return 1
}

# The address the environment gave this node before any lab touched it. The
# networking lab must not steal it.
primary_lab_ip() { printf '%s' "${LAB_PRIMARY_IP:-}"; }
# unit_prop <unit> <Property>
unit_prop() { systemctl show -p "$2" --value "$1" 2>/dev/null; }

# check_sh / check_not_sh run their snippet in a subshell via `bash -c`, so the
# helpers above have to be exported for those snippets to see them.
export -f user_exists group_exists group_gid user_shell user_home user_gid           user_uid in_group mode_of perms_of owner_of selinux_type fstab_line           mount_opts mount_src mount_fstype dev_uuid size_gib df_gib approx           bool_persist unit_prop mode_bit group_writable other_writable owner_exec group_exec other_exec sgid_set suid_set sticky_set lab_platform root_disk lab_disk lab_net mgmt_iface spare_iface primary_lab_ip 2>/dev/null || true

# ------------------------------------------------------------------- summary --
summary() {
  _v_close_section

  echo "${C_BOLD}--------------------------------------------------------${C_RESET}"
  local failcol="$C_DIM"
  ((V_FAIL)) && failcol="$C_RED"
  echo "  ${C_GREEN}${V_PASS} passed${C_RESET}   ${failcol}${V_FAIL} failed${C_RESET}   ${C_YELLOW}${V_WARN} warn${C_RESET}   ${C_DIM}${V_SKIP} skipped${C_RESET}   ${C_CYAN}${V_MANUAL} to check by hand${C_RESET}"

  if ((V_SCORE_MODE)); then
    local secs=${#V_SECTIONS_TOTAL[@]} bad=${#V_FAILED_SECTIONS[@]} good score=0 pct=0
    good=$((secs - bad))
    if ((secs)); then score=$((good * 300 / secs)); pct=$((good * 100 / secs)); fi
    echo
    echo "  ${C_BOLD}Tasks fully correct: ${good}/${secs}${C_RESET}"
    echo "  ${C_BOLD}Scaled score: ${score}/300 (${pct}%) — pass mark is 210/300 (70%)${C_RESET}"
    if ((score >= 255)); then
      echo "  ${C_GREEN}-> 85%+ : exam-ready on this mock.${C_RESET}"
    elif ((score >= 210)); then
      echo "  ${C_YELLOW}-> Pass, but below the 85% go/no-go bar.${C_RESET}"
    else
      echo "  ${C_RED}-> Below the pass mark. See the failed tasks above.${C_RESET}"
    fi
  fi

  if ((${#V_FAILED_LINES[@]})) && ((V_BLIND == 0)); then
    echo
    echo "  ${C_RED}Not yet met:${C_RESET}"
    local d
    for d in "${V_FAILED_LINES[@]}"; do echo "    - $d"; done
  fi

  # Reboot evidence — the exam grades after a restart, so the harness tracks it.
  if ((V_HARD && V_FAIL == 0 && V_PASS > 0)) &&
     [[ -z $V_LAST_PASS_BOOT || $V_LAST_PASS_BOOT == "$V_BOOT_ID" ]]; then
    echo
    echo "  ${C_RED}HARD MODE: every check passed, but not across a reboot.${C_RESET}"
    echo "  ${C_DIM}That is not a pass here. Reboot and run this again — if it still${C_RESET}"
    echo "  ${C_DIM}passes, it counts. Persistence is the thing being tested.${C_RESET}"
    printf '%s' "$V_BOOT_ID" > "$V_STATE_DIR/lab-$V_LAB.boot" 2>/dev/null || true
    echo
    return 1
  fi

  if ((V_FAIL == 0 && V_PASS > 0)); then
    if [[ -n $V_LAST_PASS_BOOT && $V_LAST_PASS_BOOT != "$V_BOOT_ID" ]]; then
      echo
      echo "  ${C_GREEN}OK: passed on a different boot than the last clean run — reboot-proven.${C_RESET}"
    else
      echo
      echo "  ${C_YELLOW}Passed, but on the same boot as the last clean run.${C_RESET}"
      echo "  ${C_DIM}Reboot and run this again. ${V_PERSIST_PASS} of these checks are the kind that${C_RESET}"
      echo "  ${C_DIM}silently disappear on restart, and both exams grade after a reboot.${C_RESET}"
    fi
    printf '%s' "$V_BOOT_ID" > "$V_STATE_DIR/lab-$V_LAB.boot" 2>/dev/null || true
  fi

  if ((V_MANUAL)); then
    echo
    echo "  ${C_CYAN}${V_MANUAL} item(s) above need your own judgement — a script cannot grade them.${C_RESET}"
  fi

  # Run history, so the log tables in the notes can be filled in from fact.
  local verdict=passed
  ((V_FAIL)) && verdict=FAILED
  printf '%s\t%s\t%s\t%d\t%d\t%d\t%s\n' \
    "$(date '+%Y-%m-%d %H:%M')" "$V_LAB" "$(_v_host)" \
    "$V_PASS" "$V_FAIL" "$V_MANUAL" "$verdict" \
    >> "$V_STATE_DIR/history.tsv" 2>/dev/null || true

  echo
  ((V_FAIL == 0)) || return 1
  return 0
}
