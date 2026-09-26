#!/usr/bin/env bash
# Install the TRUST faucet as a systemd service.
#
#   sudo ./install.sh
#   sudo nano /etc/trustville-faucet.env     # PRIVATE_KEY, FAUCET_CODE
#   sudo systemctl enable --now trustville-faucet
#   journalctl -fu trustville-faucet
#
# It listens on 127.0.0.1:8080 by default. Put nginx or a Cloudflare tunnel in front and
# point faucet.didlab.org at it -- the service does no TLS of its own, and Cloudflare is
# also where per-IP rate limiting belongs.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

id -u trustfaucet >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin trustfaucet

install -d -m 755 /opt/trustville-faucet
install -m 644 "$SRC/faucet.mjs" "$SRC/package.json" /opt/trustville-faucet/
( cd /opt/trustville-faucet && npm install --omit=dev --no-audit --no-fund )
chown -R trustfaucet:trustfaucet /opt/trustville-faucet

install -d -m 750 -o trustfaucet -g trustfaucet /var/lib/trustville-faucet

if [ ! -f /etc/trustville-faucet.env ]; then
  cat > /etc/trustville-faucet.env <<'EOF'
# The faucet's hot key. It can send TRUST and nothing else -- keep a SMALL balance in it
# and top it up, rather than funding it once and forgetting.
PRIVATE_KEY=

# Leave FAUCET_CODE empty for an open faucet. A shared course code is the cheapest gate
# that works: students have it, the open internet does not, and rotating it each term
# cancels last term's scripts.
FAUCET_CODE=

PORT=8080
RPC_URL=https://eth.didlab.org
EXPLORER_URL=https://explorer.didlab.org

DRIP_TRUST=1
COOLDOWN_HOURS=24
MAX_PER_IP_PER_DAY=3
MAX_TRUST_PER_DAY=50
ENOUGH_TRUST=0.5

# Optional Cloudflare Turnstile instead of, or as well as, the course code.
TURNSTILE_SECRET=

STATE_FILE=/var/lib/trustville-faucet/state.json
EOF
  chmod 600 /etc/trustville-faucet.env
  echo "created /etc/trustville-faucet.env -- put the faucet PRIVATE_KEY in it"
fi

install -m 644 "$HERE/trustville-faucet.service" /etc/systemd/system/
systemctl daemon-reload

cat <<'EOF'

Installed. Next:

  sudo nano /etc/trustville-faucet.env          # PRIVATE_KEY, and FAUCET_CODE if you want one
  sudo systemctl enable --now trustville-faucet
  curl -s localhost:8080/status | jq

Then fund the faucet address (shown by /status) with enough TRUST for a term, and point
faucet.didlab.org at 127.0.0.1:8080.
EOF
