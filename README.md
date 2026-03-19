![image](https://github.com/pumbaX/install_amnezia2/blob/main/pic.png)

# Install_amnezia2

Два скрипта для быстрого развёртывания **AmneziaWG 2.0** на чистом VPS (Ubuntu 22.04 / 24.04).

## Что это

[AmneziaWG 2.0](https://amnezia.org/downloads) — продвинутый VPN-протокол на базе WireGuard с обфускацией трафика под обычные протоколы (QUIC, DNS и др.). Устойчив к DPI-блокировкам.

## Файлы

| Файл | Описание |
|---|---|
| `install.sh` | Установка зависимостей, модуля amneziawg, настройка firewall |
| `gen_awg2.sh` | Генерация серверного и клиентского конфига AWG 2.0 с интерактивным выбором параметров |
| `add_client.sh` | Добавление нового клиента к существующему серверу |

## Требования к серверу

- Ubuntu 22.04 или 24.04
- KVM-виртуализация (не OpenVZ/LXC)
- Публичный IPv4
- Root-доступ по SSH

## Установка

### Шаг 1 — клонируй репозиторий

```bash
git clone https://github.com/pumbaX/install_amnezia2.git
cd install_amnezia2
chmod +x install.sh gen_awg2.sh add_client.sh
```

### Шаг 2 — установка зависимостей

```bash
./install.sh
```

Скрипт установит:
- `amneziawg` + `amneziawg-tools` через официальный PPA
- Загрузит kernel-модуль `amneziawg`
- Включит IP forwarding
- Настроит UFW (порты 22, 51820)

> Если после `apt upgrade` система попросит перезагрузку — сделай `reboot` и запусти `./install.sh` снова.

### Шаг 3 — генерация конфига сервера и первого клиента

```bash
./gen_awg2.sh
```

Скрипт интерактивно спросит DNS, IP-подсеть, MTU, порт. После подтверждения:
- Сгенерирует ключи (сервер + клиент + preshared)
- Создаст случайные параметры обфускации (Jc, S1–S4, H1–H4 в виде диапазонов)
- Добавит `I1` — DNS-пакет для маскировки трафика (совместим со всеми версиями AmneziaVPN)
- Поднимет интерфейс `awg0`
- Выведет QR-код для импорта в приложение

### Шаг 4 — добавление клиентов

```bash
./add_client.sh
```

Или без клонирования:

```bash
bash <(curl -s https://raw.githubusercontent.com/pumbaX/install_amnezia2/main/add_client.sh)
```

### Шаг 5 — автостарт

```bash
systemctl enable awg-quick@awg0
```

## Параметры AWG 2.0

| Параметр | Описание |
|---|---|
| `Jc` | Кол-во мусорных пакетов перед хендшейком |
| `Jmin` / `Jmax` | Диапазон размера мусорных пакетов |
| `S1` / `S2` | Мусор в init и response пакетах |
| `S3` / `S4` | Доп. обфускация (AWG 2.0) |
| `H1`–`H4` | Magic-заголовки в виде диапазонов (AWG 2.0) |
| `I1` | Имитация реального протокола (DNS google.com) |

> **I1 совместимость**: скрипты используют формат без `<c><t><r 16>` — работает на всех версиях AmneziaVPN. Теги `<c><t><r 16>` вызывают ErrorCode 1000 на старых клиентах.

## Файлы после генерации

```
/etc/amnezia/amneziawg/awg0.conf   # серверный конфиг
/root/client1_awg2.conf             # клиентский конфиг (первый)
/root/<name>_awg2.conf              # клиенты добавленные через add_client.sh
```

## Импорт на клиенте

Используй приложение **AmneziaVPN**:
- Импорт через QR-код (выводится в терминале)
- Импорт через файл `.conf`

Скачать: [amnezia.org/downloads](https://amnezia.org/downloads)

## Сброс и переустановка

```bash
awg-quick down /etc/amnezia/amneziawg/awg0.conf 2>/dev/null || true
rm -rf /etc/amnezia
rm -f /root/*_awg2.conf
ip link delete dev awg0 2>/dev/null || true
```
