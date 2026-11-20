#!/usr/bin/env bash
# setup-nodebb-106.sh — installation de NodeBB dans le LXC 106 (forum-autonomie).
# À lancer en root DANS le conteneur :  pct enter 106  puis bash setup-nodebb-106.sh
# Idempotent sur les paquets ; l'étape 4 (setup NodeBB) est interactive, à faire une seule fois.

set -euo pipefail

if ! grep -q 'forum-autonomie' /etc/hostname 2>/dev/null; then
  echo "ERREUR : exécuter dans le LXC 106 (pct enter 106), pas sur l'hôte." >&2
  exit 1
fi

# --- 1. Paquets de base + Redis ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl git build-essential redis-server
systemctl enable --now redis-server

# --- 2. Node.js 20 (NodeSource ; le node de Debian 12 est trop ancien pour NodeBB v3) ---
if ! command -v node >/dev/null || ! node -v | grep -qE 'v(1[89]|2[0-9])\.'; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
node -v

# --- 3. NodeBB v3 dans /opt/nodebb ---
if [ ! -d /opt/nodebb ]; then
  git clone --branch v3.x --depth 1 https://github.com/NodeBB/NodeBB.git /opt/nodebb
fi
cd /opt/nodebb
./nodebb upgrade -mi   # installe dépendances npm sans démarrer

# --- 4. Configuration initiale (interactive, une seule fois) ---
# Répondre : URL = http://192.168.0.106:4567 ; host = 0.0.0.0 ; Redis par défaut ;
# admin : créer le compte administrateur (identifiant local, pas votre email réel).
echo ""
echo "=== Paquets et NodeBB installés. ==="
echo "=== Lancez maintenant :  cd /opt/nodebb && ./nodebb setup  ==="
echo "=== Réponses conseillées : URL http://192.168.0.106:4567, host 0.0.0.0, Redis par défaut. ==="
echo "=== Puis : ./nodebb start  (ou systemd, voir README). ==="
