#!/usr/bin/env bash
#
# sync-tailnet-ip.sh -- keep the tailnet-bound compose projects pinned to the
# CURRENT Tailscale IPv4 address.
#
# Added 2026-08-14.
#
# Installed on the host at ~/.local/bin/sync-tailnet-ip.sh, run from cron:
#   @reboot          /home/mike/.local/bin/sync-tailnet-ip.sh >> $HOME/tailnet-ip-sync.log 2>&1
#   */15 * * * *     /home/mike/.local/bin/sync-tailnet-ip.sh >> $HOME/tailnet-ip-sync.log 2>&1
# Not yet brought under Ansible management -- copy it into place by hand for now,
# same as the rest of homelab/scripts/ until host provisioning covers it too.
#
# Background: homepage, open-webui, duplicati and portainer publish their ports
# to the Tailscale address as well as loopback, and must NOT be published on the
# LAN (duplicati reads /etc and /home/mike; portainer holds the raw docker
# socket). That address used to be hardcoded in all four
# docker-compose.yml files. If the tailnet address ever changed, every one of
# them would fail to bind and stay down.
#
# This script writes the live address into each project's .env as TAILNET_IP
# (the compose files interpolate it) and re-runs `docker compose up -d` for any
# project that has drifted. It also re-ups a project whose container is running
# but has no host port mapping -- a state Docker can land in when the address
# was missing at bind time, where `docker ps` shows the service healthy while
# nothing is actually listening.
#
# Run from cron: @reboot and every 15 minutes. Safe to run at any time; it is a
# no-op when everything already matches.

set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PROJECTS=(homepage open-webui duplicati portainer)
CONTAINERS=(homepage open-webui duplicati portainer)
BASE=/home/mike

log() { printf '%s %s\n' "$(date -Is)" "$*"; }

# --- wait for the docker daemon (we may be running from @reboot) -------------
for _ in $(seq 1 60); do
  docker info >/dev/null 2>&1 && break
  sleep 5
done
if ! docker info >/dev/null 2>&1; then
  log "ERROR: docker daemon not ready after 5 minutes; giving up"
  exit 1
fi

# --- wait for tailscaled to hand out an IPv4 --------------------------------
ip=""
for _ in $(seq 1 60); do
  ip=$(tailscale ip -4 2>/dev/null | head -n1 || true)
  [[ -n $ip ]] && break
  sleep 5
done
if [[ -z $ip ]]; then
  log "ERROR: no Tailscale IPv4 after 5 minutes; giving up"
  exit 1
fi

# Sanity check: Tailscale hands out CGNAT 100.64.0.0/10 addresses. If we ever
# read something outside that, treat it as a bug rather than rewriting every
# .env with a bad value and recreating four containers on top of it.
if [[ ! $ip =~ ^100\.([6-9][0-9]|1[0-2][0-7])\. ]]; then
  log "ERROR: '$ip' is not in the Tailscale CGNAT range; refusing to apply"
  exit 1
fi

# --- apply -------------------------------------------------------------------
for i in "${!PROJECTS[@]}"; do
  proj=${PROJECTS[$i]}
  cont=${CONTAINERS[$i]}
  dir=$BASE/$proj
  envf=$dir/.env
  reason=""

  [[ -d $dir ]] || { log "WARN: $dir missing, skipping"; continue; }

  # 1. Does .env carry the current address?
  cur=$(sed -n 's/^TAILNET_IP=//p' "$envf" 2>/dev/null | head -n1 || true)
  if [[ $cur != "$ip" ]]; then
    if [[ -f $envf ]] && grep -q '^TAILNET_IP=' "$envf"; then
      # Rewrite in place, preserving the file's other contents and its mode.
      sed -i "s|^TAILNET_IP=.*|TAILNET_IP=$ip|" "$envf"
    else
      # Create or append. New files must not be world-readable: the other .env
      # files in these directories hold service passwords at mode 0600.
      [[ -f $envf ]] || { install -m 600 /dev/null "$envf"; }
      printf 'TAILNET_IP=%s\n' "$ip" >>"$envf"
    fi
    reason="env ${cur:-unset} -> $ip"
  fi

  # 2. Is the running container actually bound to it, and actually published?
  #    An empty .NetworkSettings.Ports on a running container means Docker
  #    published nothing, however healthy `docker ps` looks. A *partial* bind
  #    (loopback published, tailnet not) leaves Ports non-empty, so we also
  #    require the tailnet address to appear in the published result -- checking
  #    HostConfig.PortBindings alone is not enough, that is only the request.
  if [[ -z $reason ]]; then
    state=$(docker inspect "$cont" --format '{{.State.Running}}' 2>/dev/null || echo missing)
    if [[ $state != true ]]; then
      reason="container $state"
    else
      bindings=$(docker inspect "$cont" --format '{{json .HostConfig.PortBindings}}' 2>/dev/null || echo '{}')
      published=$(docker inspect "$cont" --format '{{json .NetworkSettings.Ports}}' 2>/dev/null || echo '{}')
      if [[ $bindings != *"$ip"* ]]; then
        reason="container not bound to $ip"
      elif [[ $published == '{}' || -z $published ]]; then
        reason="container running but no published ports"
      elif [[ $published != *"$ip"* ]]; then
        reason="container not publishing on $ip (partial bind)"
      fi
    fi
  fi

  if [[ -n $reason ]]; then
    log "$proj: $reason -- recreating"
    ( cd "$dir" && docker compose up -d --force-recreate ) \
      || log "ERROR: $proj failed to come up"
  fi
done

log "done (tailnet ip $ip)"
