# Homelab Ansible

Host-as-code for the homelab. Two phases:

- **Phase 1 — stack deploy.** Brings every container in `homelab/compose/` to
  its desired state from a fresh checkout. Runs inside a docker container so
  no Ansible install is needed on the host.
- **Phase 2 — host provisioning.** Codifies everything outside docker compose:
  apt packages, system service config, firewall rules, SSH hardening, and the
  on-disk config for the two host-touching containers (Caddy + fail2ban).
  Runs natively on the host because it touches `apt`, `systemctl`, and `ufw`.

## What's here

```
homelab/ansible/
├── ansible.cfg                  # defaults + inventory pointer
├── inventory/hosts.yml          # single host: mchomeserver (connection: local)
├── group_vars/
│   ├── all.yml                  # service catalogue, networks, ufw rules
│   ├── vault.yml.example        # template for ansible-vault secrets
│   └── vault.yml                # encrypted (gitignored) — Gmail App Password
├── requirements.yml             # Galaxy collections (community.general etc.)
├── Dockerfile                   # ansible+docker image for Phase 1
├── deploy-stack.yml             # Phase 1 playbook
├── run.sh                       # Phase 1 wrapper (containerised)
├── provision-host.yml           # Phase 2 playbook
├── run-host.sh                  # Phase 2 wrapper (host-native)
└── roles/                       # Phase 2 roles
    ├── unattended_upgrades/
    ├── docker_host/
    ├── msmtp/
    ├── service_configs/         # Caddyfile + fail2ban jail.local
    ├── ssh_hardening/
    └── ufw/
```

---

## Phase 1 — stack deploy

The wrapper invokes `cytopia/ansible:latest-tools` (with `docker-cli`,
`docker-cli-compose`, and `rsync` layered on via the local Dockerfile),
bind-mounting the repo, the runtime directory tree, and the Docker socket.

```bash
# From the repo root:
bash homelab/ansible/run.sh                 # full deploy
bash homelab/ansible/run.sh --check --diff  # dry-run, show what would change
bash homelab/ansible/run.sh -v              # verbose
```

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

---

## Phase 2 — host provisioning

Runs on the host directly (not containerised) because `apt`, `systemctl`,
and `ufw` need to act *as* the host, not from inside an Alpine container.

### One-off setup

```bash
sudo apt install -y ansible-core
cd ~/aws-devops-lab/homelab/ansible
ansible-galaxy collection install -r requirements.yml

# Create the encrypted vault (Gmail App Password lives here)
cp group_vars/vault.yml.example group_vars/vault.yml
ansible-vault encrypt group_vars/vault.yml
ansible-vault edit group_vars/vault.yml   # fill in the real values

# Optional: avoid typing the vault password every run
echo 'your-vault-password' > ~/.ansible-vault-pass
chmod 600 ~/.ansible-vault-pass
```

### Running it

```bash
# ALWAYS dry-run first — especially before applying ssh_hardening or ufw.
bash run-host.sh --check --diff

# Apply everything (will prompt for sudo password)
bash run-host.sh

# Apply just one role
bash run-host.sh --tags unattended-upgrades
bash run-host.sh --tags ssh

# Apply everything except the lock-yourself-out-risky roles
bash run-host.sh --skip-tags risky
```

### Roles

| Role                | Tags                    | What it does                                          |
|---------------------|-------------------------|-------------------------------------------------------|
| `unattended_upgrades` | `safe`                | Daily apt updates + email notifications via msmtp    |
| `docker_host`       | `safe`                  | Verifies docker + compose; sets daemon log limits    |
| `msmtp`             | `mail`                  | `/etc/msmtprc` + aliases for system mail via Gmail   |
| `service_configs`   | `caddy`, `fail2ban`     | Templates the host-touching containers' configs      |
| `ssh_hardening`     | `risky`                 | `/etc/ssh/sshd_config.d/00-hardening.conf`           |
| `ufw`               | `risky`                 | Declarative firewall ruleset from `group_vars/all.yml` |

### Safety notes

- **SSH hardening** validates the new config with `sshd -t` BEFORE replacing
  the live file. If validation fails, no change is applied.
- **UFW** refuses to enable itself if `ufw_rules` is empty or missing port 22
  (would otherwise lock you out).
- Keep an out-of-band recovery path open (Tailscale SSH or physical console)
  the first time you run the `risky` tags.

---

## Idempotency

A second run immediately after a successful one should report
`ok=N changed=0`. Tasks that may legitimately re-run (image pulls when new
digests are available, `newaliases` after aliases-file change) will report
`changed` only when something actually changes.
