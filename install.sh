#!/bin/bash
set -euo pipefail

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
  net-tools curl ufw iptables qrencode </dev/null

echo "=== Kernel headers ==="
apt-get install -y -q linux-headers-$(uname -r) 2>/dev/null || \
apt-get install -y -q linux-headers-generic || \
{ echo "ОШИБКА: не удалось установить linux-headers"; exit 1; }

echo "=== AmneziaWG (PPA) ==="
add-apt-repository -y ppa:amnezia/ppa
apt-get update -q
apt-get install -y -q amneziawg amneziawg-tools

command -v awg &>/dev/null \
  && echo "✓ amneziawg-tools: $(awg --version)" \
  || { echo "ОШИБКА: awg не найден"; exit 1; }

echo "=== Проверка модуля ==="
if modprobe amneziawg; then
  echo "✓ модуль загружен"
else
  echo "⚠️ Модуль не загрузился. Сделай reboot и запусти скрипт снова"
fi

echo "=== IP Forwarding ==="
sysctl -w net.ipv4.ip_forward=1 -q
grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || \
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

echo "=== NAT + FORWARD ==="
EXT_IF=$(ip route | awk '/default/ {print $5; exit}')
[[ -z "$EXT_IF" ]] && { echo "ОШИБКА: не найден default интерфейс"; exit 1; }
echo "✓ интерфейс: $EXT_IF"

iptables -t nat -C POSTROUTING -o "$EXT_IF" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o "$EXT_IF" -j MASQUERADE

iptables -C FORWARD -i awg0 -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -i awg0 -j ACCEPT

iptables -C FORWARD -o awg0 -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -o awg0 -j ACCEPT

# Сохраняем NAT правила через if-pre-up hook (UFW не умеет сохранять NAT)
IPTABLES_HOOK="/etc/network/if-pre-up.d/iptables-nat"
cat > "$IPTABLES_HOOK" <<EOF
#!/bin/sh
iptables -t nat -C POSTROUTING -o $EXT_IF -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o $EXT_IF -j MASQUERADE
iptables -C FORWARD -i awg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i awg0 -j ACCEPT
iptables -C FORWARD -o awg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -o awg0 -j ACCEPT
EOF
chmod +x "$IPTABLES_HOOK"
echo "✓ NAT правила сохранены в $IPTABLES_HOOK"

echo "=== Папка конфигов ==="
mkdir -p /etc/amnezia/amneziawg
chmod 700 /etc/amnezia/amneziawg

echo "=== Firewall ==="
read -rp "SSH порт [22]: " SSH_PORT
SSH_PORT=${SSH_PORT:-22}

ufw allow "${SSH_PORT}/tcp" comment "SSH" || true
ufw allow 80/tcp  comment "HTTP"  || true
ufw allow 443/tcp comment "HTTPS" || true

echo "=== UFW FORWARD policy ==="
sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

ufw --force enable || true
ufw status verbose

echo "======================================="
echo "✓ Установка завершена"
echo ""
echo "Дальше:"
echo "1. Сгенерируй конфиг: ./gen_awg2.sh"
echo "2. Запусти: systemctl start awg-quick@awg0"
echo "3. Автозапуск (после создания конфига):"
echo "   systemctl enable awg-quick@awg0"
echo "======================================="
