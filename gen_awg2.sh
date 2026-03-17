#!/bin/bash

set -e
[[ $EUID -ne 0 ]] && { echo "Запускай от root"; exit 1; }
command -v awg &>/dev/null || { echo "ОШИБКА: сначала запусти install.sh"; exit 1; }

# ── Выбор DNS ──────────────────────────────────────────────
echo ""
echo "Выбери DNS для клиента:"
echo "  1) Cloudflare  — 1.1.1.1, 1.0.0.1"
echo "  2) Google      — 8.8.8.8, 8.8.4.4"
echo "  3) OpenDNS     — 208.67.222.222, 208.67.220.220"
echo "  4) Ввести вручную"
read -rp "Выбор [1-4] (Enter = Cloudflare): " DNS_CHOICE
DNS_CHOICE=${DNS_CHOICE:-1}

case $DNS_CHOICE in
  1) CLIENT_DNS="1.1.1.1, 1.0.0.1" ;;
  2) CLIENT_DNS="8.8.8.8, 8.8.4.4" ;;
  3) CLIENT_DNS="208.67.222.222, 208.67.220.220" ;;
  4) read -rp "Введи DNS: " CLIENT_DNS ;;
  *) CLIENT_DNS="1.1.1.1, 1.0.0.1" ;;
esac

# ── Выбор IP ───────────────────────────────────────────────
echo ""
echo "Выбери Address для клиента:"
echo "  1) 10.8.0.2/32"
echo "  2) 10.8.1.2/32"
echo "  3) 10.11.2.2/32"
echo "  4) 10.20.11.2/32"
echo "  5) Ввести вручную"
read -rp "Выбор [1-5] (Enter = 10.8.0.2): " ADDR_CHOICE
ADDR_CHOICE=${ADDR_CHOICE:-1}

case $ADDR_CHOICE in
  1) CLIENT_ADDR="10.8.0.2/32";   SERVER_ADDR="10.8.0.1/24";   CLIENT_NET="10.8.0.0/24" ;;
  2) CLIENT_ADDR="10.8.1.2/32";   SERVER_ADDR="10.8.1.1/24";   CLIENT_NET="10.8.1.0/24" ;;
  3) CLIENT_ADDR="10.11.2.2/32";  SERVER_ADDR="10.11.2.1/24";  CLIENT_NET="10.11.2.0/24" ;;
  4) CLIENT_ADDR="10.20.11.2/32"; SERVER_ADDR="10.20.11.1/24"; CLIENT_NET="10.20.11.0/24" ;;
  5)
    read -rp "IP клиента: " CLIENT_ADDR
    read -rp "IP сервера: " SERVER_ADDR
    read -rp "Подсеть NAT: " CLIENT_NET
    ;;
  *) CLIENT_ADDR="10.8.0.2/32"; SERVER_ADDR="10.8.0.1/24"; CLIENT_NET="10.8.0.0/24" ;;
esac

# ── Выбор MTU ──────────────────────────────────────────────
echo ""
echo "Выбери MTU:"
echo "  1) 1420 — стандартный"
echo "  2) 1380 — лучше для мобильных"
echo "  3) 1280 — максимальная совместимость"
echo "  4) Ввести вручную"
read -rp "Выбор [1-4] (Enter = 1380): " MTU_CHOICE
MTU_CHOICE=${MTU_CHOICE:-2}

case $MTU_CHOICE in
  1) MTU=1420 ;;
  2) MTU=1380 ;;
  3) MTU=1280 ;;
  4) read -rp "MTU: " MTU ;;
  *) MTU=1380 ;;
esac

# ── Выбор порта ────────────────────────────────────────────
echo ""
read -rp "Порт сервера [51820 / r = случайный]: " PORT
if [[ "$PORT" == "r" || "$PORT" == "R" ]]; then
  PORT=$(( RANDOM % 35500 + 30001 ))
  echo "  → случайный порт: $PORT"
else
  PORT=${PORT:-51820}
fi

echo ""
echo "✓ DNS:    $CLIENT_DNS"
echo "✓ Клиент: $CLIENT_ADDR"
echo "✓ Сервер: $SERVER_ADDR"
echo "✓ MTU:    $MTU"
echo "✓ Порт:   $PORT"
read -rp "Продолжить? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-y}
[[ $CONFIRM != "y" && $CONFIRM != "Y" ]] && { echo "Отменено."; exit 0; }

# ── Ключи ──────────────────────────────────────────────────
SERVER_PRIVKEY=$(awg genkey)
SERVER_PUBKEY=$(echo "$SERVER_PRIVKEY" | awg pubkey)
CLIENT_PRIVKEY=$(awg genkey)
CLIENT_PUBKEY=$(echo "$CLIENT_PRIVKEY" | awg pubkey)
PRESHARED_KEY=$(awg genpsk)

SERVER_IP=$(curl -s --connect-timeout 10 -4 ifconfig.me)
[[ -z "$SERVER_IP" ]] && { echo "ОШИБКА: не удалось получить внешний IP"; exit 1; }
IFACE=$(ip route | awk '/default/{print $5; exit}')

Jc=$((RANDOM % 5 + 3))
Jmin=10
Jmax=50
S1=$((RANDOM % 30 + 10))       # 10-39
S2=$((S1 + RANDOM % 20 + 1))   # != S1+56, ≤ 64
if [[ $S2 -gt 64 ]]; then S2=64; fi
if [[ $S2 -eq $((S1 + 56)) ]]; then S2=$((S2 + 1)); fi
if [[ $S2 -gt 64 ]]; then S2=1; fi
S3=$((RANDOM % 30 + 5))         # 5-34, ≤ 64
S4=$((RANDOM % 16 + 1))         # 1-16, строго ≤ 32

# H1-H4: равномерное распределение по всему uint32 (4 квадранта ~1 млрд каждый)
Q=$((4294967295 / 4))
H1_START=$(( RANDOM * RANDOM % Q ))
H1_W=$(( RANDOM % 100000 + 30000 ))
H1="${H1_START}-$((H1_START + H1_W))"

H2_START=$(( Q + RANDOM * RANDOM % Q ))
H2_W=$(( RANDOM % 100000 + 30000 ))
H2="${H2_START}-$((H2_START + H2_W))"

H3_START=$(( Q * 2 + RANDOM * RANDOM % Q ))
H3_W=$(( RANDOM % 100000 + 30000 ))
H3="${H3_START}-$((H3_START + H3_W))"

H4_START=$(( Q * 3 + RANDOM * RANDOM % Q ))
H4_W=$(( RANDOM % 100000 + 30000 ))
H4="${H4_START}-$((H4_START + H4_W))"

I1='<b 0x84050100000100000000000006676f6f676c6503636f6d0000010001>'

echo 1 > /proc/sys/net/ipv4/ip_forward
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

mkdir -p /etc/amnezia/amneziawg

# Снос старого интерфейса если есть
awg-quick down /etc/amnezia/amneziawg/awg0.conf 2>/dev/null || \
  ip link delete dev awg0 2>/dev/null || true

{
  echo "[Interface]"
  echo "PrivateKey = $SERVER_PRIVKEY"
  echo "Address = $SERVER_ADDR"
  echo "ListenPort = $PORT"
  echo "Jc = $Jc"
  echo "Jmin = $Jmin"
  echo "Jmax = $Jmax"
  echo "S1 = $S1"
  echo "S2 = $S2"
  echo "S3 = $S3"
  echo "S4 = $S4"
  echo "H1 = $H1"
  echo "H2 = $H2"
  echo "H3 = $H3"
  echo "H4 = $H4"
  echo "I1 = $I1"
  echo ""
  echo "PostUp   = ip link set dev awg0 mtu $MTU; echo 1 > /proc/sys/net/ipv4/ip_forward; iptables -t nat -A POSTROUTING -s $CLIENT_NET -o $IFACE -j MASQUERADE; iptables -A FORWARD -i awg0 -j ACCEPT; iptables -A FORWARD -o awg0 -j ACCEPT"
  echo "PostDown = iptables -t nat -D POSTROUTING -s $CLIENT_NET -o $IFACE -j MASQUERADE; iptables -D FORWARD -i awg0 -j ACCEPT; iptables -D FORWARD -o awg0 -j ACCEPT"
  echo ""
  echo "[Peer]"
  echo "PublicKey = $CLIENT_PUBKEY"
  echo "PresharedKey = $PRESHARED_KEY"
  echo "AllowedIPs = $CLIENT_ADDR"
} > /etc/amnezia/amneziawg/awg0.conf

chmod 600 /etc/amnezia/amneziawg/awg0.conf

{
  echo "[Interface]"
  echo "PrivateKey = $CLIENT_PRIVKEY"
  echo "Address = $CLIENT_ADDR"
  echo "DNS = $CLIENT_DNS"
  echo "MTU = $MTU"
  echo "Jc = $Jc"
  echo "Jmin = $Jmin"
  echo "Jmax = $Jmax"
  echo "S1 = $S1"
  echo "S2 = $S2"
  echo "S3 = $S3"
  echo "S4 = $S4"
  echo "H1 = $H1"
  echo "H2 = $H2"
  echo "H3 = $H3"
  echo "H4 = $H4"
  echo "I1 = $I1"
  echo ""
  echo "[Peer]"
  echo "PublicKey = $SERVER_PUBKEY"
  echo "PresharedKey = $PRESHARED_KEY"
  echo "Endpoint = $SERVER_IP:$PORT"
  echo "AllowedIPs = 0.0.0.0/0, ::/0"
  echo "PersistentKeepalive = 25"
} > /root/client1_awg2.conf

chmod 600 /root/client1_awg2.conf

awg-quick up /etc/amnezia/amneziawg/awg0.conf

# ── Открыть порт в UFW ─────────────────────────────────────
if command -v ufw &>/dev/null; then
  read -rp "Открыть порт $PORT/udp в UFW? [Y/n]: " OPEN_UFW
  OPEN_UFW=${OPEN_UFW:-y}
  if [[ $OPEN_UFW =~ ^[Yy]$ ]]; then
    ufw allow "${PORT}/udp" comment "AmneziaWG" || true
    echo "✓ Порт ${PORT}/udp открыт"
  fi
fi

which qrencode &>/dev/null && qrencode -t ansiutf8 -s 1 -m 1 < /root/client1_awg2.conf

echo "======================================="
echo "✓ Сервер: /etc/amnezia/amneziawg/awg0.conf"
echo "✓ Клиент: /root/client1_awg2.conf"
echo "IP: $SERVER_IP:$PORT | Интерфейс: $IFACE"
echo "DNS: $CLIENT_DNS | MTU: $MTU"
echo "Jc=$Jc Jmin=$Jmin Jmax=$Jmax"
echo "======================================="
