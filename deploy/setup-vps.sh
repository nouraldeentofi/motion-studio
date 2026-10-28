#!/usr/bin/env bash
# Puts the studio online on this VPS at https://studio.nouraldeentofi.com (Debian/Ubuntu).
# It adds the site to the web server that already answers on ports 80/443 (Caddy, nginx or Apache)
# and never starts a second one next to it, so the other sites on this server keep working.
# Before running: add a DNS "A" record  studio → this server's IP  (Cloudflare: "DNS only").
# Run on the server:   curl -fsSL https://raw.githubusercontent.com/nouraldeentofi/motion-studio/main/deploy/setup-vps.sh | sudo bash
# Running it again later just pulls the latest version of the site.

# Everything sits in main() so bash reads the whole script before running any of it:
# under `curl | sudo bash` stdin is the script itself, and nothing below may eat it.
main() {
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

DOMAIN="${DOMAIN:-studio.nouraldeentofi.com}"
ROOT="/var/www/$DOMAIN"
REPO="https://github.com/nouraldeentofi/motion-studio.git"

[ "$(id -u)" -eq 0 ] || { echo "run it with sudo"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq "${2:-$1}"; } </dev/null; }
needpkg() { dpkg -s "$1" >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq "$1"; } </dev/null; }
fill() { sed "s#__DOMAIN__#$DOMAIN#g; s#__ROOT__#$ROOT#g" "$1"; }
# no email is sent anywhere: the certificate renews by itself through certbot's timer
cert() { certbot "--$1" -d "$DOMAIN" --redirect --non-interactive --agree-tos --register-unsafely-without-email </dev/null; }
need git
need ss iproute2

# 1 · the files (a git clone, so updates are one fetch; the copy here is only ever the published one)
if [ -d "$ROOT/.git" ]; then
  git -C "$ROOT" fetch -q --depth 1 </dev/null
  git -C "$ROOT" reset -q --hard '@{u}'
  echo "✓ files updated in $ROOT"
else
  mkdir -p "$(dirname "$ROOT")"
  git clone --depth 1 "$REPO" "$ROOT" </dev/null
  echo "✓ files cloned into $ROOT"
fi
chmod -R a+rX "$ROOT"   # the web server runs as its own user and must be able to read the files

# 2 · which program already answers on port 80 / 443?
owners="$(ss -ltnpH '( sport = :80 or sport = :443 )' 2>/dev/null | grep -o 'users:(("[^"]*' | cut -d'"' -f2 | sort -u || true)"
owner="$(echo "$owners" | head -1)"
[ "$(echo "$owners" | grep -c .)" -le 1 ] || owner="several"
echo "• port 80/443 is served by: $(echo "${owners:-nothing yet}" | paste -sd' ')"

# an nginx that is installed but not running must not grab the ports at the next reboot
calm_nginx() {
  if command -v nginx >/dev/null 2>&1 && ! systemctl is-active --quiet nginx && systemctl is-enabled --quiet nginx 2>/dev/null; then
    systemctl disable nginx >/dev/null 2>&1 || true
    echo "• nginx is installed but not running here: switched off its start at boot, so it never takes ports 80/443 from the server that has them now"
  fi
  rm -f "/etc/nginx/sites-enabled/$DOMAIN" "/etc/nginx/conf.d/$DOMAIN.conf"
}

# nothing listening, but another web server is installed (stopped right now): leave the choice to a human
if [ -z "$owner" ] && { command -v caddy || command -v apache2 || command -v docker; } >/dev/null 2>&1; then
  owner="stopped"
fi

case "$owner" in
  caddy)
    calm_nginx
    # the Caddyfile this Caddy was started with (the Debian package uses /etc/caddy/Caddyfile)
    CF="$(pgrep -xa caddy | grep -o -- '--config[= ][^ ]*' | head -1 | sed 's/--config[= ]//' || true)"
    CF="${CF:-/etc/caddy/Caddyfile}"
    [ -f "$CF" ] || { echo "Caddy is running but $CF was not found. Send this output to Claude."; exit 1; }
    if grep -qE "^[[:space:]]*(https?://)?$DOMAIN([[:space:]:,{]|$)" "$CF"; then
      echo "✓ $DOMAIN is already in $CF"
    else
      BAK="$CF.bak.$(date +%Y%m%d%H%M%S)"
      cp -p "$CF" "$BAK"
      { echo; fill "$ROOT/deploy/caddy.conf" | grep -v "setup-vps.sh fills in"; } >> "$CF"
      if ! err="$(caddy validate --adapter caddyfile --config "$CF" 2>&1)"; then
        cp -p "$BAK" "$CF"
        echo "$err" | tail -3
        echo "Caddy did not accept the new block, so $CF was restored unchanged. Send this output to Claude."
        exit 1
      fi
      echo "✓ added $DOMAIN to $CF (backup: $BAK)"
    fi
    systemctl reload caddy 2>/dev/null || caddy reload --adapter caddyfile --config "$CF"
    echo "✓ Caddy reloaded (it gets the HTTPS certificate by itself)"
    ;;
  nginx|"")
    if [ -z "$owner" ]; then need nginx; systemctl enable --now nginx; fi
    if [ -d /etc/nginx/sites-available ]; then
      SITE="/etc/nginx/sites-available/$DOMAIN"; LINK="/etc/nginx/sites-enabled/$DOMAIN"
    else
      SITE="/etc/nginx/conf.d/$DOMAIN.conf"; LINK=""
    fi
    # after the first run certbot has added HTTPS to this file: keep it
    wrote=""
    if grep -qs "managed by Certbot" "$SITE"; then
      echo "✓ $SITE already has HTTPS, left as it is"
    else
      fill "$ROOT/deploy/nginx.conf" > "$SITE"; wrote=1
    fi
    [ -z "$LINK" ] || ln -sf "$SITE" "$LINK"
    if ! nginx -t; then
      if [ -n "$LINK" ]; then rm -f "$LINK"; elif [ -n "$wrote" ]; then rm -f "$SITE"; fi
      echo "nginx did not accept the config, so the site was taken out again. Send this output to Claude."
      exit 1
    fi
    systemctl reload nginx
    if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
      needpkg certbot; needpkg python3-certbot-nginx
      cert nginx
    fi
    echo "✓ nginx serves $DOMAIN"
    ;;
  apache2)
    calm_nginx
    # after the first run certbot has added an HTTPS twin of this site: keep the pair as it is
    if [ ! -e "/etc/apache2/sites-available/$DOMAIN-le-ssl.conf" ]; then
      fill "$ROOT/deploy/apache.conf" > "/etc/apache2/sites-available/$DOMAIN.conf"
    fi
    a2enmod headers >/dev/null
    a2ensite "$DOMAIN" >/dev/null
    if ! apache2ctl configtest; then
      a2dissite "$DOMAIN" >/dev/null || true
      echo "Apache did not accept the config, so the site was taken out again. Send this output to Claude."
      exit 1
    fi
    systemctl reload apache2
    if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
      needpkg certbot; needpkg python3-certbot-apache
      cert apache
    fi
    echo "✓ Apache serves $DOMAIN"
    ;;
  *)
    calm_nginx
    case "$owner" in
      stopped) echo "Nothing answers on ports 80/443 right now, but a web server (Caddy, Apache or Docker) is installed here." ;;
      several) echo "Ports 80 and 443 belong to different programs." ;;
      *)       echo "Ports 80/443 belong to \"$owner\" (for example Docker or Traefik)." ;;
    esac
    echo "Nothing was changed on the web server. Send this output to Claude together with:"
    echo "  sudo ss -ltnp | grep -E ':(80|443) '   and   docker ps"
    exit 1
    ;;
esac

echo
echo "done → https://$DOMAIN"
}

main "$@"
