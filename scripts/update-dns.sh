#!/bin/bash
set -e

# Load environment variables
source /opt/vpn/.env

# Get current public IP
IP=$(curl -s https://api.ipify.org)

# Update Cloudflare A record
curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$CF_RECORD_ID" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$IP\",\"ttl\":60,\"proxied\":false}"

echo "$(date): Updated $DOMAIN to $IP" | sudo tee -a /var/log/update-dns.log > /dev/null

# Renew cert if within 30 days of expiry
certbot renew --quiet 2>/dev/null || true
