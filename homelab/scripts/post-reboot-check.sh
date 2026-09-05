#!/usr/bin/env bash
#
# post-reboot-check.sh -- compare the live service state against the snapshot in
# /home/mike/pre-reboot-baseline.txt, and probe the four tailnet-bound UIs.
#
# Installed on the host at ~/.local/bin/post-reboot-check.sh. NOT a cron job -- run by
# hand once the box is back up after any reboot. Compares against the snapshot in
# /home/mike/pre-reboot-baseline.txt, which is host-local state and NOT committed
# (it contains the live tailnet address and the full internal listener map).
# Refresh that baseline BEFORE a planned reboot, or it reports stale false failures.
# Not yet brought under Ansible management -- copy it into place by hand for now,
# same as the rest of homelab/scripts/ until host provisioning covers it too.
#
# Added 2026-08-14 to verify the ip_nonlocal_bind + sync-tailnet-ip fixes across
# a reboot. Run it once the box is back up.

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
BASE=/home/mike/pre-reboot-baseline.txt

# Slow-starting containers (open-webui especially) are not listening yet in the first
# ~90s, so running this too early reports a FALSE failure -- lo:000 ts:000 on a service
# that is merely still booting. Seen 2026-09-05 during the AC-power-loss verification.
# Wait it out rather than reporting a scare.
up=$(cut -d. -f1 /proc/uptime)
if (( up < 90 )); then
  wait=$(( 90 - up ))
  echo "note: only ${up}s since boot -- waiting ${wait}s for slow starters (open-webui)"
  echo "      before probing, to avoid false failures."
  echo
  sleep "$wait"
fi

echo "=== uptime ==="
uptime -p
echo

echo "=== tailscale ==="
tailscale ip -4 2>&1 | head -n1
echo

echo "=== ip_nonlocal_bind (want 1) ==="
sysctl -n net.ipv4.ip_nonlocal_bind 2>&1
echo

if [[ -f $BASE ]]; then
  echo "=== containers missing vs baseline ==="
  before=$(sed -n '/^## containers/,/^## listeners/p' "$BASE" | grep -vE '^#')
  now=$(docker ps --format '{{.Names}}' | sort)
  missing=$(comm -23 <(echo "$before" | sort -u) <(echo "$now" | sort -u))
  if [[ -z $missing ]]; then echo "(none -- all baseline containers are running)"; else echo "$missing"; fi
  echo
fi

echo "=== any container not running ==="
docker ps -a --filter 'status=exited' --filter 'status=dead' --filter 'status=restarting' \
  --format '{{.Names}}\t{{.Status}}' | grep -v '^wedding-app-wedding-migrate-1' \
  | grep -v '^wedding-app-wedding-init-uploads-1' || true
echo

echo "=== tailnet-bound services (want 200 on both) ==="
ip=$(tailscale ip -4 2>/dev/null | head -n1)
for entry in "homepage 3000 http" "open-webui 3002 http" "duplicati 8200 http" "portainer 9443 https"; do
  set -- $entry
  name=$1; port=$2; scheme=$3
  lo=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 "$scheme://127.0.0.1:$port/")
  ts=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 "$scheme://$ip:$port/")
  printf '%-12s lo:%s ts:%s\n' "$name" "$lo" "$ts"
done
echo

echo "=== LAN exposure check (want NO output) ==="
ss -ltn | awk 'NR>1{print $4}' | grep -E '^(0\.0\.0\.0|\*|192\.168\.1\.10):(3000|3002|8200|9443)$' \
  && echo "!! WARNING: a hardened service is listening on the LAN" \
  || echo "(clean -- nothing on the LAN)"
echo

echo "=== sync log, last run ==="
tail -n 12 /home/mike/tailnet-ip-sync.log 2>/dev/null || echo "(no log yet)"
