# prepare.sh

Скрипт для развёртывания и сопровождения набора инструментов внутреннего тестирования на проникновение на Kali/Debian-подобных системах. Устанавливает зависимости из apt, uv, Go, репозитории и релизы с GitHub и умеет проверять версии инструментов через git ls-remote.

Исходным источником правды для версий, коммитов и URL остаётся сам [`prepare.sh`](./prepare.sh).

## Быстрый старт

```bash
# Полностью автоматическая установка
sudo -v && curl -fsSL https://raw.githubusercontent.com/ShAmRoWw/prepare.sh/refs/heads/main/prepare.sh | bash -s -- --auto

# Ручной запуск из репозитория
git clone https://github.com/ShAmRoWw/prepare.sh.git
cd prepare.sh && chmod +x prepare.sh
./prepare.sh
```

## Команды

| Команда | Что делает |
|---------|------------|
| `./prepare.sh` | Локально проверяет наличие инструментов без доступа к сети |
| `./prepare.sh --install` | Устанавливает отсутствующие инструменты и зависимости |
| `./prepare.sh --auto` | То же, что `--install`, но без интерактивных вопросов |
| `./prepare.sh --check-updates` | Сравнивает версии инструментов, заданные в скрипте, с актуальными версиями из реопзиториев инструментов |
| `./prepare.sh --skip <имя>` | Помечает текущее состояние инструмента как пропущенное при проверке на наличие обновлений |
| `./prepare.sh --unskip <имя>` | Убирает пропуск |
| `./prepare.sh --skip-list` | Показывает локальный список пропущенных обновлений |
| `./prepare.sh --skip-export` | Печатает `skipped.conf` в stdout |
| `./prepare.sh --skip-import <файл>` | Импортирует список пропущенных версий из файла или stdin |

## Что устанавливается

**Системные пакеты (apt):** git, curl, wget, python3-pip, libpcap-dev, libkrb5-dev, seclists, wmctrl, docker.io, docker-compose.

**Go:** закрепленная в скрипте версия Go и утилиты httpx, nuclei.

**Python через uv tool install:** penelope, netexec, bloodyAD, pre2k, smbclientng, AD-Miner, conpass, ldeep, certipy, dnsrecon, msldap, RITM, impacket, manspider.

**Обычные репозитории (~/tools):** ntlmv1-multi.

**Бинарные релизы:** pretender, rusthound-ce, kerbrute, legba, chisel.

**Репозитории с отдельным venv:** krbrelayx, bloodhound-automation, targetedKerberoast, pyLDAPWordlistHarvester, ASRepCatcher, PCredz.

**Утилиты Windows:** Group3r.exe, Snaffler.exe.

**Дополнительно:** обновление шаблонов nuclei в ~/tools/nuclei-templates.

## Структура файлов

```text
~/tools/                                   репозитории и рабочие директории инструментов
~/tools/chisel/                            chisel
~/tools/for_windows/                       утилиты для Windows
~/tools/bloodhound-automation/projects/    проекты BloodHound
~/tools/nuclei-templates/                  шаблоны nuclei
~/.local/bin/                              wrapper скрипты и бинарники
~/.local/share/prepare/                    логи установки, skipped.conf и служебные маркеры
/usr/local/go/                             Go SDK
~/go/bin/                                  Go утилиты
```

## Проверка обновлений

`--check-updates` параллельно делает запросы к репозиториям инструментов, получает версии и сравнивает их с заданными в коде скрипта:

- `✓ (актуально)` — удаленный коммит/тег совпадает с зафиксированным;
- `↑` — в актуальной версии репозитория появился новый тег или новые коммиты;
- `✓ (пропущено: ...)` — обновление было помечено через `--skip`.

Важно: --check-updates только показывает расхождения. Он не меняет установку, а --install не выполняет полноценное обновление уже существующих инструментов.

## Список пропущенных версий и синхронизация

`--skip <имя>` запоминает текущий HEAD репозитория как сознательно пропущенный. Если после этого последняя версия двинется дальше, `--check-updates` снова покажет обновление.

Для синхронизации между машинами можно использовать приватный GitHub Gist, для этого:

1. Создайте приватный gist с файлом `skipped.conf`.
2. Проверьте значение `SKIP_GIST_ID` в начале скрипта. Подставьте ID своего gist'а или оставьте пустую строку, чтобы полностью отключить синхронизацию.
3. Создайте Classic PAT (Personal Access Token) и в скоупе выберите только `gist`.

Поведение:

- чтение файла происходит при `--check-updates`, `--skip` и `--unskip`;
- при записи (`--skip`, `--unskip`) токен запрашивается интерактивно и не сохраняется на диск;
- при пустом `SKIP_GIST_ID` всё работает только локально.

Ручной перенос между машинами тоже поддерживается:

```bash
./prepare.sh --skip-export > skips.conf
scp skips.conf user@host2:~/
ssh host2 './prepare.sh --skip-import skips.conf'
```

## Sudo обёртки

Для `pretender`, `RITM`, `PCredz` и `ASRepCatcher` скрипт создаёт sudo обёртку в `~/.local/bin`: исходный исполняемый файл переименовывается в `*.orig`, а обёртка запускает его через `sudo`.

## Требования

- Kali, Debian или Ubuntu-подобная система с `apt`
- `bash` 4.4+
- архитектура `x86_64`
- доступ в интернет
- `sudo` для установки пакетов и Docker

Скрипт разрабатывался под Kali Linux, так что на других дистрибутивах совместимость не гарантируется.
