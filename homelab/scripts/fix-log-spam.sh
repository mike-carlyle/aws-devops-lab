#!/usr/bin/env bash
#
# fix-log-spam.sh -- bound the on-disk log sinks. RUN WITH SUDO.
#
# Installed on the host at ~/.local/bin/fix-log-spam.sh (mode 0700). NOT a cron job --
# run by hand with sudo, and it supports --dry-run:
#   sudo /home/mike/.local/bin/fix-log-spam.sh --dry-run
#   sudo /home/mike/.local/bin/fix-log-spam.sh
# Not yet brought under Ansible management -- copy it into place by hand for now,
# same as the rest of homelab/scripts/ until host provisioning covers it too.
#
#   sudo /home/mike/.local/bin/fix-log-spam.sh --dry-run   # show what would change
#   sudo /home/mike/.local/bin/fix-log-spam.sh             # apply
#
# Written 2026-09-05 after the netdata/AppArmor investigation.
#
# BACKGROUND. netdata's apps.plugin was generating ~768 AppArmor ptrace denials per
# MINUTE (~1.1M/day) because the docker-default profile denies ptrace toward unconfined
# (host) processes. The SOURCE of that flood is already fixed -- apps.plugin was slowed
# from 1s to 5s in netdata.conf. This script fixes the SINKS, so that any future flood
# from any source is bounded rather than eating the disk and burying real events.
#
# WHY THIS MATTERS MORE THAN DISK SPACE. ~86% of those denials were being dropped by
# the kernel printk rate limiter, and that limiter is GLOBAL to the audit path. So the
# flood was also swallowing UNRELATED audit records -- other containers' denials,
# seccomp violations, capability audits. That is the concrete reason the 4 Sep power-cut
# forensics were so hard to read. Log hygiene here is a security-visibility fix.
#
# WHAT THIS DOES NOT DO. It does not touch AppArmor, netdata, Docker, or any container.
# The investigation considered a custom AppArmor profile (docker-default plus a silent
# `deny ptrace (read) peer=unconfined,` rule) and REJECTED it: the profile would have to
# be hand-cloned from a Go template inside the dockerd binary, can never be diffed
# against what is actually loaded (root-only, and even root cannot dump loaded rule
# text), would drift silently on every Docker upgrade, and a parse failure at boot makes
# netdata crash-loop. Not worth it to silence a log line.

set -uo pipefail

DRY=0
[[ ${1:-} == --dry-run ]] && DRY=1

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: must run as root.  sudo $0 ${1:-}" >&2
  exit 1
fi

STAMP=$(date +%Y%m%d-%H%M%S)
run() {
  if (( DRY )); then echo "  [dry-run] $*"; else eval "$@"; fi
}

echo "=============================================================="
echo " BEFORE"
echo "=============================================================="
journalctl --disk-usage
ls -la /var/log/kern.log /var/log/syslog 2>/dev/null | awk '{printf "  %-22s %10.1f MB\n", $NF, $5/1048576}'
echo

# --------------------------------------------------------------------------
# 1. Cap the systemd journal.
#
# It is NOT currently unbounded -- journald self-caps at 4G (10% of the filesystem,
# capped) and it sits at ~2.6G. But the ceiling is implicit and larger than this box
# needs. A drop-in makes the policy explicit and survives package upgrades, unlike
# editing the vendor file at /etc/systemd/journald.conf.
# --------------------------------------------------------------------------
echo "=============================================================="
echo " 1. Journal size cap  ->  /etc/systemd/journald.conf.d/10-size-limits.conf"
echo "=============================================================="
run "mkdir -p /etc/systemd/journald.conf.d"
if (( DRY )); then
  echo "  [dry-run] would write SystemMaxUse=1G, SystemMaxFileSize=128M, MaxRetentionSec=4week"
else
  cat > /etc/systemd/journald.conf.d/10-size-limits.conf <<'EOF'
# Explicit journal bounds. Added 2026-09-05.
#
# Previously unset, so journald used its implicit default (10% of the filesystem,
# capped at 4G) and had grown to 2.6G -- 86.9% of which was a single repeated
# AppArmor denial from netdata's apps.plugin.
#
# 1G with a 4-week retention bound is ample for this host and keeps the signal
# readable. Raise SystemMaxUse if you ever need deeper history for an investigation.
#
# NOTE: journald rate limiting (RateLimitIntervalSec/RateLimitBurst) is deliberately
# NOT set here. It would not have helped: those denials arrive with _TRANSPORT=kernel
# and carry no unit identity, so the per-service limiter has no bucket to count them
# against and they bypass it entirely. Size caps are the real defence; rate limiting
# is not. Do not "fix" a future flood by tuning those values.
[Journal]
SystemMaxUse=1G
SystemMaxFileSize=128M
MaxRetentionSec=4week
EOF
  echo "  written."
fi
echo

# --------------------------------------------------------------------------
# 2. Bound the rsyslog copies -- the genuinely uncapped sink.
#
# The vendor drop-in /usr/lib/systemd/journald.conf.d/syslog.conf sets
# ForwardToSyslog=yes, so rsyslog writes a SECOND and THIRD copy of every kernel
# message to kern.log and syslog. Those had reached ~1.1 GB uncompressed.
#
# /etc/logrotate.d/rsyslog ships 'weekly' with 'rotate 4' and NO maxsize, so a flood
# grows unbounded for up to seven days. 'daily' + 'maxsize 100M' bounds it both ways.
# --------------------------------------------------------------------------
echo "=============================================================="
echo " 2. logrotate bounds  ->  /etc/logrotate.d/rsyslog"
echo "=============================================================="
LR=/etc/logrotate.d/rsyslog
BACKUP_DIR=/var/backups

# CRITICAL: the backup must NOT live in /etc/logrotate.d/. `include /etc/logrotate.d`
# reads EVERY file in that directory regardless of extension, so a `rsyslog.bak-*`
# sibling is parsed as a second config and produces
#   "error: duplicate log entry for /var/log/syslog ... skipping"
# which makes the nightly logrotate.service fail. An earlier version of this script
# made exactly that mistake on 2026-09-05; the cleanup below removes any such file.
for stray in /etc/logrotate.d/*.bak-* /etc/logrotate.d/*.bak /etc/logrotate.d/*~; do
  [[ -e $stray ]] || continue
  echo "  !! removing stray config in logrotate.d (breaks nightly rotation): $stray"
  run "mv '$stray' $BACKUP_DIR/\$(basename '$stray')"
done

if grep -q 'maxsize' "$LR" 2>/dev/null; then
  echo "  already has maxsize -- skipping (idempotent)."
else
  run "mkdir -p $BACKUP_DIR"
  run "cp $LR $BACKUP_DIR/logrotate-rsyslog.bak-$STAMP"
  run "sed -i 's/^\tweekly$/\tdaily/; s/^\trotate 4$/\trotate 14/' $LR"
  run "sed -i '/^\tdaily$/a \\\tmaxsize 100M' $LR"
  echo "  weekly -> daily, rotate 4 -> 14, added maxsize 100M"
  echo "  backup -> $BACKUP_DIR/logrotate-rsyslog.bak-$STAMP"
fi

# Fail fast if the directory is not parseable -- better to know now than at 00:00.
if ! (( DRY )); then
  if logrotate -d /etc/logrotate.conf >/dev/null 2>&1; then
    echo "  logrotate config parses cleanly."
  else
    echo "  !! WARNING: logrotate reports a config error:"
    logrotate -d /etc/logrotate.conf 2>&1 | grep -E '^error:' | sed 's/^/     /'
  fi
fi
echo "  NOTE: this is a dpkg conffile. A future rsyslog upgrade may prompt about it;"
echo "        keeping the local version is correct."
echo

# --------------------------------------------------------------------------
# 3. Reclaim what has already accumulated.
# --------------------------------------------------------------------------
echo "=============================================================="
echo " 3. Reclaim existing spam"
echo "=============================================================="
run "systemctl restart systemd-journald"
run "journalctl --vacuum-size=1G"

# NOTE — must invoke logrotate against the MAIN config, not the fragment.
# /var/log is group-writable (root:syslog drwxrwxr-x), which trips logrotate's
# safety check: it will not rotate a log in a group-writable directory unless an
# `su` directive says whose privileges to drop to. That directive is the global
# `su root adm` on line 10 of /etc/logrotate.conf. Passing
# /etc/logrotate.d/rsyslog directly bypasses the main config, so logrotate loads
# the rules, updates its state file, and then silently rotates NOTHING. That is
# exactly what happened on the first run of this script (2026-09-05 12:33).
# /etc/logrotate.conf pulls in /etc/logrotate.d via its include, so the rsyslog
# rules still apply. --force rotates every configured log once, which is harmless.
run "logrotate --force /etc/logrotate.conf"
echo

echo "=============================================================="
echo " AFTER"
echo "=============================================================="
if (( DRY )); then
  echo "  (dry run -- nothing changed)"
else
  journalctl --disk-usage
  ls -la /var/log/kern.log /var/log/syslog 2>/dev/null | awk '{printf "  %-22s %10.1f MB\n", $NF, $5/1048576}'
  echo
  echo "  Verify the journald drop-in took effect:"
  systemd-analyze cat-config systemd/journald.conf 2>/dev/null | grep -E 'SystemMaxUse|SystemMaxFileSize|MaxRetentionSec' | sed 's/^/    /'
fi
echo
echo "TO REVERT:"
echo "  rm /etc/systemd/journald.conf.d/10-size-limits.conf"
echo "  cp /etc/logrotate.d/rsyslog.bak-$STAMP /etc/logrotate.d/rsyslog"
echo "  systemctl restart systemd-journald"
