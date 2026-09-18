#!/usr/bin/env bash
#
# Creates the dapp.didlab.org web host as a Proxmox VM, from nothing to a
# running nginx in one command. Run this ON THE PROXMOX HOST as root.
#
#   ./create-dapp-vm.sh                      # create with the defaults below
#   VMID=121 VM_IP=172.16.0.21/24 ./create-dapp-vm.sh
#   TUNNEL_TOKEN=eyJ... ./create-dapp-vm.sh  # also wire up the Cloudflare tunnel
#   ./create-dapp-vm.sh --force              # destroy an existing VMID and rebuild
#
# Every setting is an environment variable with a default; nothing is prompted,
# so the same command can be re-run or dropped into CI.
set -euo pipefail

# ----------------------------------------------------------------- settings
VMID="${VMID:-120}"
VM_NAME="${VM_NAME:-didlab-dapp}"
CORES="${CORES:-2}"
MEMORY_MB="${MEMORY_MB:-4096}"
DISK_SIZE="${DISK_SIZE:-32G}"
STORAGE="${STORAGE:-local-lvm}"          # where the VM disk lives
SNIPPET_STORAGE="${SNIPPET_STORAGE:-local}"  # must have the "snippets" content type
BRIDGE="${BRIDGE:-vmbr1}"
VLAN_TAG="${VLAN_TAG:-}"                 # empty = untagged
VM_IP="${VM_IP:-172.16.0.20/24}"         # static, matching didlab-app on 172.16.0.10
VM_GW="${VM_GW:-172.16.0.1}"
VM_DNS="${VM_DNS:-1.1.1.1 8.8.8.8}"
APP_USER="${APP_USER:-didlab}"
SSH_PUBKEY="${SSH_PUBKEY:-$HOME/.ssh/id_ed25519.pub}"
SITE_HOST="${SITE_HOST:-dapp.didlab.org}"
DAPP_REPO="${DAPP_REPO:-https://github.com/touidhasan/didlab-trustville.git}"
DAPP_BRANCH="${DAPP_BRANCH:-main}"
LAN_CIDR="${LAN_CIDR:-172.16.0.0/24}"
ENABLE_FIREWALL="${ENABLE_FIREWALL:-1}"
TUNNEL_TOKEN="${TUNNEL_TOKEN:-}"
DEPLOY_ON_BOOT="${DEPLOY_ON_BOOT:-1}"    # run dapp-deploy once cloud-init finishes
START_VM="${START_VM:-1}"
IMAGE_URL="${IMAGE_URL:-https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2}"
IMAGE_CACHE="${IMAGE_CACHE:-/var/lib/vz/template/cache}"

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --no-start) START_VM=0 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVISION="$SCRIPT_DIR/provision-dapp-host.sh"

die() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

# ---------------------------------------------------------------- preflight
step "checking the host"
[ "$(id -u)" -eq 0 ] || die "run this as root on the Proxmox host"
command -v qm >/dev/null || die "qm not found — this must run on a Proxmox VE host"
command -v pvesm >/dev/null || die "pvesm not found"
[ -f "$PROVISION" ] || die "missing $PROVISION (keep both scripts together)"
[ -f "$SSH_PUBKEY" ] || die "no SSH public key at $SSH_PUBKEY — set SSH_PUBKEY=/path/to/key.pub"

pvesm status --storage "$STORAGE" >/dev/null 2>&1 || die "storage '$STORAGE' not found (see: pvesm status)"
pvesm status --storage "$SNIPPET_STORAGE" >/dev/null 2>&1 || die "storage '$SNIPPET_STORAGE' not found"

# cloud-init user-data is passed as a snippet, which the storage must accept.
if ! pvesm status --content snippets 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$SNIPPET_STORAGE"; then
  die "storage '$SNIPPET_STORAGE' does not allow snippets.
     Fix: Datacenter > Storage > $SNIPPET_STORAGE > Content, tick 'Snippets'
     (or: pvesm set $SNIPPET_STORAGE --content snippets,iso,vztmpl,backup)"
fi

ip link show "$BRIDGE" >/dev/null 2>&1 || die "bridge '$BRIDGE' not found on this host"

if qm status "$VMID" >/dev/null 2>&1; then
  [ "$FORCE" -eq 1 ] || die "VM $VMID already exists — pass --force to destroy and rebuild it, or set VMID=<free id>"
  step "destroying existing VM $VMID (--force)"
  qm stop "$VMID" --skiplock 1 >/dev/null 2>&1 || true
  sleep 3
  qm destroy "$VMID" --purge 1 --destroy-unreferenced-disks 1
fi

# ------------------------------------------------------------- base image
step "fetching the Debian cloud image"
mkdir -p "$IMAGE_CACHE"
IMAGE_FILE="$IMAGE_CACHE/$(basename "$IMAGE_URL")"
if [ -s "$IMAGE_FILE" ]; then
  echo "using cached $IMAGE_FILE"
else
  curl -fSL --retry 3 -o "$IMAGE_FILE.part" "$IMAGE_URL" || die "download failed: $IMAGE_URL"
  mv "$IMAGE_FILE.part" "$IMAGE_FILE"
fi

# --------------------------------------------------------- cloud-init data
step "writing cloud-init user-data"
SNIPPET_DIR="$(pvesm path "${SNIPPET_STORAGE}:snippets/x" 2>/dev/null | xargs dirname || true)"
[ -n "$SNIPPET_DIR" ] || SNIPPET_DIR="/var/lib/vz/snippets"
mkdir -p "$SNIPPET_DIR"
USERDATA="$SNIPPET_DIR/${VM_NAME}-user-data.yaml"

PROVISION_B64="$(base64 -w0 "$PROVISION")"
SSH_KEY_LINE="$(cat "$SSH_PUBKEY")"

cat >"$USERDATA" <<YAML
#cloud-config
hostname: ${VM_NAME}
fqdn: ${SITE_HOST}
manage_etc_hosts: true
package_update: true

users:
  - name: ${APP_USER}
    groups: [sudo]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: true
    ssh_authorized_keys:
      - ${SSH_KEY_LINE}

ssh_pwauth: false
disable_root: true

write_files:
  - path: /root/provision-dapp-host.sh
    permissions: '0700'
    encoding: b64
    content: ${PROVISION_B64}

runcmd:
  - [ bash, -lc, "APP_USER='${APP_USER}' DAPP_REPO='${DAPP_REPO}' DAPP_BRANCH='${DAPP_BRANCH}' SITE_HOST='${SITE_HOST}' LAN_CIDR='${LAN_CIDR}' ENABLE_FIREWALL='${ENABLE_FIREWALL}' TUNNEL_TOKEN='${TUNNEL_TOKEN}' /root/provision-dapp-host.sh 2>&1 | tee /var/log/dapp-provision.log" ]
YAML

if [ "$DEPLOY_ON_BOOT" = "1" ]; then
  cat >>"$USERDATA" <<'YAML'
  - [ bash, -lc, "dapp-deploy >> /var/log/dapp-provision.log 2>&1 || echo 'first deploy failed — run: sudo dapp-deploy' >> /var/log/dapp-provision.log" ]
YAML
fi

echo "wrote $USERDATA"

# ------------------------------------------------------------- create VM
step "creating VM $VMID ($VM_NAME)"
NET="virtio,bridge=${BRIDGE}"
[ -n "$VLAN_TAG" ] && NET="${NET},tag=${VLAN_TAG}"

qm create "$VMID" \
  --name "$VM_NAME" \
  --cores "$CORES" \
  --cpu host \
  --memory "$MEMORY_MB" \
  --balloon 0 \
  --net0 "$NET" \
  --ostype l26 \
  --scsihw virtio-scsi-single \
  --agent enabled=1 \
  --serial0 socket \
  --vga serial0 \
  --description "Trustville dApp web host (${SITE_HOST}) — created by create-dapp-vm.sh"

step "importing the disk into $STORAGE"
# The volume id differs by storage type (local-lvm: vm-120-disk-0, directory:
# 120/vm-120-disk-0.raw), so take it from importdisk's own output.
IMPORT_OUT="$(qm importdisk "$VMID" "$IMAGE_FILE" "$STORAGE" 2>&1 | tee /dev/stderr)"
DISK_VOLID="$(printf '%s\n' "$IMPORT_OUT" | sed -n "s/.*as '\(unused[0-9]*:\)\?\([^']*\)'.*/\2/p" | tail -1)"
[ -n "$DISK_VOLID" ] || DISK_VOLID="${STORAGE}:vm-${VMID}-disk-0"
echo "disk volume: $DISK_VOLID"

qm set "$VMID" --scsi0 "${DISK_VOLID},discard=on,ssd=1" >/dev/null
# qm disk resize is PVE 7.1+; older releases use qm resize.
qm disk resize "$VMID" scsi0 "$DISK_SIZE" >/dev/null 2>&1 || qm resize "$VMID" scsi0 "$DISK_SIZE" >/dev/null
qm set "$VMID" --boot order=scsi0 >/dev/null

step "attaching cloud-init"
qm set "$VMID" --ide2 "${STORAGE}:cloudinit" >/dev/null
qm set "$VMID" --ciuser "$APP_USER" --sshkeys "$SSH_PUBKEY" >/dev/null
qm set "$VMID" --ipconfig0 "ip=${VM_IP},gw=${VM_GW}" >/dev/null
qm set "$VMID" --nameserver "$VM_DNS" >/dev/null
qm set "$VMID" --cicustom "user=${SNIPPET_STORAGE}:snippets/$(basename "$USERDATA")" >/dev/null
qm set "$VMID" --onboot 1 >/dev/null

if [ "$START_VM" != "1" ]; then
  echo; echo "VM $VMID created but not started (--no-start). Start it with: qm start $VMID"
  exit 0
fi

step "starting VM $VMID"
qm start "$VMID"

# --------------------------------------------------------------- wait + report
IP_ONLY="${VM_IP%%/*}"
step "waiting for the guest agent (first boot installs packages; ~2-4 minutes)"
for _ in $(seq 1 60); do
  if qm agent "$VMID" ping >/dev/null 2>&1; then
    echo "guest agent is up"
    break
  fi
  sleep 5
done

echo
echo "-------------------------------------------------------------"
echo " VM $VMID ($VM_NAME) is running"
echo " Address    : $IP_ONLY"
echo " SSH        : ssh ${APP_USER}@${IP_ONLY}"
echo " Site root  : /srv/www/current  (nginx)"
echo " Deploy     : sudo dapp-deploy [branch|tag]"
echo " Roll back  : sudo dapp-rollback"
echo " Setup log  : /var/log/dapp-provision.log  (and: cloud-init status --wait)"
echo
echo " Check it serves once provisioning finishes:"
echo "   curl -s http://${IP_ONLY}/healthz"
if [ -z "$TUNNEL_TOKEN" ]; then
  echo
  echo " Cloudflare tunnel is NOT configured yet. On the VM run:"
  echo "   sudo cloudflared service install <your-tunnel-token>"
  echo " then point the tunnel's ${SITE_HOST} hostname at http://localhost:80"
fi
echo "-------------------------------------------------------------"
