# prepare.sh

Скрипт ставит и проверяет набор инструментов для внутреннего тестирования на проникновение на Kali Linux AMD64. Он устанавливает системные зависимости, Go и uv, скачивает закреплённые релизы, создаёт окружения python и обёртки команд, настраивает tmux, Nuclei и локальный проект BloodHound.

> Установка поддерживается только на Kali Linux AMD64. Скрипт необходимо запускать от обычного пользователя, а все необходимые операции он сам выполнит через sudo.

Точные URL, версии, коммиты и контрольные суммы задаются в [`prepare.sh`](./prepare.sh) и являются источником правды. Скрипт предназначен только для систем и инфраструктуры, на проверку которых у вас есть разрешение.

## Быстрый старт

### Автоматическая установка

`--auto` не задаёт вопросов и применяет действия по умолчанию, включая удаление предустановленных `netexec`, `python3-msldap`, `dnsrecon` и `certipy-ad`. Перед запуском нужно заранее открыть сессию sudo:

```bash
sudo -v && curl -fsSL https://raw.githubusercontent.com/ShAmRoWw/prepare.sh/refs/heads/main/prepare.sh | bash -s -- --auto
```

### Запуск из репозитория

```bash
git clone https://github.com/ShAmRoWw/prepare.sh.git
cd prepare.sh && chmod +x prepare.sh
# Интерактивная установка
./prepare.sh --install

# Только проверка того, какие инструменты уже установлены
./prepare.sh
```

После установки перезагрузите оболочку или примените изменённый `PATH`:

```bash
source ~/.zshrc
```

## Что устанавливается

### Системные пакеты APT

Основной список:

```text
git curl wget python3-pip libpcap-dev libkrb5-dev seclists wmctrl
tmux unzip libsqlite3-dev build-essential cargo bind9-dnsutils util-linux
nftables python3-nftables tesseract-ocr libreoffice
```

Дополнительно по необходимости:

- `chromium`, если не найден рабочий Chromium или Google Chrome для `gowitness`;
- `docker.io`, если команда docker отсутствует или не работает;
- `docker-compose`, если недоступны и `docker compose`, и `docker-compose`.

Для DNS используется пакет `bind9-dnsutils`.

### go и go-утилиты

- go `1.26.5` устанавливается в `/usr/local/go` из официального архива с проверкой SHA-256, только если go ещё не найден.
- `httpx` и `nuclei` устанавливаются в `~/go/bin`. Скрипт сначала пытается использовать официальный Linux AMD64 release текущей стабильной версии с проверкой checksum, модуля и заявленной версии, а при невозможности собирает тот же тег через `go install`.
- `katana` собирается в `~/go/bin` через `go install ...@latest` с `CGO_ENABLED=1`.

### Python утилиты через uv

Каждый инструмент устанавливается из git репозитория с ревизией, закреплённой в `UV_TOOLS`:

```text
penelope              ntlmv1-multi         wsuks
pyGPOAbuse            bloodhound-ce-python netexec
bloodyAD              pre2k                smbclientng
AD-Miner              conpass              ldeep
certipy               dnsrecon             msldap
RITM                  impacket             manspider
```

### Закреплённые бинарные релизы

| Инструмент | Версия | Устанавливаемые команды |
| --- | --- | --- |
| pretender | `v1.4.1` | `pretender` |
| flashingestor | `v0.4.1` | `flashingestor`, `dcprobe`, `ingest2json` |
| rusthound-ce | `v2.4.91` | `rusthound-ce` |
| kerbrute | `v1.0.3` | `kerbrute` |
| legba | `1.3.0` | `legba` |
| bettercap | `v2.41.7` | `bettercap` |
| gowitness | `3.1.1` | `gowitness` |

`chisel` версии `1.11.8` устанавливается отдельно в `~/tools/chisel/chisel`.

### Репозитории с отдельным venv

Все репозитории клонируются в `~/tools/<имя>` на закреплённый коммит. Для каждого создаётся venv и одна или несколько команд в `~/.local/bin`.

| Репозиторий | Основная команда | Дополнительные команды |
| --- | --- | --- |
| krbrelayx | `krbrelayx` | `krbrelayx.py`, `addspn.py`, `dnstool.py`, `printerbug.py` |
| bloodhound-automation | `bloodhound-automation` | — |
| targetedKerberoast | `targetedKerberoast` | — |
| pyLDAPWordlistHarvester | `pyLDAPWordlistHarvester` | `LDAPWordlistHarvester.py` |
| ASRepCatcher | `ASRepCatcher` | — |
| PCredz | `PCredz` | `Pcredz` |
| CVE-2025-33073 | `CVE-2025-33073` | — |
| gssapi-abuse | `gssapi-abuse` | — |
| CVE-2026-54121 | `CVE-2026-54121` | `certighost.py` |
| SCCMSecrets | `SCCMSecrets` | — |
| cmloot | `cmloot` | — |

### Windows утилиты

В `~/tools/for_windows`:

- `Group3r.exe` `1.0.69`;
- `Snaffler.exe` `1.0.244`.

### tmux и журналирование

Скрипт клонирует в `~/.tmux/plugins`:

- `tmux-plugins/tpm`;
- `tmux-plugins/tmux-sensible`;
- `ShAmRoWw/tmux-logging`.

Если уже существует `$XDG_CONFIG_HOME/tmux/tmux.conf` (по умолчанию `~/.config/tmux/tmux.conf`), используется он; иначе изменяется `~/.tmux.conf`. Пользовательские строки сохраняются, а управляемые параметры помещаются между маркерами `BEGIN/END prepare.sh`:

- `history-limit 100000`;
- `mouse on`;
- настройки TPM и трёх плагинов;
- каталог журналов `~/tmux_logs/%Y-%m-%d`.

Перед публикацией конфигурация проверяется в изолированном tmux-сервере. Если tmux уже запущен, файл сразу перечитывается.

### Шаблоны Nuclei

При первой установке определяется последний стабильный тег `nuclei-templates`, скачиваются архив и официальный checksum, после чего шаблоны публикуются в `~/tools/nuclei-templates`. Путь сохраняется в конфигурации Nuclei.

### Docker и BloodHound

Docker включается и запускается через systemd. Текущий пользователь добавляется в группу `docker`; до следующего входа в систему установщик и обёртка `bloodhound-automation` выполняют Docker-команды через `sg docker`.

