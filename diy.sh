#!/bin/bash
# Point the built image's default LAN address at this deployment's subnet.
sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate

# ---------------------------------------------------------------------------
# Nikki: ship the official apk feed key and enable weekly auto-update.
#
# OpenWrt 25.12 uses apk (not opkg). Nikki publishes a signed apk feed at
#   https://nikkinikki.pages.dev/<branch>/<arch>/nikki
# so the stack can be upgraded with plain `apk upgrade`.
# ---------------------------------------------------------------------------
BASE=package/base-files/files
NIKKI_REPO="https://nikkinikki.pages.dev"
NIKKI_FEED="$NIKKI_REPO/openwrt-25.12/x86_64/nikki/packages.adb"

# 1) Trust key for Nikki's feed (apk rejects the index without it)
mkdir -p "$BASE/etc/apk/keys"
wget -q -O "$BASE/etc/apk/keys/nikki.pem" "$NIKKI_REPO/public-key.pem"

# 2) Helper that updates only the Nikki stack (never the whole system)
mkdir -p "$BASE/usr/bin"
cat > "$BASE/usr/bin/nikki-update" <<'EOF'
#!/bin/sh
# Update the Nikki stack from its official apk feed.
exec >/tmp/nikki-update.log 2>&1
echo "=== $(date) ==="
apk update
apk upgrade --no-interactive nikki luci-app-nikki luci-i18n-nikki-zh-cn mihomo-meta
echo "exit=$?"
EOF
chmod +x "$BASE/usr/bin/nikki-update"

# 3) First-boot setup: register the feed, drop the dangling distfeeds entry,
#    and schedule the weekly update.
mkdir -p "$BASE/etc/uci-defaults"
cat > "$BASE/etc/uci-defaults/99-nikki-feed" <<'EOF'
#!/bin/sh

# register the official Nikki feed (append, never overwrite)
grep -q 'nikkinikki.pages.dev' /etc/apk/repositories.d/customfeeds.list 2>/dev/null || \
	echo 'https://nikkinikki.pages.dev/openwrt-25.12/x86_64/nikki/packages.adb' \
		>> /etc/apk/repositories.d/customfeeds.list

# the build adds dangling "nikki" and "video" entries to distfeeds.list (404 upstream); drop them
[ -f /etc/apk/repositories.d/distfeeds.list ] && \
	sed -i -E '\#/packages/x86_64/(nikki|video)/packages\.adb#d' /etc/apk/repositories.d/distfeeds.list

# weekly auto-update of the Nikki stack (Sunday 04:17)
touch /etc/crontabs/root
grep -q 'nikki-update' /etc/crontabs/root || \
	echo '17 4 * * 0 /usr/bin/nikki-update' >> /etc/crontabs/root
/etc/init.d/cron restart >/dev/null 2>&1

exit 0
EOF
chmod +x "$BASE/etc/uci-defaults/99-nikki-feed"

# ---------------------------------------------------------------------------
# EasyTier: pinned to 2.6.4 (commit 8428a89d).
#
# This is the exact build already running on the existing deployment's gateway
# and storage host. Newer releases are deliberately NOT used. The APKs are
# shipped inside the image and installed once, on first boot.
# ---------------------------------------------------------------------------
EZT_VER="2.6.4"
EZT_URL="https://github.com/EasyTier/luci-app-easytier/releases/download/v${EZT_VER}/EasyTier-v${EZT_VER}-x86_64-SNAPSHOT.zip"
EZT_DIR="$BASE/etc/easytier-pkgs"

mkdir -p "$EZT_DIR" /tmp/ezt
wget -q -O /tmp/ezt.zip "$EZT_URL"
unzip -oq /tmp/ezt.zip -d /tmp/ezt
cp -f "/tmp/ezt/easytier-noweb-${EZT_VER}.apk"        "$EZT_DIR/"
cp -f "/tmp/ezt/luci-app-easytier-${EZT_VER}-r1.apk"  "$EZT_DIR/"
cp -f /tmp/ezt/luci-i18n-easytier-zh-cn-*.apk         "$EZT_DIR/luci-i18n-easytier-zh-cn.apk"
rm -rf /tmp/ezt /tmp/ezt.zip

cat > "$BASE/etc/uci-defaults/98-easytier-install" <<'EOF'
#!/bin/sh
# Install the pinned EasyTier stack shipped in the image (2.6.4 / 8428a89d).
if [ -d /etc/easytier-pkgs ]; then
	apk add --no-network --allow-untrusted /etc/easytier-pkgs/*.apk >/tmp/easytier-install.log 2>&1
	rm -rf /etc/easytier-pkgs
fi
exit 0
EOF
chmod +x "$BASE/etc/uci-defaults/98-easytier-install"
