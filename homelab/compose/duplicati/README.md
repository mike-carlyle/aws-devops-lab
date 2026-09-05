# Duplicati — offsite backup

The compose file next to this README brings the container up. It does **not** bring back the
backup *job*, which lives only in `/home/mike/duplicati/config/Duplicati-server.sqlite` — a
file that is itself inside the backup it defines. This README is the paper copy, so the job
can be rebuilt on a fresh host.

Job name: **Homelab Config** · target: **OneDrive**, `Documents/Personal/Backup/Homelab/`
Encryption: AES · retention: `keep-time = 14D` · schedule: daily 02:00 UTC (after the 02:20
and 02:30 database dumps, so each night's dumps are swept the same night).

## ⚠ The passphrase problem — read this first

The AES passphrase is stored in `Duplicati-server.sqlite`, encrypted with
`SETTINGS_ENCRYPTION_KEY` from `/home/mike/duplicati/.env`. Both of those files are inside the
backup. **If the only copy of the passphrase is on this machine, the entire OneDrive archive
is unrecoverable the moment the machine is gone** — which is precisely the scenario the
archive exists for.

Keep the passphrase somewhere off this box: a password manager, or written down. Retrieve it
from the UI (job → Options → the passphrase field), not from this repo — it must never be
committed here.

**A restore has never been performed.** As of 2026-09-05 the job's history is 173 backups and
zero restores, so the decrypt-and-download path a real disaster needs is untested. A backup
that has never been restored is a hypothesis. Restoring a single small file to a scratch
directory would settle it in minutes.

## Source paths

```
/source/etc/                      # host config: msmtprc, sysctl.d, systemd drop-ins, logrotate.d
/source/home/.config/             # includes the healthchecks.io ping URL for the heartbeat
/source/home/.local/bin/          # the host scripts (also mirrored in homelab/scripts/)
/source/home/.ssh/                # SSH private keys
/source/home/adguard/             # AdGuardHome.yaml — the LAN's ONLY DNS config
/source/home/aws-devops-lab/      /source/home/bills-tracker/    /source/home/caddy/
/source/home/duplicati/           /source/home/fail2ban/         /source/home/family-calendar/
/source/home/family-calendar-spike/  /source/home/homepage/      /source/home/jellyfin/
/source/home/migration-discovery/ /source/home/minecraft/        /source/home/netdata/
/source/home/ollama/              /source/home/open-webui/       /source/home/portainer/
/source/home/qbittorrent-vpn/     /source/home/uptime-kuma/      /source/home/watchtower/
/source/home/wedding-app/
```

Exclude filters:

```
/source/home/qbittorrent-vpn/downloads/     /source/home/qbittorrent-vpn/radarr/
/source/home/jellyfin/cache/                /source/home/ollama/data/models/
/source/home/open-webui/data/cache/         */node_modules/            */.next/
```

Advanced option: `--skip-files-larger-than = 100MB`

## Why those values (2026-09-05 changes, from a DR audit)

**`/source/etc/` was missing entirely.** `/etc` had been mounted read-only into the container
since the beginning but was never in the source selection, so no host configuration outside
`/home/mike` was backed up — including `/etc/msmtprc`, which holds the Gmail app password.

**`~/.ssh` and `~/.config` were missing**, so both SSH private keys and the healthchecks.io
ping URL — the only monitoring that survives this box dying — existed in exactly one place.

**open-webui was only its compose file.** The source list named
`/source/home/open-webui/docker-compose.yml`, not the directory, so 890 MB of accounts and
chat history was excluded. Now the whole directory is included, with `data/cache/` filtered
out — that cache is 889 MB of the 890 MB, and the part worth keeping (`webui.db`) is 764 KB.

**A stale `/home/` entry** backed up the Duplicati container's own empty home directory.
Removed.

**`--skip-files-larger-than` was 50 MB**, which silently excluded Uptime Kuma's 76.5 MB
`kuma.db` — every monitor, notification channel and push token. Raised to 100 MB rather than
removed: the limit is load-bearing, and at 100 MB it still excludes the 233 MB Minecraft
server binary (redownloadable) and Duplicati's own 105 MB block database (rebuildable from
the target, and far too churny to version 14 times).

## Why the container runs as root

`PUID=0/PGID=0`, changed from `1000` on 2026-09-05. Duplicati had been silently
permission-denied on root-owned paths for roughly 38 consecutive runs, so
`AdGuardHome.yaml` — the entire configuration of the LAN's only DNS server — had never been
backed up once. Those denials appeared only in the nightly warning stream, which had long
since been normalised into noise.

A backup tool cannot back up root-owned config without root read access; keeping it
unprivileged only moves the privilege to whatever process stages the files instead. The
trade-off is stated in full in the compose file. Effect measured immediately: warnings per
run fell from **15 to 3**, and examined files rose from 21,139 to 22,156.

## Known residual gaps

- **Three files are still skipped, now for a different reason: they are locked**, being live
  SQLite databases written while the backup runs — `portainer/data/portainer.db`,
  `adguard/work/data/sessions.db`, `adguard/work/data/stats.db`. AdGuard's *config* is
  captured; only its session and stats databases are not. Portainer's live database is not
  captured at all. The general fix is to snapshot SQLite with `sqlite3 .backup` to a
  sibling file on a timer and let Duplicati take the snapshot instead of the live file.
- **Docker named volumes are not backed up.** Duplicati mounts only `/home` and `/etc`, never
  `/var/lib/docker/volumes/`. The wedding-app uploaded-documents volume is covered separately
  by its own backup sidecar's nightly tarball, but other named volumes are not.
- **Local and offsite retention are both 14 days and expire together**, so corruption noticed
  on day 15 is unrecoverable. There is no monthly or yearly tier.
- **The crontab is not backed up.** `/var/spool/cron/crontabs/` is outside both mounts. The
  jobs are documented in the header comments of each script in `homelab/scripts/`.
