
![image](https://github.com/pumbaX/install_amnezia.sh/blob/main/pic.png)

# Install_amnezia.sh!
Два скрипта для быстрого развёртывания **AmneziaWG 2.0** на чистом VPS (Ubuntu 22.04 / 24.04).

## Что это

[AmneziaWG 2.0](https://docs.amnezia.org) — продвинутый VPN-протокол на базе WireGuard с обфускацией трафика под обычные протоколы (QUIC, DNS и др.). Устойчив к DPI-блокировкам.

## Файлы

| Файл | Описание |
|---|---|
| `install.sh` | Установка зависимостей, модуля amneziawg, настройка firewall |
| `gen_awg2.sh` | Генерация серверного и клиентского конфига AWG 2.0 с интерактивным выбором параметров |

## Требования к серверу

- Ubuntu 22.04 или 24.04
- KVM-виртуализация (не OpenVZ/LXC)
- Публичный IPv4
- Root-доступ по SSH

## Установка

### Шаг 1 — клонируй репозиторий

```bash
git clone https://github.com/pumbaX/install_amnezia.sh.git
cd install_amnezia.sh
chmod +x install.sh gen_awg2.sh
```

### Шаг 2 — установка

```bash
./install.sh
```

Скрипт установит:
- `amneziawg` + `amneziawg-tools` через официальный PPA
- Загрузит kernel-модуль `amneziawg`
- Включит IP forwarding
- Настроит UFW (порты 22, 51820)

> Если после `apt upgrade` система попросит перезагрузку — сделай `reboot` и запусти `./install.sh` снова.

### Шаг 3 — генерация конфига

```bash
./gen_awg2.sh
```

Скрипт интерактивно спросит:

**DNS для клиента:**
```
1) Cloudflare  — 1.1.1.1, 1.0.0.1
2) Google      — 8.8.8.8, 8.8.4.4
3) OpenDNS     — 208.67.222.222, 208.67.220.220
4) Ввести вручную
```

**IP-адрес клиента:**
```
1) 10.8.0.2/32
2) 10.8.1.2/32
3) 10.10.0.2/32
4) 10.10.11.2/32
5) Ввести вручную
```

После подтверждения скрипт:
- Сгенерирует ключи (сервер + клиент + preshared)
- Создаст случайные параметры обфускации (Jc, S1-S4, H1-H4 в виде диапазонов)
- Добавит I1 — DNS-пакет для маскировки трафика
- Поднимет интерфейс `awg0`
- Выведет QR-код для импорта в приложение

## Параметры AWG 2.0

| Параметр | Описание |
|---|---|
| `Jc` | Кол-во мусорных пакетов перед хендшейком |
| `Jmin` / `Jmax` | Диапазон размера мусорных пакетов |
| `S1` / `S2` | Мусор в init и response пакетах |
| `S3` / `S4` | Доп. обфускация (новое в 2.0) |
| `H1`-`H4` | Magic-заголовки в виде диапазонов (новое в 2.0) |
| `I1`-`I5` | Имитация реального протокола (QUIC, DNS и др.) |

## Файлы после генерации

```
/etc/amnezia/amneziawg/awg0.conf   # серверный конфиг
/root/client1_awg2.conf             # клиентский конфиг
```

## Импорт на клиенте

Используй приложение **AmneziaVPN версии 4.8.12.7+**:
- Импорт через QR-код (выводится в терминале)
- Импорт через файл `client1_awg2.conf`

Скачать: [amnezia.org/downloads](https://amnezia.org/downloads)

## Сброс и переустановка

```bash
awg-quick down /etc/amnezia/amneziawg/awg0.conf 2>/dev/null || true
rm -rf /etc/amnezia
rm -f /root/client1_awg2.conf
ip link delete dev awg0 2>/dev/null || true
./gen_awg2.sh
```

## Лицензия

MIT
