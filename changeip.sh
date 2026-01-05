#!/bin/bash

CFG="/etc/network/interfaces"
IFACE="ens3"

[ "$EUID" -ne 0 ] && echo "Run as root" && exit 1

# گرفتن IP اصلی
PRIMARY_IP=$(awk "/iface $IFACE inet static/{f=1} f&&/address/{print \$2; exit}" "$CFG")

# گرفتن aliasها
mapfile -t ALIASES < <(awk "/iface $IFACE:[0-9]+ inet static/{print \$2}" "$CFG")

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

# Gateway جدید: سه بخش اول IP + .1
NEW_GATEWAY=$(echo "$TARGET_IP" | awk -F. '{print $1"."$2"."$3".1"}')

echo
echo "Swapping IPs:"
echo "ens3        : $PRIMARY_IP"
echo "$TARGET_ALIAS : $TARGET_IP"
echo "New gateway : $NEW_GATEWAY"
echo

read -p "Continue? (y/n): " c
[ "$c" != "y" ] && exit 0

# بکاپ
BACKUP="$CFG.bak.$(date +%F_%H-%M-%S)"
cp "$CFG" "$BACKUP"
echo "Backup saved: $BACKUP"

# خواندن فایل و جایگزینی IP و gateway
inblock=0
gw_added=0
> /tmp/interfaces.new
while IFS= read -r line; do
  # شروع بلاک ens3
  if [[ $line =~ ^iface\ ens3\ inet\ static ]]; then
    inblock=1
    gw_added=0
    echo "$line" >> /tmp/interfaces.new
    continue
  fi

  # تغییر address
  if [[ $inblock -eq 1 && $line =~ ^[[:space:]]*address ]]; then
    echo "    address   $TARGET_IP" >> /tmp/interfaces.new
    continue
  fi

  # تغییر gateway
  if [[ $inblock -eq 1 && $line =~ ^[[:space:]]*gateway ]]; then
    echo "    gateway   $NEW_GATEWAY" >> /tmp/interfaces.new
    gw_added=1
    continue
  fi

  # پایان بلاک ens3
  if [[ $inblock -eq 1 && -z $line ]]; then
    if [[ $gw_added -eq 0 ]]; then
      echo "    gateway   $NEW_GATEWAY" >> /tmp/interfaces.new
    fi
    inblock=0
  fi

  # بلاک alias
  if [[ $line =~ ^iface\ ens3:[0-9]+ ]]; then
    inalias=1
    echo "$line" >> /tmp/interfaces.new
    continue
  fi

  if [[ $inalias -eq 1 && $line =~ ^[[:space:]]*address ]]; then
    echo "    address   $PRIMARY_IP" >> /tmp/interfaces.new
    continue
  fi

  if [[ $inalias -eq 1 && -z $line ]]; then
    inalias=0
  fi

  # خطوط دیگر بدون تغییر
  echo "$line" >> /tmp/interfaces.new
done < "$CFG"

mv /tmp/interfaces.new "$CFG"

# ریستارت شبکه
systemctl restart networking || service networking restart

echo "Done."
ip -4 addr show ens3
