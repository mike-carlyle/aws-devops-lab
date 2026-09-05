#!/usr/bin/env bash
#
# heartbeat.sh -- outbound dead-man's-switch ping to healthchecks.io.
#
# Installed on the host at ~/.local/bin/heartbeat.sh (mode 0700), run from cron:
#   */5 * * * *      /home/mike/.local/bin/heartbeat.sh
#
# !! THE PING URL IS A SECRET AND IS DELIBERATELY NOT IN THIS REPO. It lives on the
# host at ~/.config/healthchecks/mchomeserver.url (mode 0600). Anyone holding it can
# forge a heartbeat and mask a real outage, so it must never be committed. To rebuild:
# create a check at healthchecks.io (period 5m / grace 15m), then write its ping URL
# to that path. The healthchecks.io side also carries the notification channels
# (email + ntfy) -- those are configured in their UI, not here.
# Not yet brought under Ansible management -- copy it into place by hand for now,
# same as the rest of homelab/scripts/ until host provisioning covers it too.
#
# Added 2026-09-05 after the 4 Sep power cut, when the box was dark for 16h20m and
# NOTHING alerted: Uptime Kuma runs ON this machine and all 17 of its monitors point
# back at it, so it died in the same instant as everything it watches.
#
# The logic is deliberately INVERTED. This script does not detect faults and report
# them -- it simply says "still here" every 5 minutes. healthchecks.io raises the alarm
# when the pings STOP. That is the only design that survives the machine vanishing
# completely (power loss, dead NIC, kernel hang), because the alerting lives off-box.
#
# Keep this dumb and unconditional. It answers exactly one question -- "is mchomeserver
# alive, booted, resolving DNS and reaching the internet?" -- and must not fail for any
# other reason. Per-service health is Uptime Kuma's job, and Kuma works fine whenever
# the box is actually up. Do not add service gating here: a deploy blipping a container
# would page Mike at 3am for something that is not an outage.
#
# The ping URL is a shared secret (anyone holding it can forge a heartbeat and mask a
# real outage) so it lives in a 0600 file, NOT in this script and NOT in the crontab.
#
# cron: */5 * * * * /home/mike/.local/bin/heartbeat.sh
# Check period 5m / grace 15m -- so a clean reboot never pages, but a real outage does.

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

URL_FILE=/home/mike/.config/healthchecks/mchomeserver.url
LOG=/home/mike/heartbeat.log

if [[ ! -r $URL_FILE ]]; then
  echo "$(date -Is) ERROR: cannot read $URL_FILE" >> "$LOG"
  exit 1
fi

URL=$(< "$URL_FILE")
URL=${URL//[$'\r\n\t ']/}

if [[ -z $URL ]]; then
  echo "$(date -Is) ERROR: ping URL is empty" >> "$LOG"
  exit 1
fi

# Best-effort diagnostic payload. healthchecks.io stores the body against the ping, so
# when an alert fires the previous heartbeat shows the box's last known state. Every
# command here is wrapped so a failure can never stop the ping itself -- the ping is
# the point, the context is a bonus.
body=$(
  {
    echo "host:       $(hostname 2>/dev/null)"
    echo "time:       $(date -Is 2>/dev/null)"
    echo "uptime:     $(uptime -p 2>/dev/null)"
    echo "load:       $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"
    echo "mem_avail:  $(awk '/MemAvailable/{printf "%.1f GiB", $2/1048576}' /proc/meminfo 2>/dev/null)"
    echo "root_used:  $(df -h --output=pcent / 2>/dev/null | tail -1 | tr -d ' ')"
    echo "containers: $(docker ps -q 2>/dev/null | wc -l) running"
    unhealthy=$(docker ps --filter health=unhealthy --format '{{.Names}}' 2>/dev/null | paste -sd, -)
    echo "unhealthy:  ${unhealthy:-none}"
  } 2>/dev/null
)

# --retry 3 rides out a transient DNS or upstream blip so we do not report a false
# outage. -m 10 bounds each attempt so a hung connection cannot stack up cron jobs.
if curl -fsS -m 10 --retry 3 --retry-delay 2 \
        --data-raw "$body" \
        "$URL" -o /dev/null 2>>"$LOG"; then
  echo "$(date -Is) ok" >> "$LOG"
else
  echo "$(date -Is) PING FAILED (exit $?) -- box is up but could not reach healthchecks.io" >> "$LOG"
fi

# Keep the log bounded; this runs 288 times a day.
if [[ -f $LOG ]] && (( $(wc -l < "$LOG") > 2000 )); then
  tail -n 500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

exit 0
