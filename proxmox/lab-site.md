# Hosting lab.didlab.org

The course site is static, so it needs no new VM. It goes on **didlab-dapp**, beside
Trustville, as a second nginx server block behind the same Cloudflare tunnel.

One machine, two sites, one tunnel to keep alive. Adding a VM for a few megabytes of HTML
would be a second thing to patch, back up and forget about.

> **Check first.** `curl -sI https://lab.didlab.org` — if something already answers there,
> find out what it is before claiming the hostname. That mistake cost an evening with
> `faucet.didlab.org`, which turned out to be a service running since the start of the
> project with the town admin key inside it.

## 1. The deploy script

On **didlab-dapp**, as root:

```bash
cat > /usr/local/bin/lab-deploy <<'EOF'
#!/usr/bin/env bash
# Publish the prebuilt course site from the `labsite` branch as a new release.
# Build it on didlab-app first:  ./scripts/publish-labsite.sh
set -euo pipefail
source /etc/dapp.env                     # reuse DAPP_REPO

SRC=/opt/labsite/repo
BRANCH=labsite

if [ -d "$SRC/.git" ]; then
  git -C "$SRC" remote set-url origin "$DAPP_REPO"
  git -C "$SRC" fetch --prune origin "$BRANCH"
else
  mkdir -p "$(dirname "$SRC")"
  git clone --branch "$BRANCH" --single-branch "$DAPP_REPO" "$SRC"
fi
git -C "$SRC" checkout -q --detach "origin/$BRANCH"

[ -f "$SRC/index.html" ] || { echo "no index.html on $BRANCH — run publish-labsite.sh"; exit 1; }

SHA="$(git -C "$SRC" rev-parse --short HEAD)"
REL="/srv/lab-releases/$(date +%Y%m%d-%H%M%S)-$SHA"
mkdir -p "$REL"
cp -r "$SRC/." "$REL/"
rm -rf "$REL/.git"

nginx -t
ln -sfn "$REL" /srv/www/lab.new && mv -Tf /srv/www/lab.new /srv/www/lab
systemctl reload nginx

# Keep the last five releases so a rollback is always one symlink away.
ls -1dt /srv/lab-releases/* | tail -n +6 | xargs -r rm -rf
echo "deployed $BRANCH ($SHA) -> $REL"
EOF
chmod +x /usr/local/bin/lab-deploy
```

A `lab-rollback` is the same one-line symlink move as `dapp-rollback`; copy that script and
change the two paths.

## 2. nginx

```bash
cat > /etc/nginx/sites-available/lab <<'EOF'
server {
    listen 8081;
    server_name lab.didlab.org;
    root /srv/www/lab;
    index index.html;

    # VitePress emits hashed asset filenames, so they can be cached hard. HTML cannot.
    location ~* \.(js|css|woff2?|svg|png|jpg|webp)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    location / {
        try_files $uri $uri.html $uri/ /index.html;
        add_header Cache-Control "no-cache";
    }

    add_header X-Content-Type-Options nosniff;
    add_header Referrer-Policy strict-origin-when-cross-origin;
}
EOF
ln -sf /etc/nginx/sites-available/lab /etc/nginx/sites-enabled/lab
mkdir -p /srv/www /srv/lab-releases
nginx -t && systemctl reload nginx
```

Port 8081 because Trustville already has 80. The tunnel is what maps hostnames to ports,
so nothing here needs to be publicly reachable.

`try_files … /index.html` matters: VitePress uses clean URLs, so `/labs/lab-3-writing-transactions`
has to resolve without a trailing `.html`.

## 3. The tunnel route

In Cloudflare Zero Trust → Networks → Tunnels → the `dapp` tunnel → **Published application
routes**, add:

| | |
| --- | --- |
| Public hostname | `lab.didlab.org` |
| Service | `http://localhost:8081` |

No DNS record to create — the wildcard already covers it, and Universal SSL covers one
level of subdomain, which `lab.didlab.org` is.

## 4. Publish

On **didlab-app**:

```bash
cd ~/didlab-trustville
./scripts/publish-labsite.sh
```

On **didlab-dapp**:

```bash
sudo lab-deploy
curl -sI https://lab.didlab.org | head -3
```

## How this stays honest

The labs are built from `docs/` in the Trustville repository, in place. The file a student
reads at lab.didlab.org is the same file a contributor edits in the pull request that
changed the code it describes.

That is the whole reason for this arrangement. A course site with its own copy of the
instructions is wrong by week three, and wrong in the direction that wastes a room full of
people's time.

CI builds the site on every pull request with dead-link checking on, so a lab that points
at a renamed file fails the build instead of failing a student mid-assessment.

## When a second course needs a home here

Move `docs/.vitepress/` into a repository of its own and have it fetch each course's `docs/`
at build time. Do it then, not now — building a multi-course site for one course is how you
end up maintaining a framework instead of a course.
