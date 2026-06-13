#!/bin/bash
set -e

# =============================================================================
# VPN First-Time Setup Script
# AWS EC2 + wg-easy + nginx + certbot + Cloudflare DNS
# Run once after launching a fresh Ubuntu instance
#
# Usage:
#   1. Clone the repo: git clone <repo_url> /opt/vpn
#   2. Copy and fill in secrets: cp /opt/vpn/.env.example /opt/vpn/.env && nano /opt/vpn/.env
#   3. Run: bash /opt/vpn/scripts/vpn-setup.sh
# =============================================================================

REPO_DIR="/opt/vpn"
ENV_FILE="$REPO_DIR/.env"

log()  { echo -e "\n\033[1;32m>>> $1\033[0m"; }
err()  { echo -e "\n\033[1;31m[ERROR] $1\033[0m"; exit 1; }
info() { echo -e "    $1"; }

# --- 0. Validate .env exists and is filled in --------------------------------
log "Checking .env..."

[ -f "$ENV_FILE" ] || err ".env not found at $ENV_FILE\n    Run: cp $REPO_DIR/.env.example $ENV_FILE && nano $ENV_FILE"

source "$ENV_FILE"

[ -z "$DOMAIN" ]        && err "DOMAIN is not set in .env"
[ -z "$EMAIL" ]         && err "EMAIL is not set in .env"
[ -z "$CF_API_TOKEN" ]  && err "CF_API_TOKEN is not set in .env"
[ -z "$CF_ZONE_ID" ]    && err "CF_ZONE_ID is not set in .env"
[ -z "$CF_RECORD_ID" ]  && err "CF_RECORD_ID is not set in .env"

info "Domain:  $DOMAIN"
info "Email:   $EMAIL"

# --- 1. System update --------------------------------------------------------
log "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# --- 2. Install Docker -------------------------------------------------------
log "Installing Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    info "Docker installed. You may need to log out and back in for group changes."
else
    info "Docker already installed, skipping."
fi

# --- 3. Configure Docker to respect UFW --------------------------------------
log "Configuring Docker daemon (disable iptables)..."
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "iptables": false
}
EOF
sudo systemctl restart docker

# --- 4. UFW ------------------------------------------------------------------
log "Configuring UFW..."

UFW_BEFORE=/etc/ufw/before.rules
if ! grep -q "MASQUERADE" "$UFW_BEFORE"; then
    info "Adding NAT MASQUERADE rules to $UFW_BEFORE..."
    sudo sed -i '1s|^|# Allow Docker containers (172.16.0.0/12) to reach the internet through eth0.\n# Required because Docker bypasses UFW by default (iptables: false in daemon.json).\n# MASQUERADE rewrites container source IPs to the instance'"'"'s public IP on outbound traffic.\n*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 172.16.0.0/12 -o eth0 -j MASQUERADE\nCOMMIT\n\n|' "$UFW_BEFORE"
else
    info "MASQUERADE rule already exists, skipping."
fi

sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 51820/udp
sudo ufw --force enable
sudo ufw reload

# --- 5. Install update-dns script and systemd service ------------------------
log "Installing update-dns script and systemd service..."

sudo cp "$REPO_DIR/scripts/update-dns.sh" /opt/vpn/scripts/update-dns.sh
sudo chmod +x /opt/vpn/scripts/update-dns.sh

sudo cp "$REPO_DIR/scripts/update-dns.service" /etc/systemd/system/update-dns.service
sudo systemctl daemon-reload
sudo systemctl enable update-dns.service

# --- 6. Update Cloudflare DNS with current IP --------------------------------
log "Updating Cloudflare DNS with current public IP..."
bash /opt/vpn/scripts/update-dns.sh

# --- 7. Write temporary HTTP-only nginx.conf for cert bootstrap --------------
log "Writing temporary HTTP-only nginx.conf for certificate bootstrap..."
cat > "$REPO_DIR/nginx.conf" <<EOF
events {}

http {
    server {
        listen 80;
        server_name $DOMAIN;

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        location / {
            return 301 https://\$host\$request_uri;
        }
    }
}
EOF

# --- 8. Start nginx and wg-easy (HTTP only) ----------------------------------
log "Starting nginx and wg-easy..."
cd "$REPO_DIR"
docker compose up -d nginx wg-easy

log "Waiting for nginx to be ready..."
sleep 5

# --- 9. Issue Let's Encrypt certificate --------------------------------------
log "Issuing Let's Encrypt certificate for $DOMAIN..."
docker compose run --rm certbot certbot certonly \
    --webroot -w /var/www/certbot \
    -d "$DOMAIN" \
    --email "$EMAIL" \
    --agree-tos --no-eff-email

# --- 10. Restore full nginx.conf with HTTPS ----------------------------------
log "Restoring full nginx.conf with HTTPS..."
cat > "$REPO_DIR/nginx.conf" <<EOF
events {}

http {
    server {
        listen 80;
        server_name $DOMAIN;

        # Required for certbot HTTP challenge
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        # Redirect everything else to HTTPS
        location / {
            return 301 https://\$host\$request_uri;
        }
    }

    server {
        listen 443 ssl;
        server_name $DOMAIN;

        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

        location / {
            proxy_pass http://wg-easy:51821;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_cache_bypass \$http_upgrade;
        }
    }
}
EOF

# --- 11. Start all containers ------------------------------------------------
log "Starting all containers..."
docker compose up -d

# --- Done --------------------------------------------------------------------
echo ""
echo "=============================================="
echo " Setup complete!"
echo " wg-easy UI : https://$DOMAIN"
echo " WireGuard  : $DOMAIN:51820"
echo "=============================================="
