# Host system config

Files under `/etc` on mchomeserver that are load-bearing and would otherwise exist only as
hand-edits on the live box. They are captured here so a rebuilt host can be brought back to
the same state.

This directory is the **single source of truth** for these files, including the ones Ansible
now applies — the `base_system` role reads `sysctl.d/99-docker-nonlocal-bind.conf` from here
rather than keeping its own copy, so the repo never holds two versions that can drift apart.
Check the "Applied by" column below before assuming a file needs copying by hand.

| Repo path | Goes to | Applied by |
|---|---|---|
| `sysctl.d/99-docker-nonlocal-bind.conf` | `/etc/sysctl.d/` | **Ansible** — `base_system` role (2026-09-06) |
| `journald.conf.d/10-size-limits.conf` | `/etc/systemd/journald.conf.d/` | `~/.local/bin/fix-log-spam.sh` |
| `logrotate.d/rsyslog` | `/etc/logrotate.d/rsyslog` | `~/.local/bin/fix-log-spam.sh` |

## `99-docker-nonlocal-bind.conf` — now applied by Ansible

`net.ipv4.ip_nonlocal_bind=1` is **required for the box to survive a reboot**.

**As of 2026-09-06 the `base_system` Ansible role applies this file**, so a rebuild no longer
depends on someone remembering to copy it. The role ships THIS file rather than keeping its own
copy, so there is only ever one version of it in the repo.

(History, because the correction matters: an earlier README claimed `base_system` set this when
it did not — a false pointer is worse than an absent one, since a rebuilder reads it and skips
the step deliberately. That is now true rather than aspirational. The role uses a plain file copy
and *not* `ansible.posix.sysctl`: the module manages only the `key=value` line, so pairing it with
a copy of the commented file makes the two rewrite each other every run and the role never
converges.)

Without it, homepage, open-webui, duplicati and portainer try to bind the Tailscale address
before `tailscaled` has assigned it to `tailscale0`, fail with "cannot assign requested
address", exhaust their restart budget and stay down until started by hand. That is not
hypothetical: it happened on 2026-08-12, when the containers gave up about 25 seconds before
tailscaled finished coming up.

## The journald and logrotate bounds

Those two were added on 2026-09-05, after the 4 September power cut, when it emerged that
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
- **Tailscale itself** — install, `tailscale up`, and the three `tailscale serve` proxies are captured nowhere in this repo. A rebuilt host has no tailnet address, so every tailnet-bound service fails to bind.
- **netdata.conf** lives inside the `netdata_netdataconfig` named volume, so it is invisible
  to both this repo and Ansible. The snippet next to the netdata compose file is a copy;
  it has to be re-appended by hand after a rebuild.
