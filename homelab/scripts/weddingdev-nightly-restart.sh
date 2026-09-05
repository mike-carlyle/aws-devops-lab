#!/usr/bin/env bash
# Nightly recycle of the wedding-app DEV container to reclaim Next.js dev-mode
# Installed on the host at ~/.local/bin/weddingdev-nightly-restart.sh, run from cron:
#   0 2 * * *        /home/mike/.local/bin/weddingdev-nightly-restart.sh
#   @reboot sleep 90 && /home/mike/.local/bin/weddingdev-nightly-restart.sh
# Not yet brought under Ansible management -- copy it into place by hand for now,
# same as the rest of homelab/scripts/ until host provisioning covers it too.
#
# memory creep. Runs at 02:00 via mike's crontab. Log: ~/weddingdev-nightly-restart.log
#
# IMPORTANT: weddingdev-app is NOT compose-managed. Its main command is
# `sleep infinity`; the dev server is started SEPARATELY via `docker exec`
# (see docs/demo-instance.md). So a plain `docker restart` clears the RAM but
# leaves dev OFFLINE — we MUST relaunch `next dev` afterwards and verify :3009.
set -uo pipefail

LOG="/home/mike/weddingdev-nightly-restart.log"
TS() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(TS)  $*" >>"$LOG"; }

# 0. the app is useless without its DB. weddingdev-db exiting unnoticed is the
# documented failure mode here (14 days dead in Jul 2026, 12 more after the
# 2026-08-28 kernel reboot), so bring the peers up first -- no-op if running.
for peer in weddingdev-db weddingdev-rsvp; do
  /usr/bin/docker start "$peer" >/dev/null 2>&1 || log "WARN: could not start $peer"
done

# 1. restart container -> kills the bloated next-server, reclaims RAM
if ! /usr/bin/docker restart weddingdev-app >/dev/null 2>&1; then
  log "FAILED: docker restart weddingdev-app"; exit 1
fi
sleep 5  # let the container's sleep-infinity entrypoint settle

# 2. relaunch the dev server (matches docs/demo-instance.md launch command)
/usr/bin/docker exec -d -e UPLOAD_DIR=/app/.uploads weddingdev-app \
  sh -lc 'cd /app && npx next dev -H 0.0.0.0 -p 3000 > /app/.next-dev.log 2>&1'

# 3. verify :3009 actually comes back (Next first-compile can take a while).
# Probe /api/health and require HTTP 200. The old check hit / and accepted ANY
# code except 000 -- the auth redirect's 307 passed, so it logged "OK" for 14
# straight nights over an app whose DB was down (2026-07-25 finding). /api/health
# returns 200 {"status":"ok"} only when Postgres answers, and 503 db_unavailable
# otherwise, so this probe fails loudly instead of silently going green.
for i in $(seq 1 30); do
  sleep 2
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:3009/api/health 2>/dev/null)"
  if [ "$code" = "200" ]; then
    log "OK: recycled + dev healthy on :3009 (/api/health 200 after ~$((i*2))s)"; break
  fi
  if [ "$i" = "30" ]; then
    log "WARN: dev DOWN — /api/health on :3009 returned '$code' (want 200) after ~60s"
  fi
done

tail -n 200 "$LOG" >"$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
