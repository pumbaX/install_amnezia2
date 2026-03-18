#!/bin/bash

set -e
[[ $EUID -ne 0 ]] && { echo "Запускай от root"; exit 1; }
command -v awg &>/dev/null || { echo "ОШИБКА: сначала запусти install.sh"; exit 1; }

── DNS ────────────────────────────────────────────────────

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

── IP ─────────────────────────────────────────────────────

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

── MTU ────────────────────────────────────────────────────

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

── Порт ───────────────────────────────────────────────────

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

── Ключи ──────────────────────────────────────────────────

SERVER_PRIVKEY=$(awg genkey)
SERVER_PUBKEY=$(echo "$SERVER_PRIVKEY" | awg pubkey)
CLIENT_PRIVKEY=$(awg genkey)
CLIENT_PUBKEY=$(echo "$CLIENT_PRIVKEY" | awg pubkey)
PRESHARED_KEY=$(awg genpsk)

SERVER_IP=$(curl -s --connect-timeout 10 -4 ifconfig.me)
[[ -z "$SERVER_IP" ]] && { echo "ОШИБКА: не удалось получить внешний IP"; exit 1; }
IFACE=$(ip route | awk '/default/{print $5; exit}')

── Junk / Obfs ────────────────────────────────────────────

Jc=$((RANDOM % 5 + 3))
Jmin=10
Jmax=50
S1=$((RANDOM % 30 + 10))
S2=$((S1 + RANDOM % 20 + 1)); [[ $S2 -gt 64 ]] && S2=64
[[ $S2 -eq $((S1 + 56)) ]] && S2=$((S2 + 1))
S3=$((RANDOM % 30 + 5))
S4=$((RANDOM % 16 + 1))

Q=$((4294967295 / 4))
H1="$(( RANDOM * RANDOM % Q ))-$(( RANDOM * RANDOM % Q + 30000 ))"
H2="$(( Q + RANDOM * RANDOM % Q ))-$(( Q + RANDOM * RANDOM % Q + 30000 ))"
H3="$(( Q2 + RANDOM * RANDOM % Q ))-$(( Q2 + RANDOM * RANDOM % Q + 30000 ))"
H4="$(( Q3 + RANDOM * RANDOM % Q ))-$(( Q3 + RANDOM * RANDOM % Q + 30000 ))"

I1='<b 0x84050100000100000000000006676f6f676c6503636f6d0000010001>'

── L1 (КЛЮЧЕВОЕ) ──────────────────────────────────────────

L1_LEN=$((RANDOM % 16 + 16))
L1="0x$(head -c $L1_LEN /dev/urandom | xxd -p -c $L1_LEN)"

echo "✓ L1: $L1"

echo 1 > /proc/sys/net/ipv4/ip_forward
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

mkdir -p /etc/amnezia/amneziawg

awg-quick down /etc/amnezia/amneziawg/awg0.conf 2>/dev/null || ip link delete dev awg0 2>/dev/null || true

── SERVER ─────────────────────────────────────────────────

cat > /etc/amnezia/amneziawg/awg0.conf <<EOF
[Interface]
PrivateKey = $SERVER_PRIVKEY
Address = $SERVER_ADDR
ListenPort = $PORT
Jc = $Jc
Jmin = $Jmin
Jmax = $Jmax
S1 = $S1
S2 = $S2
S3 = $S3
S4 = $S4
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4
I1 = $I1
SpecialJunkL1 = $L1

PostUp   = ip link set dev awg0 mtu $MTU; iptables -t nat -A POSTROUTING -s $CLIENT_NET -o $IFACE -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s $CLIENT_NET -o $IFACE -j MASQUERADE

[Peer]
PublicKey = $CLIENT_PUBKEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = $CLIENT_ADDR
EOF

── CLIENT ────────────────────────────────────────────────

cat > /root/client1_awg2.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVKEY
Address = $CLIENT_ADDR
DNS = $CLIENT_DNS
MTU = $MTU
Jc = $Jc
Jmin = $Jmin
Jmax = $Jmax
S1 = $S1
S2 = $S2
S3 = $S3
S4 = $S4
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4
I1 = $I1
SpecialJunkL1 = $L1

[Peer]
PublicKey = $SERVER_PUBKEY
PresharedKey = $PRESHARED_KEY
Endpoint = $SERVER_IP:$PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

awg-quick up /etc/amnezia/amneziawg/awg0.conf

echo "✓ Готово. L1 синхронизирован."
