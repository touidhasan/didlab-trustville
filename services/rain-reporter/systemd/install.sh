#!/usr/bin/env bash
# Install the rain reporters as systemd services, one per station.
#
#   sudo ./install.sh north east west
#
# Then put each station's key in its own file and start it:
#
#   sudo install -m 600 /dev/null /etc/rain-reporter/north.env
#   sudo nano /etc/rain-reporter/north.env       # PRIVATE_KEY=0x...
#   sudo systemctl enable --now rain-reporter@north
#
# Watch them:  journalctl -fu 'rain-reporter@*'
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
[ $# -ge 1 ] || { echo "usage: $0 <station> [station...]"; exit 1; }

id -u rainreporter >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin rainreporter

install -d -m 755 /opt/rain-reporter
install -m 644 "$SRC/reporter.mjs" "$SRC/package.json" /opt/rain-reporter/

# Installed outside the repo, the script cannot find deployments/252501.json by walking
# up, so the oracle address is pinned into each station's env file instead. Read it here,
# once, from the repo this was installed from.
ORACLE_ADDR=""
if [ -f "$SRC/../../deployments/252501.json" ]; then
  ORACLE_ADDR="$(python3 -c "import json;print(json.load(open('$SRC/../../deployments/252501.json'))['contracts'].get('RainOracle',''))")"
fi
[ -n "$ORACLE_ADDR" ] || echo "warning: no RainOracle in deployments — set ORACLE in each env file by hand"

( cd /opt/rain-reporter && npm install --omit=dev --no-audit --no-fund )
chown -R rainreporter:rainreporter /opt/rain-reporter

install -d -m 750 /etc/rain-reporter
install -m 644 "$HERE/rain-reporter@.service" /etc/systemd/system/
systemctl daemon-reload

for station in "$@"; do
  env_file="/etc/rain-reporter/$station.env"
  if [ ! -f "$env_file" ]; then
    printf '# %s station\nPRIVATE_KEY=\nORACLE=%s\n# DROUGHT=1\n# LIE=9000\n' "$station" "$ORACLE_ADDR" > "$env_file"
    chmod 600 "$env_file"
    echo "created $env_file — put this station's PRIVATE_KEY in it"
  fi
done

cat <<'EOF'

Installed. For each station:

  sudo nano /etc/rain-reporter/<station>.env        # set PRIVATE_KEY
  sudo systemctl enable --now rain-reporter@<station>

  journalctl -fu 'rain-reporter@*'                  # watch all of them

Each key needs TRUST for gas and REPORTER_ROLE on the oracle. The service exits
immediately and says which is missing if either is not in place.
EOF
