# AWS DevOps Learning Lab

This is my personal repository documenting my hands-on learning journey towards a DevOps Engineer role. It covers both formal AWS study working towards the SAA-C03 certification and practical self-directed work including a home server and Docker environment I've built and run myself.

I'm learning in public here, so you'll find real notes, things that went wrong, and honest reflections alongside the actual work.

---

## Goals

| Goal | Target | Status |
|------|--------|--------|
| AWS SAA-C03 Certification | Within 6-12 months | In Progress |
| Transition to DevOps Engineer | 6-12 months | In Progress |
| Build a practical AWS portfolio | Ongoing | In Progress |

---

## Course

I'm following the Ultimate AWS Certified Solutions Architect Associate 2026 by Stephane Maarek on Udemy. Each section combines video learning with hands-on practicals in my personal AWS account.

---

## Structure

```
aws-devops-lab/
├── 00-homelab/              ← Self-built Ubuntu home server running Docker
├── 01-aws-fundamentals/
├── 02-iam/
├── 03-ec2/
├── 04-databases/
├── 05-route53/
└── certifications/
    └── saa-prep/
```

---

## Progress

| Section | Topic | Status |
|---------|-------|--------|
| 00 | Homelab: Ubuntu Server and Docker | In Progress |
| 01 | AWS Fundamentals | Complete |
| 02 | IAM | Complete |
| 03 | EC2 | Complete |
| 04 | Databases (RDS, Aurora, ElastiCache) | Complete |
| 05 | Route 53 | Not Started |

---

## Skills Covered So Far

**Homelab and Linux**
- Ubuntu Server administration on self-built hardware
- Docker and container networking including network isolation patterns, with compose files documented for each service
- Running and managing services including Jellyfin, AdGuard Home, Tailscale, Netdata, Portainer and Watchtower
- Remote access via Tailscale mesh VPN and Magic DNS
- Automated OS patching with unattended-upgrades
- Automated container updates with Watchtower
- Email notifications via msmtp and Gmail for automated events
- DNS troubleshooting and resolving real infrastructure problems
- Troubleshooting real infrastructure problems without a safety net

**AWS**
- AWS global infrastructure and how regions and availability zones work in practice
- Identity and access management and why least-privilege matters from day one
- EC2 compute, instance types, and SSH access
- AWS networking including VPCs, security groups, ENIs, and the differences between IP types
- Storage with EBS, EFS, and AMIs and when to use each
- High availability patterns using Elastic Load Balancers and Auto Scaling Groups
- Managed databases with RDS, Aurora and ElastiCache including read replicas, Multi-AZ, caching strategies and RDS Proxy

---

## How I Document

Each section has a notes file covering the key concepts, what I actually built, and honest reflections on what tripped me up. The homelab section is updated as the project evolves. AWS sections 1-3 were written retrospectively and from section 4 onwards I'm documenting as I go.
