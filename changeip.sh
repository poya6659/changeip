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

# Gateway جدید
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
echo "Backup saved: $BACKUP"

# فایل جدید
awk -v PIP="$PRIMARY_IP" -v TIP="$TARGET_IP" -v GW="$NEW_GATEWAY" '
{
  # شروع بلاک ens3
  if ($1=="iface" && $2=="ens3" && $3=="inet" && $4=="static") {
    inblock=1
    print $0
    next
  }
  # تغییر address
  if (inblock && $1=="address") {print "    address   " TIP; next}
  # تغییر یا اضافه کردن gateway
  if (inblock && $1=="gateway") {print "    gateway   " GW; next}
  # اگر بلاک تموم شد و gateway نبود اضافه کن
  if (inblock && NF==0) {
    if (!gw_found) {print "    gateway   " GW; gw_found=1}
    inblock=0
  }
  # بلاک alias
  if ($1=="iface" && $2 ~ /^ens3:[0-9]+$/ && $3=="inet" && $4=="static") {
    inblock2=1
    print $0
    next
  }
  if (inblock2 && $1=="address") {print "    address   " PIP; next}
  if (inblock2 && NF==0) {inblock2=0}
  print $0
}' "$CFG" > /tmp/interfaces.new

mv /tmp/interfaces.new "$CFG"

systemctl restart networking || service networking restart

echo "Done."
ip -4 addr show ens3
