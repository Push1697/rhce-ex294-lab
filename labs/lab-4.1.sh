#!/usr/bin/env bash
# Lab 4.1 — Containers with podman, rootless        (03-EX200-Exam-Prep)
# Run on rhel01 as the ORDINARY USER — not root, not with sudo.
#   ./lab-4.1.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/verify-lib.sh"

DATA=/opt/webdata
PORT=8080

running_container() { podman ps --format '{{.Names}}' 2>/dev/null | head -1; }
CTR=""

publishes_port() {
  local p
  p=$(podman ps --format '{{.Ports}}' 2>/dev/null)
  echo "published ports: ${p:-<none>}"
  grep -q "$PORT" <<<"$p"
}

volume_mounted() {
  local m
  m=$(podman inspect "$CTR" --format '{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Mode}}){{"\n"}}{{end}}' 2>/dev/null)
  echo "${m:-<no mounts>}"
  grep -q "$DATA" <<<"$m"
}

volume_relabelled() {
  local t
  t=$(selinux_type "$DATA")
  echo "$DATA is labelled ${t:-<unknown>}"
  [[ $t == container_file_t ]]
}

serves_the_host_file() {
  local body file
  file=$(find "$DATA" -maxdepth 1 -type f -name '*.htm*' -print -quit 2>/dev/null)
  [[ -n ${file:-} ]] || file=$(find "$DATA" -maxdepth 1 -type f -print -quit 2>/dev/null)
  [[ -n ${file:-} ]] || { echo "no file in $DATA to serve"; return 1; }
  body=$(curl -s --max-time 5 "http://localhost:$PORT/$(basename "$file")" 2>&1)
  [[ -z ${body// /} ]] && body=$(curl -s --max-time 5 "http://localhost:$PORT/" 2>&1)
  echo "served: ${body:0:60}"
  echo "on disk: $(head -c 60 "$file")"
  grep -qF "$(head -c 40 "$file")" <<<"$body"
}

user_unit_enabled() {
  local u
  u=$(systemctl --user list-unit-files --no-legend 2>/dev/null |
      awk '$1 ~ /container|podman|^'"${CTR:-zzz}"'/ { print $1; exit }')
  [[ -z ${u:-} ]] && u=$(systemctl --user list-units --no-legend 2>/dev/null |
      awk '$1 ~ /container|podman/ { print $1; exit }')
  echo "user unit: ${u:-<none found>}"
  [[ -n ${u:-} ]] || return 1
  systemctl --user is-enabled --quiet "$u"
}

linger_enabled() {
  local l
  l=$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)
  [[ -z ${l:-} ]] && l=$(loginctl show-user "$USER" 2>/dev/null | sed -n 's/^Linger=//p')
  echo "Linger=${l:-<unknown>}"
  [[ $l == yes ]]
}

# Did the container come up on this boot without anyone logging in?
started_on_this_boot() {
  local boot started
  boot=$(date -d "$(uptime -s)" +%s)
  started=$(podman inspect "$CTR" --format '{{.State.StartedAt}}' 2>/dev/null)
  [[ -n ${started:-} ]] || return 1
  local st; st=$(date -d "$started" +%s 2>/dev/null) || return 1
  echo "boot $(date -d "@$boot" '+%F %T'), container started $(date -d "@$st" '+%F %T')"
  ((st >= boot))
}

# ------------------------------------------------------------------------------
lab_init "4.1" "Containers with podman, rootless" --host rhel01 --user "$@"

need_cmd "every check in this lab" podman || { summary; exit 1; }
CTR=$(running_container)

section "1. The image was found and pulled"
check "at least one image is present locally" bash -c 'podman images --noheading | grep -q .'
report "images" bash -c 'podman images --format "{{.Repository}}:{{.Tag}} {{.Size}}"'
manual "You can report which ports the image exposes" \
  "podman inspect <image> — you should have looked before running it."

section "2. The container runs rootless"
check_sh "a container is running for $USER" '[[ -n "$(podman ps --format "{{.Names}}" | head -1)" ]]'
if [[ -z ${CTR:-} ]]; then
  fail "the rest of this lab" "no running container, so nothing else can be checked"
  summary; exit 1
fi
info "container: $CTR"
check "it is not running as root" \
  bash -c '[[ $(id -u) -ne 0 ]] && ! sudo -n podman ps --format "{{.Names}}" 2>/dev/null | grep -qx "'"$CTR"'"'
check "it is published on host port $PORT" publishes_port

section "3. Persistent storage from the host"
check_dir "$DATA exists" "$DATA"
check "the host directory is mounted into the container" volume_mounted
check -p "$DATA carries the container_file_t label (the :Z was applied)" volume_relabelled
check "the page served comes from the file on the host" serves_the_host_file

section "4. It starts at boot as this user, with nobody logged in"
check -p "a systemd --user unit for the container is enabled" user_unit_enabled
check -p "lingering is enabled for $USER" linger_enabled
info "Without linger the unit only starts when you log in — and the grader never will."
check -p "the running container was started on this boot" started_on_this_boot

section "5. An environment variable was set at run time"
check_match "the container carries an env var you set" '^[A-Z_]+=' \
  bash -c "podman inspect $CTR --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -vE '^(PATH|TERM|HOSTNAME|HOME|container)='"
report "environment inside the container" \
  bash -c "podman inspect $CTR --format '{{range .Config.Env}}{{println .}}{{end}}' | head -8"

section "6. Storage survives the container"
manual "Data in $DATA survived a podman rm and recreate" \
  "Destructive to test automatically. Do it by hand once, deliberately."

summary
