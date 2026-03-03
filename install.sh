#!/bin/bash

set -e
[[ $EUID -ne 0 ]] && { echo "Запускай от root"; exit 1; }

echo "=== Обновление системы ==="
apt update && apt upgrade -y

echo "=== Зависимости ==="
apt install -y software-properties-common python3-launchpadlib \
linux-headers-$(uname -r) net-tools curl git ufw iptables qrencode

echo "=== AmneziaWG PPA ==="
add-apt-repository -y ppa:amnezia/ppa
apt update
apt install -y amneziawg amneziawg-tools

echo "=== Проверка модуля ==="
modprobe amneziawg || {
echo "ОШИБКА: модуль не загрузился. Сделай reboot и запусти install.sh снова"
exit 1
}
lsmod | grep amneziawg && echo "✓ модуль загружен"

echo "=== IP Forwarding ==="
echo 1 > /proc/sys/net/ipv4/ip_forward
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

echo "=== Папка конфигов ==="
mkdir -p /etc/amnezia/amneziawg
chmod 700 /etc/amnezia/amneziawg

echo "=== Firewall ==="
ufw allow 22/tcp   || true
ufw allow 51820/udp || true
ufw --force enable  || true

echo "======================================="
echo "✓ Установка завершена"
echo "Теперь запускай: ./gen_awg2.sh"
echo "======================================="
