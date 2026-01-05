#!/bin/bash

CFG="/etc/network/interfaces"
IFACE="ens3"

[ "$EUID" -ne 0 ] && echo "Run as root" && exit 1

# IP اصلی
PRIMARY_IP=$(awk "/iface $IFACE inet static/{f=1} f&&/address/{print \$2; exit}" "$CFG")

# گرفتن aliasها و IPهایشان
declare -A ALIAS_IPS
while read -r alias; do
    ip=$(awk "/iface $alias inet static/{f=1} f&&/address/{print \$2; exit}" "$CFG")
    ALIAS_IPS["$alias"]="$ip"
done < <(awk "/iface $IFACE:[0-9]+/ {print \$2}" "$CFG")

# گزینه‌ها برای منو
OPTIONS=()
for a in "${!ALIAS_IPS[@]}"; do
    OPTIONS+=("$a → ${ALIAS_IPS[$a]}")
done

echo "Primary IP:"
echo "ens3 → $PRIMARY_IP"
echo
echo "Select IP to make PRIMARY (number only):"

select CHOICE in "${OPTIONS[@]}"; do
  [ -n "$CHOICE" ] && break
done

TARGET_ALIAS=$(echo "$CHOICE" | awk '{print $1}')
TARGET_IP="${ALIAS_IPS[$TARGET_ALIAS]}"

# Gateway جدید
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

# خواندن فایل و تغییر IP اصلی و alias انتخاب شده
> /tmp/interfaces.new
inblock=0
inalias=""
gw_added=0

while IFS= read -r line; do
    # شروع بلاک ens3
    if [[ $line =~ ^iface\ ens3\ inet\ static ]]; then
        inblock=1
        gw_added=0
        echo "$line" >> /tmp/interfaces.new
        continue
    fi

    if [[ $inblock -eq 1 && $line =~ ^[[:space:]]*address ]]; then
        echo "    address   $TARGET_IP" >> /tmp/interfaces.new
        continue
    fi

    if [[ $inblock -eq 1 && $line =~ ^[[:space:]]*gateway ]]; then
        echo "    gateway   $NEW_GATEWAY" >> /tmp/interfaces.new
        gw_added=1
        continue
    fi

    if [[ $inblock -eq 1 && -z $line ]]; then
        if [[ $gw_added -eq 0 ]]; then
            echo "    gateway   $NEW_GATEWAY" >> /tmp/interfaces.new
        fi
        inblock=0
    fi

    # بلاک aliasها
    if [[ $line =~ ^iface\ ens3:[0-9]+ ]]; then
        alias_name=$(echo $line | awk '{print $2}')
        inalias="$alias_name"
        echo "$line" >> /tmp/interfaces.new
        continue
    fi

    if [[ -n "$inalias" && $line =~ ^[[:space:]]*address ]]; then
        # فقط IP alias انتخاب شده با IP اصلی قبلی swap شود
        if [[ "$inalias" == "$TARGET_ALIAS" ]]; then
            echo "    address   $PRIMARY_IP" >> /tmp/interfaces.new
        else
            echo "$line" >> /tmp/interfaces.new
        fi
        continue
    fi

    # پایان alias
    if [[ -n "$inalias" && -z $line ]]; then
        inalias=""
    fi

    # خطوط دیگر بدون تغییر
    echo "$line" >> /tmp/interfaces.new
done < "$CFG"

mv /tmp/interfaces.new "$CFG"

# ریستارت شبکه
systemctl restart networking || service networking restart

echo "Done."
ip -4 addr show ens3
