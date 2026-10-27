#!/usr/bin/env bash
# Puts the studio online on this VPS at https://studio.nouraldeentofi.com (Debian/Ubuntu).
# It adds the site to the web server that already answers on ports 80/443 (Caddy, nginx or Apache)
# and never starts a second one next to it, so the other sites on this server keep working.
# Before running: add a DNS "A" record  studio → this server's IP  (Cloudflare: "DNS only").
# Run on the server:   curl -fsSL https://raw.githubusercontent.com/nouraldeentofi/motion-studio/main/deploy/setup-vps.sh | sudo bash
# Running it again later just pulls the latest version of the site.
set -euo pipefail

DOMAIN="${DOMAIN:-studio.nouraldeentofi.com}"
ROOT="/var/www/$DOMAIN"
REPO="https://github.com/nouraldeentofi/motion-studio.git"

[ "$(id -u)" -eq 0 ] || { echo "run it with sudo"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq "${2:-$1}"; }; }
needpkg() { dpkg -s "$1" >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq "$1"; }; }
fill() { sed "s#__DOMAIN__#$DOMAIN#g; s#__ROOT__#$ROOT#g" "$1"; }
need git
need ss iproute2

# 1 · the files (a git clone, so updates are one pull)
if [ -d "$ROOT/.git" ]; then
  git -C "$ROOT" pull --ff-only
  echo "✓ files updated in $ROOT"
else
  mkdir -p "$(dirname "$ROOT")"
  git clone --depth 1 "$REPO" "$ROOT"
  echo "✓ files cloned into $ROOT"
fi

# 2 · which program already answers on port 80 / 443?
owner="$(ss -ltnpH '( sport = :80 or sport = :443 )' 2>/dev/null | grep -o 'users:(("[^"]*' | head -1 | cut -d'"' -f2 || true)"
echo "• port 80/443 is served by: ${owner:-nothing yet}"

# an nginx that is installed but not running must not grab the ports at the next reboot
calm_nginx() {
  if command -v nginx >/dev/null 2>&1 && ! systemctl is-active --quiet nginx && systemctl is-enabled --quiet nginx 2>/dev/null; then
    systemctl disable nginx >/dev/null 2>&1 || true
    echo "• nginx is installed but not running here: switched off its start at boot, so it never takes ports 80/443 from $1"
  fi
  rm -f "/etc/nginx/sites-enabled/$DOMAIN" "/etc/nginx/conf.d/$DOMAIN.conf"
}

case "$owner" in
  caddy)
    calm_nginx caddy
    # the Caddyfile this Caddy was started with (the Debian package uses /etc/caddy/Caddyfile)
    CF="$(ps -o args= -C caddy | grep -o -- '--config[= ][^ ]*' | head -1 | sed 's/--config[= ]//' || true)"
    CF="${CF:-/etc/caddy/Caddyfile}"
    [ -f "$CF" ] || { echo "Caddy is running but $CF was not found. Send this output to Claude."; exit 1; }
    if grep -qE "^[[:space:]]*(https?://)?$DOMAIN([[:space:]:,{]|$)" "$CF"; then
      echo "✓ $DOMAIN is already in $CF"
    else
      cp "$CF" "$CF.bak.$(date +%Y%m%d%H%M%S)"
      { echo; fill "$ROOT/deploy/caddy.conf" | grep -v "setup-vps.sh fills in"; } >> "$CF"
      if ! caddy validate --adapter caddyfile --config "$CF" >/dev/null 2>&1; then
        cp "$(ls -t "$CF".bak.* | head -1)" "$CF"
        echo "Caddy did not accept the new block, so $CF was restored unchanged. Send this output to Claude."
        exit 1
      fi
      echo "✓ added $DOMAIN to $CF (backup: $(ls -t "$CF".bak.* | head -1))"
    fi
    systemctl reload caddy 2>/dev/null || caddy reload --adapter caddyfile --config "$CF"
    echo "✓ Caddy reloaded (it gets the HTTPS certificate by itself)"
    ;;
  nginx|"")
    if [ -z "$owner" ]; then need nginx; systemctl enable --now nginx; fi
    if [ -d /etc/nginx/sites-available ]; then
      fill "$ROOT/deploy/nginx.conf" > "/etc/nginx/sites-available/$DOMAIN"
      ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
    else
      fill "$ROOT/deploy/nginx.conf" > "/etc/nginx/conf.d/$DOMAIN.conf"
    fi
    nginx -t
    systemctl reload nginx
    if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
      needpkg certbot; needpkg python3-certbot-nginx
      certbot --nginx -d "$DOMAIN" --redirect
    fi
    echo "✓ nginx serves $DOMAIN"
    ;;
  apache2|httpd)
    calm_nginx apache
    fill "$ROOT/deploy/apache.conf" > "/etc/apache2/sites-available/$DOMAIN.conf"
    a2enmod headers >/dev/null
    a2ensite "$DOMAIN" >/dev/null
    apache2ctl configtest
    systemctl reload apache2
    if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
      needpkg certbot; needpkg python3-certbot-apache
      certbot --apache -d "$DOMAIN" --redirect
    fi
    echo "✓ Apache serves $DOMAIN"
    ;;
  *)
    echo "Ports 80/443 belong to \"$owner\" (for example Docker or Traefik). Nothing was changed on the web server."
    echo "Send this output to Claude together with:  sudo ss -ltnp | grep -E ':(80|443) '   and   docker ps"
    exit 1
    ;;
esac

echo
echo "done → https://$DOMAIN"
