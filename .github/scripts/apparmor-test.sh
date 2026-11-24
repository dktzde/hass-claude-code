#!/usr/bin/env bash
# Tests addon/apparmor.txt on the runner: the file must parse and hold exactly
# one top-level profile (the Supervisor refuses anything else). Then the
# profile is loaded in enforce mode, also while the add-on ships it in
# complain mode, and the image runs under it: s6-overlay starts and stops, and
# the tools Claude Code and the add-on use run. Any access the profile denies
# fails the test, with the kernel's log lines.
#
# Without the Supervisor the init scripts cannot read the options, so s6
# stops the container right after its first services. That still runs
# s6-overlay and bashio; a separate container checks that "docker stop"
# reaches the process inside. chroot, whose capability the profile does not
# list, checks that denials show up in the journal at all (the explicit deny
# rules taken from docker-default are not logged).
# Needs sudo (to load the profile) and an AppArmor-enabled kernel, as on the
# GitHub-hosted Ubuntu runners.
# Usage: apparmor-test.sh <image>
set -euo pipefail
image=$1
profile_file=addon/apparmor.txt

profiles=$(grep -c '^profile ' "$profile_file" || true)
if [ "$profiles" != 1 ]; then
  echo "::error::$profile_file must have exactly one line starting with 'profile ' (found $profiles)"
  exit 1
fi
name=$(sed -n 's/^profile \([^ ]*\).*/\1/p' "$profile_file")

enforce=$(mktemp)
sed 's/,complain)/)/' "$profile_file" > "$enforce"
sudo apparmor_parser --replace "$enforce"
echo "Loaded profile $name in enforce mode"

since=$(date '+%Y-%m-%d %H:%M:%S')

run() {
  echo "::group::$1"
  docker run --rm --security-opt "apparmor=$name" --entrypoint bash "$image" -c "$1"
  echo "::endgroup::"
}

confinement=$(docker run --rm --security-opt "apparmor=$name" --entrypoint cat "$image" /proc/self/attr/current)
echo "Confinement: $confinement"
if [ "$confinement" != "$name (enforce)" ]; then
  echo "::error::The container does not run under profile $name in enforce mode"
  exit 1
fi

run 'claude --version'
run 'python3 -c "import json, sqlite3, ssl, yaml; print(\"python ok\")"'
run 'node --version && gh --version && rg --version && jq --version && command -v mosquitto_pub ttyd'
run 'cd /tmp && git init -q t && cd t && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m t && git log --oneline'
run 'tmux new-session -d -s t "sleep 30" && tmux list-sessions && tmux display-message -p -t t "#{pane_current_path}" && tmux kill-server'
run 'ps aux | head -5 && ping -c 1 -W 2 127.0.0.1'
run 'mkdir -p /data/t && chown nobody /data/t && chmod 700 /data/t && touch /data/t/x && ls -la /data/t'
run 'apk add --no-cache tree > /dev/null && tree --version'

echo "::group::s6-overlay start (stops early without the Supervisor)"
container=$(docker run -d --security-opt "apparmor=$name" "$image")
sleep 15
docker logs "$container" 2>&1 | tail -30
docker rm -f "$container" > /dev/null
echo "::endgroup::"

echo "::group::docker stop"
container=$(docker run -d --security-opt "apparmor=$name" --entrypoint bash "$image" -c 'trap "echo got SIGTERM; exit 0" TERM; sleep 300 & wait')
sleep 2
docker stop -t 20 "$container" > /dev/null
status=$(docker inspect -f '{{.State.ExitCode}}' "$container")
docker logs "$container"
docker rm "$container" > /dev/null
if [ "$status" != 0 ]; then
  echo "::error::The container did not stop on SIGTERM (exit code $status)"
  exit 1
fi
echo "::endgroup::"

# Must be denied and logged
if docker run --rm --security-opt "apparmor=$name" --entrypoint chroot "$image" / true 2> /dev/null; then
  echo "::error::chroot was not denied"
  exit 1
fi
sleep 2

# Kernel or audit transport, depending on the runner's journald
denied=$(sudo journalctl --since "$since" --no-pager | grep 'apparmor="DENIED"' | grep -F "profile=\"$name\"" || true)
if ! grep -qF 'capname="sys_chroot"' <<< "$denied"; then
  sudo journalctl --since "$since" --no-pager | grep -i apparmor | tail -20 || true
  echo "::error::The denied chroot is not in the journal, so this test cannot see denials"
  exit 1
fi
denied=$(grep -vF 'capname="sys_chroot"' <<< "$denied" || true)
if [ -n "$denied" ]; then
  echo "$denied"
  echo "::error::The AppArmor profile denied the accesses above"
  exit 1
fi
echo "No access denied by profile $name"
