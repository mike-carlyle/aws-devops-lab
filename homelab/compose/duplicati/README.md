# Duplicati — offsite backup

The compose file next to this README brings the container up. It does **not** bring back the
backup *job*, which lives only in `/home/mike/duplicati/config/Duplicati-server.sqlite` — a
file that is itself inside the backup it defines. This README is the paper copy, so the job
can be rebuilt on a fresh host.

Job name: **Homelab Config** · target: **OneDrive**, `Documents/Personal/Backup/Homelab/`
Encryption: AES · retention: `keep-time = 14D` · schedule: daily 02:00 UTC (after the 02:20
and 02:30 database dumps, so each night's dumps are swept the same night).

## ⚠ The passphrase — read this first

The AES passphrase is stored in `Duplicati-server.sqlite`, encrypted with
`SETTINGS_ENCRYPTION_KEY` from `/home/mike/duplicati/.env`. Both of those files are inside the
backup, so **the copy on this machine is useless in exactly the disaster the archive exists for.**

**The off-box copy is in the password manager** (confirmed 2026-09-25, and proven correct by the
restore test below). It must never be committed here. If it is ever rotated, update the password
manager in the same sitting and re-run the restore test.

## Restoring

**Last verified 2026-09-25**: two files (`adguard/conf/AdGuardHome.yaml`,
`duplicati/docker-compose.yml`) restored straight from OneDrive with `--no-local-db`, an empty
database and the password-manager passphrase. Both were byte-identical to the live files (sha256).
It took 24 s after the index download. Re-run this test after any change to the passphrase,
target or Duplicati major version. A backup that has never been restored is a hypothesis.

### A. Test restore on the live box (safe, touches nothing live)

This does **not** use the job's database or its stored passphrase. It is the same path a rebuilt
box would take, so it is a real test and not a self-check.

1. **Target URL.** `GET /api/v1/backup/1` masks the OneDrive `authid` as `****`, so use the
   export endpoint with a one-time token and write the URL straight into a root-only file, never
   to the terminal. Log in with `POST /api/v1/auth/login {"Password": …}` (the password is in
   `.env`), then `POST /api/v1/auth/issuetoken/export` →
   `GET /api/v1/backup/1/export?export-passwords=true&token=<token>` → `.Backup.TargetURL` →
   `docker exec -i duplicati sh -c 'umask 077; cat > /tmp/dr-target-url'`.
2. **Passphrase**, from the password manager, typed so it never echoes or lands in shell history:
   ```bash
   read -rsp 'Duplicati passphrase: ' P; echo; printf %s "$P" | docker exec -i duplicati sh -c 'umask 077; cat > /tmp/dr-pass'; unset P
   ```
3. **Restore** into a scratch folder with a fresh, empty database:
   ```bash
   docker exec duplicati sh -c 'mkdir -p /tmp/dr-restore /tmp/dr-db && PASSPHRASE=$(cat /tmp/dr-pass)      /app/duplicati/duplicati-cli restore "$(cat /tmp/dr-target-url)"      /source/home/adguard/conf/AdGuardHome.yaml /source/home/duplicati/docker-compose.yml      --restore-path=/tmp/dr-restore --no-local-db=true --dbpath=/tmp/dr-db/dr.sqlite --encryption-module=aes'
   ```
   Pipe the output through `sed -E 's/authid=[^& "]*/authid=<redacted>/g'` if it may be logged.
   An exit code of `2` means "completed with warnings", and it did so on the verified run with no
   warning text shown. It is not a failure. Look for `Restored N (...) files`.
4. **Compare**: `sha256sum` each file under `/tmp/dr-restore/` against `/source/home/<same path>`.
   A mismatch is only expected if the live file changed since the last 02:00 UTC run.
5. **Clean up** (the passphrase is sitting in a file):
   `docker exec duplicati rm -rf /tmp/dr-pass /tmp/dr-target-url /tmp/dr-restore /tmp/dr-db`

### B. Real disaster: the box is gone

What you need: this repo, the passphrase from the password manager, and the Microsoft account
login for OneDrive. Nothing else from the old box.

1. Bring the container up from the compose file next to this README, with a **new** `.env`:
   generate a new `DUPLICATI__WEBSERVICE_PASSWORD` and `SETTINGS_ENCRYPTION_KEY`, and set
   `TAILNET_IP`. The old settings key is not needed, because you are not reusing the old database.
2. **The old OneDrive `authid` is gone with the box.** It is an OAuth token from Duplicati's
   login service and existed only inside the encrypted job config. In the UI, go to
   **Restore → Direct restore from backup files → Microsoft OneDrive v2**, path
   `Documents/Personal/Backup/Homelab/`, press **AuthID** and sign in to Microsoft to get a fresh one.
3. Enter the passphrase. Duplicati builds a temporary database from the remote index (a few
   minutes) and then lists every version, 14 days back.
4. Restore to a scratch location first, not over `/source`, because the source mounts are `:ro`
   by design. Add a temporary writable bind mount (for example `/home/mike/restore:/restore`) and
   restore there, then move things into place. The **order** matters: `adguard/` first (it is the
   LAN's only DNS server, so nothing resolves until it is back), then `etc/`, `.ssh/` and `.config/`,
   then the app directories.
5. Recreate the backup job from the values at the top of this README and in "Source paths"
   below, attach the alerting hook (next section), and run it once by hand.
   Alternatively, restore `duplicati/config/` from the backup and reuse the old `.env`, which
   brings the original job back whole.

## Failure alerting

Every run pushes its result to the Uptime Kuma push monitor **"Duplicati Backup"**, through the
job's advanced option `--run-script-after=/config/scripts/kuma-push.sh`:

- **Success** or **Warning** marks the monitor up. Warning counts as up on purpose, because every
  run carries about 3 warnings about locked files (see below).
- **Error**, **Fatal** or **Unknown** marks it down and emails straight away.
- **No run at all** sends nothing, and Kuma's 26 h push window emails on the silence.

The script and its push URL (`/config/scripts/kuma-push-url`, root-only, holds the token) live in
the container's `/config`, **not in this repo**. The script always exits 0, so a Kuma problem can
never fail a backup. Kuma runs `network_mode: host`, so the beat arrives on the host INPUT chain
from this stack's bridge. That is why the compose file pins the subnet to `172.24.0.0/16`, and
`group_vars/all.yml` allows port 3001 from `duplicati_cidr` only. The pin and the ufw rule are
one mechanism, so don't change one without the other. Added 2026-09-25, after the OneDrive quota
lapse of 2026-09-17/18 failed two nightly runs and nothing noticed.

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
