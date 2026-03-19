#!/bin/bash
set -e
[[ $EUID -ne 0 ]] && { echo "Запускай от root"; exit 1; }

echo "=== Обновление системы ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -y -q \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold"

echo "=== Зависимости ==="
apt-get install -y -q \
  software-properties-common \
  python3-launchpadlib \
  net-tools curl ufw iptables qrencode

# Headers — fallback на generic если текущее ядро не найдено
apt-get install -y -q linux-headers-$(uname -r) 2>/dev/null || \
  apt-get install -y -q linux-headers-generic || \
  { echo "ОШИБКА: не удалось установить linux-headers"; exit 1; }

echo "=== AmneziaWG (PPA) ==="
add-apt-repository -y ppa:amnezia/ppa
apt-get update -q
apt-get install -y -q amneziawg amneziawg-tools

command -v awg &>/dev/null \
  && echo "✓ amneziawg-tools: $(awg --version)" \
  || { echo "ОШИБКА: awg не найден после установки"; exit 1; }

echo "=== Проверка модуля ==="
modprobe amneziawg || { echo "ОШИБКА: сделай reboot и запусти снова"; exit 1; }
lsmod | grep -q amneziawg && echo "✓ модуль загружен"

echo "=== IP Forwarding ==="
echo 1 > /proc/sys/net/ipv4/ip_forward
grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || \
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p -q

echo "=== Папка конфигов ==="
mkdir -p /etc/amnezia/amneziawg
chmod 700 /etc/amnezia/amneziawg

echo "=== Firewall ==="
read -rp "SSH порт [22]: " SSH_PORT
SSH_PORT=${SSH_PORT:-22}
ufw allow "${SSH_PORT}/tcp" comment "SSH" || true
ufw allow 80/tcp  comment "HTTP"  || true
ufw allow 443/tcp comment "HTTPS" || true

ufw --force enable || true
ufw status

echo "=== Автозапуск AWG ==="
systemctl enable awg-quick@awg0 2>/dev/null || true
echo "✓ Автозапуск awg-quick@awg0 включён"

echo "======================================="
echo "✓ Установка завершена"
echo "Теперь запускай: ./gen_awg2.sh"
echo "======================================="
