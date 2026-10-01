#!/usr/bin/env bash
#
# docker-builder-prune.sh -- cap Docker's BuildKit build cache at 10GB.
#
# Installed on the host at ~/.local/bin/docker-builder-prune.sh, run from cron:
#   30 4 * * *       /home/mike/.local/bin/docker-builder-prune.sh
# Not yet brought under Ansible management -- copy it into place by hand for now,
# same as the rest of homelab/scripts/ until host provisioning covers it too.
#
# Added 2026-10-01. Every deploy of the self-built app stacks adds build cache and
# nothing ever trimmed it: it reached 48.6GB by 2026-09-11, then grew back at about
# 3.5GB a week after a manual prune. BuildKit's own GC never kicked in, because its
# default limits scale with disk size and this disk is 936GB.
#
# Why cron and not `builder.gc` in /etc/docker/daemon.json: that only takes effect
# after a dockerd restart. This needs neither root nor a restart (mike is in the
# docker group).
#
# --max-used-space trims oldest-first until the cache is at or under the cap, so the
# newest ~10GB of layers stay warm and the next rebuild is still fast. -a makes
# internal/frontend records count too (see `docker builder prune --help`). Cache held
# by a running build is never removed, and the run is a no-op when already under.
#
# Log: ~/docker-builder-prune.log -- one line per run with the amount reclaimed.
set -uo pipefail

LOG="/home/mike/docker-builder-prune.log"
TS() { date '+%Y-%m-%d %H:%M:%S'; }

if out=$(/usr/bin/docker builder prune -af --max-used-space 10GB 2>&1); then
  echo "$(TS)  OK      $(printf '%s\n' "$out" | tail -1)" >>"$LOG"
else
  echo "$(TS)  FAILED  $(printf '%s\n' "$out" | tail -1)" >>"$LOG"
  exit 1
fi
