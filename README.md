# Personal VPN — wg-easy + Cloudflare

A self-hosted WireGuard VPN running on any Ubuntu server, with:
- **wg-easy** for WireGuard management and web UI
- **nginx** as reverse proxy with Let's Encrypt SSL
- **Cloudflare** for dynamic DNS (no static IP needed)
- **UFW** firewall with Docker compatibility

Designed for on-demand use — start the server when needed, stop it when done.
DNS updates automatically on every boot via a systemd service.

---

## File Structure

```
vpn/
├── .env.example            # secrets template — copy to .env and fill in
├── .gitignore
├── docker-compose.yml      # wg-easy + nginx + certbot
├── nginx.conf              # reverse proxy config (full HTTPS version)
└── scripts/
    ├── vpn-setup.sh        # first-time setup — run once on a fresh server
    ├── update-dns.sh       # updates Cloudflare DNS with current public IP
    └── update-dns.service  # systemd service — runs update-dns.sh on every boot
```

---

## Prerequisites

- Any Ubuntu 24 server (VPS, cloud instance, bare metal)
- Domain managed on Cloudflare
- SSH access to the server
- Ports open in your provider's firewall: 22/tcp, 80/tcp, 443/tcp, 51820/udp

---

## First-Time Setup

### 1. Clone the repo

```bash
git clone <your_repo_url> /opt/vpn
```

### 2. Create and fill in `.env`

```bash
cp /opt/vpn/.env.example /opt/vpn/.env
nano /opt/vpn/.env
```

| Variable | Description |
|---|---|
| `DOMAIN` | Your VPN subdomain e.g. `vpn.yourdomain.com` |
| `EMAIL` | Email for Let's Encrypt notifications |
| `CF_API_TOKEN` | Cloudflare API token with *Edit zone DNS* permission |
| `CF_ZONE_ID` | Found on the Cloudflare dashboard for your domain |
| `CF_RECORD_ID` | See below |

**Getting your Cloudflare Record ID:**
```bash
curl -X GET "https://api.cloudflare.com/client/v4/zones/YOUR_ZONE_ID/dns_records?name=vpn.yourdomain.com" \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -H "Content-Type: application/json"
```
Copy the `id` field from the response.

**Cloudflare DNS record settings:**
- Type: `A`
- Name: `vpn` (or your subdomain)
- Proxy status: **grey cloud (DNS only)** — must NOT be proxied
- TTL: **1 minute**

### 3. Run the setup script

```bash
bash /opt/vpn/scripts/vpn-setup.sh
```

This will:
1. Update system packages
2. Install Docker
3. Configure Docker to respect UFW
4. Set up UFW firewall rules
5. Install and enable the DNS update systemd service
6. Update Cloudflare DNS with the current public IP
7. Bootstrap the Let's Encrypt certificate
8. Start all containers

---

## Daily Usage

### Start the VPN
1. Start your server from your provider's console
2. Wait ~2 minutes (boot + DNS propagation)
3. Connect your WireGuard client using `vpn.yourdomain.com`

### Access the web UI
```
https://vpn.yourdomain.com
```

### Stop the VPN
Stop the server from your provider's console when done.

---

## How It Works

### Dynamic DNS
On every boot, `update-dns.service` runs `update-dns.sh` which:
- Fetches the server's current public IP
- Updates the Cloudflare A record via API
- Renews the Let's Encrypt cert if within 30 days of expiry

### Networking
```
Client → vpn.yourdomain.com:443 → nginx → wg-easy:51821 (internal only)
Client → vpn.yourdomain.com:51820/udp → WireGuard
```

Port `51821` is never exposed to the host — only nginx can reach wg-easy internally via the Docker network.

### Docker + UFW
Docker bypasses UFW by default. This is fixed by:
- Setting `"iptables": false` in `/etc/docker/daemon.json`
- Adding a NAT MASQUERADE rule in `/etc/ufw/before.rules` so containers can still reach the internet

---

## Troubleshooting

**Can't connect after starting the server:**
- Wait 2 minutes for DNS propagation
- Check DNS updated: `dig vpn.yourdomain.com`
- Check service ran: `sudo systemctl status update-dns.service`
- Check log: `cat /var/log/update-dns.log`

**SSL cert errors:**
- Force renew: `sudo certbot renew --force-renewal`
- Check nginx: `docker logs nginx`

**wg-easy UI not loading:**
- Check containers: `docker compose -f /opt/vpn/docker-compose.yml ps`
- Check logs: `docker logs nginx` / `docker logs wg-easy`

**Port 51821 still accessible:**
- Verify Docker daemon config: `cat /etc/docker/daemon.json`
- Check UFW rules: `sudo ufw status`
- Restart Docker: `sudo systemctl restart docker && sudo ufw reload`
