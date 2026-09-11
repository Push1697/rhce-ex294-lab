#!/usr/bin/env bash
# Advanced break-fix verification                   (10-Advanced-Breakfix-Labs)
# Run on rhel01 (or rhel02 for the NFS drill), as root, after repairing.
#
#   sudo ./verify advanced              check every drill's domain
#   sudo ./verify advanced --only=f4    check just one
#   sudo ./verify advanced --after-reboot
#
# One section per drill. Every section passes on a healthy box, so it also works
# as a general "is this machine sane" sweep before a mock.
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

ONLY=""
for a in "$@"; do case "$a" in --only=*) ONLY=${a#--only=} ;; esac; done

want() { [[ -z ${ONLY:-} || $ONLY == "$1" ]]; }

# ------------------------------------------------------------------- f1 -------
nsswitch_sources_intact() {
  local bad=0 key line
  for key in passwd group hosts shadow; do
    line=$(grep -E "^[[:space:]]*$key:" /etc/nsswitch.conf 2>/dev/null | head -1)
    [[ -n ${line:-} ]] || { echo "no '$key:' line at all in nsswitch.conf"; bad=1; continue; }
    echo "$line"
    grep -qw files <<<"$line" || { echo "  ^ '$key' never consults local files"; bad=1; }
  done
  return $bad
}

etc_hosts_actually_used() {
  local h out
  # take a name that only /etc/hosts knows about
  h=$(awk '$1 !~ /^#/ && NF >= 2 && $1 !~ /^(127\.|::1)/ { print $2; exit }' /etc/hosts)
  [[ -n ${h:-} ]] || { echo "nothing useful in /etc/hosts to test with"; return 2; }
  out=$(getent hosts "$h" 2>&1)
  echo "getent hosts $h -> ${out:-<nothing>}"
  [[ -n ${out// /} ]]
}

authselect_consistent() {
  command -v authselect >/dev/null 2>&1 || { echo "authselect not in use here"; return 2; }
  local out
  out=$(authselect check 2>&1)
  echo "$out"
  grep -qi 'differs\|modified\|not valid' <<<"$out" && return 1
  return 0
}

# ------------------------------------------------------------------- f2 -------
no_immutable_configs() {
  local hits
  # lsattr -R prints a bare "path:" header line for every directory it walks.
  # Those lines have one field, so the old test `$1 ~ /i/` was matching the
  # *path* whenever it contained the letter i — /etc/terminfo, /etc/dnf/plugins
  # and a dozen others were reported as immutable on a completely clean box.
  # With two fields, $1 really is the attribute string, where i means immutable.
  hits=$(lsattr -R -a /etc 2>/dev/null |
         awk 'NF == 2 && $1 ~ /i/ && $2 !~ /[/][.][.]?$/ { print }')
  [[ -z ${hits// /} ]] && return 0
  echo "files under /etc carrying the immutable attribute:"
  echo "$hits" | head -8
  return 1
}

configs_parse() {
  local bad=0
  if rpm -q httpd >/dev/null 2>&1; then
    httpd -t >/dev/null 2>&1 || { echo "httpd's configuration does not parse:"; httpd -t 2>&1 | head -3; bad=1; }
  fi
  if command -v chronyd >/dev/null 2>&1; then
    chronyd -Q 'server 127.127.1.0' >/dev/null 2>&1 ||
      chronyd -p >/dev/null 2>&1 ||
      echo "  (could not syntax-check chrony.conf on this build — check by hand)"
  fi
  sshd -t >/dev/null 2>&1 || { echo "sshd's configuration does not parse"; bad=1; }
  return $bad
}

# ------------------------------------------------------------------- f3 -------
docroot_of() {
  grep -hE '^[[:space:]]*DocumentRoot' /etc/httpd/conf/httpd.conf \
    /etc/httpd/conf.d/*.conf 2>/dev/null | tail -1 | awk '{ gsub(/"/, "", $2); print $2 }'
}

docroot_labelled_by_policy() {
  local d
  d=$(docroot_of)
  [[ -n ${d:-} && -d $d ]] || { echo "cannot determine the document root"; return 2; }
  echo "document root: $d (label: $(selinux_type "$d"))"
  local out
  out=$(restorecon -Rvn "$d" 2>&1)
  [[ -z ${out//[[:space:]]/} ]] && return 0
  echo "a dry-run relabel wants to change things — the label came from chcon, not policy:"
  echo "$out" | head -5
  return 1
}

every_listen_port_is_labelled() {
  local p bad=0 ports
  ports=$(grep -rhE '^[[:space:]]*Listen[[:space:]]+' /etc/httpd/conf/httpd.conf \
          /etc/httpd/conf.d/*.conf 2>/dev/null | awk '{ print $2 }' | grep -oE '[0-9]+$' | sort -u)
  [[ -n ${ports:-} ]] || { echo "no Listen directive found"; return 2; }
  for p in $ports; do
    if semanage port -l 2>/dev/null | grep '^http_port_t' | grep -qE "(^|[^0-9])$p([^0-9]|$)"; then
      echo "Listen $p — labelled http_port_t"
    else
      echo "Listen $p — NOT labelled http_port_t, so httpd cannot bind it"; bad=1
    fi
  done
  return $bad
}

httpd_reachable_locally() {
  local p body
  p=$(grep -rhE '^[[:space:]]*Listen[[:space:]]+' /etc/httpd/conf/httpd.conf \
      /etc/httpd/conf.d/*.conf 2>/dev/null | awk '{ print $2 }' | grep -oE '[0-9]+$' | head -1)
  p=${p:-80}
  body=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://localhost:$p/" 2>&1)
  echo "curl http://localhost:$p/ -> $body"
  [[ $body == 200 ]]
}

firewall_matches_listeners() {
  local bad=0 p ports svcs open
  svcs=$(firewall-cmd --list-services 2>/dev/null)
  open=$(firewall-cmd --list-ports 2>/dev/null)
  echo "firewall services: ${svcs:-<none>}"
  echo "firewall ports:    ${open:-<none>}"
  ports=$(grep -rhE '^[[:space:]]*Listen[[:space:]]+' /etc/httpd/conf/httpd.conf \
          /etc/httpd/conf.d/*.conf 2>/dev/null | awk '{ print $2 }' | grep -oE '[0-9]+$' | sort -u)
  for p in $ports; do
    case "$p" in
      80)  grep -qw http <<<"$svcs"  || grep -q '80/tcp' <<<"$open"  || { echo "port 80 is not open"; bad=1; } ;;
      443) grep -qw https <<<"$svcs" || grep -q '443/tcp' <<<"$open" || { echo "port 443 is not open"; bad=1; } ;;
      *)   grep -q "$p/tcp" <<<"$open" || { echo "port $p is served but not open"; bad=1; } ;;
    esac
  done
  return $bad
}

# ------------------------------------------------------------------- f4 -------
no_phantom_dependencies() {
  local bad=0 d u dep
  for d in /etc/systemd/system/*.service.d /usr/lib/systemd/system/*.service.d; do
    [[ -d $d ]] || continue
    for f in "$d"/*.conf; do
      [[ -f $f ]] || continue
      while read -r dep; do
        [[ -n ${dep// /} ]] || continue
        if [[ ! -d $dep ]]; then
          echo "$f requires a mount for '$dep', which does not exist"; bad=1
        fi
      done < <(grep -hE '^[[:space:]]*RequiresMountsFor=' "$f" 2>/dev/null | cut -d= -f2- | tr ' ' '\n')
      while read -r dep; do
        [[ -n ${dep// /} ]] || continue
        systemctl list-unit-files "$dep" >/dev/null 2>&1 ||
          systemctl cat "$dep" >/dev/null 2>&1 ||
          { echo "$f requires unit '$dep', which systemd cannot find"; bad=1; }
      done < <(grep -hE '^[[:space:]]*(Requires|BindsTo)=' "$f" 2>/dev/null | cut -d= -f2- | tr ' ' '\n')
    done
  done
  return $bad
}

no_failed_units() {
  local n
  n=$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | grep -c .)
  [[ ${n:-0} -eq 0 ]] && return 0
  systemctl --failed --no-legend --plain
  return 1
}

enabled_units_are_startable() {
  local bad=0 u
  for u in httpd sshd firewalld chronyd siteguard; do
    systemctl list-unit-files "$u.service" >/dev/null 2>&1 || continue
    systemctl is-enabled --quiet "$u" 2>/dev/null || continue
    systemctl is-active --quiet "$u" || { echo "$u is enabled but not running"; bad=1; }
  done
  return $bad
}

unit_dropins_verify() {
  local out
  out=$(systemd-analyze verify httpd.service sshd.service 2>&1 |
        grep -viE 'warning: unit file|may be misspelled|command.*not found in|^$')
  [[ -z ${out//[[:space:]]/} ]] && return 0
  echo "$out" | head -6
  return 1
}

# ------------------------------------------------------------------- f5 -------
no_deleted_but_open_files() {
  command -v lsof >/dev/null 2>&1 || { echo "lsof is not installed"; return 2; }
  local hits
  hits=$(lsof -nP +L1 2>/dev/null | awk 'NR == 1 || $7 + 0 > 52428800')
  local n
  n=$(awk 'NR > 1' <<<"$hits" | grep -c .)
  if [[ ${n:-0} -eq 0 ]]; then
    echo "no deleted-but-open file is holding more than 50 MB"
    return 0
  fi
  echo "$hits" | head -6
  return 1
}

space_and_inodes_sane() {
  local bad=0 line
  while read -r line; do
    echo "$line"; bad=1
  done < <(df -P --output=pcent,target 2>/dev/null | awk 'NR > 1 && $1 + 0 > 90 { print "over 90% full: " $2 " (" $1 ")" }')
  while read -r line; do
    echo "$line"; bad=1
  done < <(df -Pi --output=ipcent,target 2>/dev/null | awk 'NR > 1 && $1 + 0 > 90 { print "over 90% of inodes used: " $2 " (" $1 ")" }')
  ((bad)) || echo "every filesystem is under 90% on both blocks and inodes"
  return $bad
}

du_agrees_with_df() {
  local dfu duu diff
  dfu=$(df -BM --output=used /var 2>/dev/null | tail -1 | tr -dc '0-9')
  duu=$(du -sBM --one-file-system /var 2>/dev/null | tr -dc '0-9')
  [[ -n ${dfu:-} && -n ${duu:-} ]] || return 2
  diff=$((dfu - duu))
  echo "df says ${dfu}M used under /var, du walks ${duu}M — difference ${diff}M"
  # /var may not be its own filesystem, in which case this is meaningless
  findmnt -no TARGET /var 2>/dev/null | grep -qx /var || {
    echo "(/var is not a separate filesystem, so this comparison is only a hint)"; return 0; }
  ((diff < 512))
}

# ------------------------------------------------------------------- f6 -------
clock_is_plausible() {
  local now newest
  now=$(date +%s)
  # Nothing on the box can be newer than "now" on a machine with a sane clock.
  newest=$(rpm -qa --qf '%{INSTALLTIME}\n' 2>/dev/null | sort -n | tail -1)
  [[ -n ${newest:-} ]] || return 2
  echo "clock:            $(date '+%Y-%m-%d %H:%M:%S')"
  echo "newest RPM install: $(date -d "@$newest" '+%Y-%m-%d %H:%M:%S')"
  if ((now < newest)); then
    echo "the clock is BEHIND the newest package install — it has been moved backwards"
    return 1
  fi
  # more than a year past the newest install is a strong smell in a fresh lab
  if (( (now - newest) > 31536000 )); then
    echo "the clock is more than a year past the newest package install"
    return 1
  fi
  return 0
}

time_sync_configured() {
  local out
  out=$(timedatectl show 2>/dev/null || timedatectl 2>/dev/null)
  echo "$out" | grep -iE 'ntp|synchronized|timezone' | head -4
  grep -qiE 'NTP=yes|NTPSynchronized=yes|NTP service: active' <<<"$out"
}

chronyd_running() {
  systemctl list-unit-files chronyd.service >/dev/null 2>&1 || { echo "chrony not installed"; return 2; }
  systemctl is-active --quiet chronyd
}

# The clock drill no longer moves the wall clock — the hypervisor put that back
# within seconds. It moves the things RHEL itself owns, so these are what has
# to be graded.
timezone_is_sane() {
  local tz off
  tz=$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null)
  off=$(date +%z)
  echo "timezone: ${tz:-<unknown>} (UTC offset $off)"
  [[ -n ${tz:-} ]] || return 2
  # Nothing here is wrong with choosing an unusual zone deliberately — but the
  # lab is built in UTC, and the drill moves it to one of the extremes.
  case "$tz" in
    Pacific/Kiritimati|Pacific/Apia|Pacific/Tongatapu|Etc/GMT-14|America/Adak)
      echo "this is the timezone the drill sets, not the one the lab was built in"
      return 1 ;;
  esac
  return 0
}

hwclock_is_utc() {
  [[ -f /etc/adjtime ]] || { echo "no /etc/adjtime on this system"; return 2; }
  local mode
  mode=$(tail -1 /etc/adjtime | tr -d '[:space:]')
  echo "/etc/adjtime says the hardware clock holds: ${mode:-<nothing>}"
  if [[ $mode == LOCAL ]]; then
    echo "so the clock will shift by the timezone offset at the next boot"
    return 1
  fi
  return 0
}

no_future_dated_files() {
  local n
  n=$(find /etc /root -xdev -newermt "+1 hour" 2>/dev/null | grep -c .)
  echo "files under /etc or /root dated in the future: ${n:-0}"
  [[ ${n:-0} -eq 0 ]]
}

# ------------------------------------------------------------------- f7 -------
sudoers_parses() { visudo -c; }

sudoers_d_permissions() {
  local bad=0 f m
  for f in /etc/sudoers.d/*; do
    [[ -f $f ]] || continue
    m=$(mode_of "$f")
    if other_writable "$f" || group_writable "$f"; then
      echo "$f is mode $m — sudo refuses to read a writable file and silently drops its rules"
      bad=1
    else
      echo "$f is mode $m"
    fi
  done
  return $bad
}

secure_path_complete() {
  local sp bad=0 d
  sp=$(sudo -n -l 2>/dev/null | grep -oE 'secure_path=[^ ]*' | head -1 | cut -d= -f2-)
  [[ -n ${sp:-} ]] || sp=$(grep -hE '^[[:space:]]*Defaults[[:space:]]+secure_path' /etc/sudoers 2>/dev/null |
                           sed -E 's/.*=[[:space:]]*//')
  [[ -n ${sp:-} ]] || { echo "no secure_path is set at all"; return 2; }
  echo "secure_path = $sp"
  for d in /usr/sbin /sbin /usr/bin; do
    grep -q "$d" <<<"$sp" || { echo "  missing: $d — 'sudo systemctl' will report command not found"; bad=1; }
  done
  return $bad
}

sudo_finds_admin_commands() {
  local bad=0 c
  for c in systemctl visudo semanage; do
    command -v "$c" >/dev/null 2>&1 || continue
    sudo -n true 2>/dev/null || { echo "cannot test: sudo -n does not work for the current user"; return 2; }
    sudo -n env PATH="$(sudo -n printenv PATH 2>/dev/null)" which "$c" >/dev/null 2>&1 ||
      { echo "sudo's PATH cannot find $c"; bad=1; }
  done
  return $bad
}

wheel_rule_present() {
  grep -Eq '^[[:space:]]*%wheel' /etc/sudoers /etc/sudoers.d/* 2>/dev/null
}

# ------------------------------------------------------------------- f8 -------
kernel_cmdline_clean() {
  local cl bad=0 arg
  cl=$(cat /proc/cmdline)
  echo "$cl"
  for arg in selinux=0 enforcing=0 audit=0 systemd.unit=rescue.target systemd.unit=emergency.target; do
    grep -qw -- "$arg" <<<"$cl" && { echo "  ^ '$arg' is on the running command line"; bad=1; }
  done
  return $bad
}

kernel_args_persistently_clean() {
  command -v grubby >/dev/null 2>&1 || return 2
  local args bad=0 arg
  args=$(grubby --info=ALL 2>/dev/null | grep '^args=')
  echo "$args" | head -4
  for arg in selinux=0 enforcing=0 audit=0; do
    grep -q -- "$arg" <<<"$args" && { echo "  ^ '$arg' is still persisted in the boot loader"; bad=1; }
  done
  return $bad
}

selinux_really_enforcing() {
  local ge
  ge=$(getenforce 2>/dev/null)
  echo "getenforce: ${ge:-<unavailable>}"
  echo "config:     $(grep '^SELINUX=' /etc/selinux/config 2>/dev/null)"
  [[ $ge == Enforcing ]]
}

no_relabel_pending() {
  [[ ! -f /.autorelabel ]] || { echo "/.autorelabel is still present — the relabel has not happened yet"; return 1; }
  local out
  out=$(restorecon -Rvn /etc 2>&1 | head -5)
  [[ -z ${out//[[:space:]]/} ]] && return 0
  echo "labels under /etc are still wrong, which is what happens when SELinux is re-enabled without a relabel:"
  echo "$out"
  return 1
}

# ------------------------------------------------------------------- f9 -------
_in_list() {   # _in_list <needle> <haystack words...>
  local n=$1; shift
  local x; for x in "$@"; do [[ $x == "$n" ]] && return 0; done
  return 1
}

resolv_conf_matches_profile() {
  command -v nmcli >/dev/null 2>&1 || return 2
  local live nm bad=0 s c

  # What NetworkManager would put in the file: every *active* profile, and its
  # applied servers, not just a statically configured ipv4.dns.
  #
  # The old version read ipv4.dns off whichever profile happened to sort first
  # and failed if it was empty. On this lab that is the NAT connection, which
  # takes its DNS from a DHCP lease — perfectly reproducible, and reported as
  # "not reproducible" on a completely clean box. It also never looked at IPv6.
  nm=$(nmcli -t -f NAME con show --active 2>/dev/null |
       while read -r c; do
         [[ -n ${c// /} ]] || continue
         nmcli -g IP4.DNS,IP6.DNS   con show "$c" 2>/dev/null | tr ',|' '  '
         nmcli -g ipv4.dns,ipv6.dns con show "$c" 2>/dev/null | tr ',|' '  '
       # nmcli -g escapes the colons in an IPv6 address as \:, so strip
       # the backslashes or every v6 nameserver compares as different.
       done | tr -d '\134' | tr -s ' \n' ' ')
  live=$(awk '/^nameserver/ { print $2 }' /etc/resolv.conf 2>/dev/null | tr '\n' ' ')

  echo "NetworkManager would write: ${nm:-<none>}"
  echo "/etc/resolv.conf has:       ${live:-<none>}"
  [[ -n ${live// /} ]] || { echo "resolv.conf names no server at all"; return 1; }

  for s in $live; do
    _in_list "$s" $nm ||
      { echo "  $s is in resolv.conf but no active profile knows it — hand-edited, and it will be overwritten"; bad=1; }
  done
  for s in $nm; do
    _in_list "$s" $live ||
      { echo "  $s is configured but missing from resolv.conf — the file will change when the connection next comes up"; bad=1; }
  done
  return $bad
}

configured_nameservers_answer() {
  local s ok=0
  for s in $(awk '/^nameserver/ { print $2 }' /etc/resolv.conf 2>/dev/null); do
    if command -v dig >/dev/null 2>&1; then
      dig +time=2 +tries=1 "@$s" . NS >/dev/null 2>&1 && ok=1
    fi
    ping -c1 -W2 "$s" >/dev/null 2>&1 && ok=1
    echo "nameserver $s: $( ((ok)) && echo reachable || echo silent)"
  done
  ((ok))
}

resolution_works() {
  local bad=0 h
  for h in rhel01 rhel02; do
    getent hosts "$h" >/dev/null 2>&1 || { echo "cannot resolve $h"; bad=1; }
  done
  ((bad)) || echo "rhel01 and rhel02 both resolve"
  return $bad
}

# ------------------------------------------------------------------ f10 -------
nfs_writes_work() {
  local m f
  m=$(findmnt -rno TARGET -t nfs,nfs4 2>/dev/null | head -1)
  [[ -n ${m:-} ]] || { echo "no NFS filesystem is mounted here"; return 2; }
  echo "testing writes on $m"
  f=$m/.verify-write-$$
  if touch "$f" 2>/dev/null; then
    rm -f "$f"
    echo "write succeeded"
    return 0
  fi
  echo "write failed: $(touch "$f" 2>&1 | head -1)"
  findmnt -no TARGET,OPTIONS "$m"
  return 1
}

nfs_mount_is_rw() {
  local m o
  m=$(findmnt -rno TARGET -t nfs,nfs4 2>/dev/null | head -1)
  [[ -n ${m:-} ]] || return 2
  o=$(findmnt -no OPTIONS "$m")
  echo "$m options: $o"
  grep -qE '(^|,)rw(,|$)' <<<"$o"
}

exports_are_rw() {
  command -v exportfs >/dev/null 2>&1 || return 2
  local out
  out=$(exportfs -v 2>/dev/null)
  [[ -n ${out// /} ]] || { echo "nothing is exported from this host"; return 2; }
  echo "$out"
  grep -q 'ro,' <<<"$out" && { echo "an export is read-only"; return 1; }
  return 0
}

# ------------------------------------------------------------------------------
lab_init "advanced" "Advanced break-fix verification" --root "$@"
[[ -n ${ONLY:-} ]] && info "checking only: $ONLY"

if want f1; then
  section "f1. Name resolution consults what it should"
  check "every nsswitch database still lists a local source" nsswitch_sources_intact
  etc_hosts_actually_used; rc=$?
  case $rc in
    0) pass "a name that only /etc/hosts knows is resolvable" ;;
    2) skipped "/etc/hosts is genuinely consulted" "no usable entry in /etc/hosts to test with" ;;
    *) fail "a name that only /etc/hosts knows is resolvable" "the file is correct but nothing reads it" ;;
  esac
  authselect_consistent; rc=$?
  case $rc in
    0) pass "authselect reports its configuration is consistent" ;;
    2) skipped "authselect consistency" "authselect is not in use on this host" ;;
    *) fail "authselect reports its configuration is consistent" \
         "nsswitch.conf was changed outside authselect" ;;
  esac
fi

if want f2; then
  section "f2. Configuration files are editable and valid"
  check "nothing under /etc carries the immutable attribute" no_immutable_configs
  check "the main service configs parse" configs_parse
  info "lsattr is the tool that finds a file root itself cannot write."
fi

if want f3; then
  section "f3. The web tier works end to end"
  check "httpd is running" systemctl is-active --quiet httpd
  docroot_labelled_by_policy; rc=$?
  case $rc in
    0) pass "the document root's label comes from policy, not chcon" ;;
    2) skipped "document root labelling" "could not determine the document root" ;;
    *) fail "the document root's label comes from policy, not chcon" \
         "a dry-run relabel would change it" ;;
  esac
  every_listen_port_is_labelled; rc=$?
  case $rc in
    0) pass "every Listen port is labelled http_port_t" ;;
    2) skipped "Listen port labelling" "no Listen directive found" ;;
    *) fail "every Listen port is labelled http_port_t" "httpd cannot bind an unlabelled port" ;;
  esac
  check "the firewall opens every port httpd listens on" firewall_matches_listeners
  check "curl against the configured port returns 200" httpd_reachable_locally
  check_eq "SELinux is still Enforcing" "Enforcing" "$(getenforce 2>/dev/null)"
  info "One symptom can have three causes. Fixing one and stopping is the trap."
fi

if want f4; then
  section "f4. Units start at boot, not just by hand"
  check "no unit depends on something that does not exist" no_phantom_dependencies
  check "no unit is in a failed state" no_failed_units
  check "every enabled unit is actually running" enabled_units_are_startable
  unit_dropins_verify; rc=$?
  case $rc in
    0) pass "systemd-analyze verify is quiet about the main units" ;;
    *) fail "systemd-analyze verify is quiet about the main units" "see the output above" ;;
  esac
  info "systemctl cat <unit> shows drop-ins too. That is where this kind of fault hides."
fi

if want f5; then
  section "f5. Disk space is accounted for"
  check "no filesystem is over 90% on blocks or inodes" space_and_inodes_sane
  no_deleted_but_open_files; rc=$?
  case $rc in
    0) pass "no deleted-but-open file is holding significant space" ;;
    2) skipped "deleted-but-open files" "lsof is not installed" ;;
    *) fail "no deleted-but-open file is holding significant space" \
         "the space returns when the descriptor closes" ;;
  esac
  du_agrees_with_df; rc=$?
  case $rc in
    0) pass "du and df agree about /var" ;;
    2) skipped "du and df agree" "could not measure both" ;;
    *) fail "du and df agree about /var" "space is allocated that no directory entry points at" ;;
  esac
fi

if want f6; then
  section "f6. The clock is trustworthy"
  clock_is_plausible; rc=$?
  case $rc in
    0) pass "the clock is consistent with what is installed on the box" ;;
    2) skipped "clock plausibility" "could not read package install times" ;;
    *) fail "the clock is consistent with what is installed on the box" "see above" ;;
  esac
  check -p "time synchronisation is configured and on" time_sync_configured
  timezone_is_sane; rc=$?
  case $rc in
    0) pass "the timezone is the one this lab is built in" ;;
    2) skipped "the timezone" "could not read it" ;;
    *) fail "the timezone is the one this lab is built in"          "every log timestamp and every wall-clock timer is offset by this" ;;
  esac
  hwclock_is_utc; rc=$?
  case $rc in
    0) pass "the hardware clock is read as UTC, so a reboot does not shift it" ;;
    2) skipped "how the hardware clock is read" "no /etc/adjtime" ;;
    *) fail "the hardware clock is read as UTC, so a reboot does not shift it"          "this one is invisible until you reboot — which is the point of it" ;;
  esac
  chronyd_running; rc=$?
  case $rc in
    0) pass "chronyd is running" ;;
    2) skipped "chronyd is running" "chrony is not installed" ;;
    *) fail "chronyd is running" "nothing is keeping this clock correct" ;;
  esac
  check "no files under /etc or /root are dated in the future" no_future_dated_files
fi

if want f7; then
  section "f7. sudo is whole"
  check "sudoers parses across all files" sudoers_parses
  check "no file in /etc/sudoers.d is group- or world-writable" sudoers_d_permissions
  secure_path_complete; rc=$?
  case $rc in
    0) pass "secure_path includes the sbin directories" ;;
    2) skipped "secure_path contents" "no secure_path is configured" ;;
    *) fail "secure_path includes the sbin directories" \
         "administrative commands will not be found through sudo" ;;
  esac
  check "the wheel rule is present and uncommented" wheel_rule_present
  sudo_finds_admin_commands; rc=$?
  case $rc in
    0) pass "sudo can find systemctl, visudo and semanage" ;;
    2) skipped "sudo command lookup" "cannot run sudo -n as the current user" ;;
    *) fail "sudo can find systemctl, visudo and semanage" "see above" ;;
  esac
fi

if want f8; then
  section "f8. SELinux is on, and stays on"
  check -p "the running kernel command line carries no override" kernel_cmdline_clean
  kernel_args_persistently_clean; rc=$?
  case $rc in
    0) pass "the boot loader persists no SELinux or target override" ;;
    2) skipped "persisted kernel arguments" "grubby is not available" ;;
    *) fail "the boot loader persists no SELinux or target override" \
         "it will come back on the next reboot" ;;
  esac
  check -p "getenforce reports Enforcing" selinux_really_enforcing
  check "no relabel is outstanding" no_relabel_pending
  info "/etc/selinux/config is not the authority. The kernel command line wins."
fi

if want f9; then
  section "f9. DNS is reproducible, not hand-edited"
  resolv_conf_matches_profile; rc=$?
  case $rc in
    0) pass "resolv.conf matches the connection profile that generates it" ;;
    2) skipped "resolv.conf matches its profile" "NetworkManager is not managing this host" ;;
    *) fail "resolv.conf matches the connection profile that generates it" \
         "this is the classic 'works until reboot' fault" ;;
  esac
  check "rhel01 and rhel02 both resolve" resolution_works
  check "at least one configured nameserver answers" configured_nameservers_answer
fi

if want f10; then
  section "f10. NFS is usable, not merely mounted"
  nfs_mount_is_rw; rc=$?
  case $rc in
    0) pass "the NFS mount is read-write" ;;
    2) skipped "NFS mount options" "no NFS filesystem mounted here" ;;
    *) fail "the NFS mount is read-write" "it mounted, which is not the same as working" ;;
  esac
  nfs_writes_work; rc=$?
  case $rc in
    0) pass "a write to the NFS mount succeeds" ;;
    2) skipped "NFS writes" "no NFS filesystem mounted here" ;;
    *) fail "a write to the NFS mount succeeds" "mount success is not write success" ;;
  esac
  exports_are_rw; rc=$?
  case $rc in
    0) pass "every export from this host is read-write" ;;
    2) skipped "export options" "this host exports nothing — check rhel02 too" ;;
    *) fail "every export from this host is read-write" "see the export list above" ;;
  esac
fi

if [[ -z ${ONLY:-} ]]; then
  section "The drill itself"
  manual "You reproduced the symptom before changing anything" \
    "Never repair what you cannot demonstrate."
  manual "Your first hypothesis was correct" \
    "Record it in the drill log in 10-Advanced-Breakfix-Labs — right or wrong."
  manual "You repaired it minimally: no SELinux disabled, no permissions widened" \
    "A fix that works by removing security is a zero in the exam and in the job."
  manual "You rebooted and re-verified" \
    "Several of these faults only reappear after a restart."
  info "Now run:  ./break-advanced.sh reveal"
fi

summary
