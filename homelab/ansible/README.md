# Homelab Ansible

Phase 1 of host-as-code for the homelab stack. Bringing the entire Docker stack
to a running state from a fresh checkout of this repo, with one command.

## What's here

```
homelab/ansible/
├── ansible.cfg               # defaults + inventory pointer
├── inventory/
│   └── hosts.yml             # single host: mchomeserver (connection: local)
├── group_vars/
│   └── all.yml               # the service catalogue and paths
├── deploy-stack.yml          # the playbook
└── run.sh                    # docker-based wrapper so no Ansible needed on the host
```

## Running it

The wrapper invokes `cytopia/ansible:latest-tools` (a maintained ansible+docker
image), bind-mounting the repo, the runtime directory tree, and the Docker
socket. No Ansible install on the host is required — just Docker.

```bash
# From the repo root:
bash homelab/ansible/run.sh                 # full deploy
bash homelab/ansible/run.sh --check --diff  # dry-run, show what would change
bash homelab/ansible/run.sh -v              # verbose
```

## What it does

For each service listed in `group_vars/all.yml`:

1. Creates the runtime directory under `$HOME/<service>/` if absent.
2. Syncs `docker-compose.yml` and any non-secret config files from
   `homelab/compose/<service>/` in the repo to the runtime location, using
   rsync. Never overwrites a real `.env` on the host.
3. If the service is marked `start: true` and its `.env` (when one is needed)
   is present, runs `docker compose pull` and brings it up.

Services that want to start but have no `.env` are listed at the end of the
run with a clear message — manual action required, run the playbook again
when fixed.

## What it does NOT do (yet)

Phase 1 is the stack deployment only. The following are Phase 2+:

- Installing Docker, msmtp, unattended-upgrades, or any host packages
- Configuring UFW rules
- Templating `/etc/ssh/sshd_config.d/00-hardening.conf` or sshd_config itself
- Provisioning `/etc/msmtprc`
- Managing the Tailscale daemon or its ACLs
- Managing the secrets in `.env` (those stay hand-edited for now)

## Idempotency

A second `run.sh` immediately after a successful one should report
`ok=N changed=0`. Tasks that may legitimately re-run (image pulls when
new digests are available) will report `changed` only when something
actually changes.
