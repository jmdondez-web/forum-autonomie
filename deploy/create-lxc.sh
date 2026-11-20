#!/usr/bin/env bash
# create-lxc.sh — création des LXC manquants sur l'hôte Proxmox VE.
# LXC 104 : trading bot (vmbr1) — LXC 106 : forum-autonomie (vmbr0) — LXC 107 : veille-ia (vmbr0)
# Usage : en root sur l'hôte :  bash create-lxc.sh          (crée 106 et 107)
#                                       bash create-lxc.sh 104|106|107   (un seul)
# Idempotent : un LXC existant est ignoré, avec message.

set -euo pipefail

# --- Paramètres réseau : ajustez ici si votre passerelle diffère ---
GW_VMBR0="192.168.0.1"
GW_VMBR1="192.168.1.1"
DNS="8.8.8.8 1.1.1.1"
ROOTFS_STORAGE="local-lvm"   # stockage rootfs (local-lvm = data sur pve)
DISK_GB=8

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERREUR : lancer en root sur l'hôte Proxmox." >&2
  exit 1
fi

# --- Template Debian 12 : téléchargé si absent ---
find_template() {
  pveam list local 2>/dev/null | awk '/debian-12-standard/ {print $1; exit}'
}

TEMPLATE="$(find_template)"
if [[ -z "$TEMPLATE" ]]; then
  echo "Template Debian 12 absent : téléchargement..."
  pveam update
  pveam download local debian-12-standard
  TEMPLATE="$(find_template)"
  if [[ -z "$TEMPLATE" ]]; then
    echo "ERREUR : impossible d'obtenir le template Debian 12." >&2
    exit 1
  fi
fi
echo "Template : $TEMPLATE"

# --- Création d'un LXC si l'ID n'existe pas déjà ---
create_ct() {
  local id="$1" hostname="$2" bridge="$3" ip="$4" gw="$5" mem="$6" swap="$7" cores="$8"
  if pct status "$id" &>/dev/null; then
    echo "LXC $id ($hostname) existe déjà — ignoré."
    return 0
  fi
  echo "Création LXC $id ($hostname) — IP $ip sur $bridge..."
  # shellcheck disable=SC2086
  pct create "$id" "$TEMPLATE" \
    --hostname "$hostname" \
    --memory "$mem" --swap "$swap" \
    --cores "$cores" \
    --rootfs "${ROOTFS_STORAGE}:${DISK_GB}" \
    --net0 "name=eth0,bridge=${bridge},ip=${ip},gw=${gw}" \
    --nameserver "$DNS" \
    --unprivileged 1 \
    --features nesting=1 \
    --start 0
  pct start "$id"
  sleep 3
  pct exec "$id" -- bash -c 'cat /etc/resolv.conf && ip -4 addr show eth0 | grep inet'
  echo "LXC $id ($hostname) créé et démarré : $ip"
}

# --- LXC 104 : trading bot ---
create_104() {
  create_ct 104 tradingbot vmbr1 192.168.1.104/24 "$GW_VMBR1" 1024 512 1
  if ! pct exec 104 -- id -u worff &>/dev/null; then
    pct exec 104 -- useradd -m -s /bin/bash worff
  fi
  echo "104 : utilisateur 'worff' créé si absent. Suite : voir trading_bot/deploy/README_LXC.md (étapes 2 à 4)."
}

# --- LXC 106 : forum-autonomie ---
create_106() {
  create_ct 106 forum-autonomie vmbr0 192.168.0.106/24 "$GW_VMBR0" 1024 512 1
  echo "106 : suite selon phasage P0 — installer Flarum ou NodeBB + Nginx."
}

# --- LXC 107 : veille-ia ---
create_107() {
  create_ct 107 veille-ia vmbr0 192.168.0.107/24 "$GW_VMBR0" 1024 512 1
  echo "107 : suite selon phasage P1 — FreshRSS, puis P2 — n8n."
}

TARGET="${1:-all}"
case "$TARGET" in
  104) create_104 ;;
  106) create_106 ;;
  107) create_107 ;;
  all) create_106; create_107 ;;
  *) echo "Usage : bash create-lxc.sh [104|106|107]" >&2; exit 1 ;;
esac

echo "Terminé. Vérification : pct list"
