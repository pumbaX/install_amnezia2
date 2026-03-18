#!/usr/bin/env bash

set -e
[[ $EUID -ne 0 ]] && { echo "Run as root"; exit 1; }
command -v awg >/dev/null || { echo "awg not installed"; exit 1; }

echo ""
echo "DNS:"
echo "1) Cloudflare (1.1.1.1)"
echo "2) Google (8.8.8.8)"
echo "3) OpenDNS"
echo "4) Manual"
read -rp "Choice [1-4]: " DNS_CHOICE
DNS_CHOICE=${DNS_CHOICE:-1}

case $DNS_CHOICE in
  1) CLIENT_DNS="1.1.1.1,1.0.0.1" ;;
  2) CLIENT_DNS="8.8.8.8,8.8.4.4" ;;
  3) CLIENT_DNS="208.67.222.222,208.67.220.220" ;;
  4) read -rp "Enter DNS: " CLIENT_DNS ;;
  *) CLIENT_DNS="1.1.1.1,1.0.0.1" ;;
esac

echo ""
echo "MTU:"
echo "1) 1420 (default)"
echo "2) 1380 (mobile)"
echo "3) 1280 (safe)"
echo "4) manual"
read -rp "Choice [1-4]: " MTU_CHOICE
MTU_CHOICE=${MTU_CHOICE:-2}

case $MTU_CHOICE in
  1) MTU=1420 ;;
  2) MTU=1380 ;;
  3) MTU=1280 ;;
  4) read -rp "Enter MTU: " MTU ;;
  *) MTU=1380 ;;
esac

CLIENT_ADDR="10.8.0.2/32"
SERVER_ADDR="10.8.0.1/24"
CLIENT_NET="10.8.0.0/24"

PORT=$((RANDOM % 20000 + 30000))

SERVER_PRIV=$(awg genkey)
SERVER_PUB=$(echo "$SERVER_PRIV" | awg pubkey)
CLIENT_PRIV=$(awg genkey)
CLIENT_PUB=$(echo "$CLIENT_PRIV" | awg pubkey)
PSK=$(awg genpsk)

SERVER_IP=$(curl -s ifconfig.me)
IFACE=$(ip route | awk '/default/ {print $5; exit}')

Jc=$((RANDOM % 3 + 4))
Jmin=20
Jmax=80

S1=$((RANDOM % 30 + 10))
S2=$((RANDOM % 30 + 20))
[[ $S2 -eq $((S1 + 56)) ]] && S2=$((S2 + 1))
S3=$((RANDOM % 20 + 5))
S4=$((RANDOM % 16 + 1))

Q=$((4294967295 / 4))
H1="$((RANDOM % Q))-$((RANDOM % Q + 30000))"
H2="$((Q + RANDOM % Q))-$((Q + RANDOM % Q + 30000))"
H3="$((Q*2 + RANDOM % Q))-$((Q*2 + RANDOM % Q + 30000))"
H4="$((Q*3 + RANDOM % Q))-$((Q*3 + RANDOM % Q + 30000))"

case $((RANDOM % 3)) in
  0) I1='<b 0x84050100000100000000000006676f6f676c6503636f6d0000010001>' ;;
  1) I1='<b 0xc700000001><rc 8><c><t><r 32>' ;;
  2) I1='<b 0x00000001><r 64>' ;;
esac

mkdir -p /etc/amnezia/amneziawg

awg-quick down /etc/amnezia/amneziawg/awg0.conf 2>/dev/null || true
ip link delete awg0 2>/dev/null || true

cat > /etc/amnezia/amneziawg/awg0.conf <<EOF
[Interface]
PrivateKey = $SERVER_PRIV
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

PostUp = ip link set awg0 mtu $MTU; iptables -t nat -A POSTROUTING -s $CLIENT_NET -o $IFACE -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s $CLIENT_NET -o $IFACE -j MASQUERADE

[Peer]
PublicKey = $CLIENT_PUB
PresharedKey = $PSK
AllowedIPs = $CLIENT_ADDR
EOF

cat > /root/client_awg.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
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
PublicKey = $SERVER_PUB
PresharedKey = $PSK
Endpoint = $SERVER_IP:$PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

sysctl -w net.ipv4.ip_forward=1
awg-quick up /etc/amnezia/amneziawg/awg0.conf

echo "DONE: $SERVER_IP:$PORT"
