#!/bin/bash

CFG="/etc/network/interfaces"
IFACE="ens3"

[ "$EUID" -ne 0 ] && echo "Run as root" && exit 1

PRIMARY_IP=$(awk "/iface $IFACE inet static/{f=1} f&&/address/{print \$2; exit}" "$CFG")

mapfile -t ALIASES < <(awk "/iface $IFACE:[0-9]+ inet static/ {print \$2}" "$CFG")

OPTIONS=()
for a in "${ALIASES[@]}"; do
  ip=$(awk "/iface $a inet static/{f=1} f&&/address/{print \$2; exit}" "$CFG")
  OPTIONS+=("$a → $ip")
done

echo "Primary IP:"
echo "ens3 → $PRIMARY_IP"
echo
echo "Select IP to make PRIMARY (number only):"

select CHOICE in "${OPTIONS[@]}"; do
  [ -n "$CHOICE" ] && break
done

TARGET_ALIAS=$(echo "$CHOICE" | awk '{print $1}')
TARGET_IP=$(echo "$CHOICE" | awk '{print $3}')

# ساخت gateway جدید: آخرین بخش 1
NEW_GATEWAY=$(echo "$TARGET_IP" | awk -F. '{print $1"."$2"."$3".1"}')

echo
echo "Swapping IPs:"
echo "ens3        : $PRIMARY_IP"
echo "$TARGET_ALIAS : $TARGET_IP"
echo "New gateway: $NEW_GATEWAY"
echo

read -p "Continue? (y/n): " c
[ "$c" != "y" ] && exit 0

BACKUP="$CFG.bak.$(date +%F_%H-%M-%S)"
cp "$CFG" "$BACKUP"

# swap address ها
sed -i \
  -e "/iface $IFACE inet static/{:a;n;/address/{s/$PRIMARY_IP/$TARGET_IP/;ba}}" \
  -e "/iface $TARGET_ALIAS inet static/{:b;n;/address/{s/$TARGET_IP/$PRIMARY_IP/;bb}}" \
  "$CFG"

# تغییر gateway به gateway جدید
sed -i "/iface $IFACE inet static/{:g;n;/gateway/{s/.*/    gateway   $NEW_GATEWAY/;g}}" "$CFG"

echo "File updated. Backup: $BACKUP"
echo "Restarting network..."

systemctl restart networking || service networking restart

echo "Done."
