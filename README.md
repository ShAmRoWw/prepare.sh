# prepare.sh

Скрипт для развёртывания и поддержки набора инструментов внутреннего пентеста. Устанавливает утилиты из разных источников (apt, Go, uv/pip, git, бинарные релизы), отслеживает обновления через `git ls-remote` и управляет пропусками версий с синхронизацией между устройствами. Разрабатывался под Kali Linux - на других системах работоспособность не гарантирована.

## Быстрый старт

```bash
# Полностью автоматическая установка
sudo -v && curl -fsSL https://raw.githubusercontent.com/ShAmRoWw/prepare.sh/refs/heads/main/prepare.sh | bash -s -- --auto

# Запуск вручную
git clone https://github.com/ShAmRoWw/prepare.sh.git
cd prepare.sh && chmod +x prepare.sh
./prepare.sh --install
```

## Команды

| Команда | Описание |
|---------|----------|
| `./prepare.sh` | Проверить наличие инструментов (без сети) |
| `./prepare.sh --install` | Установить отсутствующие инструменты |
| `./prepare.sh --auto` | Автоматическая установка без вопросов |
| `./prepare.sh --check-updates` | Проверить наличие новых версий на remote |
| `./prepare.sh --skip <имя>` | Пропустить текущее обновление инструмента |
| `./prepare.sh --unskip <имя>` | Отменить пропуск обновления |
| `./prepare.sh --skip-list` | Показать пропущенные обновления |
| `./prepare.sh --skip-export` | Экспорт пропусков в stdout |
| `./prepare.sh --skip-import <файл>` | Импорт пропусков из файла или stdin |

## Что устанавливается

**Системные зависимости:** git, curl, wget, python3-pip, libpcap-dev, seclists, docker, libkrb5-dev, wmctrl.

**Go:** указанная версия Go и утилиты: httpx, nuclei.

**Python (uv tool install):** netexec, impacket, certipy, bloodyAD, penelope, ldeep, msldap, dnsrecon, smbclient-ng, AD-Miner, pre2k, conpass, RITM.

**Бинарные релизы:** pretender, rusthound-ce, kerbrute, legba, chisel.

**Git-репозитории с venv:** krbrelayx, targetedKerberoast, ASRepCatcher, PCredz, pyLDAPWordlistHarvester, bloodhound-automation.

**Windows-утилиты:** Group3r.exe, Snaffler.exe (скачиваются в `~/tools/for_windows/`).

**BloodHound:** автоматическое развёртывание через bloodhound-automation (Docker).

## Структура файлов

```
~/tools/                        — git-репозитории и venv-инструменты
~/.local/bin/                   — обёртки и бинарники
~/.local/share/prepare/         — логи установки и skip-конфигурация
/usr/local/go/                  — Go
~/go/bin/                       — Go-утилиты
```

## Проверка обновлений

`--check-updates` делает один запрос `git ls-remote` на каждый инструмент (параллельно) и сравнивает HEAD и теги с версиями, указанными в скрипте. Результаты:

- ✓ **(актуально)** — remote совпадает с закреплённой версией
- ↑ **→ новый тег / новые коммиты** — есть обновления
- ✓ **(пропущено: abc123)** — обновление пропущено через `--skip`

Для обновления инструмента измените версию/коммит в конфигурации скрипта и запустите `--install`.

## Пропуск обновлений (skip)

Если обновление нежелательно, `--skip <имя>` запоминает текущий HEAD remote и при следующем `--check-updates` он будет отображаться как актуальный. Новые коммиты после пропущенного HEAD снова покажут обновление.

### Синхронизация списка пропущенных версий между устройствами

Список пропущенных версий инструментов можно синхронизировать через приватный GitHub Gist.

**Настройка:**

1. Создать приватный gist с файлом `skipped.conf`.
2. Скопировать ID гиста из URL и заменить переменную `SKIP_GIST_ID` в начале скрипта.
3. Создать Personal Access Token: [github.com/settings/tokens](https://github.com/settings/tokens) → Generate new token (classic) → scope **gist**.

**Как работает:**

- **Чтение** (при `--check-updates`, `--skip`, `--unskip`) — автоматически скачивает skip-файл из Gist API без токена и заменяет локальный.
- **Запись** (при `--skip`, `--unskip`) — после изменения интерактивно запрашивает токен для push в Gist. Токен нигде не сохраняется. Можно нажать Enter, чтобы пропустить push — изменения останутся только локальными.
- **Без настройки** — если `SKIP_GIST_ID` пуст, всё работает только локально.

Также доступен ручной экспорт/импорт:
```bash
./prepare.sh --skip-export > skips.conf
scp skips.conf user@host2:~/
ssh host2 './prepare.sh --skip-import skips.conf'
```

## Sudo-обёртки

Инструменты, требующие привилегий (pretender, RITM, PCredz, ASRepCatcher), автоматически оборачиваются в sudo-обёртку: оригинал переименовывается в `.name.orig`, а на его месте создаётся скрипт, вызывающий оригинал через `sudo`.

## Требования

- Debian/Ubuntu-based дистрибутив (apt)
- Архитектура x86_64
- bash ≥ 4.4 (ассоциативные массивы)
- Доступ в интернет
