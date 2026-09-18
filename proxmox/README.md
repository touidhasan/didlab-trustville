# Proxmox: the dapp.didlab.org web host

Two scripts create the VM that serves the site. `create-dapp-vm.sh` runs on the Proxmox
host; `provision-dapp-host.sh` is embedded into cloud-init and runs inside the new VM on
first boot. Keep both files together.

```
create-dapp-vm.sh        → qm create + cloud-init          (run as root on Proxmox)
provision-dapp-host.sh   → nginx, deploy tools, cloudflared (runs inside the VM)
```

## Run it

```bash
scp -r proxmox root@proxmox-host:/root/
ssh root@proxmox-host
cd /root/proxmox
./create-dapp-vm.sh
```

With the Cloudflare tunnel wired up in the same run:

```bash
TUNNEL_TOKEN=eyJhIjoi... ./create-dapp-vm.sh
```

## Defaults

| Variable | Default | Notes |
| --- | --- | --- |
| `VMID` | `120` | Refuses to touch an existing VM unless `--force` |
| `VM_NAME` | `didlab-dapp` | |
| `CORES` / `MEMORY_MB` / `DISK_SIZE` | `2` / `4096` / `32G` | A static site needs little; raise if you add services |
| `STORAGE` | `local-lvm` | Where the disk goes |
| `SNIPPET_STORAGE` | `local` | Must allow the **Snippets** content type |
| `BRIDGE` / `VLAN_TAG` | `vmbr1` / none | Same bridge as didlab-app |
| `VM_IP` / `VM_GW` | `172.16.0.20/24` / `172.16.0.1` | Static, beside didlab-app on .10 |
| `APP_USER` / `SSH_PUBKEY` | `didlab` / `~/.ssh/id_ed25519.pub` | Key-only login; passwords disabled |
| `DAPP_REPO` / `DAPP_BRANCH` | the public repo / `main` | What `dapp-deploy` pulls |
| `LAN_CIDR` / `ENABLE_FIREWALL` | `172.16.0.0/24` / `1` | ufw allows SSH + HTTP from the LAN only |
| `TUNNEL_TOKEN` | empty | Empty means install cloudflared but don't connect it |
| `DEPLOY_ON_BOOT` | `1` | Runs `dapp-deploy` once provisioning finishes |

Flags: `--force` (destroy and rebuild that VMID), `--no-start`, `--help`.

## What you get

- **Debian 12 cloud image**, cached in `/var/lib/vz/template/cache` so re-runs are fast.
- **nginx** serving `/srv/www/current`, an SPA fallback, one-year cache on `/assets/`,
  no-cache on `index.html`, and `/healthz`.
- **`dapp-deploy [branch|tag]`** — pulls the repo, copies its committed `dist/` into a new
  timestamped release, and swaps the symlink atomically. Visitors never see a half-written
  site. Keeps the last five releases; refuses to deploy if `dist/index.html` is missing.
- **`dapp-rollback`** — points back at the previous release in one command.
- **cloudflared**, connected if you passed a token.
- **ufw** allowing SSH and HTTP from your LAN only. The tunnel is an outbound connection,
  so nothing needs to be exposed to the internet.

## After it runs

```bash
ssh didlab@172.16.0.20
cloud-init status --wait          # provisioning finishes a minute or two after boot
curl -s http://172.16.0.20/healthz
sudo dapp-deploy                  # if DEPLOY_ON_BOOT was off, or to publish a new version
tail -f /var/log/dapp-provision.log
```

Then point the Cloudflare tunnel's `dapp.didlab.org` hostname at `http://localhost:80`.

## Notes

- No private keys belong on this VM. It serves static files and holds nothing that signs
  transactions. Contract deploys stay on your build machine.
- The site talks to `eth.didlab.org` from the student's browser, not from this VM, so the
  VM needs no access to the chain.
- Deploying the same commit twice creates a second release directory; that is intentional,
  so a re-deploy is always a clean copy.
