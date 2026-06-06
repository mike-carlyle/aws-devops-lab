# Infrastructure & Cloud Lab

My personal lab for hands-on infrastructure and cloud study.

Two things live here. The main one is my homelab: a self-built Ubuntu server running a stack of Dockerised services I use day to day, managed as code so the whole setup is documented and reproducible. Alongside it are my AWS study notes, working slowly towards the SAA-C03 certification.

I keep my notes in public, so you will find real configs, runbooks, the reasoning behind the choices, and the things that tripped me up.

## Homelab

A self-built Ubuntu server, managed as code under `homelab/`.

| Service | Purpose |
|---------|---------|
| AdGuard Home | Network-wide DNS and ad blocking, with DNSSEC validation |
| Jellyfin | Self-hosted media streaming |
| Caddy | Reverse proxy adding HTTP basic auth in front of services that lack their own (currently fronting Netdata) |
| Tailscale | Mesh VPN and Magic DNS for remote access, with Tailnet Lock and ACL-restricted accounts |
| Netdata | Real-time system and container metrics |
| Portainer | Container management UI |
| Homepage | Service dashboard with live widgets reading each service's API |
| Uptime Kuma | Availability monitoring with email alerts |
| Watchtower | Automated container image updates, fronted by a Docker socket proxy |
| Duplicati | Encrypted, scheduled cloud backups |
| fail2ban | SSH brute-force protection |
| Minecraft | A private Bedrock server, Tailscale-only via ACL |

Each service has its own folder under `homelab/compose/` with a `docker-compose.yml` and an `.env.example`. The real `.env` files hold the secrets and stay out of version control.

```bash
cd homelab/compose/<service>
cp .env.example .env    # then fill in the secrets
docker compose up -d
```

Every push runs a GitHub Action that lints the YAML and validates each compose file, so a broken config cannot slip in unnoticed. The next step is full host provisioning under `homelab/ansible/`, so the box can be rebuilt from a bare Ubuntu install with one playbook.

**Security**, built in from the start rather than bolted on:

- SSH key-only authentication, with a separate keypair per device
- UFW firewall with per-service rules scoped to LAN and Tailscale
- fail2ban guarding SSH against brute-force attempts
- Tailnet Lock protecting against Tailscale account takeover
- Caddy adding auth in front of services that have none
- A Docker socket proxy limiting Watchtower to a minimal endpoint allowlist rather than full daemon access
- DNSSEC validation in AdGuard with a validating upstream resolver
- Secrets kept in per-service `.env` files, out of git

## AWS study

Working through the SAA-C03 material (Stephane Maarek's course) at my own pace. Notes live under `aws/`. This track is on the back burner while the homelab is the focus, but I add to it when I pick the course back up.

| Section | Topic | Status |
|---------|-------|--------|
| 01 | Fundamentals | Complete |
| 02 | IAM | Complete |
| 03 | EC2 | Complete |
| 04 | Databases (RDS, Aurora, ElastiCache) | Complete |
| 05 | Route 53 | Not started |

---

## Skills covered so far

**Homelab and Linux**

- Ubuntu Server administration on self-built hardware, kept current with unattended-upgrades and emailed change notifications
- Docker and container networking, including bridge vs host networking trade-offs, network isolation patterns, and per-service compose files
- Identity and access hardening: SSH key-only authentication with per-device keypairs, UFW per-service rules, fail2ban for SSH brute-force protection, Tailnet Lock protecting against Tailscale account takeover
- Reverse-proxy authentication using Caddy to add HTTP basic auth in front of services that lack their own
- Docker API surface reduction using a socket proxy in front of Watchtower so its Docker access is limited to a minimal endpoint allowlist rather than full daemon access
- DNSSEC validation in AdGuard with a validating upstream resolver, verified end-to-end against deliberately broken-signature test domains
- Encrypted cloud backups with Duplicati to OneDrive, verified by test restores; backup passphrases stored off-server
- Container observability via Homepage as a service dashboard with live widgets, Netdata for deep performance metrics, and Uptime Kuma for availability monitoring and alerting
- Secrets managed via per-service `.env` files alongside docker-compose, kept out of version control with `.gitignore` and `.env.example` templates
- Email notifications via msmtp and Gmail for automated events
- Remote access via Tailscale mesh VPN, Magic DNS, and ACLs restricting external accounts to specific services
- DNS troubleshooting and resolving real infrastructure problems
- Reading logs, isolating variables, and confirming theories before applying fixes — the same diagnostic loop that works whether the system is a home server or a production environment

**AWS**

- AWS global infrastructure and how regions and availability zones work in practice
- Identity and access management and why least-privilege matters from day one
- EC2 compute, instance types, and SSH access
- AWS networking including VPCs, security groups, ENIs, and the differences between IP types
- Storage with EBS, EFS, and AMIs and when to use each
- High availability patterns using Elastic Load Balancers and Auto Scaling Groups
- Managed databases with RDS, Aurora and ElastiCache including read replicas, Multi-AZ, caching strategies and RDS Proxy

---

## How I document

Each section has a notes file covering the key concepts, what I actually built, and honest reflections on what tripped me up. The homelab section is updated as the project evolves. AWS sections 1–3 were written retrospectively and from section 4 onwards I am documenting as I go.
