# Homelab: Ubuntu Server with Docker

## The idea

I had an old PC I built back in 2016 sitting unused. Rather than let it gather dust I decided to repurpose it as a home server. The goal was practical: learn Linux properly, get hands-on with Docker outside of a GUI, and run some useful services at home. It turned out to be one of the most useful things I've done for my technical development.

---

## Hardware

A self-built PC from 2016, repurposed as a headless Ubuntu Server. Running 24/7 on the home network at 192.168.1.10.

---

## What's running

| Container | Purpose | Port |
|-----------|---------|------|
| qBittorrent | Download client | 8080 |
| Gluetun | WireGuard VPN tunnel (Mullvad) | - |
| Jellyfin | Media server | 8096 |
| AdGuard Home | Network-wide DNS ad blocking | 3000 / 53 |
| Tailscale | Remote access | - |
| Netdata | System monitoring | 19999 |
| Portainer | Container management UI | 9000 |
| Watchtower | Automated container updates | - |

---

## Architecture

The setup is split into distinct network stacks, which was a deliberate decision to keep services isolated from each other.

The download client runs inside a dedicated Docker network called vpn_net, alongside the Gluetun container which handles the WireGuard VPN tunnel. Any traffic from the download client is forced through Gluetun before it reaches the internet. If the VPN drops, the traffic stops. This is sometimes called a kill switch pattern and it was one of the trickier parts of the setup to get right.

Jellyfin runs on the standard bridge network and reads media from a shared volume at /movies, which the download client writes to at /downloads. The two containers never talk directly to each other but share the filesystem, which keeps things clean.

AdGuard Home handles DNS for the entire network, blocking ads and trackers at the DNS level before they reach any device. The Tenda MX12 router is pointed at 192.168.1.10 as primary DNS with 1.1.1.1 as a fallback in case the server is offline.

Tailscale provides remote access, allowing me to connect back into the home network securely when away. In practice I use this to run updates and manage containers remotely, and to access Jellyfin when I'm not at home.

Netdata and Portainer sit on top of everything as management tools. Netdata gives real-time visibility into system health and resource usage. Portainer provides a web UI for managing all the containers without needing to SSH in every time.

Watchtower runs on a one hour scan cycle and automatically updates any containers where a newer image is available, keeping the stack current without manual intervention.

![Homelab Architecture](screenshots/homelab-architecture.png)

---

## How it came together

The initial server setup and core containers took around five and a half hours. Getting the VPN routing working came about a week later and took another two hours on top of that.

I came into this having only used Docker through a GUI previously. Doing everything in Linux via the command line was a step up. The Gluetun container in particular took a lot of attempts to get right. Getting the networking configured so that the download client's traffic was actually routing through the VPN rather than around it wasn't obvious and required a fair bit of troubleshooting. AI helped me work through the configuration once I understood what I was actually trying to achieve.

---

## Improvements and updates

### Tailscale Magic DNS

After getting Tailscale working for remote access I looked into making it easier to reach services without having to remember IP addresses and port combinations. One option was to buy a domain name and set up DNS records pointing to each service, something like jellyfin.mchomeserver.com. But a free option already existed within Tailscale itself.

Enabling Magic DNS in the Tailscale settings automatically assigns a DNS name to each device on the Tailscale network based on the device name. So instead of connecting to 192.168.1.10:8096 for Jellyfin, I can now use mchomeserver:8096 which is much more practical, especially when accessing multiple services remotely.

### DNS resolution issue after enabling Magic DNS

After enabling Magic DNS, running sudo apt update on the server produced a series of warnings and package updates failed. Pinging 8.8.8.8 by IP worked fine, but pinging google.com by hostname failed. This pointed to a DNS resolution problem rather than a network connectivity issue.

The cause was that Magic DNS had taken over all DNS queries on the server and was routing them through Tailscale's resolver at 100.100.100.100. When Tailscale couldn't resolve an external hostname it had no fallback to reach public DNS servers.

The fix was to add global nameservers in the Tailscale DNS settings alongside Magic DNS. DNS queries now go to Tailscale's 100.100.100.100 first, with Google (8.8.8.8) and Cloudflare (1.1.1.1) as fallbacks. Package updates and general internet connectivity from the server have worked correctly since.

### Automated OS updates with unattended-upgrades

Configured unattended-upgrades on Ubuntu to automatically apply security and package updates daily. Manual reboots are handled separately and done periodically when convenient rather than automatically, to avoid unexpected downtime.

When updates are applied an email notification is sent via msmtp using a Gmail account. This means I get confirmation of what was updated without having to log in and check manually.

### Automated container updates with Watchtower

Watchtower is a container that monitors all other running containers and automatically pulls and applies updated images when they become available. It runs on a one hour scan cycle.

Like unattended-upgrades, Watchtower sends an email notification via msmtp and Gmail whenever a container image is updated. Both notification systems were tested and confirmed working before being left to run.

The combination of unattended-upgrades and Watchtower means both the underlying OS and the container stack stay current automatically. The email notifications provide visibility without requiring manual checks.

### Watchtower scanning fix

About a week after setting up Watchtower, checking the logs revealed it was running scans every hour as expected but reporting `Scanned=0` each time. The logs showed it was running with both label filtering and a scope restriction:

```
Only checking containers using enable label, in scope "mike"
```

The containers had the enable label set correctly:

```
com.centurylinklabs.watchtower.enable=true
```

But they were missing the required scope label:

```
com.centurylinklabs.watchtower.scope=mike
```

Because the scope label was absent, Watchtower ignored all containers entirely despite the enable label being present.

The fix was to remove the scope restriction (`--scope mike`) from the Watchtower configuration so it filters by the enable label only. A manual scan was then triggered to verify:

```bash
docker exec watchtower /watchtower --run-once
```

After the change Watchtower successfully scanned all running containers and sent notification emails reporting available updates for Portainer and AdGuard Home, confirming that both container discovery and notifications are working correctly.

### Replacing Pi-hole with AdGuard Home

Pi-hole was the original choice for network-wide DNS ad blocking. The web UI was accessible and the container ran without issues, but two problems prevented it from working properly. The password configuration was not saving correctly, and pointing the Tenda MX12 mesh router to use it as the primary DNS server consistently failed. Research suggested AdGuard Home tends to work more reliably with this router, so the decision was made to switch rather than continue troubleshooting.

The AdGuard Home container was up and running in under ten minutes. Initial testing was done by manually changing the DNS settings on an iPhone rather than at the router level, which allowed testing without affecting the rest of the network.

During testing an issue came up where ads were only being blocked when not connected to Tailscale VPN. Disabling the VPN and testing confirmed the blocking worked correctly without it, which pinpointed Tailscale as the cause rather than AdGuard itself. The fix was to add the server IP to the DNS namespace in the Tailscale settings, which meant AdGuard was used as the DNS server regardless of whether Tailscale was active or not. AI helped confirm the fix once the cause had been identified through testing.

With that resolved, the Tenda MX12 router was pointed to 192.168.1.10 as the primary DNS server. This required accessing the router settings through the iPhone app rather than the browser-based interface, which didn't expose the relevant setting. With the router change in place, all devices on the network now route DNS queries through AdGuard Home automatically.

The impact was visible immediately. Visiting ad-heavy sites like speedtest.net showed noticeably fewer adverts, and the AdGuard dashboard confirmed DNS queries coming through from devices across the network.

![AdGuard Home dashboard showing DNS queries and blocked requests](screenshots/adguard-dashboard.png)

---

## What hasn't worked yet

### Backups to OneDrive

Getting automated backups to OneDrive has been the most stubborn problem so far and two attempts have failed.

The first attempt used Duplicati but failed at the initial login step as the password setup for the web UI couldn't be completed.

The second attempt was more ambitious. A fully containerised backup solution using restic with rclone to back up docker-compose files and other key server configs to OneDrive on a nightly schedule with 14-day retention. In practice several things blocked a reliable setup. Mounting the rclone configuration into the container failed due to relative paths and permissions issues. Installing rclone at runtime inside the Alpine-based restic container proved unreliable and produced repeated executable not found errors. Headless OneDrive authentication also required an external device which added friction, and mounting host binaries into the container created further complexity. After repeated troubleshooting the setup was reverted to its original state.

The exercise was useful despite failing. It highlighted specific pitfalls around containerised backups to cloud providers: headless OAuth authentication is genuinely awkward, Alpine-based containers need careful handling for runtime installs, and file system permissions between host and container need explicit attention. A working solution is still the goal and the next attempt will be informed by what went wrong here.

---

## What I learned

Running Docker properly in Linux is meaningfully different from using it through a GUI. Writing and editing docker-compose files directly, understanding how container networking actually works, and debugging why a container won't start are all skills that don't translate from clicking around a UI.

The VPN routing setup gave me a real understanding of Docker network isolation. The whole point of vpn_net is that containers on it can only reach the outside world through Gluetun. If that container goes down, the others on that network lose internet access entirely. Understanding why that works requires understanding how Docker handles routing between networks, which is directly applicable to the AWS networking concepts I'm covering in the SAA course.

The Magic DNS issue and the AdGuard/Tailscale conflict were both good examples of how changes in one part of a system can have unexpected effects elsewhere. In both cases the diagnostic approach was the same: isolate the variable, test with it removed, and confirm the theory before applying a fix. That approach works whether you're troubleshooting a home server or a production environment.

Tailscale is genuinely impressive for remote access. It uses a mesh VPN approach where devices connect directly to each other rather than through a central server. Setting it up took about ten minutes and it just works. Magic DNS builds on top of that to make day to day use much more practical.

---

### Hardware upgrade: PWM fans and thermal management

The original 2016 hardware had three fans (two case fans and one CPU fan) that ran at 100% constantly. This was loud and drawing more power than necessary for a server sitting at low load most of the time.

Three PWM fans were purchased and installed, two at the front as intake and one at the rear as exhaust. The original CPU fan was kept as it was already PWM rated.

Fan curves were then configured in Linux using fan control software, which brought idle noise and power draw down significantly. The CPU fan didn't show up when running lm-sensors, and research suggests the BIOS is likely managing that curve directly without exposing it to the OS. That's something to revisit another time.

---

## What's next

- Find a working backup solution to OneDrive
- Document the docker-compose files for each stack
- Revisit CPU fan curve, currently managed by BIOS and not visible to lm-sensors
- Upgrade OS and Docker storage from HDD to SSD including drive cloning and migration

---

## Skills this covers

Linux server administration, Docker, container networking, VPN configuration, DNS troubleshooting, remote access, system monitoring, automated patching, infrastructure observability, and systematic fault isolation. Most of these map directly onto the containerisation, networking, and operational topics coming up in the AWS portion of my learning.
