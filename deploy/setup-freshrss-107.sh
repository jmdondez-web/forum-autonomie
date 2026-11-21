#!/usr/bin/env bash
# setup-freshrss-107.sh - FreshRSS dans LXC 107 (Debian 12)
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then echo "Run as root inside LXC 107"; exit 1; fi

echo "== Packages =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx git php-fpm php-curl php-xml php-mbstring php-intl php-gd php-zip php-sqlite3 sqlite3 > /dev/null
PHPV=$(ls /etc/php/ | grep -E "^[0-9.]+$" | head -1)

echo "== FreshRSS =="
mkdir -p /usr/share/FreshRSS
if [ ! -d /usr/share/FreshRSS/.git ]; then
  git clone -q --depth 1 https://github.com/FreshRSS/FreshRSS.git /usr/share/FreshRSS
else
  git -C /usr/share/FreshRSS pull -q || true
fi
chown -R www-data:www-data /usr/share/FreshRSS
for d in data extensions cache; do mkdir -p /usr/share/FreshRSS/$d; chown www-data:www-data /usr/share/FreshRSS/$d; done

echo "== Nginx =="
cat > /etc/nginx/sites-available/freshrss <<'NGINX'
server {
    listen 80 default_server;
    server_name _;
    root /usr/share/FreshRSS/p;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/PHPSOCK;
    }

    location ~ /\.(?!well-known) {
        deny all;
    }
}
NGINX
sed -i "s|/run/php/PHPSOCK|/run/php/php$PHPV-fpm.sock|" /etc/nginx/sites-available/freshrss
ln -sf /etc/nginx/sites-available/freshrss /etc/nginx/sites-enabled/freshrss
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx php$PHPV-fpm
systemctl reload nginx

echo "== Done =="
echo "Open http://192.168.0.107/ and run the web installer (SQLite, create admin)."
