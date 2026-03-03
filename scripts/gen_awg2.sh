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
read -rp "Выбор [1-4]: " DNS_CHOICE

case $DNS_CHOICE in
  1) CLIENT_DNS="1.1.1.1, 1.0.0.1" ;;
  2) CLIENT_DNS="8.8.8.8, 8.8.4.4" ;;
  3) CLIENT_DNS="208.67.222.222, 208.67.220.220" ;;
  4) read -rp "Введи DNS (через запятую): " CLIENT_DNS ;;
  *) CLIENT_DNS="1.1.1.1, 1.0.0.1" ;;
esac

# ── Выбор IP клиента ───────────────────────────────────────
echo ""
echo "Выбери Address для клиента:"
echo "  1) 10.8.0.2/32"
echo "  2) 10.8.1.2/32"
echo "  3) 10.10.0.2/32"
echo "  4) 10.10.11.2/32"
echo "  5) Ввести вручную"
read -rp "Выбор [1-5]: " ADDR_CHOICE

case $ADDR_CHOICE in
  1) CLIENT_ADDR="10.8.0.2/32";   SERVER_ADDR="10.8.0.1/24";   CLIENT_NET="10.8.0.0/24" ;;
  2) CLIENT_ADDR="10.8.1.2/32";   SERVER_ADDR="10.8.1.1/24";   CLIENT_NET="10.8.1.0/24" ;;
  3) CLIENT_ADDR="10.10.0.2/32";  SERVER_ADDR="10.10.0.1/24";  CLIENT_NET="10.10.0.0/24" ;;
  4) CLIENT_ADDR="10.10.11.2/32"; SERVER_ADDR="10.10.11.1/24"; CLIENT_NET="10.10.11.0/24" ;;
  5)
    read -rp "Введи IP клиента (пример: 10.20.0.2/32): " CLIENT_ADDR
    read -rp "Введи IP сервера (пример: 10.20.0.1/24): " SERVER_ADDR
    read -rp "Введи подсеть для NAT (пример: 10.20.0.0/24): " CLIENT_NET
    ;;
  *) CLIENT_ADDR="10.8.0.2/32"; SERVER_ADDR="10.8.0.1/24"; CLIENT_NET="10.8.0.0/24" ;;
esac

# ── Выбор MTU ──────────────────────────────────────────────
echo ""
echo "Выбери MTU:"
echo "  1) 1420 — стандартный"
echo "  2) 1380 — лучше для мобильных / нестабильных сетей"
echo "  3) 1280 — максимальная совместимость"
echo "  4) Ввести вручную"
read -rp "Выбор [1-4]: " MTU_CHOICE

case $MTU_CHOICE in
  1) MTU=1420 ;;
  2) MTU=1380 ;;
  3) MTU=1280 ;;
  4) read -rp "Введи MTU (1280-1420): " MTU ;;
  *) MTU=1420 ;;
esac

echo ""
echo "✓ DNS:    $CLIENT_DNS"
echo "✓ Клиент: $CLIENT_ADDR"
echo "✓ Сервер: $SERVER_ADDR"
echo "✓ MTU:    $MTU"
read -rp "Продолжить? [y/n]: " CONFIRM
[[ $CONFIRM != "y" ]] && { echo "Отменено."; exit 0; }

# ── Ключи ──────────────────────────────────────────────────
SERVER_PRIVKEY=$(awg genkey)
SERVER_PUBKEY=$(echo "$SERVER_PRIVKEY" | awg pubkey)
CLIENT_PRIVKEY=$(awg genkey)
CLIENT_PUBKEY=$(echo "$CLIENT_PRIVKEY" | awg pubkey)
PRESHARED_KEY=$(awg genpsk)

SERVER_IP=$(curl -s -4 ifconfig.me)
PORT=51820
IFACE=$(ip route | awk '/default/{print $5; exit}')

Jc=$((RANDOM % 5 + 3))
Jmin=10
Jmax=50
S1=$((RANDOM % 100 + 50))
S2=$((RANDOM % 100 + 50))
S3=$((RANDOM % 5 + 1))
S4=$((RANDOM % 3 + 1))

mapfile -t STARTS < <(shuf -i 1000000000-2000000000 -n 4 | sort -n)
H1="${STARTS[0]}-$((STARTS[0] + RANDOM % 300000000 + 50000000))"
H2="${STARTS[1]}-$((STARTS[1] + RANDOM % 300000000 + 50000000))"
H3="${STARTS[2]}-$((STARTS[2] + RANDOM % 300000000 + 50000000))"
H4="${STARTS[3]}-$((STARTS[3] + RANDOM % 100000000 + 10000000))"

I1='<b 0x084481800001000300000000077469636b65747306776964676574096b696e6f706f69736b0272750000010001c00c0005000100000039001806776964676574077469636b6574730679616e646578c025c0390005000100000039002b1765787465726e616c2d7469636b6574732d776964676574066166697368610679616e646578036e657400c05d000100010000001c000457fafe25>'

# ── IP Forwarding ──────────────────────────────────────────
echo 1 > /proc/sys/net/ipv4/ip_forward
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

mkdir -p /etc/amnezia/amneziawg

cat > /etc/amnezia/amneziawg/awg0.conf <<EOF
[Interface]
PrivateKey = $SERVER_PRIVKEY
Address = $SERVER_ADDR
ListenPort = $PORT
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

PostUp   = echo 1 > /proc/sys/net/ipv4/ip_forward; \
           iptables -t nat -A POSTROUTING -s $CLIENT_NET -o $IFACE -j MASQUERADE; \
           iptables -A FORWARD -i awg0 -j ACCEPT; \
           iptables -A FORWARD -o awg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s $CLIENT_NET -o $IFACE -j MASQUERADE; \
           iptables -D FORWARD -i awg0 -j ACCEPT; \
           iptables -D FORWARD -o awg0 -j ACCEPT

[Peer]
PublicKey = $CLIENT_PUBKEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = $CLIENT_ADDR
EOF

chmod 600 /etc/amnezia/amneziawg/awg0.conf

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

[Peer]
PublicKey = $SERVER_PUBKEY
PresharedKey = $PRESHARED_KEY
Endpoint = $SERVER_IP:$PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 /root/client1_awg2.conf

awg-quick up /etc/amnezia/amneziawg/awg0.conf

which qrencode &>/dev/null && qrencode -t ansiutf8 < /root/client1_awg2.conf

echo "======================================="
echo "✓ Сервер: /etc/amnezia/amneziawg/awg0.conf"
echo "✓ Клиент: /root/client1_awg2.conf"
echo "IP: $SERVER_IP:$PORT | Интерфейс: $IFACE"
echo "DNS: $CLIENT_DNS | MTU: $MTU"
echo "Адрес клиента: $CLIENT_ADDR"
echo "Jc=$Jc Jmin=$Jmin Jmax=$Jmax"
echo "S1=$S1 S2=$S2 S3=$S3 S4=$S4"
echo "======================================="
