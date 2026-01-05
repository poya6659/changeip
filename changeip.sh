#!/bin/bash

IFACE="ens3"

clear
echo "==== Primary IP Setter for $IFACE ===="
echo

# گرفتن IPهای IPv4
mapfile -t IPS < <(ip -o -4 addr show dev "$IFACE" | awk '{print $4}')

if [ ${#IPS[@]} -eq 0 ]; then
  echo "❌ No IPv4 address found on $IFACE"
  exit 1
fi

echo "Available IPs on $IFACE:"
select PRIMARY in "${IPS[@]}"; do
  [ -n "$PRIMARY" ] && break
done

echo
echo "✅ Selected primary IP: $PRIMARY"
echo

read -p "⚠️ Network will restart. Continue? (y/n): " CONFIRM
[ "$CONFIRM" != "y" ] && exit 0

# بقیه IPها
OTHERS=()
for ip in "${IPS[@]}"; do
  [ "$ip" != "$PRIMARY" ] && OTHERS+=("$ip")
done

echo
echo "▶ Reordering IPs on $IFACE ..."

# حذف همه IPها
for ip in "${IPS[@]}"; do
  ip addr del "$ip" dev "$IFACE"
done

# اضافه کردن IP اصلی اول
ip addr add "$PRIMARY" dev "$IFACE"

# اضافه کردن بقیه IPها
for ip in "${OTHERS[@]}"; do
  ip addr add "$ip" dev "$IFACE"
done

# ریستارت شبکه
if systemctl is-active --quiet networking; then
  systemctl restart networking
elif systemctl is-active --quiet NetworkManager; then
  systemctl restart NetworkManager
else
  echo "⚠️ Network service not detected, skipping restart"
fi

echo
echo "🎉 Done! Current IP order:"
ip -4 addr show dev "$IFACE"
