#!/usr/bin/env bash
# ansible-lib.sh — additions to verify-lib.sh for the Month 2 (EX294) labs.
# Source it AFTER verify-lib.sh. Everything here runs on rhel-control.

# ------------------------------------------------------------ project location --
# Default ~/ansible; override with --proj=/path or ANSIBLE_PROJ=/path.
# The Month 1 check scripts, for a_remote_verify. The Month 2 lab scripts set
# _D to their own directory before sourcing this.
A_LABS_DIR="${A_LABS_DIR:-${_D:-.}}"

A_PROJ="${ANSIBLE_PROJ:-$HOME/ansible}"
for _a in "$@"; do
  case "$_a" in --proj=*) A_PROJ="${_a#--proj=}" ;; esac
done
unset _a

a_init() {   # a_init — cd into the project and report where we are
  if [[ ! -d $A_PROJ ]]; then
    echo "${C_RED}   No Ansible project directory at $A_PROJ.${C_RESET}"
    echo "${C_RED}   Pass --proj=/path/to/project.${C_RESET}"
    exit 2
  fi
  cd "$A_PROJ" || exit 2
  info "project: $A_PROJ"
  command -v ansible >/dev/null 2>&1 || {
    echo "${C_RED}   ansible-core is not installed on this host.${C_RESET}"; exit 2; }
}

# ------------------------------------------------------------------- playbooks --
A_LAST_RUN=""

# a_run <playbook> [extra args...]   run a playbook, keep the output in A_LAST_RUN
a_run() {
  local pb="$1"; shift
  A_LAST_RUN=$(ansible-playbook "$pb" "$@" 2>&1)
  local rc=$?
  V_LAST_OUT="$A_LAST_RUN"
  return $rc
}

# The recap line is the truth. Parse it per host.
a_recap() { grep -E '^[^ ]+ +: +ok=' <<<"${1:-$A_LAST_RUN}"; }

a_recap_field() {   # a_recap_field <field> [output]  → total across hosts
  a_recap "${2:-$A_LAST_RUN}" |
    sed -n "s/.*$1=\([0-9]*\).*/\1/p" |
    awk '{ s += $1 } END { print s + 0 }'
}

# a_playbook_ok <playbook>   syntax, then a real run that must not fail
a_playbook_ok() {
  local pb="$1"
  a_run "$pb" || { echo "$A_LAST_RUN" | tail -15; return 1; }
  local failed unreach
  failed=$(a_recap_field failed); unreach=$(a_recap_field unreachable)
  a_recap
  [[ ${failed:-0} -eq 0 && ${unreach:-0} -eq 0 ]]
}

# a_idempotent <playbook>   a second run must report changed=0 on every host
a_idempotent() {
  local pb="$1" changed
  a_run "$pb" || { echo "the run itself failed:"; echo "$A_LAST_RUN" | tail -15; return 1; }
  changed=$(a_recap_field changed)
  a_recap
  if [[ ${changed:-0} -ne 0 ]]; then
    echo "changed=$changed on a repeat run — these tasks are not idempotent:"
    grep -B2 'changed:' <<<"$A_LAST_RUN" | grep -E '^TASK' | head -8
    return 1
  fi
  return 0
}

a_no_handlers_fired() { ! grep -q 'RUNNING HANDLER' <<<"$A_LAST_RUN"; }
a_handlers_fired()    { grep -q 'RUNNING HANDLER' <<<"$A_LAST_RUN"; }

# ------------------------------------------------------------------- inventory --
a_groups()       { ansible-inventory --graph 2>/dev/null; }
a_group_has()    { ansible "$1" --list-hosts 2>/dev/null | grep -q "^  *$2\$"; }
a_hosts_in()     { ansible "$1" --list-hosts 2>/dev/null | sed '1d;s/ //g'; }
a_ping_ok()      { ansible "$1" -m ping 2>&1 | grep -c 'SUCCESS'; }

a_all_reachable() {   # every host in a pattern answers a ping
  local pat="${1:-all}" out n hosts
  out=$(ansible "$pat" -m ping 2>&1)
  n=$(grep -c 'SUCCESS' <<<"$out")
  hosts=$(a_hosts_in "$pat" | grep -c .)
  echo "$n of $hosts host(s) in '$pat' answered"
  grep -E 'UNREACHABLE|FAILED' <<<"$out" | head -3
  [[ ${n:-0} -gt 0 && ${n:-0} -eq ${hosts:-0} ]]
}

a_become_works() {
  local out
  out=$(ansible "${1:-all}" -m command -a 'id -u' --become 2>&1)
  echo "$out" | grep -E 'rc=|^[0-9]+$|CHANGED' | head -4
  ! grep -q 'password is required' <<<"$out" &&
    [[ $(grep -c '^0$' <<<"$out") -gt 0 || $(grep -c 'rc=0' <<<"$out") -gt 0 ]]
}

# ------------------------------------------------------------- content checks --
# a_uses_no_shell <file...>   command/shell/raw modules are a smell in these labs
a_uses_no_shell() {
  local hits
  hits=$(grep -nE '^[[:space:]]*-?[[:space:]]*(ansible\.builtin\.)?(shell|command|raw):' "$@" 2>/dev/null)
  [[ -z ${hits// /} ]] && return 0
  echo "command/shell/raw used where a real module exists:"
  echo "$hits" | head -6
  return 1
}

# a_yaml_ok <file>   parseable by the same YAML parser Ansible uses
a_yaml_ok() {
  python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$1" 2>&1
}

a_has_module() {   # a_has_module <module-substring> <file...>
  grep -qE "(^|[[:space:].])${1}:" "${@:2}" 2>/dev/null
}

a_cfg_is_mine() {   # ansible must be reading THIS project's ansible.cfg
  local cfg
  cfg=$(ansible --version 2>/dev/null | sed -n 's/.*config file = //p' | head -1)
  echo "config file in use: ${cfg:-<none>}"
  [[ -n ${cfg:-} && $cfg == "$A_PROJ"/* ]]
}

a_dir_not_world_writable() {   # the silent reason an ansible.cfg gets ignored
  local m
  m=$(mode_of "$A_PROJ")
  echo "$A_PROJ is mode $m"
  [[ ${m: -1} != 2 && ${m: -1} != 3 && ${m: -1} != 6 && ${m: -1} != 7 ]]
}

# --------------------------------------------------- reuse the Month 1 checks --
# a_remote_verify <host-pattern> <lab-script> [script args]
#
# The Month 1 lab scripts source the shared library, which does not exist on a
# managed node. So bundle library + script into one self-contained file and
# hand that to the `script` module. Week 6 is "re-do RHCSA through Ansible", so
# the same checks should grade it — from the control node, without logging in.
a_remote_verify() {
  local pat="$1" lab="$2"; shift 2
  local labs_dir lib_dir tmp out rc
  labs_dir=$A_LABS_DIR
  lib_dir=$labs_dir/../lib
  [[ -f $labs_dir/$lab ]] || {
    echo "cannot find $labs_dir/$lab"
    echo "run this from the verify/ tree (not from dist/), or set A_LABS_DIR"
    return 1; }
  tmp=$(mktemp /tmp/verify-bundle-XXXXXX.sh) || return 1
  {
    echo '#!/usr/bin/env bash'
    cat "$lib_dir/verify-lib.sh"
    grep -v '^\. "\$(dirname' "$labs_dir/$lab"
  } > "$tmp"
  chmod +x "$tmp"
  out=$(ansible "$pat" -m script -a "$tmp $* --no-color --no-mutate" --become 2>&1)
  rc=$?
  rm -f "$tmp"
  # Show the remote check output, which the script module returns as stdout.
  sed -e 's/\\n/\n/g' <<<"$out" | grep -E '^\s*(\[|==|--|  [0-9]+ passed)' | head -40
  ((rc == 0)) && ! grep -qE 'FAILED|fatal:' <<<"$out"
}

export -f a_recap a_recap_field a_yaml_ok a_uses_no_shell a_has_module a_group_has a_hosts_in 2>/dev/null || true
