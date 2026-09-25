#!/usr/bin/env bash
# Meltiew server installer for Ubuntu (tested target: 24.04 + nginx).
# Safe to re-run: it updates the code and keeps the database.
#   curl -fsSL https://raw.githubusercontent.com/narezy/Meltiew/main/deploy/install.sh | sudo bash
set -euo pipefail

DOMAIN="meltiew.narez.xyz"
REPO_TARBALL="${REPO_TARBALL:-https://codeload.github.com/narezy/Meltiew/tar.gz/refs/heads/main}"
# Optional: direct link to the APK to publish at https://$DOMAIN/meltiew.apk
APK_URL="${APK_URL:-}"
APP_DIR=/opt/meltiew
DATA_DIR=/var/lib/meltiew

say() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "Запусти от root (sudo)"; exit 1; }

say "Пакеты"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ca-certificates tar nginx >/dev/null

# Private Node for Meltiew only, so other apps on this box keep their node.
NODE_VER=v24.21.0
NODE_DIR=/opt/meltiew-node
if [ ! -x "$NODE_DIR/bin/node" ] || [ "$("$NODE_DIR/bin/node" -v)" != "$NODE_VER" ]; then
  say "Ставлю Node.js $NODE_VER в $NODE_DIR"
  arch=$(uname -m); case "$arch" in x86_64) narch=x64;; aarch64) narch=arm64;; *) echo "Неизвестная архитектура $arch"; exit 1;; esac
  ntmp=$(mktemp -d)
  curl -fsSL "https://nodejs.org/dist/$NODE_VER/node-$NODE_VER-linux-$narch.tar.xz" -o "$ntmp/node.tar.xz"
  apt-get install -y -qq xz-utils >/dev/null
  rm -rf "$NODE_DIR" && mkdir -p "$NODE_DIR"
  tar -xJf "$ntmp/node.tar.xz" -C "$NODE_DIR" --strip-components=1
  rm -rf "$ntmp"
fi
echo "node $("$NODE_DIR/bin/node" -v)"

say "Пользователь и папки"
id meltiew >/dev/null 2>&1 || useradd --system --home "$DATA_DIR" --shell /usr/sbin/nologin meltiew
mkdir -p "$APP_DIR" "$DATA_DIR"
chown meltiew:meltiew "$DATA_DIR"
chmod 750 "$DATA_DIR"

say "Код сервера"
tmp=$(mktemp -d)
curl -fsSL "$REPO_TARBALL" -o "$tmp/repo.tar.gz"
mkdir -p "$tmp/meltiew"
tar -xzf "$tmp/repo.tar.gz" -C "$tmp/meltiew" --strip-components=1
(cd "$tmp/meltiew/server" && PATH="$NODE_DIR/bin:$PATH" npm ci --omit=dev --no-audit --no-fund --loglevel=error)
rm -rf "$APP_DIR.new"
mkdir -p "$APP_DIR.new"
cp -a "$tmp/meltiew/server/." "$APP_DIR.new/"
if [ -f "$APP_DIR/public/meltiew.apk" ]; then cp "$APP_DIR/public/meltiew.apk" "$APP_DIR.new/public/"; fi
rm -rf "$APP_DIR.old"
[ -d "$APP_DIR" ] && mv "$APP_DIR" "$APP_DIR.old"
mv "$APP_DIR.new" "$APP_DIR"
if [ -n "$APK_URL" ]; then
  say "Кладу APK на сайт"
  curl -fsSL "$APK_URL" -o "$APP_DIR/public/meltiew.apk" || echo "APK скачать не вышло, сайт будет без него"
fi
chown -R root:root "$APP_DIR"

say "systemd"
cp "$tmp/meltiew/deploy/meltiew.service" /etc/systemd/system/meltiew.service
systemctl daemon-reload
systemctl enable --now meltiew >/dev/null
systemctl restart meltiew
sleep 1.5
curl -fsS http://127.0.0.1:7350/api/health && echo

say "nginx"
conf=/etc/nginx/sites-available/$DOMAIN
others=$(grep -rls "server_name[^;]*$DOMAIN" /etc/nginx/ 2>/dev/null | grep -v "$conf" || true)
if [ -n "$others" ]; then
  echo "ВНИМАНИЕ: $DOMAIN уже упоминается тут: $others"
  echo "Оставляю как есть, но если сайт не откроется, убери оттуда $DOMAIN."
fi
if [ -f "$conf" ] && grep -q "ssl_certificate" "$conf"; then
  echo "Конфиг с SSL уже есть, не трогаю"
else
  cp "$tmp/meltiew/deploy/nginx-meltiew.conf" "$conf"
fi
ln -sf "$conf" /etc/nginx/sites-enabled/$DOMAIN
if ! nginx -t 2>/tmp/meltiew-nginx.log; then
  cat /tmp/meltiew-nginx.log
  rm -f /etc/nginx/sites-enabled/$DOMAIN
  echo "nginx -t упал, откатил свой конфиг. Остальные сайты не тронуты."
  exit 1
fi
systemctl reload nginx

say "HTTPS (Let's Encrypt)"
if ! grep -q "ssl_certificate" "$conf"; then
  if ! command -v certbot >/dev/null 2>&1; then
    apt-get install -y -qq certbot python3-certbot-nginx >/dev/null
  fi
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect \
    || echo "certbot не смог выпустить сертификат. Проверь, что A-запись $DOMAIN указывает на этот сервер."
fi
nginx -t && systemctl reload nginx

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow 'Nginx Full' >/dev/null || true
fi

rm -rf "$tmp"
say "Готово"
curl -fsS "https://$DOMAIN/api/health" && echo && echo "https://$DOMAIN работает" || echo "Проверь https://$DOMAIN вручную"
