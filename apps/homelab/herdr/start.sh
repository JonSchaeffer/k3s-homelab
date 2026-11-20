#!/bin/sh
# Bootstraps a self-contained Herdr node: Tailscale (userspace, SSH enabled),
# herdr-core, and Oh My Pi. All state lives on the PVC via $HOME.
set -eu

if [ ! -x /usr/local/bin/tailscale ]; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
if [ ! -x /usr/local/bin/herdr-core ]; then
  curl -fsSL https://releases.herdr.dev/core/install.sh | HC_INSTALL_DIR=/usr/local/bin sh
fi

mkdir -p /var/lib/tailscale "$HOME/.config/herdr-core"

# userspace networking: no NET_ADMIN and no /dev/net/tun required.
# --ssh is what lets the Herdr phone app connect without an SSH key.
tailscaled \
  --tun=userspace-networking \
  --ssh \
  --state=/var/lib/tailscale/tailscaled.state \
  --socket=/tmp/tailscaled.sock \
  --port=41641 &

for _ in $(seq 1 30); do
  [ -S /tmp/tailscaled.sock ] && break
  sleep 1
done

if [ -n "${TS_AUTHKEY:-}" ]; then
  tailscale --socket=/tmp/tailscaled.sock up \
    --authkey="$TS_AUTHKEY" \
    --hostname=herdr \
    --ssh \
    --accept-routes=false || echo "tailscale up failed; check logs"
fi

# Keep the container alive; hc starts and daemonises its core on first use.
exec sleep infinity
