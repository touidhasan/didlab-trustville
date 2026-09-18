#!/usr/bin/env bash
# Runs INSIDE the new VM on first boot (cloud-init embeds this file).
# Turns a plain Debian cloud image into the dapp.didlab.org web host:
# nginx serving atomic releases, a git-based deploy command, and cloudflared.
set -euo pipefail

APP_USER="${APP_USER:-didlab}"
DAPP_REPO="${DAPP_REPO:-https://github.com/touidhasan/didlab-trustville.git}"
DAPP_BRANCH="${DAPP_BRANCH:-main}"
SITE_HOST="${SITE_HOST:-dapp.didlab.org}"
LAN_CIDR="${LAN_CIDR:-172.16.0.0/24}"
ENABLE_FIREWALL="${ENABLE_FIREWALL:-1}"
TUNNEL_TOKEN="${TUNNEL_TOKEN:-}"

log() { echo "[provision] $*"; }

export DEBIAN_FRONTEND=noninteractive
log "installing packages"
apt-get update -qq
apt-get install -y -qq nginx git rsync curl ca-certificates qemu-guest-agent unattended-upgrades ufw

install -d -o "$APP_USER" -g "$APP_USER" /opt/dapp /srv/releases /srv/www

# ---------------------------------------------------------------- deploy tool
cat >/usr/local/bin/dapp-deploy <<'DEPLOY'
#!/usr/bin/env bash
# Pull the repo and publish its prebuilt dist/ as a new release.
# Usage: dapp-deploy [git-ref]     (default: the configured branch)
set -euo pipefail
source /etc/dapp.env

REF="${1:-$DAPP_BRANCH}"
SRC=/opt/dapp/repo

if [ -d "$SRC/.git" ]; then
  git -C "$SRC" remote set-url origin "$DAPP_REPO"
  git -C "$SRC" fetch --tags --prune origin
else
  git clone "$DAPP_REPO" "$SRC"
  git -C "$SRC" fetch --tags --prune origin
fi

# A ref may be a branch (use the remote's tip) or a tag/commit.
if git -C "$SRC" rev-parse --verify --quiet "origin/$REF" >/dev/null; then
  git -C "$SRC" checkout -q --detach "origin/$REF"
else
  git -C "$SRC" checkout -q --detach "$REF"
fi

SHA="$(git -C "$SRC" rev-parse --short HEAD)"
[ -f "$SRC/dist/index.html" ] || {
  echo "dist/index.html missing at $REF — run 'npm run build' and commit dist/ before deploying" >&2
  exit 1
}

REL="/srv/releases/$(date +%Y%m%d-%H%M%S)-$SHA"
rm -rf "$REL"
cp -a "$SRC/dist" "$REL"
ln -sfn "$REL" /srv/www/current.new
mv -Tf /srv/www/current.new /srv/www/current      # atomic swap; no half-served site
nginx -t && systemctl reload nginx

# keep the five most recent releases so a rollback is always one command away
ls -1dt /srv/releases/* | tail -n +6 | xargs -r rm -rf
echo "deployed $REF ($SHA) -> $REL"
DEPLOY
chmod +x /usr/local/bin/dapp-deploy

cat >/usr/local/bin/dapp-rollback <<'ROLLBACK'
#!/usr/bin/env bash
# Point the site at the previous release. Usage: dapp-rollback [release-dir]
set -euo pipefail
TARGET="${1:-$(ls -1dt /srv/releases/* | sed -n 2p)}"
[ -d "$TARGET" ] || { echo "no release to roll back to" >&2; exit 1; }
ln -sfn "$TARGET" /srv/www/current.new
mv -Tf /srv/www/current.new /srv/www/current
nginx -t && systemctl reload nginx
echo "now serving $TARGET"
ROLLBACK
chmod +x /usr/local/bin/dapp-rollback

cat >/etc/dapp.env <<ENV
DAPP_REPO="$DAPP_REPO"
DAPP_BRANCH="$DAPP_BRANCH"
SITE_HOST="$SITE_HOST"
ENV

# ---------------------------------------------------------------------- nginx
rm -f /etc/nginx/sites-enabled/default
cat >/etc/nginx/sites-available/dapp <<NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $SITE_HOST _;

    root /srv/www/current;
    index index.html;

    # The site is static files only — no app process, no database, no keys here.
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Vite writes content-hashed filenames, so assets can be cached forever.
    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    # index.html must never be cached, or a deploy looks like it did nothing.
    location = /index.html {
        add_header Cache-Control "no-cache";
    }

    location = /healthz {
        access_log off;
        default_type text/plain;
        return 200 "ok\n";
    }

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    gzip on;
    gzip_types text/plain text/css application/javascript application/json image/svg+xml;
    gzip_min_length 1024;

    client_max_body_size 4m;
}
NGINX
ln -sf /etc/nginx/sites-available/dapp /etc/nginx/sites-enabled/dapp

# A placeholder release so nginx has a document root before the first deploy.
PLACEHOLDER=/srv/releases/00000000-000000-placeholder
install -d "$PLACEHOLDER"
cat >"$PLACEHOLDER/index.html" <<'HTML'
<!doctype html><meta charset="utf-8"><title>Trustville — not deployed yet</title>
<style>body{font:16px/1.6 system-ui;margin:12vh auto;max-width:34rem;padding:0 1rem;color:#1b2233}
code{background:#f1efe9;padding:2px 6px;border-radius:4px}</style>
<h1>Host is ready</h1>
<p>No release deployed yet. On this VM run <code>sudo dapp-deploy</code>.</p>
HTML
ln -sfn "$PLACEHOLDER" /srv/www/current

nginx -t
systemctl enable --now nginx
systemctl restart nginx

# ----------------------------------------------------------------- cloudflared
log "installing cloudflared"
ARCH="$(dpkg --print-architecture)"
if curl -fsSL -o /tmp/cloudflared.deb \
  "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"; then
  apt-get install -y -qq /tmp/cloudflared.deb || log "cloudflared package install failed"
  rm -f /tmp/cloudflared.deb
  if [ -n "$TUNNEL_TOKEN" ]; then
    cloudflared service install "$TUNNEL_TOKEN"
    systemctl enable --now cloudflared
    log "cloudflared running — point the tunnel's public hostname at http://localhost:80"
  else
    log "no tunnel token given; run 'sudo cloudflared service install <token>' later"
  fi
else
  log "could not download cloudflared — install it manually"
fi

# -------------------------------------------------------------------- firewall
if [ "$ENABLE_FIREWALL" = "1" ]; then
  log "configuring ufw (ssh + http from $LAN_CIDR only; the tunnel is outbound)"
  ufw --force reset >/dev/null
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow from "$LAN_CIDR" to any port 22 proto tcp
  ufw allow from "$LAN_CIDR" to any port 80 proto tcp
  ufw --force enable
fi

systemctl enable --now qemu-guest-agent || true
log "done — site root /srv/www/current, deploy with: sudo dapp-deploy"
