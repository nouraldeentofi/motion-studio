#!/usr/bin/env bash
# Puts the studio online on this VPS at https://studio.nouraldeentofi.com (Debian/Ubuntu, nginx or Apache).
# Before running: add a DNS "A" record  studio → this server's IP  and wait until it resolves.
# Run on the server:   curl -fsSL https://raw.githubusercontent.com/nouraldeentofi/motion-studio/main/deploy/setup-vps.sh | sudo bash
# Running it again later just pulls the latest version of the site.
set -euo pipefail

DOMAIN="${DOMAIN:-studio.nouraldeentofi.com}"
ROOT="/var/www/$DOMAIN"
REPO="https://github.com/nouraldeentofi/motion-studio.git"

need() { command -v "$1" >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq "${2:-$1}"; }; }
need git

# 1 · the files (a git clone, so updates are one pull)
if [ -d "$ROOT/.git" ]; then
  git -C "$ROOT" pull --ff-only
  echo "updated $ROOT"
else
  mkdir -p "$(dirname "$ROOT")"
  git clone --depth 1 "$REPO" "$ROOT"
  echo "cloned into $ROOT"
fi

# 2 · the web server (nginx if present, otherwise Apache, otherwise install nginx)
fill() { sed "s#__DOMAIN__#$DOMAIN#g; s#__ROOT__#$ROOT#g" "$1"; }
if command -v apache2 >/dev/null 2>&1 && ! command -v nginx >/dev/null 2>&1; then
  fill "$ROOT/deploy/apache.conf" > "/etc/apache2/sites-available/$DOMAIN.conf"
  a2enmod headers >/dev/null
  a2ensite "$DOMAIN" >/dev/null
  apache2ctl configtest
  systemctl reload apache2
  PLUGIN=apache
else
  need nginx
  if [ -d /etc/nginx/sites-available ]; then
    fill "$ROOT/deploy/nginx.conf" > "/etc/nginx/sites-available/$DOMAIN"
    ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
  else
    fill "$ROOT/deploy/nginx.conf" > "/etc/nginx/conf.d/$DOMAIN.conf"
  fi
  nginx -t
  systemctl reload nginx
  PLUGIN=nginx
fi

# 3 · HTTPS (needed: the watermark password check only works on a secure page)
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  need certbot
  need "python3-certbot-$PLUGIN"
  certbot "--$PLUGIN" -d "$DOMAIN" --redirect
fi

echo
echo "done → https://$DOMAIN"
