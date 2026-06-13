# AGENTS.md — AI Agent Instructions

This file contains instructions and guardrails for AI agents working on this repository.
Read it fully before making any changes.

---

## What This Repo Does

A self-hosted WireGuard VPN on any Ubuntu server. It runs as a set of Docker containers
(wg-easy, nginx, certbot) managed by a single `docker-compose.yml`. A systemd
service updates Cloudflare DNS with the server's public IP on every boot, since
no static IP is used.

Mistakes here can cause loss of SSH access, exposed ports, broken VPN connectivity,
or a lapsed SSL certificate. Take extra care.

---

## File Responsibilities

| File | Purpose |
|---|---|
| `.env` | Secrets — never committed, never hardcoded anywhere |
| `.env.example` | Template for `.env` — only file with secret keys, no values |
| `docker-compose.yml` | Defines wg-easy, nginx, certbot containers and shared volumes |
| `nginx.conf` | Reverse proxy config — always the full HTTP + HTTPS version in the repo |
| `scripts/vpn-setup.sh` | First-time setup only — run once on a fresh server |
| `scripts/update-dns.sh` | Updates Cloudflare DNS and renews cert — runs on every boot |
| `scripts/update-dns.service` | systemd unit that triggers `update-dns.sh` on boot |

---

## Hard Rules — Never Violate These

- **Never remove or modify the `22/tcp` UFW rule.** Removing it locks the user out of SSH with no easy recovery path.
- **Never commit `.env`.** It contains secrets. It is in `.gitignore` for a reason.
- **Never hardcode secrets.** All sensitive values (API tokens, zone IDs, domain names) must come from `.env`.
- **Never expose port `51821` to the host** in `docker-compose.yml`. The wg-easy UI must only be accessible through nginx on port 443.
- **Never proxy the Cloudflare DNS record.** The orange cloud (proxied) mode blocks WireGuard traffic. The A record must always be grey cloud (DNS only).
- **Never remove the NAT MASQUERADE rule** from `/etc/ufw/before.rules`. Without it, Docker containers cannot reach the internet.
- **Never set `"iptables": true`** in `/etc/docker/daemon.json`. Docker would bypass UFW and expose container ports publicly.

---

## Important Conventions

### `.env` is the single source of truth for configuration
All scripts source `/opt/vpn/.env`. The systemd service loads it via `EnvironmentFile=`.
Docker Compose reads it automatically from the project directory.
If a new configurable value is needed, add it to both `.env.example` and source it from `.env` — never inline it.

### `nginx.conf` in the repo is always the full HTTPS version
During the cert bootstrap, `vpn-setup.sh` temporarily overwrites `nginx.conf` with
an HTTP-only version, then restores the full version after the cert is issued.
Do not commit the HTTP-only version — it is intentionally temporary.

### Docker network IPs are fixed
`wg-easy` is pinned to `10.42.42.42` on the internal Docker network.
The UFW MASQUERADE rule covers `172.16.0.0/12` which includes the Docker bridge subnet `172.17.0.0/16`.
If you change the network config, verify both the container IPs and the MASQUERADE subnet still align.

### Port 51820 is UDP
WireGuard traffic runs on `51820/udp`. Do not change it to TCP — WireGuard is UDP only.

---

## Safe Ways to Make Changes

### Changing nginx config
1. Edit `nginx.conf`
2. On the server: `docker compose -f /opt/vpn/docker-compose.yml exec nginx nginx -t` to validate
3. `docker compose -f /opt/vpn/docker-compose.yml restart nginx` to apply

### Changing docker-compose.yml
1. Validate the file: `docker compose -f /opt/vpn/docker-compose.yml config`
2. Apply: `docker compose -f /opt/vpn/docker-compose.yml up -d`

### Changing UFW rules
1. Always verify port 22 remains open before saving
2. Run `sudo ufw status` after changes to confirm the rule set is correct
3. Test SSH connectivity before closing the terminal session

### Updating the DNS script
1. After editing `scripts/update-dns.sh`, run it manually to verify: `bash /opt/vpn/scripts/update-dns.sh`
2. Check the log: `cat /var/log/update-dns.log`

---

## What To Do If Something Goes Wrong

| Problem | Safe recovery |
|---|---|
| nginx won't start | Check `docker logs nginx` — likely a bad `nginx.conf`. Restore last working version and restart. |
| SSL cert missing | Re-run the certbot bootstrap step from `vpn-setup.sh` manually |
| DNS not updating | Check `systemctl status update-dns.service` and `cat /var/log/update-dns.log` |
| Port 51821 exposed | Verify `daemon.json` has `"iptables": false` and restart Docker + reload UFW |
| Lost SSH access | Use your hosting provider's emergency console or out-of-band access as a fallback |

---

## Out of Scope

Do not make changes to:
- Hosting provider firewall rules (managed outside this repo in the provider's console)
- The WireGuard client configs (managed through the wg-easy UI)
- Server sizing or storage (managed in the provider's console)
- Cloudflare DNS record settings other than the A record content (managed in Cloudflare dashboard)
