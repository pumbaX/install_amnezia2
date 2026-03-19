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
  build-essential git \
  net-tools curl ufw iptables qrencode

# Headers — fallback на generic если текущее ядро не найдено
apt-get install -y -q linux-headers-$(uname -r) 2>/dev/null || \
  apt-get install -y -q linux-headers-generic || \
  { echo "ОШИБКА: не удалось установить linux-headers"; exit 1; }

echo "=== AmneziaWG kernel module (PPA) ==="
add-apt-repository -y ppa:amnezia/ppa
apt-get update -q
apt-get install -y -q amneziawg

echo "=== Проверка модуля ==="
modprobe amneziawg || { echo "ОШИБКА: сделай reboot и запусти снова"; exit 1; }
lsmod | grep -q amneziawg && echo "✓ модуль загружен"

# ── Выбор версии amneziawg-tools ──────────────────────────
echo ""
echo "Выбери версию amneziawg-tools (awg / awg-quick):"
echo ""
echo "  1) PPA — v1.0.20210914"
echo "     Старая версия. AWG 1.5: Jc/Jmin/Jmax, S1/S2, H1-H4 одиночные, I1-I5."
echo "     Без S3/S4 и H1-H4 диапазонов. Совместима со всеми клиентами."
echo ""
echo "  2) GitHub — v1.0.20260223 (рекомендуется)"
echo "     Сборка из исходников. Полный AWG 2.0: S3/S4, H1-H4 диапазоны,"
echo "     полный I1 с тегами <c><t><r 16>, I2-I5. Требует AmneziaVPN 4.8+ на клиенте."
echo ""
read -rp "Выбор [1-2] (Enter = GitHub): " TOOLS_CHOICE
TOOLS_CHOICE=${TOOLS_CHOICE:-2}

case $TOOLS_CHOICE in
  1)
    echo "=== amneziawg-tools из PPA ==="
    apt-get install -y -q amneziawg-tools
    ;;
  *)
    echo "=== amneziawg-tools из исходников (GitHub) ==="
    rm -rf /tmp/awg-tools
    git clone https://github.com/amnezia-vpn/amneziawg-tools.git /tmp/awg-tools \
      || { echo "ОШИБКА: git clone провалился"; exit 1; }
    make -C /tmp/awg-tools/src \
      || { echo "ОШИБКА: сборка awg-tools провалилась"; exit 1; }
    make -C /tmp/awg-tools/src install \
      || { echo "ОШИБКА: установка awg-tools провалилась"; exit 1; }
    rm -rf /tmp/awg-tools
    ;;
esac

command -v awg &>/dev/null \
  && echo "✓ amneziawg-tools: $(awg --version)" \
  || { echo "ОШИБКА: awg не найден в PATH после установки"; exit 1; }

echo "=== IP Forwarding ==="
echo 1 > /proc/sys/net/ipv4/ip_forward
grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || \
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p -q

echo "=== Папка конфигов ==="
mkdir -p /etc/amnezia/amneziawg
chmod 700 /etc/amnezia/amneziawg

echo "=== Firewall ==="
ufw allow 22/tcp  comment "SSH"   || true
ufw allow 80/tcp  comment "HTTP"  || true
ufw allow 443/tcp comment "HTTPS" || true

read -rp "Открыть порт AmneziaWG? [Y/n]: " OPEN_PORT
OPEN_PORT=${OPEN_PORT:-y}
if [[ $OPEN_PORT =~ ^[Yy]$ ]]; then
  read -rp "Порт [51820]: " AWG_PORT
  AWG_PORT=${AWG_PORT:-51820}
  ufw allow "${AWG_PORT}/udp" comment "AmneziaWG" || true
  echo "✓ Порт ${AWG_PORT}/udp открыт"
fi

ufw --force enable || true
ufw status

echo "=== Автозапуск AWG ==="
systemctl enable awg-quick@awg0 2>/dev/null || true
echo "✓ Автозапуск awg-quick@awg0 включён"

echo "======================================="
echo "✓ Установка завершена"
echo "Теперь запускай: ./gen_awg2.sh"
echo "======================================="
