# Host system config

Files under `/etc` on mchomeserver that are load-bearing but not yet managed by Ansible.
They are captured here so a rebuilt host can be brought back to the same state by hand.

Like `homelab/scripts/`, these are **copy-into-place-by-hand** for now. When host
provisioning grows to cover them, they should move into an Ansible role and this
directory should go away.

| Repo path | Goes to | Applied by |
|---|---|---|
| `journald.conf.d/10-size-limits.conf` | `/etc/systemd/journald.conf.d/` | `~/.local/bin/fix-log-spam.sh` |
| `logrotate.d/rsyslog` | `/etc/logrotate.d/rsyslog` | `~/.local/bin/fix-log-spam.sh` |

Both were added on 2026-09-05, after the 4 September power cut, when it emerged that
netdata's `apps.plugin` had been generating ~768 AppArmor `ptrace` denials per minute
(~1.1M/day). That flood was 86.9% of every byte in the journal, and — because the kernel
printk rate limiter is global to the audit path — it was also silently discarding
*unrelated* audit records from other containers. It made the power-cut forensics far
harder to read than they should have been.

The denial rate itself was fixed at source (see `../compose/netdata/netdata.conf.snippet`).
These two files are the defensive layer: they bound the sinks so that any *future* flood,
from any source, cannot fill the disk or bury the signal.

## Notes that are easy to get wrong

**`logrotate.d/rsyslog` is a dpkg conffile.** A future `rsyslog` package upgrade will prompt
about it; keeping the local version is correct. The change is `weekly` → `daily`,
`rotate 4` → `rotate 14`, plus a new `maxsize 100M`. Before this it had no size cap at all,
so a flood could grow unbounded for up to seven days — `kern.log` and `syslog` had reached
~1.1 GB between them.

**Never put a backup copy inside `/etc/logrotate.d/`.** That directory is `include`d
wholesale, so a `rsyslog.bak-*` sibling is parsed as a second config declaring the same
log paths, producing `duplicate log entry` errors that make the whole nightly
`logrotate.service` run fail. Back up to `/var/backups/` instead.

**Force rotation against the main config, never a fragment.** `/var/log` is group-writable
(`root:syslog`), which trips logrotate's safety check — it refuses to rotate unless an `su`
directive says whose privileges to drop to, and that lives in `/etc/logrotate.conf`
(`su root adm`). Running `logrotate --force /etc/logrotate.d/rsyslog` loads the rules,
updates the state file, and then silently rotates *nothing*. Use
`logrotate --force /etc/logrotate.conf`; its `include` still picks up the fragment.

**Checking the config as a non-root user is misleading.** `logrotate -d /etc/logrotate.conf`
as uid 1000 emits ~14 spurious `error:` lines about the state file and `switching euid`.
Those are permission artefacts, not config errors. Filter them
(`grep -vE 'state file|switching euid'`) or look for the real signatures: `duplicate log
entry` and `found error in file`.

**Journald rate limiting would not have helped and is deliberately not set.** These denials
arrive with `_TRANSPORT=kernel` and carry no unit identity, so journald's per-service
limiter has no bucket to count them against and they bypass it entirely. Size caps are the
real defence here.

## Not captured, and cannot be

- **BIOS.** `Restore on AC power loss` must be **Always On** (factory default is Always Off).
  On this board it is directly under the **Advanced** tab, not buried in AMD CBS. See
  `../notes.md` for why this matters and how to verify it.
- **`net.ipv4.ip_nonlocal_bind=1`** — set by the Ansible `base_system` role, not here.
- **netdata.conf** lives inside the `netdata_netdataconfig` named volume, so it is invisible
  to both this repo and Ansible. The snippet next to the netdata compose file is a copy;
  it has to be re-appended by hand after a rebuild.
