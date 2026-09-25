#!/usr/bin/env bash
#
# docker-sock-refresh — repair containers severed by a docker.socket restart.
#
# WHY THIS EXISTS (2026-09-16):
#   Upgrading the docker-ce package restarts docker.socket, not just docker.service.
#   systemd unlinks and recreates /var/run/docker.sock, giving it a NEW INODE. A bind
#   mount of a *file* pins the inode, so every already-running container that mounts the
#   socket keeps pointing at the old, deleted inode and can never reconnect — silently,
#   and forever, until that container is restarted.
#
#   On 2026-09-16 an `apt upgrade` (docker-ce 29.8.0 -> 29.8.1) severed socket-proxy,
#   homepage-dockerproxy, netdata and portainer in one go. Every one of them still
#   reported "Up 4 days (healthy)" because none of their healthchecks touch the socket.
#   Watchtower logged a 503 HTML page (HAProxy's, from socket-proxy — NOT dockerd) and
#   Uptime Kuma's Type:docker monitor cried Minecraft-down for a server that was fine.
#
# WHAT IT DOES
#   Compares the host's socket inode against the one each container actually sees (read
#   through /proc/<pid>/root, so it needs no binaries inside the container — portainer
#   has no `stat`) and restarts ONLY the containers whose view is stale. A no-op on a
#   normal boot, where every container already has the current socket.
#
# Watchtower is deliberately NOT handled here: it reaches the API over TCP
# (DOCKER_HOST=tcp://socket-proxy:2375) and opens fresh connections each run, so it
# recovers by itself once socket-proxy is back.

set -uo pipefail

SOCK=/var/run/docker.sock
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

log() { printf '%s\n' "$*"; }

# Must be root: reading another container's /proc/<pid>/mountinfo and restarting
# containers both need it. Without it every container reads as "unreadable" and the
# fail-safe below would restart the lot. Refuse rather than cause the outage we exist
# to prevent.
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR: must run as root (needs /proc/<pid>/mountinfo)."
    exit 1
fi

# dockerd may still be restoring containers when this unit fires. Wait for the API.
ready=0
for _ in $(seq 1 60); do
    if docker info >/dev/null 2>&1; then ready=1; break; fi
    sleep 1
done
if [ "$ready" -ne 1 ]; then
    log "ERROR: dockerd API not ready after 60s — aborting without touching anything."
    exit 1
fi

host_ino=$(stat -L -c %i "$SOCK" 2>/dev/null)
if [ -z "$host_ino" ]; then
    log "ERROR: cannot stat $SOCK — aborting."
    exit 1
fi
log "host $SOCK inode=$host_ino"

stale=()
while read -r id name; do
    [ -n "$id" ] || continue

    pid=$(docker inspect -f '{{.State.Pid}}' "$id" 2>/dev/null)
    if [ -z "$pid" ] || [ "$pid" = "0" ]; then
        continue   # not running / still starting: its mount is new anyway
    fi

    mi="/proc/$pid/mountinfo"
    if [ ! -r "$mi" ]; then
        # Never skip silently: a container we cannot inspect is exactly the one that
        # could be sitting blind. Say so loudly, and restart it if it does mount the socket.
        if docker inspect -f '{{range .Mounts}}{{if or (eq .Source "/var/run/docker.sock") (eq .Source "/run/docker.sock")}}YES{{end}}{{end}}' "$id" 2>/dev/null | grep -q YES; then
            log "  $name: mountinfo unreadable and it mounts the socket — restarting to be safe"
            stale+=("$name")
        else
            log "  $name: mountinfo unreadable (does not mount the socket) — ignoring"
        fi
        continue
    fi

    # mountinfo fields: 1=id 2=parent 3=maj:min 4=root-within-fs 5=mount point.
    # A container that bind-mounts the socket has a line whose mount POINT ends in
    # docker.sock. Field 4 is the authoritative staleness signal: when the source file
    # is unlinked (as a docker.socket restart does), the kernel appends "//deleted".
    #
    # Field 5 is the mount point as already resolved by the kernel (/run/docker.sock),
    # which is why the inode cross-check below uses it rather than the Destination from
    # `docker inspect` (/var/run/docker.sock). That distinction matters: netdata's image
    # has /var/run as an ABSOLUTE symlink to /run, and an absolute symlink under
    # /proc/<pid>/root resolves against the READER's root — so statting the Destination
    # silently escaped into the host's own socket and every container looked healthy.
    # That false negative left netdata blind on 2026-09-18 while the unit logged "ok".
    verdict=""
    while read -r mroot mpoint; do
        case "$mpoint" in
            *docker.sock)
                if [ "${mroot%//deleted}" != "$mroot" ]; then
                    verdict="STALE (mount source deleted)"
                    break
                fi
                c_ino=$(stat -L -c %i "/proc/$pid/root${mpoint}" 2>/dev/null)
                if [ -n "$c_ino" ] && [ "$c_ino" != "$host_ino" ]; then
                    verdict="STALE (sees inode=$c_ino)"
                    break
                fi
                verdict="ok"
                ;;
        esac
    done < <(awk '{print $4, $5}' "$mi" 2>/dev/null)

    [ -n "$verdict" ] || continue   # container does not mount the socket at all

    if [ "$verdict" = "ok" ]; then
        log "  $name: ok"
    else
        log "  $name: $verdict — restarting"
        stale+=("$name")
    fi
done < <(docker ps --format '{{.ID}} {{.Names}}')

if [ "${#stale[@]}" -eq 0 ]; then
    log "nothing stale — no action taken."
    exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY RUN: would restart: ${stale[*]}"
    exit 0
fi

# socket-proxy first: it is the one everything else reaches the API through.
ordered=()
for n in "${stale[@]}"; do [ "$n" = "socket-proxy" ] && ordered+=("$n"); done
for n in "${stale[@]}"; do [ "$n" != "socket-proxy" ] && ordered+=("$n"); done

rc=0
for n in "${ordered[@]}"; do
    if docker restart -t 20 "$n" >/dev/null 2>&1; then
        log "restarted $n"
    else
        log "ERROR: failed to restart $n"
        rc=1
    fi
done

exit $rc
