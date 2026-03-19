#!/bin/bash
set -euo pipefail
[[ $EUID -ne 0 ]] && { echo "Запускай от root"; exit 1; }

SERVER_CONF="/etc/amnezia/amneziawg/awg0.conf"
[[ ! -f "$SERVER_CONF" ]] && { echo "ОШИБКА: конфиг сервера не найден ($SERVER_CONF)"; exit 1; }
command -v awg  &>/dev/null || { echo "ОШИБКА: awg не найден"; exit 1; }
command -v curl &>/dev/null || { echo "ОШИБКА: curl не найден"; exit 1; }

# ── Следующий свободный IP ─────────────────────────────────
SERVER_NET=$(grep "^Address" "$SERVER_CONF" | awk -F'=' '{print $2}' | tr -d ' ')
BASE_IP=$(echo "$SERVER_NET" | cut -d. -f1-3)
LAST_IP=$(grep "^AllowedIPs" "$SERVER_CONF" | awk -F'=' '{print $2}' | tr -d ' ' \
  | cut -d/ -f1 | cut -d. -f4 | sort -n | tail -1)
LAST_IP=${LAST_IP:-1}
NEXT_IP=$((LAST_IP + 1))
CLIENT_ADDR="${BASE_IP}.${NEXT_IP}/32"

echo ""
echo "Следующий свободный IP: $CLIENT_ADDR"
read -rp "Имя клиента (пример: phone, laptop): " CLIENT_NAME
[[ -z "$CLIENT_NAME" ]] && { echo "ОШИБКА: имя не может быть пустым"; exit 1; }

read -rp "Использовать IP $CLIENT_ADDR? [Y/n]: " CONFIRM_IP
CONFIRM_IP=${CONFIRM_IP:-y}
if [[ ! $CONFIRM_IP =~ ^[Yy]$ ]]; then
  read -rp "Введи IP вручную (пример: ${BASE_IP}.5/32): " CLIENT_ADDR
fi

# ── Выбор DNS ──────────────────────────────────────────────
echo ""
echo "DNS:"
echo "  1) Cloudflare  — 1.1.1.1, 1.0.0.1"
echo "  2) Google      — 8.8.8.8, 8.8.4.4"
echo "  3) OpenDNS     — 208.67.222.222, 208.67.220.220"
echo "  4) Вручную"
read -rp "Выбор [1-4] (Enter = Cloudflare): " DNS_CHOICE
DNS_CHOICE=${DNS_CHOICE:-1}
case $DNS_CHOICE in
  1) CLIENT_DNS="1.1.1.1, 1.0.0.1" ;;
  2) CLIENT_DNS="8.8.8.8, 8.8.4.4" ;;
  3) CLIENT_DNS="208.67.222.222, 208.67.220.220" ;;
  4) read -rp "DNS: " CLIENT_DNS ;;
  *) CLIENT_DNS="1.1.1.1, 1.0.0.1" ;;
esac

# ── Выбор I1 ───────────────────────────────────────────────
# Без <c><t><r 16> — совместимо со всеми версиями AmneziaVPN
echo ""
echo "Имитация протокола (I1):"
echo "  1) Google DNS (рекомендуется, совместимо со всеми клиентами)"
echo "  2) Яндекс/Кинопоиск DNS"
echo "  3) Из серверного конфига"
echo "  4) Без имитации (AWG 1.0)"
read -rp "Выбор [1-4] (Enter = Google): " I1_CHOICE
I1_CHOICE=${I1_CHOICE:-1}
case $I1_CHOICE in
  1) I1_LINE="I1 = <b 0x84050100000100000000000006676f6f676c6503636f6d0000010001>" ;;
  2) I1_LINE="I1 = <b 0x084481800001000300000000077469636b65747306776964676574096b696e6f706f69736b0272750000010001c00c0005000100000039001806776964676574077469636b6574730679616e646578c025c0390005000100000039002b1765787465726e616c2d7469636b6574732d776964676574066166697368610679616e646578036e657400c05d000100010000001c000457fafe25>" ;;
  3) I1_LINE=$(grep "^I1" "$SERVER_CONF" || true) ;;
  4) I1_LINE="" ;;
  *) I1_LINE="I1 = <b 0x84050100000100000000000006676f6f676c6503636f6d0000010001>" ;;
esac

# ── Данные сервера ─────────────────────────────────────────
SERVER_PUBKEY=$(awg show awg0 public-key 2>/dev/null) \
  || { echo "ОШИБКА: интерфейс awg0 не поднят. Запусти: awg-quick up $SERVER_CONF"; exit 1; }
SERVER_IP=$(curl -s --connect-timeout 10 -4 ifconfig.me)
[[ -z "$SERVER_IP" ]] && { echo "ОШИБКА: не удалось получить внешний IP"; exit 1; }
PORT=$(grep "^ListenPort" "$SERVER_CONF" | awk -F'=' '{print $2}' | tr -d ' ')
MTU=$(grep "^PostUp" "$SERVER_CONF" | grep -oP 'mtu \K\d+' | head -1 || true)
MTU=${MTU:-1380}

# ── Генерация ключей ───────────────────────────────────────
CLIENT_PRIVKEY=$(awg genkey)
CLIENT_PUBKEY=$(echo "$CLIENT_PRIVKEY" | awg pubkey)
PRESHARED_KEY=$(awg genpsk)

# ── Добавляем peer в серверный конфиг ─────────────────────
{
  echo ""
  echo "[Peer]"
  echo "# $CLIENT_NAME"
  echo "PublicKey = $CLIENT_PUBKEY"
  echo "PresharedKey = $PRESHARED_KEY"
  echo "AllowedIPs = $CLIENT_ADDR"
} >> "$SERVER_CONF"

awg set awg0 peer "$CLIENT_PUBKEY" \
  preshared-key <(echo "$PRESHARED_KEY") \
  allowed-ips "$CLIENT_ADDR"

# ── Клиентский конфиг ──────────────────────────────────────
CLIENT_FILE="/root/${CLIENT_NAME}_awg2.conf"
{
  echo "[Interface]"
  echo "PrivateKey = $CLIENT_PRIVKEY"
  echo "Address = $CLIENT_ADDR"
  echo "DNS = $CLIENT_DNS"
  echo "MTU = $MTU"
  grep -E "^(Jc|Jmin|Jmax|S1|S2|S3|S4|H1|H2|H3|H4) " "$SERVER_CONF" | head -12
  [[ -n "$I1_LINE" ]] && echo "$I1_LINE"
  echo ""
  echo "[Peer]"
  echo "PublicKey = $SERVER_PUBKEY"
  echo "PresharedKey = $PRESHARED_KEY"
  echo "Endpoint = $SERVER_IP:$PORT"
  echo "AllowedIPs = 0.0.0.0/0, ::/0"
  echo "PersistentKeepalive = 25"
} > "$CLIENT_FILE"
chmod 600 "$CLIENT_FILE"

# ── QR-код ─────────────────────────────────────────────────
command -v qrencode &>/dev/null && qrencode -t ansiutf8 -s 1 -m 1 < "$CLIENT_FILE"

echo "======================================="
echo "✓ Клиент: $CLIENT_NAME"
echo "✓ IP:     $CLIENT_ADDR"
echo "✓ DNS:    $CLIENT_DNS"
echo "✓ MTU:    $MTU"
echo "✓ Конфиг: $CLIENT_FILE"
echo "======================================="
