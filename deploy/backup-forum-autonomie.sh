#!/usr/bin/env bash
# backup-forum-autonomie.sh - sauvegarde quotidienne forum-autonomie
# A executer sur le hotes Proxmox (root). Installe par /etc/cron.d.
set -uo pipefail

DIR=/var/backups/forum-autonomie
DATE=$(date +%F)
mkdir -p "$DIR"

echo "== Sauvegarde du $DATE =="

# Redis du forum : flush propre sans arreter nodebb (SAVE bloquant court)
pct exec 106 -- redis-cli save > /dev/null
pct exec 106 -- cat /var/lib/redis/dump.rdb > "$DIR/redis-dump.$DATE.rdb"

# Config et upload NodeBB
pct exec 106 -- cat /opt/nodebb/config.json > "$DIR/nodebb-config.json.$DATE"
pct exec 106 -- tar czf - -C /opt/nodebb uploads > "$DIR/nodebb-uploads.$DATE.tar.gz"

# FreshRSS : data complet (sqlite + config + users + extensions)
pct exec 107 -- tar czf - -C /usr/share/FreshRSS data > "$DIR/freshrss-data.$DATE.tar.gz"

# Journal de restauration toujours a jour
cp /root/backup-forum-autonomie.sh "$DIR/" 2> /dev/null || true
curl -fsSL -o "$DIR/REINSTALL.md" https://raw.githubusercontent.com/jmdondez-web/forum-autonomie/main/docs/REINSTALL.md 2> /dev/null || true

# Retention : 45 jours
find "$DIR" -name "redis-dump.*" -mtime +45 -delete
find "$DIR" -name "nodebb-*" -mtime +45 -delete
find "$DIR" -name "freshrss-*" -mtime +45 -delete

echo "== Termine =="
ls -lh "$DIR" | tail -6