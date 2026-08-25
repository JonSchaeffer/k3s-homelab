#!/bin/sh
set -eu

NS="${NAMESPACE:-homelab}"
REGION="${PIA_REGION:-us_chicago}"
SECRET="qbittorrent-vpn-secret"
DEPLOY="qbittorrent"

: "${PIA_USER:?PIA_USER is required}"
: "${PIA_PASS:?PIA_PASS is required}"

log() { echo "[$(date -Iseconds)] $*"; }

log "refreshing PIA WireGuard config for region=$REGION"

# 1. PIA's own CA certificate (verifies the WireGuard API TLS identity)
curl -fsSL -o /tmp/ca.rsa.4096.crt \
  https://raw.githubusercontent.com/pia-foss/manual-connections/master/ca.rsa.4096.crt

# 2. Server list (strip PIA's trailing signature blob)
curl -fsSL "https://serverlist.piaservers.net/vpninfo/servers/v4" \
  | tr -d '\n' | sed 's/\(.*\}\).*/\1/' > /tmp/servers.json

WG_IP=$(jq -r --arg r "$REGION" '.regions[] | select(.id==$r) | .servers.wg[0].ip' /tmp/servers.json)
WG_CN=$(jq -r --arg r "$REGION" '.regions[] | select(.id==$r) | .servers.wg[0].cn' /tmp/servers.json)
if [ -z "$WG_IP" ] || [ "$WG_IP" = "null" ]; then
  log "ERROR: region '$REGION' not found in PIA server list" >&2
  exit 1
fi
log "selected $REGION WireGuard server: $WG_CN ($WG_IP)"

# 3. Auth token
TOKEN=$(curl -fsS -X POST 'https://www.privateinternetaccess.com/api/client/v2/token' \
  --form "username=$PIA_USER" --form "password=$PIA_PASS" | jq -r '.token')
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  log "ERROR: PIA authentication failed" >&2
  exit 1
fi
log "authenticated"

# 4. Ephemeral WireGuard keypair
PRIV=$(wg genkey)
PUB=$(printf '%s\n' "$PRIV" | wg pubkey)

# 5. Register the public key, get connection details
RESP=$(curl -fsS -G --connect-to "$WG_CN::$WG_IP:" --cacert /tmp/ca.rsa.4096.crt \
  --data-urlencode "pt=$TOKEN" --data-urlencode "pubkey=$PUB" \
  "https://$WG_CN:1337/addKey")

if [ "$(echo "$RESP" | jq -r '.status')" != "OK" ]; then
  log "ERROR: addKey failed: $RESP" >&2
  exit 1
fi

SERVER_KEY=$(echo "$RESP" | jq -r '.server_key')
SERVER_IP=$(echo "$RESP" | jq -r '.server_ip')
SERVER_PORT=$(echo "$RESP" | jq -r '.server_port')
PEER_IP=$(echo "$RESP" | jq -r '.peer_ip')
DNS=$(echo "$RESP" | jq -r '.dns_servers[0]')

# 6. Atomically update the secret
kubectl -n "$NS" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET
  namespace: $NS
type: Opaque
stringData:
  WIREGUARD_PRIVATE_KEY: "$PRIV"
  WIREGUARD_PUBLIC_KEY: "$SERVER_KEY"
  WIREGUARD_ENDPOINT_IP: "$SERVER_IP"
  WIREGUARD_ENDPOINT_PORT: "$SERVER_PORT"
  WIREGUARD_ADDRESSES: "$PEER_IP/32"
  DNS_ADDRESS: "$DNS"
EOF
log "updated secret $SECRET"

# 7. Restart so gluetun picks up the new config
kubectl -n "$NS" rollout restart deployment "$DEPLOY"
log "restarted deployment $DEPLOY"

log "OK: $REGION -> $SERVER_IP (peer $PEER_IP)"
