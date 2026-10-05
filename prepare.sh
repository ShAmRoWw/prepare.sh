#!/usr/bin/env bash
#
# prepare.sh — установка инструментов
# Поддерживаемая платформа установки: Kali Linux AMD64 (x86_64).
#
# Использование:
#   ./prepare.sh                — проверить наличие установленных инструментов
#   ./prepare.sh --install       — установить отсутствующие инструменты
#   ./prepare.sh --auto          — полностью автоматическая установка (без вопросов)
#   ./prepare.sh --check-updates — сверить, есть ли новые версии на remote
#   ./prepare.sh --auto --proxy-all — использовать заданный proxy на всех этапах
#
# Параллелизм установки и проверки обновлений:
# PREPARE_INSTALL_JOBS=1..16 (по умолчанию 4).
#
# Proxy по умолчанию применяется только к bloodhound-automation.
# --proxy-all включает его для всех сетевых операций, в том числе --check-updates.
#
# Быстрый старт (curl):
#   curl -fsSL https://raw.githubusercontent.com/ShAmRoWw/prepare.sh/refs/heads/main/prepare.sh | bash -s -- --auto

set -euo pipefail

# ─── Цвета ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
GRAY='\033[38;5;242m'
NC='\033[0m' # No Color

# ─── Конфигурация ─────────────────────────────────────────────────────────────
TOOLS_DIR="$HOME/tools"
LOCAL_BIN="$HOME/.local/bin"
GO_BIN_DIR="$HOME/go/bin"
LOG_DIR="$HOME/.local/share/prepare"
SKIP_FILE="$HOME/.local/share/prepare/skipped.conf"
STATE_LOCK_FILE="$HOME/.local/share/prepare/state.lock"
INSTALL_LOCK_FILE="$HOME/.local/share/prepare/install.lock"
FIRST_INSTALL_MARKER="$HOME/.local/share/prepare/first_install_done"
TMUX_PLUGIN_DIR="$HOME/.tmux/plugins"
TMUX_LOG_DIR="$HOME/tmux_logs"

# ─── Remote-синхронизация skip-списка через GitHub Gist ───────────────────────
# Заполните SKIP_GIST_ID идентификатором приватного гиста для синхронизации
# между устройствами. Если пусто — работает только локально.
SKIP_GIST_ID="87ba4463703d9c46cf2c969091992e28"
SKIP_GIST_FILE="skipped.conf"
declare -a PROXY_ENV_ARGS=()
declare -A PROXY_SETTINGS=()
PROXY_SCOPE=bloodhound
PROXY_INITIALIZED=false

# Число независимых установок, выполняемых одновременно. Значение можно
# переопределить через PREPARE_INSTALL_JOBS=1..16.
INSTALL_JOBS=4

# ─── PATH: добавляем директории инструментов (bash не читает .bashrc) ─────────
for _p in "$HOME/.local/bin" "/usr/local/go/bin" "$GO_BIN_DIR"; do
    case ":$PATH:" in
        *":$_p:"*) ;;
        *) export PATH="$_p:$PATH" ;;
    esac
done
unset _p

# Версия Go для новой установки. Уже установленный Go скрипт не заменяет.
GO_VERSION="1.27.1"
GO_LINUX_AMD64_SHA256="63d339f0da5ab53635a56f2490a7984dfe12dfcff22ad749f63edaf590168445"

# uv tools: [имя]="версия|URL_репозитория|ветка_для_проверки_обновлений"
# Устанавливается как: uv tool install "git+${URL}@${версия}"
declare -A UV_TOOLS=(
    [penelope]="v0.21.0|https://github.com/brightio/penelope"
    [ntlmv1-multi]="c17f17df4c0355eb32c0392cdf0fc6178c99a10d|https://github.com/evilmog/ntlmv1-multi"
    [wsuks]="7e0a179e01d3468e69ec9c457b6def94b8abf4b0|https://github.com/NeffIsBack/wsuks"
    [pyGPOAbuse]="c18e1de919ed465f6b55104d596f7eabba6b9668|https://github.com/Hackndo/pyGPOAbuse"
    [bloodhound-ce-python]="6fa5ba5e553d061c253c323ccc59c3cbb96f4593|https://github.com/dirkjanm/BloodHound.py|bloodhound-ce"
    [netexec]="a0a37b7af81d1ce687ce5a1ac66a5867708f51f8|https://github.com/Pennyw0rth/NetExec"
    [bloodyAD]="0328081cbe9e615be8d33345ec0832f83e67aa80|https://github.com/CravateRouge/bloodyAD"
    [pre2k]="c2671c3bff87566572baf81d8106d819b7c89275|https://github.com/garrettfoster13/pre2k"
    [smbclientng]="3a8a902a5861416a324878b39378879a46cbf3ed|https://github.com/p0dalirius/smbclient-ng"
    [AD-Miner]="v1.9.0|https://github.com/AD-Security/AD_Miner"
    [conpass]="a55bc35b882ae6c6b604a9835142a65b807093d4|https://github.com/login-securite/conpass"
    [ldeep]="2.0.3|https://github.com/franc-pentest/ldeep"
    [certipy]="5.1.0|https://github.com/ly4k/Certipy"
    [dnsrecon]="1.6.3|https://github.com/darkoperator/dnsrecon"
    [msldap]="8955a87a365da972319076b0fb00b670865b9880|https://github.com/skelsec/msldap"
    [RITM]="b81e51222eb33f8ecd4a95b9fb0809a3a4ad0e1c|https://github.com/Tw1sm/RITM"
    [impacket]="c38d1eeb6cd284633ed161689c5d81841d4678b8|https://github.com/fortra/impacket"
    [manspider]="52cf157e281c6e4ae91230b2a60de54a2fe502a9|https://github.com/ShAmRoWw/MANSPIDER|main"
)

# uv-инструменты, которым нужен конкретный управляемый Python.
declare -A UV_TOOL_PYTHON=(
    [ntlmv1-multi]="3.14"
    [manspider]="3.12"
)

# uv-инструменты, которым нужны модули из системного Python. Для них uv
# использует указанный интерпретатор, а созданный venv получает доступ к
# system site-packages. Список импортов проверяется после установки.
declare -A UV_SYSTEM_PYTHON=(
    [wsuks]="/usr/bin/python3"
)
declare -A UV_SYSTEM_IMPORTS=(
    [wsuks]="nftables"
)

# Go-утилиты
declare -A GO_TOOLS=(
    [httpx]="github.com/projectdiscovery/httpx/cmd/httpx@latest"
    [nuclei]="github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
)

# Официальные release-бинарники этих проектов собираются из тех же CLI entry
# points, что указаны в GO_TOOLS. Версия сначала разрешается через Go module,
# затем скачивается соответствующий ей release и проверяется checksum.
# Katana намеренно отсутствует: её release собирается с CGO_ENABLED=0, тогда
# как требуемая этой конфигурацией установка использует CGO_ENABLED=1.
declare -A GO_RELEASE_REPOS=(
    [httpx]="projectdiscovery/httpx"
    [nuclei]="projectdiscovery/nuclei"
)

# Go-утилиты с CGO_ENABLED=1: [имя]="модуль@версия"
declare -A GO_TOOLS_CGO=(
    [katana]="github.com/projectdiscovery/katana/cmd/katana@latest"
)

# tmux plugins: [имя]="URL"
declare -A TMUX_PLUGINS=(
    [tpm]="https://github.com/tmux-plugins/tpm"
    [tmux-sensible]="https://github.com/tmux-plugins/tmux-sensible"
    [tmux-logging]="https://github.com/ShAmRoWw/tmux-logging"
)

# git clone --revision (в ~/tools): [имя]="URL|коммит"
declare -A GIT_REPOS=()

# Бинарники:
# [имя]="версия|URL|тип_архива|путь_к_бинарнику|необязательный_SHA256_бинарника"
declare -A BINARY_TOOLS=(
    [pretender]="v1.4.1|https://github.com/RedTeamPentesting/pretender/releases/download/v1.4.1/pretender_Linux_x86_64.tar.gz|tar.gz|pretender"
    [flashingestor]="v0.4.1|https://github.com/Macmod/flashingestor/releases/download/v0.4.1/flashingestor-linux-amd64.tar.gz|tar.gz|flashingestor-linux-amd64"
    [rusthound-ce]="v2.5.14|https://github.com/g0h4n/RustHound-CE/releases/download/v2.5.14/rusthound-ce-Linux-gnu-x86_64.tar.gz|tar.gz|rusthound-ce"
    [kerbrute]="v1.0.3|https://github.com/ropnop/kerbrute/releases/download/v1.0.3/kerbrute_linux_amd64|binary|kerbrute"
    [legba]="1.3.0|https://github.com/evilsocket/legba/releases/download/1.3.0/legba-1.3.0-linux-x86_64.tar.gz|tar.gz|legba-1.3.0-linux-x86_64/legba"
    [bettercap]="v2.41.7|https://github.com/bettercap/bettercap/releases/download/v2.41.7/bettercap_linux_amd64.zip|zip|bettercap"
    [gowitness]="3.2.0|https://github.com/sensepost/gowitness/releases/download/3.2.0/gowitness-3.2.0-linux-amd64|binary|gowitness|d315bf505691ea64a87f6231a757acfee0a94c024ab3531f35b3c52dad15895e"
    [trufflehog]="v3.97.9|https://github.com/trufflesecurity/trufflehog/releases/download/v3.97.9/trufflehog_3.97.9_linux_amd64.tar.gz|tar.gz|trufflehog|2e0a09c37d104c2f3069021f0c1ab33cf07287b6aca4d59eb4684d7d73fb89b4"
)

# Дополнительные CLI из того же release-артефакта:
# [основной_инструмент]="имя_команды=путь_в_архиве,..."
declare -A BINARY_TOOL_EXTRA_COMMANDS=(
    [flashingestor]="dcprobe=dcprobe-linux-amd64,ingest2json=ingest2json-linux-amd64"
)

# Chisel
CHISEL_VERSION="1.12.0"
CHISEL_URL="https://github.com/jpillora/chisel/releases/download/v${CHISEL_VERSION}/chisel_${CHISEL_VERSION}_linux_amd64.gz"

# Вариант Impacket с параметром --remove-mic-partial для CVE-2025-33073.
CVE_2025_IMPACKET_COMMIT="d3144ec7ecff7dc3d5c14aaf50a0e7e11531ed73"
CVE_2025_IMPACKET_URL="https://github.com/decoder-it/impacket-partial-mic.git"

# Git-репо с venv: [имя]="URL|коммит|точка_входа.py|доп_pip_пакеты"
declare -A VENV_REPOS=(
    [krbrelayx]="https://github.com/dirkjanm/krbrelayx.git|10b45a33bc4361ec4a5546eea62db2e4244d3255|krbrelayx.py|dnspython,impacket,ldap3"
    [bloodhound-automation]="https://github.com/Tanguy-Boisset/bloodhound-automation.git|92a1b6ccb3c2968359992d16fb15bae7f51e61b2|bloodhound-automation.py|"
    [targetedKerberoast]="https://github.com/ShutdownRepo/targetedKerberoast.git|ebed0790002dfae503eb5e5525a0630f131fa117|targetedKerberoast.py|"
    [pyLDAPWordlistHarvester]="https://github.com/p0dalirius/pyLDAPWordlistHarvester.git|78cd116f56554b0fface83f4074a29447fa35c54|LDAPWordlistHarvester.py|"
    [ASRepCatcher]="https://github.com/Yaxxine7/ASRepCatcher.git|4b70dcaf09dc75b4c1b60965c883ada2128adf8c|ASRepCatcher/ASRepCatcher.py|"
    [PCredz]="https://github.com/lgandx/PCredz.git|a07051d392b50bded1a19734cb70f97010cd90a5|Pcredz|pcapy-ng"
    [CVE-2025-33073]="https://github.com/mverschu/CVE-2025-33073.git|13f6aa8199c1fb00788c1500015008b7b53c2322|CVE-2025-33073.py|"
    [gssapi-abuse]="https://github.com/CCob/gssapi-abuse.git|cc71152dbf0f1ca0cb4e6819fc9f66621231e50c|gssapi-abuse.py|"
    [CVE-2026-54121]="https://github.com/aniqfakhrul/CVE-2026-54121.git|34d3067c40d4e81e21d4c1f0f749936a109fb305|certighost.py|impacket,cryptography,asn1crypto,pycryptodomex,pyasn1"
    [SCCMSecrets]="https://github.com/synacktiv/SCCMSecrets.git|5488158d097a7f76b879e0e5db7d9e123380fd7a|SCCMSecrets.py|"
    [cmloot]="https://github.com/shelltrail/cmloot.git|cfe1ae884e7ea224a44da8e9432fb8852e625e23|cmloot.py|"
)

# Дополнительные команды venv-репозиториев. Основная команда с именем ключа
# VENV_REPOS сохраняется как короткий совместимый алиас; здесь перечислены
# точные upstream-имена и остальные CLI из репозитория.
# [репозиторий]="имя_команды=относительная_точка_входа,..."
declare -A VENV_EXTRA_COMMANDS=(
    [krbrelayx]="krbrelayx.py=krbrelayx.py,addspn.py=addspn.py,dnstool.py=dnstool.py,printerbug.py=printerbug.py"
    [pyLDAPWordlistHarvester]="LDAPWordlistHarvester.py=LDAPWordlistHarvester.py"
    [PCredz]="Pcredz=Pcredz"
    [CVE-2026-54121]="certighost.py=certighost.py"
)

# Windows-утилиты
declare -A WIN_TOOLS=(
    [Group3r.exe]="https://github.com/Group3r/Group3r/releases/download/1.0.69/Group3r.exe"
    [Snaffler.exe]="https://github.com/SnaffCon/Snaffler/releases/download/1.0.244/Snaffler.exe"
)

# Инструменты, требующие запуска с sudo
declare -A SUDO_REQUIRED=( [RITM]=1 [pretender]=1 [PCredz]=1 [ASRepCatcher]=1 [CVE-2025-33073]=1 [CVE-2026-54121]=1 [krbrelayx]=1 [bettercap]=1 [wsuks]=1 )

# Команды uv-пакета, которые должны получить sudo-обёртку.
declare -A SUDO_UV_COMMANDS=(
    [RITM]="ritm,roastinthemiddle"
)

# Маппинг пакетов, чей бинарник не совпадает с именем пакета: [пакет]="бинарник1,бинарник2"
declare -A KNOWN_BINARIES=(
    [impacket]="secretsdump.py,ntlmrelayx.py"
    [certipy]="certipy"
    [AD-Miner]="AD-miner"
    [pyGPOAbuse]="pygpoabuse"
)

declare -a KALI_PREINSTALLED_TOOLS=( netexec msldap dnsrecon certipy )
declare -A KALI_SYSTEM_PACKAGES=(
    [netexec]="netexec"
    [msldap]="python3-msldap"
    [dnsrecon]="dnsrecon"
    [certipy]="certipy-ad"
)
# Версия Python для конкретных venv-репозиториев.
# gssapi==1.8.2 поддерживает py37-py312; на py313 сборка из sdist падает.
declare -A VENV_PYTHON=(
    [gssapi-abuse]="3.12"
)

# Большинство проектов используют .venv; этот проект ожидает каталог venv
# также внутри собственного кода.
declare -A VENV_DIR_NAME=(
    [CVE-2025-33073]="venv"
)

# ─── Вспомогательные функции ──────────────────────────────────────────────────

info()    { echo -e "${BLUE}[*]${NC} $*"; }
success() { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[-]${NC} $*"; }
header()  { echo -e "\n${CYAN}══════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════════${NC}"; }

declare -a EXIT_HOOKS=()
declare -a WINCH_HOOKS=()
PROGRESS_TTY_QUERY_FD=4

run_exit_hooks() {
    local status=$?
    local i
    for (( i=${#EXIT_HOOKS[@]} - 1; i>=0; i-- )); do
        eval "${EXIT_HOOKS[$i]}" || true
    done
    return "$status"
}

run_winch_hooks() {
    local hook
    for hook in "${WINCH_HOOKS[@]}"; do
        eval "$hook" || true
    done
}

register_exit_hook() {
    EXIT_HOOKS+=("$1")
    trap run_exit_hooks EXIT
}

register_winch_hook() {
    WINCH_HOOKS+=("$1")
    trap run_winch_hooks WINCH
}

PROGRESS_TOTAL=0
PROGRESS_CURRENT=0
PROGRESS_WIDTH=32
PROGRESS_LABEL=""
PROGRESS_FOOTER_ENABLED=false
PROGRESS_FOOTER_TRIED=false
PROGRESS_FOOTER_SUSPENDED=false
PROGRESS_CURSOR_ROW=1
PROGRESS_CURSOR_COL=1
PROGRESS_FOOTER_ROWS=0
PROGRESS_FOOTER_LAST_ROW=0
PROGRESS_FOOTER_SCROLL_BOTTOM=0

progress_format_line() {
    local current="$1" total="$2" label="$3"
    [ "$total" -gt 0 ] || return 0

    local filled=$(( current * PROGRESS_WIDTH / total ))
    [ "$filled" -gt "$PROGRESS_WIDTH" ] && filled="$PROGRESS_WIDTH"
    local empty=$(( PROGRESS_WIDTH - filled ))
    local done_bar pending_bar

    printf -v done_bar '%*s' "$filled" ''
    done_bar=${done_bar// /#}
    printf -v pending_bar '%*s' "$empty" ''
    pending_bar=${pending_bar// /-}

    printf '%b[%s%s]%b %s/%s %s' \
        "$DIM" "$done_bar" "$pending_bar" "$NC" "$current" "$total" "$label"
}

progress_footer_capture_size() {
    local tty_size tty_rows
    if [ -t "$PROGRESS_TTY_QUERY_FD" ]; then
        tty_size=$(stty size <&"$PROGRESS_TTY_QUERY_FD" 2>/dev/null || true)
    else
        tty_size=$(stty size < /dev/tty 2>/dev/null || true)
    fi
    tty_rows=${tty_size%% *}

    if [[ ! "$tty_rows" =~ ^[0-9]+$ ]] || [ "$tty_rows" -lt 2 ]; then
        tty_rows=$(tput lines 2>/dev/null || true)
    fi

    [[ "$tty_rows" =~ ^[0-9]+$ ]] || return 1
    [ "$tty_rows" -ge 2 ] || return 1

    PROGRESS_FOOTER_ROWS="$tty_rows"
    PROGRESS_FOOTER_LAST_ROW=$((PROGRESS_FOOTER_ROWS - 1))
    PROGRESS_FOOTER_SCROLL_BOTTOM=$((PROGRESS_FOOTER_ROWS - 2))
}

progress_capture_cursor() {
    local old_stty response row col

    [ -t "$PROGRESS_TTY_QUERY_FD" ] || return 1

    old_stty=$(stty -g <&"$PROGRESS_TTY_QUERY_FD" 2>/dev/null) || return 1
    stty -echo -icanon min 0 time 0 <&"$PROGRESS_TTY_QUERY_FD" 2>/dev/null || return 1

    printf '\033[6n' >&"$PROGRESS_TTY_QUERY_FD"
    IFS=';' read -r -u "$PROGRESS_TTY_QUERY_FD" -d R -t 0.5 response col || true
    stty "$old_stty" <&"$PROGRESS_TTY_QUERY_FD" 2>/dev/null || true

    row=${response#*[}
    [[ "$row" =~ ^[0-9]+$ && "$col" =~ ^[0-9]+$ ]] || return 1

    PROGRESS_CURSOR_ROW="$row"
    PROGRESS_CURSOR_COL="$col"
}

progress_footer_draw() {
    [ "$PROGRESS_FOOTER_ENABLED" = true ] || return 1
    [ "$PROGRESS_FOOTER_SUSPENDED" = true ] && return 0

    local line
    line=$(progress_format_line "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$PROGRESS_LABEL")

    tput sc 2>/dev/null || true
    tput cup "$PROGRESS_FOOTER_LAST_ROW" 0 2>/dev/null || true
    tput el 2>/dev/null || true
    printf '%b' "$line"
    tput rc 2>/dev/null || true
}

progress_footer_apply_layout() {
    local restore_row restore_col overflow i

    [ "$PROGRESS_FOOTER_ENABLED" = true ] || return 1
    [ "$PROGRESS_FOOTER_SUSPENDED" = true ] && return 0
    progress_footer_capture_size || return 1

    restore_row=$((PROGRESS_FOOTER_SCROLL_BOTTOM + 1))
    restore_col=1
    if progress_capture_cursor; then
        restore_row="$PROGRESS_CURSOR_ROW"
        restore_col="$PROGRESS_CURSOR_COL"
    fi

    [ "$restore_row" -lt 1 ] && restore_row=1
    [ "$restore_col" -lt 1 ] && restore_col=1
    if [ "$restore_row" -gt $((PROGRESS_FOOTER_SCROLL_BOTTOM + 1)) ]; then
        overflow=$((restore_row - PROGRESS_FOOTER_SCROLL_BOTTOM - 1))
        tput cup "$PROGRESS_FOOTER_LAST_ROW" 0 2>/dev/null || true
        for ((i = 0; i < overflow; i++)); do
            printf '\n'
        done
        restore_row=$((PROGRESS_FOOTER_SCROLL_BOTTOM + 1))
        restore_col=1
    fi

    tput csr 0 "$PROGRESS_FOOTER_SCROLL_BOTTOM" 2>/dev/null || return 1
    tput cup "$PROGRESS_FOOTER_LAST_ROW" 0 2>/dev/null || true
    tput el 2>/dev/null || true
    printf '%b' "$(progress_format_line "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$PROGRESS_LABEL")"
    tput cup $((restore_row - 1)) $((restore_col - 1)) 2>/dev/null || true
}

progress_footer_handle_winch() {
    [ "$PROGRESS_FOOTER_ENABLED" = true ] || return 0
    if [ "$PROGRESS_FOOTER_SUSPENDED" = true ]; then
        progress_footer_capture_size || true
        return 0
    fi
    progress_footer_apply_layout || true
}

progress_footer_suspend() {
    [ "$PROGRESS_FOOTER_ENABLED" = true ] || return 0
    [ "$PROGRESS_FOOTER_SUSPENDED" = true ] && return 0

    tput sc 2>/dev/null || true
    tput csr 0 $((PROGRESS_FOOTER_ROWS - 1)) 2>/dev/null || true
    tput cup "$PROGRESS_FOOTER_LAST_ROW" 0 2>/dev/null || true
    tput el 2>/dev/null || true
    tput rc 2>/dev/null || true
    tput cnorm 2>/dev/null || true

    PROGRESS_FOOTER_SUSPENDED=true
}

progress_footer_resume() {
    [ "$PROGRESS_FOOTER_ENABLED" = true ] || return 0
    [ "$PROGRESS_FOOTER_SUSPENDED" = true ] || return 0

    PROGRESS_FOOTER_SUSPENDED=false
    tput civis 2>/dev/null || true
    progress_footer_apply_layout || true
}

progress_footer_cleanup() {
    [ "$PROGRESS_FOOTER_ENABLED" = true ] || return 0

    tput sc 2>/dev/null || true
    tput csr 0 $((PROGRESS_FOOTER_ROWS - 1)) 2>/dev/null || true
    tput cup "$PROGRESS_FOOTER_LAST_ROW" 0 2>/dev/null || true
    tput el 2>/dev/null || true
    tput rc 2>/dev/null || true
    tput cnorm 2>/dev/null || true

    PROGRESS_FOOTER_ENABLED=false
    PROGRESS_FOOTER_SUSPENDED=false
}

progress_footer_init() {
    [ "$PROGRESS_FOOTER_ENABLED" = true ] && return 0
    [ "$PROGRESS_FOOTER_TRIED" = true ] && return 1
    PROGRESS_FOOTER_TRIED=true

    command -v tput >/dev/null 2>&1 || return 1
    # Группировка сохраняет stderr: `exec ... 2>/dev/null` без команды
    # применил бы перенаправление к текущей оболочке до конца скрипта.
    if ! { exec 4<>/dev/tty; } 2>/dev/null; then
        return 1
    fi
    register_exit_hook "exec 4>&- 4<&-"

    PROGRESS_FOOTER_ENABLED=true
    register_exit_hook "progress_footer_cleanup"
    register_winch_hook "progress_footer_handle_winch"
    tput civis 2>/dev/null || true

    if ! progress_footer_apply_layout; then
        progress_footer_cleanup
        return 1
    fi
}

progress_render() {
    local current="$1" total="$2" label="$3"
    [ "$total" -gt 0 ] || return 0

    PROGRESS_CURRENT="$current"
    PROGRESS_TOTAL="$total"
    PROGRESS_LABEL="$label"

    if progress_footer_init; then
        progress_footer_draw
    else
        printf '%b\n' "$(progress_format_line "$current" "$total" "$label")"
    fi
}

progress_start() {
    PROGRESS_TOTAL="$1"
    PROGRESS_CURRENT=0
    progress_render "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$2"
}

progress_step() {
    PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))
    progress_render "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$1"
}

progress_finish() {
    PROGRESS_CURRENT="$PROGRESS_TOTAL"
    progress_render "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$1"
}

install_phase() {
    local title="$1"
    progress_step "$title"
    header "$title"
}

cmd_exists() { command -v "$1" &>/dev/null; }

gowitness_browser() {
    local candidate candidate_path
    for candidate in chromium chromium-browser google-chrome google-chrome-stable; do
        if candidate_path=$(command -v "$candidate" 2>/dev/null) \
            && "$candidate_path" --version &>/dev/null; then
            printf '%s\n' "$candidate_path"
            return 0
        fi
    done
    return 1
}

nuclei_templates_config_file() {
    if [ -n "${NUCLEI_CONFIG_DIR:-}" ]; then
        printf '%s/.templates-config.json\n' "$NUCLEI_CONFIG_DIR"
    else
        printf '%s/nuclei/.templates-config.json\n' \
            "${XDG_CONFIG_HOME:-$HOME/.config}"
    fi
}

nuclei_templates_config_matches() {
    local templates_dir="$1"
    local config_file
    config_file=$(nuclei_templates_config_file)

    [ -f "$config_file" ] || return 1
    python3 - "$config_file" "$templates_dir" <<'PY'
import json
from pathlib import Path
import sys

try:
    data = json.loads(Path(sys.argv[1]).read_text())
    configured = data.get("nuclei-templates-directory") if isinstance(data, dict) else None
except (OSError, TypeError, ValueError):
    raise SystemExit(1)

if not configured:
    raise SystemExit(1)

actual = Path(configured).expanduser().resolve()
expected = Path(sys.argv[2]).expanduser().resolve()
raise SystemExit(0 if actual == expected else 1)
PY
}

nuclei_templates_config_set_dir() {
    local templates_dir="$1"
    local templates_version="${2:-}"
    local config_file
    config_file=$(nuclei_templates_config_file)

    if [ ! -f "$config_file" ] && [ -z "$templates_version" ]; then
        return 1
    fi
    python3 - "$config_file" "$templates_dir" "$templates_version" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

config_file = Path(sys.argv[1])
templates_dir = Path(sys.argv[2]).expanduser().resolve()
templates_version = sys.argv[3]

try:
    if config_file.exists():
        data = json.loads(config_file.read_text())
        if not isinstance(data, dict):
            raise ValueError("unexpected nuclei templates config format")
    else:
        data = {}
        config_file.parent.mkdir(parents=True, exist_ok=True)

    directory = str(templates_dir)
    data["nuclei-templates-directory"] = directory
    for provider in ("s3", "github", "gitlab", "azure"):
        data[f"custom-{provider}-templates-directory"] = str(
            templates_dir / provider
        )

    if templates_version:
        data["nuclei-templates-version"] = templates_version
        data["nuclei-templates-latest-version"] = templates_version
        ignore_file = config_file.parent / ".nuclei-ignore"
        if ignore_file.is_file():
            ignore_hash = hashlib.md5(
                ignore_file.read_bytes()
            ).hexdigest()
            data["nuclei-ignore-hash"] = ignore_hash
            data["nuclei-latest-ignore-hash"] = ignore_hash

    fd, temporary_name = tempfile.mkstemp(
        prefix=f".{config_file.name}.prepare.", dir=config_file.parent
    )
    try:
        with os.fdopen(fd, "w") as temporary_file:
            json.dump(data, temporary_file, separators=(",", ":"))
            temporary_file.write("\n")
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_name, config_file)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise
except (OSError, TypeError, ValueError):
    raise SystemExit(1)
PY
}

nuclei_templates_dir_complete() {
    local templates_dir="$1"
    local template_count

    [ -d "$templates_dir" ] || return 1
    template_count=$(find "$templates_dir" -type f \
        \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \) \
        -print 2>/dev/null | wc -l)
    [ "$template_count" -ge 1000 ]
}

# Nuclei 3.11.0 скрывает ошибку встроенного загрузчика шаблонов: runner
# записывает warning, после чего -update-templates вызывает os.Exit(0). Этот
# путь скачивает тот же официальный source archive без GitHub API, проверяет
# опубликованный release checksum и только затем публикует каталог.
install_nuclei_templates_release() {
    local templates_dir="$1"
    local repo_url="https://github.com/projectdiscovery/nuclei-templates.git"
    local all_refs version plain_version archive_name checksum_name
    local parent stage archive checksum_file expected actual root
    local config_file config_dir ignore_tmp

    if [ -e "$templates_dir" ] || [ -L "$templates_dir" ]; then
        error "Прямая установка не выполняется поверх существующего пути: $templates_dir"
        return 1
    fi

    info "Определение последнего стабильного release nuclei-templates без GitHub API..."
    if ! all_refs=$(git ls-remote --tags "$repo_url" 'refs/tags/*' 2>/dev/null); then
        error "Не удалось получить список тегов nuclei-templates"
        return 1
    fi
    version=$(latest_stable_tag_from_refs "$all_refs")
    if ! is_stable_version_tag "$version"; then
        error "Не удалось определить стабильную версию nuclei-templates"
        return 1
    fi

    plain_version="${version#v}"
    archive_name="nuclei-templates-${plain_version}.zip"
    checksum_name="nuclei-templates-${plain_version}_checksums.txt"
    parent=$(dirname "$templates_dir")
    mkdir -p "$parent"
    if ! stage=$(mktemp -d "${parent}/.nuclei-templates.prepare.XXXXXX"); then
        error "Не удалось создать временный каталог для nuclei-templates"
        return 1
    fi
    archive="${stage}/${archive_name}"
    checksum_file="${stage}/${checksum_name}"

    info "Скачивание nuclei-templates ${version} и официального SHA-256..."
    if ! wget -q \
        "https://github.com/projectdiscovery/nuclei-templates/releases/download/${version}/${checksum_name}" \
        -O "$checksum_file"; then
        rm -rf -- "$stage"
        error "Не удалось скачать checksum nuclei-templates ${version}"
        return 1
    fi
    if ! wget -q \
        "https://github.com/projectdiscovery/nuclei-templates/archive/refs/tags/${version}.zip" \
        -O "$archive"; then
        rm -rf -- "$stage"
        error "Не удалось скачать архив nuclei-templates ${version}"
        return 1
    fi

    expected=$(awk -v wanted="$archive_name" '$2 == wanted { print $1; exit }' \
        "$checksum_file")
    if ! actual=$(sha256sum "$archive" 2>/dev/null | awk '{print $1}'); then
        rm -rf -- "$stage"
        error "Не удалось вычислить SHA-256 архива nuclei-templates"
        return 1
    fi
    if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]] || [ "$actual" != "$expected" ]; then
        rm -rf -- "$stage"
        error "Архив nuclei-templates ${version} не прошёл проверку SHA-256"
        return 1
    fi
    if ! unzip -tq "$archive" >/dev/null \
        || ! mkdir -p "${stage}/unpack" \
        || ! unzip -q "$archive" -d "${stage}/unpack"; then
        rm -rf -- "$stage"
        error "Архив nuclei-templates ${version} повреждён"
        return 1
    fi

    root="${stage}/unpack/nuclei-templates-${plain_version}"
    if ! nuclei_templates_dir_complete "$root" || [ ! -f "${root}/.nuclei-ignore" ]; then
        rm -rf -- "$stage"
        error "Архив nuclei-templates ${version} не содержит полный набор шаблонов"
        return 1
    fi

    config_file=$(nuclei_templates_config_file)
    config_dir=$(dirname "$config_file")
    mkdir -p "$config_dir"
    if ! ignore_tmp=$(mktemp "${config_dir}/.nuclei-ignore.prepare.XXXXXX") \
        || ! install -m 0644 "${root}/.nuclei-ignore" "$ignore_tmp" \
        || ! mv "$ignore_tmp" "${config_dir}/.nuclei-ignore"; then
        [ -n "${ignore_tmp:-}" ] && rm -f -- "$ignore_tmp"
        rm -rf -- "$stage"
        error "Не удалось установить .nuclei-ignore"
        return 1
    fi

    # Встроенный установщик Nuclei также исключает dot-файлы/dot-каталоги
    # (кроме .new-additions) и README из опубликованного дерева шаблонов.
    if ! find "$root" -depth -mindepth 1 -name '.*' ! -name '.new-additions' \
            -exec rm -rf -- {} + \
        || ! find "$root" -type f -name 'README.md' -delete; then
        rm -rf -- "$stage"
        error "Не удалось подготовить дерево nuclei-templates"
        return 1
    fi

    if [ -e "$templates_dir" ] || [ -L "$templates_dir" ] \
        || ! mv "$root" "$templates_dir"; then
        rm -rf -- "$stage"
        error "Не удалось опубликовать каталог nuclei-templates"
        return 1
    fi
    rm -rf -- "$stage"

    if ! nuclei_templates_config_set_dir "$templates_dir" "$version" \
        || ! nuclei_templates_config_matches "$templates_dir"; then
        backup_incomplete_path "$templates_dir"
        error "Не удалось записать метаданные nuclei-templates ${version}"
        return 1
    fi
    info "Проверенный release nuclei-templates ${version} установлен напрямую"
}

configure_install_jobs() {
    local requested="${PREPARE_INSTALL_JOBS:-4}"
    if [[ ! "$requested" =~ ^[1-9][0-9]*$ ]] || [ "$requested" -gt 16 ]; then
        error "PREPARE_INSTALL_JOBS должен быть целым числом от 1 до 16"
        return 1
    fi
    INSTALL_JOBS="$requested"
}

# Независимые установки выполняются ограниченными пакетами фоновых задач.
# Каждая задача пишет в отдельный лог: это не перемешивает вывод и позволяет
# дождаться всех задач пакета перед возвратом ошибки.
INSTALL_JOB_DIR=""
declare -a INSTALL_JOB_PIDS=()
declare -a INSTALL_JOB_LABELS=()
declare -a INSTALL_JOB_LOGS=()
INSTALL_JOB_SEQUENCE=0

install_jobs_init() {
    [ -n "$INSTALL_JOB_DIR" ] && return 0
    INSTALL_JOB_DIR=$(mktemp -d)
    local cleanup_hook
    printf -v cleanup_hook 'rm -rf -- %q' "$INSTALL_JOB_DIR"
    register_exit_hook "$cleanup_hook"
}

wait_install_jobs() {
    local i status failed=0 line

    for i in "${!INSTALL_JOB_PIDS[@]}"; do
        status=0
        if wait "${INSTALL_JOB_PIDS[$i]}"; then
            status=0
        else
            status=$?
        fi
        if [ -s "${INSTALL_JOB_LOGS[$i]}" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                printf '[%s] %s\n' "${INSTALL_JOB_LABELS[$i]}" "$line"
            done < "${INSTALL_JOB_LOGS[$i]}"
        fi
        if [ "$status" -ne 0 ]; then
            error "${INSTALL_JOB_LABELS[$i]}: установка завершилась с ошибкой"
            failed=1
        fi
    done

    INSTALL_JOB_PIDS=()
    INSTALL_JOB_LABELS=()
    INSTALL_JOB_LOGS=()
    [ "$failed" -eq 0 ]
}

queue_install_job() {
    local label="$1"
    shift
    local log_file

    install_jobs_init
    INSTALL_JOB_SEQUENCE=$((INSTALL_JOB_SEQUENCE + 1))
    log_file="${INSTALL_JOB_DIR}/job_${INSTALL_JOB_SEQUENCE}.log"
    ( "$@" ) > "$log_file" 2>&1 &
    INSTALL_JOB_PIDS+=("$!")
    INSTALL_JOB_LABELS+=("$label")
    INSTALL_JOB_LOGS+=("$log_file")

    if [ "${#INSTALL_JOB_PIDS[@]}" -ge "$INSTALL_JOBS" ]; then
        wait_install_jobs
    fi
}

# Remote-проверки используют тот же предел параллелизма, что и установка.
declare -a CHECK_UPDATE_JOB_PIDS=()

track_check_update_job() {
    local pid="$1"
    CHECK_UPDATE_JOB_PIDS+=("$pid")

    if [ "${#CHECK_UPDATE_JOB_PIDS[@]}" -ge "$INSTALL_JOBS" ]; then
        wait "${CHECK_UPDATE_JOB_PIDS[0]}" || true
        CHECK_UPDATE_JOB_PIDS=("${CHECK_UPDATE_JOB_PIDS[@]:1}")
    fi
}

wait_check_update_jobs() {
    local pid
    for pid in "${CHECK_UPDATE_JOB_PIDS[@]}"; do
        wait "$pid" || true
    done
    CHECK_UPDATE_JOB_PIDS=()
}

# Экранирует строку для безопасного использования в grep-regex
regex_escape() { printf '%s' "$1" | sed 's/[][\\.^$*+?{}()|]/\\&/g'; }

# Сравнивает полный и допустимо сокращённый хеши коммитов.
# Слишком короткие значения намеренно не принимаются.
hashes_match() {
    local a="$1" b="$2"
    [[ "$a" =~ ^[0-9a-f]{12,40}$ && "$b" =~ ^[0-9a-f]{12,40}$ ]] || return 1
    local len=${#a}
    [[ ${#b} -lt $len ]] && len=${#b}
    [[ "${a:0:$len}" == "${b:0:$len}" ]]
}

is_full_commit() {
    [[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

# Межпроцессные блокировки автоматически снимаются ядром при завершении.
declare -A HELD_LOCK_FDS=()

acquire_lock() {
    local lock_file="$1" purpose="$2"
    local fd

    if [[ -v "HELD_LOCK_FDS[$lock_file]" ]]; then
        return 0
    fi
    if ! cmd_exists flock; then
        error "Не найдена команда flock, необходимая для блокировки: $purpose"
        return 1
    fi

    mkdir -p "$(dirname "$lock_file")"
    exec {fd}> "$lock_file"
    chmod 600 "$lock_file" 2>/dev/null || true
    if ! flock -n "$fd"; then
        exec {fd}>&-
        error "Уже выполняется другая операция: $purpose"
        return 1
    fi
    HELD_LOCK_FDS["$lock_file"]="$fd"
}

acquire_state_lock() {
    acquire_lock "$STATE_LOCK_FILE" "работа со списком пропусков"
}

acquire_install_lock() {
    acquire_lock "$INSTALL_LOCK_FILE" "установка"
}

# Проверяет, что Go-утилита установлена именно из ~/go/bin (а не системный омоним, например python-httpx на Kali)
is_go_tool() {
    local name="$1"
    local bin_path
    bin_path=$(command -v "$name" 2>/dev/null) || return 1
    [[ "$bin_path" == "$GO_BIN_DIR/"* ]] && [ -x "$bin_path" ] && [ -s "$bin_path" ]
}

needs_sudo() { [[ -v "SUDO_REQUIRED[$1]" ]]; }

# sudo наследуют основная команда проекта и её точный upstream-алиас.
# Самостоятельные вспомогательные CLI (например addspn.py/dnstool.py) в
# повышенных локальных привилегиях не нуждаются.
venv_command_needs_sudo() {
    local project_name="$1" command_name="$2" entrypoint="$3" primary_entrypoint
    needs_sudo "$project_name" || return 1
    primary_entrypoint=$(echo "${VENV_REPOS[$project_name]}" | cut -d'|' -f3)
    [ "$command_name" = "$project_name" ] || [ "$entrypoint" = "$primary_entrypoint" ]
}

venv_path_for() {
    local name="$1" dir="$2"
    printf '%s/%s' "$dir" "${VENV_DIR_NAME[$name]:-.venv}"
}

# Выводит все команды venv-репозитория в формате имя|точка_входа.
# Первой всегда идёт совместимая команда с именем ключа VENV_REPOS.
venv_command_specs() {
    local name="$1" primary_entrypoint="$2"
    local item command_name command_entrypoint
    local entries=()

    printf '%s|%s\n' "$name" "$primary_entrypoint"
    if [[ -v "VENV_EXTRA_COMMANDS[$name]" ]]; then
        IFS=',' read -r -a entries <<< "${VENV_EXTRA_COMMANDS[$name]}"
        for item in "${entries[@]}"; do
            command_name="${item%%=*}"
            command_entrypoint="${item#*=}"
            printf '%s|%s\n' "$command_name" "$command_entrypoint"
        done
    fi
}

venv_repo_complete() {
    local name="$1" dir="$2"
    local venv_dir entrypoint command_name command_entrypoint wrapper

    [[ -v "VENV_REPOS[$name]" ]] || return 1
    venv_dir=$(venv_path_for "$name" "$dir")
    entrypoint=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f3)

    [ -d "$dir/.git" ] \
        && git -C "$dir" rev-parse HEAD &>/dev/null \
        && [ -x "${venv_dir}/bin/python" ] \
        && [ -f "${venv_dir}/.prepare_complete" ] \
        || return 1

    while IFS='|' read -r command_name command_entrypoint; do
        wrapper="${LOCAL_BIN}/${command_name}"
        [ -f "${dir}/${command_entrypoint}" ] \
            && [ -x "$wrapper" ] \
            && prepare_venv_wrapper_matches "$command_name" "$wrapper" \
                "${venv_dir}/bin/python" "${dir}/${command_entrypoint}" \
            || return 1
    done < <(venv_command_specs "$name" "$entrypoint")

    return 0
}

backup_incomplete_path() {
    local path="$1"
    local backup
    backup="${path}.incomplete.$(date +%Y%m%d%H%M%S).$$"
    mv "$path" "$backup"
    warn "Незавершённый объект сохранён: $backup"
}

is_first_install_run() { [ ! -f "$FIRST_INSTALL_MARKER" ]; }

mark_first_install_done() {
    mkdir -p "$(dirname "$FIRST_INSTALL_MARKER")"
    : > "$FIRST_INSTALL_MARKER"
}

is_kali() {
    [ -r /etc/os-release ] || return 1
    local os_id os_like
    os_id=$( . /etc/os-release; printf '%s' "${ID:-}" )
    os_like=$( . /etc/os-release; printf '%s' "${ID_LIKE:-}" )
    [[ "$os_id" == "kali" || "$os_like" == *kali* ]]
}

require_kali_amd64() {
    if ! is_kali; then
        error "Установка поддерживается только на Kali Linux AMD64"
        return 1
    fi

    local machine_arch deb_arch
    machine_arch=$(uname -m 2>/dev/null || true)
    deb_arch=$(dpkg --print-architecture 2>/dev/null || true)
    if [ "$machine_arch" != "x86_64" ] || [ "$deb_arch" != "amd64" ]; then
        error "Неподдерживаемая архитектура: kernel=${machine_arch:-неизвестно}, dpkg=${deb_arch:-неизвестно}"
        error "Установка поддерживается только на Kali Linux AMD64 (x86_64)"
        return 1
    fi
}

# Оборачивает бинарник в sudo-обёртку: переименовывает оригинал в .name.orig.
# Чужие файлы и неоднозначные частичные состояния не перезаписываются.
wrap_with_sudo() {
    local bin_path="$1" name="$2"
    local orig="${bin_path}.orig"
    local marker="# Managed by prepare.sh: sudo wrapper for ${name}"

    if [ -f "$orig" ]; then
        if [ ! -x "$orig" ] || [ ! -s "$orig" ]; then
            error "sudo-обёртка $name: исходный файл повреждён: $orig"
            return 1
        fi
        if [ -f "$bin_path" ] && grep -Fqx "$marker" "$bin_path"; then
            return 0
        fi
        if [ -e "$bin_path" ]; then
            error "sudo-обёртка $name: ${orig} уже существует, а ${bin_path} не является управляемой обёрткой"
            return 1
        fi
    else
        if [ ! -f "$bin_path" ]; then
            error "sudo-обёртка: файл не найден: ${bin_path}"
            return 1
        fi
        mv "$bin_path" "$orig"
    fi

    local tmp
    tmp=$(mktemp "${bin_path}.prepare.XXXXXX")
    {
        echo '#!/usr/bin/env bash'
        echo "$marker"
        printf 'exec sudo %q "$@"\n' "$orig"
    } > "$tmp"
    chmod 755 "$tmp"
    mv "$tmp" "$bin_path"
    success "sudo-обёртка: ${bin_path}"
}

is_prepare_venv_wrapper() {
    local name="$1" wrapper="$2"
    [ -f "$wrapper" ] && {
        grep -Fqx "# Managed by prepare.sh: venv wrapper for ${name}" "$wrapper" \
            || grep -Fqx "# Обёртка для $name (требует sudo)" "$wrapper" \
            || grep -Fqx "# Обёртка для $name — запуск из любой директории" "$wrapper"
    }
}

prepare_venv_wrapper_matches() {
    local name="$1" wrapper="$2" python_path="$3" entrypoint_path="$4"
    local python_q entrypoint_q
    printf -v python_q '%q' "$python_path"
    printf -v entrypoint_q '%q' "$entrypoint_path"

    is_prepare_venv_wrapper "$name" "$wrapper" \
        && grep -Fq "$python_q" "$wrapper" \
        && grep -Fq "$entrypoint_q" "$wrapper"
}

write_venv_command_wrapper() {
    local project_name="$1" command_name="$2" dir="$3" venv_dir="$4" entrypoint="$5"
    local wrapper="${LOCAL_BIN}/${command_name}"
    local marker="# Managed by prepare.sh: venv wrapper for ${command_name}"
    local tmp launch_command python_q entrypoint_q

    if [ -e "$wrapper" ] || [ -L "$wrapper" ]; then
        if ! is_prepare_venv_wrapper "$command_name" "$wrapper"; then
            error "Не заменяю существующий неуправляемый файл: $wrapper"
            return 1
        fi
    fi

    tmp=$(mktemp "${wrapper}.prepare.XXXXXX")
    {
        echo '#!/usr/bin/env bash'
        echo "$marker"
        printf 'export PATH=%q:"$PATH"\n' "${venv_dir}/bin"
        if venv_command_needs_sudo "$project_name" "$command_name" "$entrypoint"; then
            printf 'exec sudo env "PATH=$PATH" %q %q "$@"\n' \
                "${venv_dir}/bin/python" "${dir}/${entrypoint}"
        elif [ "$project_name" = "bloodhound-automation" ] \
            && [ "$command_name" = "bloodhound-automation" ]; then
            # usermod не меняет supplementary groups уже открытой оболочки.
            # Если docker-группа назначена, но ещё не активна, запускаем только
            # эту команду через sg; после нового login-сеанса ветка не нужна.
            printf -v python_q '%q' "${venv_dir}/bin/python"
            printf -v entrypoint_q '%q' "${dir}/${entrypoint}"
            launch_command="exec ${python_q} ${entrypoint_q}"
            echo 'if command -v sg >/dev/null 2>&1; then'
            echo '    _prepare_user=$(id -un)'
            echo '    case " $(id -nG "$_prepare_user") " in'
            echo '        *" docker "*)'
            echo '            case " $(id -nG) " in'
            echo '                *" docker "*) ;;'
            echo '                *)'
            printf '                    _prepare_cmd=%q\n' "$launch_command"
            echo '                    for _prepare_arg in "$@"; do'
            echo "                        printf -v _prepare_quoted ' %q' \"\$_prepare_arg\""
            echo '                        _prepare_cmd+=$_prepare_quoted'
            echo '                    done'
            echo '                    exec sg docker -c "$_prepare_cmd"'
            echo '                    ;;'
            echo '            esac'
            echo '            ;;'
            echo '    esac'
            echo 'fi'
            printf 'exec %q %q "$@"\n' \
                "${venv_dir}/bin/python" "${dir}/${entrypoint}"
        else
            printf 'exec %q %q "$@"\n' \
                "${venv_dir}/bin/python" "${dir}/${entrypoint}"
        fi
    } > "$tmp"
    chmod 755 "$tmp"
    mv "$tmp" "$wrapper"
    success "Обёртка: ${wrapper}"
}

write_venv_wrapper() {
    local name="$1" dir="$2" venv_dir="$3" primary_entrypoint="$4"
    local spec command_name entrypoint wrapper
    local specs=()

    mapfile -t specs < <(venv_command_specs "$name" "$primary_entrypoint")

    # Сначала проверяем весь набор, чтобы конфликт одной команды не оставил
    # частично опубликованные обёртки.
    for spec in "${specs[@]}"; do
        IFS='|' read -r command_name entrypoint <<< "$spec"
        if [ ! -f "${dir}/${entrypoint}" ]; then
            error "$name: не найдена точка входа для $command_name: ${dir}/${entrypoint}"
            return 1
        fi
        wrapper="${LOCAL_BIN}/${command_name}"
        if { [ -e "$wrapper" ] || [ -L "$wrapper" ]; } \
            && ! is_prepare_venv_wrapper "$command_name" "$wrapper"; then
            error "Не заменяю существующий неуправляемый файл: $wrapper"
            return 1
        fi
    done

    for spec in "${specs[@]}"; do
        IFS='|' read -r command_name entrypoint <<< "$spec"
        write_venv_command_wrapper "$name" "$command_name" "$dir" \
            "$venv_dir" "$entrypoint" || return 1
    done
}

is_valid_windows_binary() {
    local path="$1"
    [ -s "$path" ] || return 1
    python3 - "$path" <<'PY'
from pathlib import Path
import struct
import sys

path = Path(sys.argv[1])
try:
    with path.open("rb") as stream:
        header = stream.read(64)
        if len(header) != 64 or header[:2] != b"MZ":
            raise ValueError
        pe_offset = struct.unpack_from("<I", header, 0x3C)[0]
        if pe_offset < 64 or pe_offset > path.stat().st_size - 4:
            raise ValueError
        stream.seek(pe_offset)
        if stream.read(4) != b"PE\0\0":
            raise ValueError
except (OSError, ValueError, struct.error):
    raise SystemExit(1)
PY
}

patch_cve_2025_install() {
    local dir="$1"
    local script="${dir}/CVE-2025-33073.py"
    local requirements="${dir}/requirements.txt"

    [ -f "$script" ] && [ -f "$requirements" ] || {
        error "CVE-2025-33073: не найдены файлы проекта: $script, $requirements"
        return 1
    }

    python3 - "$script" "$requirements" "$CVE_2025_IMPACKET_URL" \
        "$CVE_2025_IMPACKET_COMMIT" <<'PY'
from pathlib import Path
import os
import sys
import tempfile

script_path = Path(sys.argv[1])
requirements_path = Path(sys.argv[2])
impacket_url = sys.argv[3]
impacket_commit = sys.argv[4]

original = script_path.read_text()
text = original

function_start = text.find("def ensure_forked_impacket():")
function_end = text.find("def run_dnstool(", function_start)
if function_start == -1 or function_end == -1:
    raise SystemExit(
        "CVE-2025-33073 patch failed: ensure_forked_impacket function not found"
    )

prepared_check = '''def ensure_forked_impacket():
    """Verify that the prepared Impacket variant is available."""
    script_dir = Path(__file__).parent.absolute()
    relay_binary = script_dir / "venv" / "bin" / "ntlmrelayx.py"

    if not relay_binary.exists():
        print("[!] Prepared virtual environment not found. Please rerun prepare.sh.")
        return False

    try:
        result = subprocess.run(
            [str(relay_binary), "--help"],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return False

    if result.returncode == 0 and "--remove-mic-partial" in result.stdout:
        return True

    print("[!] Required ntlmrelayx option is unavailable. Please rerun prepare.sh.")
    return False


'''
text = text[:function_start] + prepared_check + text[function_end:]

replacements = (
    (
        'cmd = ["impacket-ntlmrelayx", "-t", target, "-smb2support"]',
        'cmd = ["ntlmrelayx.py", "-t", target, "-smb2support"]',
    ),
)

for old, new in replacements:
    if new in text:
        continue
    if old not in text:
        raise SystemExit(
            f"CVE-2025-33073 patch failed: expected fragment not found: {old}"
        )
    text = text.replace(old, new, 1)

requirements_original = requirements_path.read_text()
pinned_requirement = f"impacket @ git+{impacket_url}@{impacket_commit}"
requirements_lines = requirements_original.splitlines()
replacement_indexes = [
    index
    for index, line in enumerate(requirements_lines)
    if line.strip() == "impacket"
    or line.strip().startswith(
        "impacket @ git+https://github.com/decoder-it/impacket-partial-mic.git@"
    )
]
if len(replacement_indexes) != 1:
    raise SystemExit(
        "CVE-2025-33073 patch failed: expected exactly one Impacket requirement"
    )
requirements_lines[replacement_indexes[0]] = pinned_requirement
requirements_text = "\n".join(requirements_lines) + "\n"


def replace_file(path: Path, content: str) -> None:
    with tempfile.NamedTemporaryFile(
        "w", dir=path.parent, prefix=f".{path.name}.prepare.", delete=False
    ) as tmp:
        tmp.write(content)
        tmp_path = Path(tmp.name)
    try:
        os.chmod(tmp_path, path.stat().st_mode)
        os.replace(tmp_path, path)
    except BaseException:
        tmp_path.unlink(missing_ok=True)
        raise


if text != original:
    replace_file(script_path, text)
if requirements_text != requirements_original:
    replace_file(requirements_path, requirements_text)
PY
    success "CVE-2025-33073: локальные пути и закреплённый Impacket согласованы с venv"
}

cve_2025_venv_ready() {
    local venv_dir="$1"
    local relay_binary="${venv_dir}/bin/ntlmrelayx.py"
    local help_output

    [ -x "$relay_binary" ] || return 1
    help_output=$("$relay_binary" --help 2>&1) || return 1
    grep -Fq -- '--remove-mic-partial' <<< "$help_output"
}

bloodhound_venv_has_legacy_packages() {
    local venv_dir="$1"
    local python_bin="${venv_dir}/bin/python"

    [ -x "$python_bin" ] || return 1
    "$python_bin" - <<'PY'
from importlib import metadata

legacy = {"ansible-core", "docker-compose"}
installed = {
    (distribution.metadata.get("Name") or "").lower()
    for distribution in metadata.distributions()
}
raise SystemExit(0 if installed & legacy else 1)
PY
}

bloodhound_venv_ready() {
    local python_bin="${1}/bin/python"
    [ -x "$python_bin" ] || return 1
    "$python_bin" -c 'import requests, colorama, yaml' &>/dev/null
}

add_to_file_if_absent() {
    local line="$1" file="$2"
    if [ -f "$file" ] && grep -qF "$line" "$file"; then
        return 0
    fi
    echo "$line" >> "$file"
}

ensure_path_entry() {
    local entry="$1"
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$rc" ] || continue
        add_to_file_if_absent "export PATH=\"$entry:\$PATH\"" "$rc"
    done
    case ":$PATH:" in
        *":$entry:"*) ;;
        *) export PATH="$entry:$PATH" ;;
    esac
}

first_nonempty_env() {
    local primary="$1" fallback="$2"
    if [ -n "${!primary:-}" ]; then
        printf '%s' "${!primary}"
    else
        printf '%s' "${!fallback:-}"
    fi
}

build_proxy_env_args() {
    local name
    PROXY_ENV_ARGS=()
    for name in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY; do
        [ -z "${!name:-}" ] || PROXY_ENV_ARGS+=("$name=${!name}")
    done
}

export_proxy_settings() {
    local scheme name upper value
    for scheme in http https all no; do
        name="${scheme}_proxy"
        upper="${name^^}"
        value="${PROXY_SETTINGS[$scheme]:-}"
        if [ -n "$value" ]; then
            export "$name=$value" "$upper=$value"
        else
            unset "$name" "$upper"
        fi
    done
    build_proxy_env_args
}

apply_proxy_scope() {
    unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
    PROXY_ENV_ARGS=()
    if [ "$PROXY_SCOPE" = all ]; then
        export_proxy_settings
    fi
}

initialize_proxy_settings() {
    [ "$PROXY_INITIALIZED" = false ] || return 0
    local scheme name
    for scheme in http https all no; do
        name="${scheme}_proxy"
        PROXY_SETTINGS[$scheme]=$(first_nonempty_env "$name" "${name^^}")
    done
    PROXY_INITIALIZED=true
    apply_proxy_scope
}

# Только дочерний процесс получает proxy: соседние параллельные установки
# и следующие этапы продолжают работать с выбранной общей областью действия.
with_bloodhound_proxy() (
    initialize_proxy_settings
    export_proxy_settings
    # Python requests обращается к локальному API BloodHound. Пользовательские
    # исключения сохраняются; localhost должен работать и при внешнем proxy.
    export no_proxy="${no_proxy:+${no_proxy},}localhost,127.0.0.1,::1,app-db,graph-db,bloodhound"
    export NO_PROXY="$no_proxy"
    build_proxy_env_args
    "$@"
)

sudo_with_proxy() {
    sudo "${PROXY_ENV_ARGS[@]}" "$@"
}

prompt_read() {
    local var_name="$1" prompt="$2"
    progress_footer_suspend
    read -rp "$prompt" "${var_name?}"
    local status=$?
    progress_footer_resume
    return "$status"
}

prompt_read_secret() {
    local var_name="$1" prompt="$2"
    progress_footer_suspend
    read -rsp "$prompt" "${var_name?}"
    local status=$?
    progress_footer_resume
    return "$status"
}

patch_bloodhound_automation_compose_file() {
    local compose_file="$1"

    [ -f "$compose_file" ] || {
        error "bloodhound-automation: не найден compose-файл: $compose_file"
        return 1
    }

    python3 - "$compose_file" <<'PY'
from pathlib import Path
import os
import sys
import tempfile

path = Path(sys.argv[1])
original = path.read_text()
text = original

# Compose запускают и напрямую: локальные исключения обязательны даже без
# with_bloodhound_proxy. Пользовательский список берём из lower/upper-case env.
proxy_lines = (
    '      - http_proxy=${http_proxy:-}\n',
    '      - https_proxy=${https_proxy:-}\n',
    '      - HTTP_PROXY=${http_proxy:-}\n',
    '      - HTTPS_PROXY=${https_proxy:-}\n',
    '      - no_proxy=localhost,127.0.0.1,::1,app-db,graph-db,bloodhound,${no_proxy:-${NO_PROXY:-}}\n',
    '      - NO_PROXY=localhost,127.0.0.1,::1,app-db,graph-db,bloodhound,${no_proxy:-${NO_PROXY:-}}\n',
)

# Сначала сворачиваем блоки от прежних запусков, затем создаём ровно один
# блок в каждой из трёх секций.
for line in proxy_lines:
    text = text.replace(line, '')

anchors = (
    '      - POSTGRES_DATABASE=${POSTGRES_DATABASE:-bloodhound}\n',
    '      - NEO4J_dbms_allow__upgrade=true\n',
    '      - bhe_disable_cypher_qc=${bhe_disable_cypher_qc:-false}\n',
)
proxy_block = ''.join(proxy_lines)
for anchor in anchors:
    if text.count(anchor) != 1:
        raise SystemExit(
            "bloodhound-automation compose patch failed: "
            f"expected exactly one fragment: {anchor.strip()}"
        )
    text = text.replace(anchor, anchor + proxy_block, 1)

old_health = '      retries: 5\n      start_period: 30s\n\n  bloodhound:\n'
new_health = '      retries: 10\n      start_period: 120s\n\n  bloodhound:\n'
if old_health in text:
    text = text.replace(old_health, new_health, 1)
elif new_health not in text:
    raise SystemExit(
        "bloodhound-automation compose patch failed: "
        "expected healthcheck fragment not found"
    )

if text != original:
    with tempfile.NamedTemporaryFile(
        "w", dir=path.parent, prefix=f".{path.name}.prepare.", delete=False
    ) as tmp:
        tmp.write(text)
        tmp_path = Path(tmp.name)
    try:
        os.chmod(tmp_path, path.stat().st_mode)
        os.replace(tmp_path, path)
    except BaseException:
        tmp_path.unlink(missing_ok=True)
        raise
PY
}

patch_bloodhound_automation_install() {
    local dir="$1"
    local project_py="${dir}/src/project.py"
    local cli_py="${dir}/bloodhound-automation.py"
    local requirements="${dir}/requirements.txt"
    local compose_file

    [ -f "$project_py" ] && [ -f "$cli_py" ] && [ -f "$requirements" ] || {
        error "bloodhound-automation: не найдены файлы проекта: $project_py, $cli_py, $requirements"
        return 1
    }

    python3 - "$project_py" "$cli_py" "$requirements" <<'PY'
from pathlib import Path
import os
import sys
import tempfile

path = Path(sys.argv[1])
cli_path = Path(sys.argv[2])
requirements_path = Path(sys.argv[3])
original = path.read_text()
cli_original = cli_path.read_text()
text = original
cli_text = cli_original

replacements = (
    (
        '        self.no_gds = no_gds\n',
        '        self.no_gds = no_gds\n        self.templates_directory = Path(__file__).resolve().parent.parent / "templates"\n',
    ),
    (
        'import pickle\n',
        'import pickle\nimport tempfile\n',
    ),
)

for old, new in replacements:
    if new in text:
        continue
    if old not in text:
        raise SystemExit(
            f"bloodhound-automation patch failed: expected fragment not found: {old.strip()}"
        )
    text = text.replace(old, new, 1)


def replace_section(source: str, start_marker: str, end_marker: str, replacement: str) -> str:
    start = source.find(start_marker)
    end = source.find(end_marker, start)
    if start == -1 or end == -1:
        raise SystemExit(
            "bloodhound-automation patch failed: "
            f"section not found: {start_marker.strip()}"
        )
    return source[:start] + replacement + source[end:]


for module in ("hashlib", "yaml"):
    line = f"import {module}\n"
    if line not in text:
        text = text.replace("import tempfile\n", "import tempfile\n" + line, 1)
ports_import = "from src.ports import reserve_project_ports, atomic_write, valid_port, compose_ports\n"
text = ''.join(line for line in text.splitlines(keepends=True) if not line.startswith("from src.ports import "))
text = text.replace("import src.utils as utils\n", "import src.utils as utils\n" + ports_import, 1)
if "from src.ports import project_lock\n" not in cli_text:
    cli_text = cli_text.replace("from src.project import Project\n", "from src.project import Project\nfrom src.ports import project_lock\n", 1)

ports_source = r'''"""Persistent host port reservations for BloodHound projects."""
from contextlib import ExitStack, contextmanager
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile

import yaml


DEFAULT_PORTS = {"bolt": 7687, "neo4j": 7474, "web": 8080}


def atomic_write(path, content, mode=None):
    path = Path(path)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile("wb" if isinstance(content, bytes) else "w",
                                         dir=path.parent, prefix=f".{path.name}.", delete=False) as output:
            temporary = Path(output.name)
            output.write(content)
        # Bind-mounted configuration must remain readable inside containers,
        # including images running as a different, unprivileged UID.
        os.chmod(temporary, mode if mode is not None else (path.stat().st_mode if path.exists() else 0o644))
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


@contextmanager
def project_lock(root, name):
    """Serialize starts of one project without blocking other projects."""
    if not name or name in (".", "..") or Path(name).name != name:
        raise ValueError("Project name must be a directory name, without a path")
    root = Path(root)
    if (root / name).is_symlink():
        raise ValueError("Project directory must not be a symbolic link")
    root.mkdir(parents=True, exist_ok=True)
    lock_name = ".start-" + hashlib.sha256(name.encode()).hexdigest() + ".lock"
    with (root / lock_name).open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ValueError(f"Project {name} is already being started; wait for that command to finish") from exc
        yield


def valid_port(value):
    if isinstance(value, bool) or not str(value).isdigit() or not 1 <= int(value) <= 65535:
        raise ValueError(f"Invalid TCP port: {value!r}; expected 1..65535")
    return int(value)


def published_ports(value):
    # Compose also accepts host port ranges; reserve the entire range.
    value = str(value)
    if value in ("", "0"):
        return set()
    bounds = value.split("-")
    if len(bounds) == 1:
        return {valid_port(value)}
    if len(bounds) != 2:
        raise ValueError(f"Invalid published port range: {value!r}")
    first, last = map(valid_port, bounds)
    if first > last:
        raise ValueError(f"Invalid published port range: {value!r}")
    return set(range(first, last + 1))


def compose_ports(config):
    if not isinstance(config, dict) or not isinstance(config.get("services"), dict):
        raise ValueError("Compose configuration has no services")
    reserved = set()
    for service in config["services"].values():
        for mapping in service.get("ports", []):
            if isinstance(mapping, dict):
                if mapping.get("protocol", "tcp") == "tcp" and mapping.get("published") is not None:
                    reserved.update(published_ports(mapping["published"]))
            else:
                address, _, protocol = str(mapping).partition("/")
                if protocol not in ("", "tcp") or ":" not in address:
                    continue
                # The last two components are host:container, including IPv6.
                host = address.rsplit(":", 1)[0].rsplit(":", 1)[-1]
                reserved.update(published_ports(host))
    return reserved


def command_output(arguments, cwd=None):
    try:
        result = subprocess.run(arguments, cwd=cwd, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, check=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as exc:
        raise ValueError(f"Could not inspect port reservations using {' '.join(arguments[:3])}") from exc
    return result.stdout


def project_ports(root, compose_command):
    reserved = set()
    for directory in sorted(root.iterdir()):
        if not directory.is_dir():
            continue
        record = directory / "ports.json"
        compose = directory / "docker-compose.yml"
        try:
            if record.exists():
                ports = json.loads(record.read_text())
                if not isinstance(ports, dict) or set(ports) != set(DEFAULT_PORTS):
                    raise ValueError("Invalid ports.json")
                reserved.update(valid_port(port) for port in ports.values())
            if compose.exists():
                # Resolve legacy ${BLOODHOUND_PORT}, .env and Compose overrides.
                resolved = command_output([*compose_command, "config"], cwd=directory)
                reserved.update(compose_ports(yaml.safe_load(resolved)))
            elif (directory / "project.pkl").exists() and not record.exists():
                raise ValueError("Missing docker-compose.yml and ports.json")
        except (OSError, ValueError, yaml.YAMLError, TypeError, AttributeError) as exc:
            raise ValueError(f"Cannot determine reserved ports for project {directory.name}: {exc}") from exc
    return reserved


def docker_ports():
    # Inspect HostConfig as well as sockets: stopped containers and Docker NAT
    # mappings without docker-proxy do not necessarily appear in `ss`.
    identifiers = command_output(["docker", "ps", "-aq"]).split()
    reserved = set()
    for offset in range(0, len(identifiers), 100):
        containers = json.loads(command_output(["docker", "inspect", *identifiers[offset:offset + 100]]))
        for container in containers:
            bindings = container.get("HostConfig", {}).get("PortBindings") or {}
            for container_port, addresses in bindings.items():
                if container_port.endswith("/tcp"):
                    for address in addresses or []:
                        reserved.update(published_ports(address.get("HostPort", "")))
            # Include actual host ports chosen dynamically by Docker.
            for container_port, addresses in (container.get("NetworkSettings", {}).get("Ports") or {}).items():
                if container_port.endswith("/tcp"):
                    for address in addresses or []:
                        reserved.update(published_ports(address.get("HostPort", "")))
    return reserved


def port_available(port):
    families = [(socket.AF_INET, "0.0.0.0")]
    if socket.has_ipv6:
        families.append((socket.AF_INET6, "::"))
    with ExitStack() as sockets:
        for family, address in families:
            try:
                connection = sockets.enter_context(socket.socket(family, socket.SOCK_STREAM))
                if family == socket.AF_INET6:
                    connection.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
                connection.bind((address, port))
            except OSError as exc:
                if family == socket.AF_INET6 and exc.errno in (errno.EAFNOSUPPORT, errno.EADDRNOTAVAIL):
                    continue
                if exc.errno in (errno.EADDRINUSE, errno.EACCES):
                    return False
                raise
    return True


def reserve_project_ports(root, name, requested, compose_command):
    # Use a single, unambiguous Compose name and keep all files under projects/.
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", name):
        raise ValueError("New project names must start with a lowercase letter or digit and contain only lowercase letters, digits, '-' or '_'")
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    with (root / ".ports.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        directory = root / name
        if os.path.lexists(directory):
            raise ValueError(f"Project {name} already exists; its configuration was preserved")
        reserved = project_ports(root, compose_command) | docker_ports()
        selected = {}
        # Explicit choices take priority over every automatically chosen port.
        for role in DEFAULT_PORTS:
            if requested.get(role) is not None:
                port = valid_port(requested[role])
                if port in reserved or not port_available(port):
                    raise ValueError(f"{role} port {port} is already in use or reserved; choose another port")
                selected[role] = port
                reserved.add(port)
        for role, default in DEFAULT_PORTS.items():
            if role in selected:
                continue
            for port in range(default, 65536):
                if port not in reserved and port_available(port):
                    selected[role] = port
                    reserved.add(port)
                    break
            else:
                raise ValueError(f"No available TCP port for {role}")
        directory.mkdir()
        # Persist before releasing the lock or contacting Docker. A failed
        # initialization still reserves its ports without a completed pickle.
        atomic_write(directory / "ports.json", json.dumps(selected, indent=2) + "\n")
        return selected
'''

docker_setup = r'''    def dockerSetup(self) -> None:
        """Render host port mappings without changing container ports."""
        compose = (self.templates_directory / "docker-compose.yml").read_text()
        replacements = {
            "      - 7687:7687": f'      - "{self.ports["bolt"]}:7687"',
            "      - 7474:7474": f'      - "{self.ports["neo4j"]}:7474"',
            "      - ${BLOODHOUND_PORT:-8080}:8080": f'      - "{self.ports["web"]}:8080"',
        }
        lines = compose.splitlines()
        for old, new in replacements.items():
            if lines.count(old) != 1:
                raise ValueError(f"Unexpected port mapping in Docker template: {old.strip()}")
            lines[lines.index(old)] = new
        if self.no_gds:
            lines = [line for line in lines if line.strip() != '- NEO4J_PLUGINS=["graph-data-science"]']

        config = json.loads((self.templates_directory / "bloodhound.config.json").read_text())
        config["root_url"] = f"http://127.0.0.1:{self.ports['web']}/"
        project_directory = self.source_directory / self.name
        atomic_write(project_directory / "bloodhound.config.json", json.dumps(config, indent=2) + "\n")
        atomic_write(project_directory / "docker-compose.yml", "\n".join(lines) + "\n")


'''
setup_end = next(marker for marker in ("    def replaceLog", "    def readDockerLogs", "    def getAdminPassword") if marker in text)
text = replace_section(text, "    def dockerSetup", setup_end, docker_setup)


# The upstream command treats every `start` as a fresh installation. Replace
# complete lifecycle methods after normalizing the pinned upstream revision so
# an already prepared checkout is upgraded idempotently as well.
admin_password_functions = r'''    def replaceLog(self, content: str) -> None:
        """Publish a complete logs.txt without reusing an old open inode."""
        log_path = self.source_directory / self.name / "logs.txt"
        with tempfile.NamedTemporaryFile(
            "w",
            dir=log_path.parent,
            prefix=".logs.txt.bloodhound-automation.",
            delete=False,
        ) as tmp:
            tmp.write(content)
            tmp_path = Path(tmp.name)
        try:
            os.replace(tmp_path, log_path)
        except BaseException:
            tmp_path.unlink(missing_ok=True)
            raise


    def readDockerLogs(self) -> str:
        """
        Refresh logs.txt from Docker's own logs without leaving a long-running
        `docker compose logs --follow` process behind.
        """
        result = subprocess.run(
            [*self.composeCommand(), "logs", "--no-color"],
            cwd=self.source_directory / self.name,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
            timeout=30,
        )
        log = result.stdout or ""
        self.replaceLog(log)
        if result.returncode != 0:
            raise subprocess.CalledProcessError(
                result.returncode,
                result.args,
                output=log,
            )
        return log


    def getAdminPassword(self) -> str:
        """Find the one-time password during initial installation."""
        start_time = time.monotonic()
        while True:
            try:
                log = self.readDockerLogs()
            except (OSError, subprocess.CalledProcessError) as exc:
                print(Fore.RED + f"[-] Could not read Docker Compose logs: {exc}" + Style.RESET_ALL)
                exit(1)
            match = re.search(r"Initial Password Set To:\s*([^#\r\n]+)", log)
            if match:
                return match.group(1).strip()
            if time.monotonic() - start_time >= self.timeout:
                raise TimeoutError("Could not find the initial admin password; check logs.txt")
            time.sleep(1)


    def waitForWebServer(self) -> None:
        """Check the live server, including when old startup logs remain."""
        start_time = time.monotonic()
        while True:
            try:
                response = requests.get(self.base_url, timeout=min(5, self.timeout))
                if response.status_code == 200:
                    print(Fore.GREEN + "[+] Web server launched successfully" + Style.RESET_ALL)
                    return
            except requests.RequestException:
                pass
            if time.monotonic() - start_time >= self.timeout:
                raise TimeoutError("Timeout while waiting for the web server; check logs.txt")
            time.sleep(1)


'''
admin_start_marker = (
    "    def replaceLog"
    if "    def replaceLog" in text
    else "    def readDockerLogs"
    if "    def readDockerLogs" in text
    else "    def getAdminPassword"
)
text = replace_section(
    text,
    admin_start_marker,
    "    def refreshJWT",
    admin_password_functions,
)

api_methods = r'''    def refreshJWT(self, adminPassword: str, quiet: bool = False) -> bool:
        """
        Get the JWT token required for actions
        """
        url = self.base_url + "/api/v2/login"
        data_to_send = {
            "login_method": "secret",
            "secret": adminPassword,
            "username": "admin"
        }
        response = requests.post(url, json=data_to_send, timeout=30)
        if response.status_code == 200:
            response_json = response.json()
            self.jwt = response_json["data"]["session_token"]
            return True
        if quiet and response.status_code in (401, 403):
            return False
        response.raise_for_status()
        raise RuntimeError(f"Unexpected login response: {response.status_code}")


    def getUserID(self) -> None:
        """
        Get the user ID of the admin account
        """
        headers = {
                    "User-Agent": "bh-automation",
                    "Authorization": f"Bearer {self.jwt}"
                }

        request0 = requests.get(self.base_url + f"/api/v2/self", headers=headers, timeout=30)
        request0.raise_for_status()
        self.user_ID = request0.json()["data"]["id"]

        print(Fore.GREEN + f"[+] UserID found : {self.user_ID}" + Style.RESET_ALL)
        return


    def resetPassword(self, adminPassword: str) -> None:
        """
        Reset the admin's password
        """
        headers = {
                    "User-Agent": "bh-automation",
                    "Authorization": f"Bearer {self.jwt}",
                    "Content-Type": "application/json",
                }

        passwData = {
            "current_secret": adminPassword,
            "needs_password_reset": False,
            "secret": self.password
        }

        request0 = requests.put(self.base_url + f"/api/v2/bloodhound-users/{self.user_ID}/secret", headers=headers, data=json.dumps(passwData), timeout=30)
        request0.raise_for_status()
        
        print(Fore.GREEN + f"[+] Changed admin password to : {self.password}" + Style.RESET_ALL)
        return

    def getApiVersion(self) -> None:
        """
        Print the current BHCE server version in green.
        """
        headers = {
            "User-Agent": "bh-automation",
            "Authorization": f"Bearer {self.jwt}",
            "Content-Type": "application/json",
        }

        response = requests.get(self.base_url + "/api/version", headers=headers, timeout=30)

        if response.status_code == 200:
            json_data = response.json().get("data", {})
            self.bhce_version = json_data.get("server_version", "unknown")

            print(Fore.GREEN + f"[+] You are using BHCE {self.bhce_version}" + Style.RESET_ALL)
        else:
            print(Fore.RED + f"[-] Failed to get BHCE version: {response.status_code}" + Style.RESET_ALL)
        return


    def save(self) -> None:
        """
        Save the project object in a pickle dump
        """
        atomic_write(self.source_directory / self.name / "project.pkl", pickle.dumps(self), mode=0o600)
        return


'''
api_end_marker = next(marker for marker in ("    def composeCommand", "    def composeUpArguments", "    def start(self)") if marker in text)
text = replace_section(text, "    def refreshJWT", api_end_marker, api_methods)

start_methods = r'''    def composeCommand(self) -> List[str]:
        """Keep new projects isolated even when COMPOSE_PROJECT_NAME is set."""
        name = getattr(self, "compose_project_name", None)
        return [*utils.command, "-p", name] if name else list(utils.command)


    def composeUpArguments(self) -> List[str]:
        """Build an offline Compose up command for the available CLI."""
        arguments = ["up", "-d"]
        if utils.command == ["docker", "compose"]:
            arguments.extend(["--pull", "never"])
        return arguments


    def missingComposeImages(self) -> List[str]:
        """Return Compose v2 images that are absent from the local daemon."""
        project_directory = self.source_directory / self.name
        config = subprocess.run(
            [*self.composeCommand(), "config", "--images"],
            cwd=project_directory,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if config.returncode != 0:
            raise subprocess.CalledProcessError(
                config.returncode,
                config.args,
                output=config.stdout,
                stderr=config.stderr,
            )

        # Preserve Compose order while avoiding duplicate inspections when
        # multiple services intentionally use the same image.
        images = list(dict.fromkeys(
            image.strip()
            for image in config.stdout.splitlines()
            if image.strip()
        ))
        if not images:
            raise RuntimeError("Docker Compose did not report any images")

        missing = []
        for image in images:
            inspected = subprocess.run(
                ["docker", "image", "inspect", image],
                text=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            if inspected.returncode != 0:
                missing.append(image)
        return missing


    def runCompose(self, arguments: List[str], log_mode: str = "a") -> None:
        """Run Compose synchronously and store its output in logs.txt."""
        if log_mode not in {"a", "w"}:
            raise ValueError(f"Unsupported log mode: {log_mode}")
        log_path = self.source_directory / self.name / "logs.txt"
        tmp_path = None
        try:
            with tempfile.NamedTemporaryFile(
                "w",
                dir=log_path.parent,
                prefix=".logs.txt.bloodhound-automation.",
                delete=False,
            ) as output_log:
                tmp_path = Path(output_log.name)
                if log_mode == "a" and log_path.is_file():
                    with open(log_path, "r", errors="replace") as current_log:
                        shutil.copyfileobj(current_log, output_log)
                result = subprocess.run(
                    [*self.composeCommand(), *arguments],
                    cwd=self.source_directory / self.name,
                    text=True,
                    stdout=output_log,
                    stderr=subprocess.STDOUT,
                    check=False,
                )
            os.replace(tmp_path, log_path)
        except BaseException:
            if tmp_path is not None:
                tmp_path.unlink(missing_ok=True)
            raise
        if result.returncode != 0:
            raise subprocess.CalledProcessError(result.returncode, result.args)


    def composeOutput(self, arguments: List[str]) -> str:
        result = subprocess.run(
            [*self.composeCommand(), *arguments], cwd=self.source_directory / self.name,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=30,
        )
        return result.stdout


    def waitForDatabases(self) -> None:
        """Allow a running database to recover from unhealthy within -t."""
        deadline = time.monotonic() + self.timeout
        print(Fore.YELLOW + f"[*] Waiting for databases (timeout: {self.timeout}s)..." + Style.RESET_ALL)
        while True:
            identifiers = self.composeOutput(["ps", "-a", "-q", "app-db", "graph-db"]).split()
            if len(identifiers) != 2:
                raise RuntimeError("Could not find both database containers; check logs.txt")
            result = subprocess.run(
                ["docker", "inspect", *identifiers], text=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, check=True, timeout=30,
            )
            states = {}
            for container in json.loads(result.stdout):
                service = container["Config"]["Labels"]["com.docker.compose.service"]
                state = container["State"]
                if state["Status"] in ("exited", "dead", "removing", "paused"):
                    raise RuntimeError(f"{service} is {state['Status']} (exit code {state.get('ExitCode')}); check logs.txt")
                health = (state.get("Health") or {}).get("Status")
                if health is None:
                    raise RuntimeError(f"{service} has no healthcheck; cannot confirm database readiness")
                states[service] = health if state["Status"] == "running" else state["Status"]
            if states == {"app-db": "healthy", "graph-db": "healthy"}:
                return
            if time.monotonic() >= deadline:
                details = ", ".join(f"{name}={status}" for name, status in sorted(states.items()))
                raise TimeoutError(f"Databases did not become ready within {self.timeout}s ({details}); retry start with a larger -t")
            time.sleep(min(2, max(0, deadline - time.monotonic())))


    def refreshGraphProxy(self) -> None:
        """Apply the proxy bypass to a legacy container without replacing its data."""
        identifiers = self.composeOutput(["ps", "-a", "-q", "graph-db"]).split()
        if len(identifiers) != 1:
            raise RuntimeError("Cannot safely update proxy settings: expected one graph-db container")
        result = subprocess.run(
            ["docker", "inspect", identifiers[0]], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, check=True, timeout=30,
        )
        container = json.loads(result.stdout)[0]
        environment = dict(item.split("=", 1) for item in container["Config"].get("Env", []) if "=" in item)
        if not any(environment.get(key) for key in ("http_proxy", "HTTP_PROXY")):
            return
        required = {"localhost", "127.0.0.1", "::1", "app-db", "graph-db", "bloodhound"}
        if all(required <= set(environment.get(key, "").split(",")) for key in ("no_proxy", "NO_PROXY")):
            return

        # Only migrate the known healthcheck. Keep custom configurations and
        # changes to the image, database credentials or data mount for review.
        expected_healthcheck = ["CMD-SHELL", "wget -O /dev/null -q http://localhost:7474 || exit 1"]
        if container["Config"].get("Healthcheck", {}).get("Test") != expected_healthcheck:
            raise RuntimeError("Cannot safely update graph-db proxy: unexpected healthcheck; container was preserved")
        resolved = yaml.safe_load(self.composeOutput(["config"]))
        service = resolved["services"]["graph-db"]
        if service.get("healthcheck", {}).get("test") != expected_healthcheck:
            raise RuntimeError("Cannot safely update graph-db proxy: healthcheck changed; container was preserved")
        configured_environment = service.get("environment") or {}
        if isinstance(configured_environment, list):
            configured_environment = dict(item.split("=", 1) for item in configured_environment if "=" in item)
        if not all(required <= set(str(configured_environment.get(key, "")).split(","))
                   for key in ("no_proxy", "NO_PROXY")):
            raise RuntimeError("graph-db proxy bypass is missing from Compose; rerun prepare.sh --install")
        if any(environment.get(key, "") != str(value if value is not None else "")
               for key, value in configured_environment.items() if key not in ("no_proxy", "NO_PROXY")):
            raise RuntimeError("Cannot safely update graph-db proxy: other environment settings changed; container was preserved")
        image = subprocess.run(
            ["docker", "image", "inspect", "--format", "{{.Id}}", service["image"]],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=30,
        )
        if image.stdout.strip() != container["Image"]:
            raise RuntimeError("Cannot safely update graph-db proxy: image changed; container was preserved")
        data_mounts = [mount for mount in service.get("volumes", [])
                       if isinstance(mount, dict) and mount.get("target") == "/data"]
        existing_mounts = [mount for mount in container.get("Mounts", []) if mount.get("Destination") == "/data"]
        if len(data_mounts) != 1 or len(existing_mounts) != 1:
            raise RuntimeError("Cannot safely update graph-db proxy: unrecognized data mount; container was preserved")
        wanted, existing = data_mounts[0], existing_mounts[0]
        if wanted.get("type") == "volume":
            source = resolved.get("volumes", {}).get(wanted.get("source"), {}).get("name")
            matches = source and existing.get("Type") == "volume" and existing.get("Name") == source
        elif wanted.get("type") == "bind":
            matches = existing.get("Type") == "bind" and existing.get("Source") == wanted.get("source")
        else:
            matches = False
        if not matches or existing.get("RW") != (not wanted.get("read_only", False)):
            raise RuntimeError("Cannot safely update graph-db proxy: data mount changed; container was preserved")
        print(Fore.YELLOW + "[*] Applying localhost proxy bypass to graph-db; keeping its image and data volume" + Style.RESET_ALL)
        self.runCompose([*self.composeUpArguments(), "--no-deps", "graph-db"], "a")


    def startServices(self, log_mode: str = "a", preserve_containers: bool = True, refresh_proxy: bool = False) -> None:
        # Compose aborts dependency startup as soon as a healthcheck becomes
        # unhealthy. Wait ourselves: GDS may still be downloading at that point.
        arguments = [*self.composeUpArguments(), "--no-deps"]
        if preserve_containers:
            arguments.append("--no-recreate")
        self.runCompose([*arguments, "app-db", "graph-db"], log_mode)
        if refresh_proxy:
            self.refreshGraphProxy()
        self.waitForDatabases()
        self.runCompose([*arguments, "bloodhound"], "a")


    def initializationConfigHashes(self) -> dict:
        directory = self.source_directory / self.name
        return {name: hashlib.sha256((directory / name).read_bytes()).hexdigest()
                for name in ("docker-compose.yml", "bloodhound.config.json")}


    def initializationConfigMatches(self, saved: dict) -> bool:
        current = self.initializationConfigHashes()
        if saved == current:
            return True
        # Accept only the exact managed proxy addition to an old manifest.
        # recordInitialization publishes the new hashes after all resume checks.
        compose = (self.source_directory / self.name / "docker-compose.yml").read_text()
        for key in ("no_proxy", "NO_PROXY"):
            line = "      - " + key + "=localhost,127.0.0.1,::1,app-db,graph-db,bloodhound,${no_proxy:-${NO_PROXY:-}}\n"
            if compose.count(line) != 3:
                return False
            compose = compose.replace(line, "")
        current["docker-compose.yml"] = hashlib.sha256(compose.encode()).hexdigest()
        return saved == current


    def restoreIncomplete(self) -> None:
        """Resume only recognizable, consistent files; never regenerate them."""
        directory = self.source_directory / self.name
        for name in ("ports.json", "docker-compose.yml", "bloodhound.config.json"):
            path = directory / name
            if not path.is_file() or path.is_symlink():
                raise ValueError(f"Cannot safely resume: missing or unsupported {name}; project files were preserved")
        ports = json.loads((directory / "ports.json").read_text())
        if not isinstance(ports, dict) or set(ports) != {"bolt", "neo4j", "web"}:
            raise ValueError("Cannot safely resume: invalid ports.json")
        ports = {role: valid_port(port) for role, port in ports.items()}
        if len(set(ports.values())) != 3:
            raise ValueError("Cannot safely resume: duplicate ports in ports.json")
        for role, requested in self.ports.items():
            if requested is not None and requested != ports[role]:
                raise ValueError(f"Project {self.name} already uses {role} port {ports[role]}; resume preserves existing ports")
        self.compose_project_name = self.name
        resolved = yaml.safe_load(self.composeOutput(["config"]))
        services = resolved.get("services", {})
        if not all(isinstance(services.get(name), dict) for name in ("app-db", "graph-db", "bloodhound")):
            raise ValueError("Cannot safely resume: expected BloodHound services are missing")
        for service, expected in (("graph-db", {ports["bolt"], ports["neo4j"]}), ("bloodhound", {ports["web"]})):
            if compose_ports({"services": {service: services[service]}}) != expected:
                raise ValueError(f"Cannot safely resume: {service} ports do not match ports.json")
        environment = services["graph-db"].get("environment") or {}
        if isinstance(environment, list):
            environment = dict(item.split("=", 1) for item in environment if "=" in item)
        plugins = json.loads(environment.get("NEO4J_PLUGINS") or "[]")
        no_gds = "graph-data-science" not in plugins
        if self.no_gds and not no_gds:
            raise ValueError("Resume preserves the GDS setting; omit --no-gds for this project")
        state_path = directory / "initialization.json"
        if state_path.exists():
            if state_path.is_symlink():
                raise ValueError("Cannot safely resume: initialization.json must not be a symbolic link")
            state = json.loads(state_path.read_text())
            if (not isinstance(state, dict) or state.get("version") != 1
                    or state.get("ports") != ports or state.get("no_gds") != no_gds
                    or not self.initializationConfigMatches(state.get("config_hashes"))
                    or not isinstance(state.get("password"), str)):
                raise ValueError("Cannot safely resume: initialization settings or project configuration changed")
            if self.password is not None and self.password != state["password"]:
                raise ValueError("Resume preserves the saved password; omit --password or provide the original value")
            self.password = state["password"]
        self.ports = ports
        self.no_gds = no_gds


    def recordInitialization(self) -> None:
        state = {"version": 1, "ports": self.ports, "password": self.password,
                 "no_gds": self.no_gds, "config_hashes": self.initializationConfigHashes()}
        atomic_write(self.source_directory / self.name / "initialization.json",
                     json.dumps(state, indent=2) + "\n", mode=0o600)


    def initializeWeb(self) -> None:
        self.waitForWebServer()
        # A previous attempt may have changed the password just before it was
        # interrupted. Authenticate with that password before trying the old one.
        if self.refreshJWT(self.password, quiet=True):
            self.getUserID()
        else:
            admin_password = self.getAdminPassword()
            if not self.refreshJWT(admin_password, quiet=True):
                raise RuntimeError("Could not authenticate with the saved or initial password; project data was preserved")
            self.getUserID()
            self.resetPassword(admin_password)
        self.getApiVersion()


    def reportStartupFailure(self, exc: Exception) -> None:
        path = self.source_directory / self.name / "logs.txt"
        try:
            previous = path.read_text(errors="replace") if path.is_file() else ""
            logs = self.readDockerLogs()
            self.replaceLog(previous + "\n" + logs)
        except (OSError, subprocess.SubprocessError):
            pass
        print(Fore.RED + f"[-] Could not start project {self.name}: {exc}" + Style.RESET_ALL)
        print(f"Check {path}. Retry start with the same project name; saved ports and data are preserved.")


    def startExisting(self) -> None:
        """Start an initialized project using local images only."""
        project_directory = self.source_directory / self.name
        if not (project_directory / "docker-compose.yml").is_file():
            print(Fore.RED + f"[-] Project {self.name} has no docker-compose.yml" + Style.RESET_ALL)
            exit(1)

        print(Fore.YELLOW + f"[*] Starting existing project {self.name} without pulling images..." + Style.RESET_ALL)
        try:
            self.startServices("w", preserve_containers=False)
            self.waitForWebServer()
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, requests.RequestException) as exc:
            self.reportStartupFailure(exc)
            exit(1)

        print(Fore.GREEN + f"[+] Project {self.name} started" + Style.RESET_ALL)
        print(Fore.GREEN + f"[+] BloodHound Web GUI: {self.base_url}" + Style.RESET_ALL)


    def start(self, resume: bool = False) -> None:
        """Create a project or finish an interrupted initialization."""
        try:
            if self.timeout <= 0:
                raise ValueError("Timeout must be greater than zero")
            if resume:
                self.restoreIncomplete()
            self.password = self.password if self.password is not None else "Chien2Sang<3"
            if not self.isValidPassword():
                raise ValueError("Password must contain at least 12 characters, uppercase, lowercase, a digit and a special character")
            if not resume:
                self.ports = reserve_project_ports(self.source_directory, self.name, self.ports, utils.command)
                self.compose_project_name = self.name
                self.dockerSetup()
            self.base_url = f"http://localhost:{self.ports['web']}"
            self.recordInitialization()
        except (OSError, ValueError, AttributeError, TypeError, yaml.YAMLError, subprocess.SubprocessError) as exc:
            print(Fore.RED + f"[-] Could not prepare project {self.name}: {exc}" + Style.RESET_ALL)
            exit(1)

        print(Fore.GREEN + f"[+] Ports: bolt={self.ports['bolt']}, neo4j={self.ports['neo4j']}, web={self.ports['web']}" + Style.RESET_ALL)
        print(Fore.GREEN + ("[+] Resuming saved project configuration" if resume else "[+] Docker setup done") + Style.RESET_ALL)
        print(Fore.YELLOW + "[*] Launching BloodHound..." + Style.RESET_ALL)
        print(f"The docker logs are accessible in {self.source_directory / self.name / 'logs.txt'}")

        # Docker images are daemon-wide, not project-specific. Reuse images
        # acquired by an earlier project and contact the registry only when at
        # least one image required by the resolved Compose file is absent.
        try:
            if utils.command == ["docker", "compose"]:
                missing_images = self.missingComposeImages()
                if missing_images:
                    print(
                        Fore.YELLOW
                        + "[*] Pulling missing Docker images: "
                        + ", ".join(missing_images)
                        + Style.RESET_ALL
                    )
                    self.runCompose(["pull"], "w")
                    up_log_mode = "a"
                else:
                    print(
                        Fore.YELLOW
                        + "[*] Reusing local Docker images without pulling..."
                        + Style.RESET_ALL
                    )
                    up_log_mode = "w"
            else:
                # Compose v1 has no `config --images` option. Its `up` command
                # already reuses local images and pulls only absent ones.
                print(
                    Fore.YELLOW
                    + "[*] Reusing local Docker images; Compose will pull only missing ones..."
                    + Style.RESET_ALL
                )
                up_log_mode = "w"
            self.startServices(up_log_mode, refresh_proxy=resume)
            self.initializeWeb()
            self.save()
            (self.source_directory / self.name / "initialization.json").unlink(missing_ok=True)
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, requests.RequestException) as exc:
            self.reportStartupFailure(exc)
            exit(1)

        print(Fore.GREEN + f"[+] Project {self.name} initialized successfully" + Style.RESET_ALL)
        print(Fore.GREEN + f"[+] BloodHound Web GUI: {self.base_url}" + Style.RESET_ALL)
        print(Fore.GREEN + f"[+] Username: admin; password: {self.password}" + Style.RESET_ALL)
        return


'''
lifecycle_start_marker = (
    "    def composeCommand"
    if "    def composeCommand" in text
    else "    def composeUpArguments"
    if "    def composeUpArguments" in text
    else "    def start(self)"
)
text = replace_section(
    text,
    lifecycle_start_marker,
    "    def extractZip",
    start_methods,
)

stop_method = '''    def stop(self) -> None:
        """Stop all project containers and wait for Compose to finish."""
        print(Fore.GREEN + f"[+] Stopping project: {self.name}" + Style.RESET_ALL)
        try:
            self.runCompose(["stop"], "w")
        except (OSError, subprocess.CalledProcessError) as exc:
            print(Fore.RED + f"An error occurred while stopping Docker Compose: {exc}")
            print(Style.RESET_ALL + "Exiting...")
            exit(1)
        print(Fore.GREEN + "[+] Done!" + Style.RESET_ALL)


'''
text = replace_section(
    text,
    "    def stop(self)",
    "    def delete(self)",
    stop_method,
)

delete_method = '''    def delete(self) -> None:
        """Remove the Compose project before deleting its directory."""
        print(Fore.YELLOW + f"[*] Deleting {self.name} project..." + Style.RESET_ALL)
        try:
            self.runCompose(["down"], "a")
        except (OSError, subprocess.CalledProcessError) as exc:
            print(Fore.RED + f"An error occurred while deleting Docker Compose project: {exc}")
            print(Style.RESET_ALL + "Exiting...")
            exit(1)
        shutil.rmtree(self.source_directory / self.name)
        print(Fore.GREEN + f"[+] The project {self.name} has been successfully deleted" + Style.RESET_ALL)
'''
delete_start = text.find("    def delete(self)")
if delete_start == -1:
    raise SystemExit("bloodhound-automation patch failed: delete method not found")
text = text[:delete_start] + delete_method
text = text.replace("[*utils.command,", "[*self.composeCommand(),")
# The command builder itself must reference the underlying CLI, not recurse.
text = text.replace('return [*self.composeCommand(), "-p", name]', 'return [*utils.command, "-p", name]')

for role, flag, default in (("bolt", "bp", 7687), ("neo4j", "np", 7474), ("web", "wp", 8080)):
    prefix = f"    parser_start.add_argument('-{flag}', '--{role}-port',"
    lines = cli_text.splitlines(keepends=True)
    matching = [index for index, line in enumerate(lines) if line.startswith(prefix)]
    if len(matching) != 1:
        raise SystemExit(f"bloodhound-automation patch failed: missing {role} port argument")
    lines[matching[0]] = prefix + f' type=int, default=None, help="Host TCP port (default: first available from {default})")\n'
    cli_text = ''.join(lines)

for prefix, replacement in (
    ("    parser_start.add_argument('-p', '--password',", '    parser_start.add_argument(\'-p\', \'--password\', type=str, default=None, help="New project password (default: Chien2Sang<3); resume preserves the saved password")\n'),
    ("    parser_start.add_argument('-t', '--timeout',", '    parser_start.add_argument(\'-t\', \'--timeout\', type=int, default=1200, help="Seconds to wait for database and web startup, including GDS download (default: 1200)")\n'),
):
    lines = cli_text.splitlines(keepends=True)
    matching = [index for index, line in enumerate(lines) if line.startswith(prefix)]
    if len(matching) != 1:
        raise SystemExit(f"bloodhound-automation patch failed: missing argument {prefix.strip()}")
    lines[matching[0]] = replacement
    cli_text = ''.join(lines)

cli_start = r'''    elif args.subparser == "start":
        if args.timeout <= 0:
            parser.error("--timeout must be greater than zero")
        project_directory = PROJECT_DIR / args.project
        project_file = project_directory / "project.pkl"

        try:
            with project_lock(PROJECT_DIR, args.project):
                if os.path.lexists(project_directory) and not project_directory.is_dir():
                    raise ValueError(f"Project path is not a directory: {project_directory}")
                if os.path.lexists(project_file):
                    with open(project_file, "rb") as pkl_file:
                        project = pickle.load(pkl_file)

                    # Preserve initialized project settings, including legacy
                    # Compose identity, while honoring this invocation's timeout.
                    project.name = args.project
                    project.source_directory = PROJECT_DIR
                    project.base_url = f"http://localhost:{project.ports['web']}"
                    project.timeout = args.timeout
                    for role in ("bolt", "neo4j", "web"):
                        requested = getattr(args, role + "_port")
                        if requested is not None and requested != project.ports[role]:
                            parser.error(f"Project {args.project} already uses {role} port {project.ports[role]}; start preserves existing ports")
                    project.startExisting()
                else:
                    project = Project(name=args.project,
                                      source_directory=PROJECT_DIR,
                                      ports={"neo4j": args.neo4j_port, "bolt": args.bolt_port, "web": args.web_port},
                                      password=args.password, timeout=args.timeout, no_gds=args.no_gds)
                    project.start(resume=project_directory.exists())
        except (OSError, ValueError, pickle.UnpicklingError, EOFError, AttributeError, ImportError, IndexError) as exc:
            print(Fore.RED + f"[-] Could not start project {args.project}: {exc}" + Style.RESET_ALL)
            exit(1)


'''
cli_text = replace_section(
    cli_text,
    '    elif args.subparser == "start":',
    '    elif args.subparser == "data":',
    cli_start,
)

requirements_original = requirements_path.read_text()
# PyYAML safely reads resolved Compose mappings, including legacy projects.
# The system Compose CLI replaces the legacy Python Ansible/Compose packages.
requirements_text = "requests==2.32.5\ncolorama\nPyYAML==6.0.3\n"
ports_path = path.parent / "ports.py"
for filename, content in ((path, text), (cli_path, cli_text), (ports_path, ports_source)):
    compile(content, str(filename), "exec")


def replace_file(file_path: Path, content: str) -> None:
    with tempfile.NamedTemporaryFile(
        "w",
        dir=file_path.parent,
        prefix=f".{file_path.name}.prepare.",
        delete=False,
    ) as tmp:
        tmp.write(content)
        tmp_path = Path(tmp.name)
    try:
        os.chmod(tmp_path, file_path.stat().st_mode if file_path.exists() else 0o644)
        os.replace(tmp_path, file_path)
    except BaseException:
        tmp_path.unlink(missing_ok=True)
        raise


if not ports_path.exists() or ports_path.read_text() != ports_source:
    replace_file(ports_path, ports_source)
if text != original:
    replace_file(path, text)
if cli_text != cli_original:
    replace_file(cli_path, cli_text)
if requirements_text != requirements_original:
    replace_file(requirements_path, requirements_text)
PY

    success "bloodhound-automation: новые проекты получают отдельные порты, повторный запуск сохраняет настройки"

    patch_bloodhound_automation_compose_file "${dir}/templates/docker-compose.yml"

    if [ -d "${dir}/projects" ]; then
        while IFS= read -r compose_file; do
            patch_bloodhound_automation_compose_file "$compose_file"
        done < <(find "${dir}/projects" -mindepth 2 -maxdepth 2 -type f -name 'docker-compose.yml' | sort)
    fi

    success "bloodhound-automation: docker-compose настроен (proxy + healthcheck)"
}

# Определяет, является ли ref полным либо достаточно длинным сокращённым коммитом.
is_commit_ref() {
    [[ "$1" =~ ^[0-9a-f]{12,40}$ ]]
}

is_stable_version_tag() {
    [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

version_tag_is_newer() {
    local candidate="${1#v}" baseline="${2#v}"
    is_stable_version_tag "$1" && is_stable_version_tag "$2" || return 1
    [ "$candidate" != "$baseline" ] \
        && [ "$(printf '%s\n%s\n' "$baseline" "$candidate" | LC_ALL=C sort -V | tail -1)" = "$candidate" ]
}

result_field() {
    local result="$1" key="$2" part
    local fields=()
    IFS=';' read -r -a fields <<< "$result"
    for part in "${fields[@]}"; do
        if [[ "$part" == "${key}:"* ]]; then
            printf '%s' "${part#*:}"
            return 0
        fi
    done
    return 1
}

result_has() {
    local result="$1" key="$2" part
    local fields=()
    IFS=';' read -r -a fields <<< "$result"
    for part in "${fields[@]}"; do
        [ "$part" = "$key" ] && return 0
    done
    return 1
}

# Извлекает версию (ref) из записи UV_TOOLS
uv_tool_ref() {
    echo "$1" | cut -d'|' -f1
}

# Извлекает URL репозитория из записи UV_TOOLS
uv_tool_url() {
    echo "$1" | cut -d'|' -f2
}

# Необязательная ветка для проектов, чей нужный вариант находится не в HEAD.
uv_tool_update_branch() {
    echo "$1" | cut -d'|' -f3
}

# Отображаемая версия для UV tool
uv_tool_display_version() {
    uv_tool_ref "$1"
}

# Извлекает версию бинарного инструмента
binary_tool_version() { echo "$1" | cut -d'|' -f1; }
binary_tool_url()     { echo "$1" | cut -d'|' -f2; }
binary_tool_type()    { echo "$1" | cut -d'|' -f3; }
binary_tool_path()    { echo "$1" | cut -d'|' -f4; }
binary_tool_sha256()  { echo "$1" | cut -d'|' -f5; }

# Выводит все команды одного release-артефакта в формате имя|путь_в_пакете.
binary_tool_command_specs() {
    local name="$1" item command_name source_path
    local entries=()

    printf '%s|%s\n' "$name" "$(binary_tool_path "${BINARY_TOOLS[$name]}")"
    if [[ -v "BINARY_TOOL_EXTRA_COMMANDS[$name]" ]]; then
        IFS=',' read -r -a entries <<< "${BINARY_TOOL_EXTRA_COMMANDS[$name]}"
        for item in "${entries[@]}"; do
            command_name="${item%%=*}"
            source_path="${item#*=}"
            printf '%s|%s\n' "$command_name" "$source_path"
        done
    fi
}

binary_tool_commands_present() {
    local name="$1" command_name source_path installed_path

    while IFS='|' read -r command_name source_path; do
        installed_path=$(command -v "$command_name" 2>/dev/null) || return 1
        [ -s "$installed_path" ] || return 1
    done < <(binary_tool_command_specs "$name")
}

# Извлекает GitHub repo URL из URL релиза/скачивания
# https://github.com/owner/repo/releases/download/... → https://github.com/owner/repo
github_repo_from_url() {
    echo "$1" | grep -oP 'https://github\.com/[^/]+/[^/]+' || true
}


# Клонирует репо во временный соседний каталог и публикует его только после
# успешной проверки ревизии.
git_clone_at_revision() {
    local url="$1" dir="$2" commit="$3"
    local parent base tmp current

    if [ -e "$dir" ] || [ -L "$dir" ]; then
        error "Не клонирую поверх существующего пути: $dir"
        return 1
    fi

    parent=$(dirname "$dir")
    base=$(basename "$dir")
    mkdir -p "$parent"
    tmp=$(mktemp -d "${parent}/.${base}.prepare.XXXXXX")

    if [ -n "$commit" ] && [ "${USE_REVISION:-false}" = true ]; then
        if ! git clone --revision="$commit" "$url" "$tmp"; then
            rm -rf -- "$tmp"
            return 1
        fi
    elif [ -n "$commit" ]; then
        # Старые Git не поддерживают clone --revision. Сначала забираем только
        # требуемый commit; если сервер не разрешает fetch по хешу, используем
        # partial clone без файлов рабочего дерева.
        if git -C "$tmp" init -q \
            && git -C "$tmp" remote add origin "$url" \
            && git -C "$tmp" fetch --depth=1 --no-tags origin "$commit" \
            && git -C "$tmp" checkout -q --detach FETCH_HEAD; then
            :
        else
            rm -rf -- "$tmp"
            tmp=$(mktemp -d "${parent}/.${base}.prepare.XXXXXX")
            if ! git clone --filter=blob:none --no-checkout "$url" "$tmp" \
                || ! git -C "$tmp" checkout -q --detach "$commit"; then
                rm -rf -- "$tmp"
                return 1
            fi
        fi
    else
        if ! git clone "$url" "$tmp"; then
            rm -rf -- "$tmp"
            return 1
        fi
    fi

    current=$(git -C "$tmp" rev-parse HEAD 2>/dev/null || true)
    if [ -z "$current" ] || { [ -n "$commit" ] && ! hashes_match "$current" "$commit"; }; then
        error "Клонированный репозиторий не прошёл проверку ревизии: $dir"
        rm -rf -- "$tmp"
        return 1
    fi

    mv "$tmp" "$dir"
}

install_missing_apt_packages() {
    local missing=()
    local package status

    for package in "$@"; do
        status=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)
        [ "$status" = "installed" ] || missing+=("$package")
    done

    if [ ${#missing[@]} -eq 0 ]; then
        success "Все системные пакеты уже установлены; существующие версии не изменяются"
        return 0
    fi

    info "Установка отсутствующих системных пакетов: ${missing[*]}"
    sudo_with_proxy DEBIAN_FRONTEND=noninteractive apt-get update -y
    sudo_with_proxy DEBIAN_FRONTEND=noninteractive apt-get install -y --no-upgrade \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        "${missing[@]}"
}

install_go_fresh() {
    local go_archive="go${GO_VERSION}.linux-amd64.tar.gz"
    local tmpdir archive stage=""

    if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
        error "Автоматическая установка Go поддерживает только Linux x86_64"
        return 1
    fi
    if sudo test -e /usr/local/go; then
        error "/usr/local/go уже существует, но go не найден в PATH; каталог оставлен без изменений"
        return 1
    fi

    tmpdir=$(mktemp -d)
    archive="${tmpdir}/${go_archive}"
    if ! wget -q "https://go.dev/dl/${go_archive}" -O "$archive"; then
        rm -rf -- "$tmpdir"
        error "Не удалось скачать Go ${GO_VERSION}"
        return 1
    fi
    if ! printf '%s  %s\n' "$GO_LINUX_AMD64_SHA256" "$archive" | sha256sum -c - >/dev/null; then
        rm -rf -- "$tmpdir"
        error "Архив Go не прошёл проверку SHA-256"
        return 1
    fi
    if ! tar -tzf "$archive" >/dev/null; then
        rm -rf -- "$tmpdir"
        error "Архив Go повреждён"
        return 1
    fi

    if ! stage=$(sudo mktemp -d /usr/local/.prepare-go.XXXXXX); then
        rm -rf -- "$tmpdir"
        error "Не удалось создать временный каталог для Go"
        return 1
    fi
    if ! sudo tar -C "$stage" -xzf "$archive" \
        || ! sudo test -x "${stage}/go/bin/go"; then
        sudo rm -rf -- "$stage"
        rm -rf -- "$tmpdir"
        error "Не удалось распаковать Go во временный каталог"
        return 1
    fi
    if sudo test -e /usr/local/go \
        || ! sudo mv -T "${stage}/go" /usr/local/go; then
        sudo rm -rf -- "$stage"
        rm -rf -- "$tmpdir"
        error "Не удалось опубликовать Go: /usr/local/go уже существует"
        return 1
    fi

    sudo rmdir "$stage" || true
    rm -rf -- "$tmpdir"
    success "Go ${GO_VERSION} установлен с проверкой целостности"
}

resolve_go_tool_version() {
    local spec="$1"
    local module
    module=$(go_tool_module "$spec")
    GO111MODULE=on go list -m -f '{{.Version}}' "${module}@latest" 2>/dev/null
}

install_official_go_release() {
    local name="$1" spec="$2" repo="$3" version="$4"
    local module plain_version asset checksum_name base_url
    local tmpdir expected actual source_file reported build_info dest_tmp

    module=$(go_tool_module "$spec")
    plain_version="${version#v}"
    asset="${name}_${plain_version}_linux_amd64.zip"
    checksum_name="${name}_${plain_version}_checksums.txt"
    base_url="https://github.com/${repo}/releases/download/${version}"
    tmpdir=$(mktemp -d)

    info "$name: скачивание официального release ${version}..."
    if ! wget -q "${base_url}/${asset}" -O "${tmpdir}/${asset}" \
        || ! wget -q "${base_url}/${checksum_name}" -O "${tmpdir}/${checksum_name}"; then
        rm -rf -- "$tmpdir"
        warn "$name: официальный release недоступен"
        return 1
    fi

    expected=$(awk -v wanted="$asset" '$2 == wanted { print $1; exit }' \
        "${tmpdir}/${checksum_name}")
    actual=$(sha256sum "${tmpdir}/${asset}" | awk '{print $1}')
    if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]] || [ "$actual" != "$expected" ]; then
        rm -rf -- "$tmpdir"
        warn "$name: release не прошёл проверку SHA-256"
        return 1
    fi
    if ! unzip -tq "${tmpdir}/${asset}" >/dev/null; then
        rm -rf -- "$tmpdir"
        warn "$name: release-архив повреждён"
        return 1
    fi

    mkdir -p "${tmpdir}/unpack"
    if ! unzip -q "${tmpdir}/${asset}" "$name" -d "${tmpdir}/unpack"; then
        rm -rf -- "$tmpdir"
        warn "$name: в release-архиве нет ожидаемого бинарника"
        return 1
    fi
    source_file="${tmpdir}/unpack/${name}"
    if [ ! -s "$source_file" ]; then
        rm -rf -- "$tmpdir"
        warn "$name: release-бинарник пуст"
        return 1
    fi
    chmod 755 "$source_file"

    build_info=$(go version -m "$source_file" 2>/dev/null || true)
    if ! grep -Fq "$module" <<< "$build_info"; then
        rm -rf -- "$tmpdir"
        warn "$name: release собран не из ожидаемого Go-модуля"
        return 1
    fi
    reported=$(go_tool_cli_version "$source_file" || true)
    if ! refs_equivalent "$reported" "$version"; then
        rm -rf -- "$tmpdir"
        warn "$name: release сообщает неожиданную версию (${reported:-неизвестно})"
        return 1
    fi

    mkdir -p "$GO_BIN_DIR"
    if [ -e "${GO_BIN_DIR}/${name}" ] || [ -L "${GO_BIN_DIR}/${name}" ]; then
        backup_incomplete_path "${GO_BIN_DIR}/${name}"
    fi
    dest_tmp=$(mktemp "${GO_BIN_DIR}/.${name}.prepare.XXXXXX")
    if ! install -m 0755 "$source_file" "$dest_tmp"; then
        rm -f -- "$dest_tmp"
        rm -rf -- "$tmpdir"
        warn "$name: не удалось подготовить release-бинарник"
        return 1
    fi
    mv "$dest_tmp" "${GO_BIN_DIR}/${name}"
    rm -rf -- "$tmpdir"
    hash -r 2>/dev/null || true

    if ! is_go_tool "$name"; then
        error "$name: release-бинарник не найден после установки"
        return 1
    fi
    success "$name ${version} установлен из проверенного официального release"
}

install_go_tool() {
    local name="$1" spec="$2"
    local version="" source_spec="$spec"

    if [[ -v "GO_RELEASE_REPOS[$name]" ]] \
        && [ "$(uname -s)" = "Linux" ] \
        && [ "$(uname -m)" = "x86_64" ]; then
        version=$(resolve_go_tool_version "$spec" || true)
        if is_stable_version_tag "$version"; then
            if install_official_go_release \
                "$name" "$spec" "${GO_RELEASE_REPOS[$name]}" "$version"; then
                return 0
            fi
            warn "$name: используется сборка из того же исходного тега"
            source_spec="${spec%@*}@${version}"
        else
            warn "$name: не удалось однозначно определить release; используется go install"
        fi
    fi

    info "Компиляция $name..."
    GOBIN="$GO_BIN_DIR" go install -v "$source_spec"
    success "$name установлен"
}

tmux_config_file() {
    local xdg_conf="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
    if [ -f "$xdg_conf" ]; then
        printf '%s' "$xdg_conf"
    else
        printf '%s' "$HOME/.tmux.conf"
    fi
}

tmux_quote() {
    local value="${1//\\/\\\\}"
    value="${value//\'/\\\'}"
    printf "'%s'" "$value"
}

tmux_plugin_executables_ready() {
    local name="$1" dir="$2" repair="${3:-false}" entry
    local entries=()
    case "$name" in
        tpm) entries=(tpm) ;;
        tmux-sensible) entries=(sensible.tmux) ;;
        tmux-logging)
            entries=(logging.tmux scripts/toggle_logging.sh scripts/start_logging.sh
                scripts/screen_capture.sh scripts/save_complete_history.sh
                scripts/clear_history.sh scripts/check_tmux_version.sh) ;;
        *) return 0 ;;
    esac

    # Проверяем весь набор до chmod: недостающие файлы и ссылки не исправляем.
    for entry in "${entries[@]}"; do
        if [ ! -f "${dir}/${entry}" ] || [ ! -s "${dir}/${entry}" ] || [ -L "${dir}/${entry}" ]; then
            error "tmux plugin $name: отсутствует или повреждён файл: ${dir}/${entry}"
            return 1
        fi
    done
    for entry in "${entries[@]}"; do
        if [ ! -x "${dir}/${entry}" ]; then
            if [ "$repair" = true ]; then
                if ! chmod u+x -- "${dir}/${entry}"; then
                    error "tmux plugin $name: не удалось восстановить право исполнения: ${dir}/${entry}"
                    return 1
                fi
            fi
            if [ ! -x "${dir}/${entry}" ]; then
                error "tmux plugin $name: файл не исполняемый: ${dir}/${entry}"
                return 1
            fi
            info "tmux plugin $name: восстановлено право исполнения: $entry"
        fi
    done
}

tmux_install_plugin() {
    local name="$1" repo="$2"
    local dir="${TMUX_PLUGIN_DIR}/${name}"

    if [ -d "$dir/.git" ]; then
        if ! git -C "$dir" rev-parse HEAD &>/dev/null; then
            error "tmux plugin $name: существующий Git-репозиторий повреждён: $dir"
            return 1
        fi
        tmux_plugin_executables_ready "$name" "$dir" true || return 1
        success "tmux plugin $name уже установлен"
        return 0
    fi
    if [ -e "$dir" ]; then
        error "Не удалось установить tmux plugin $name: ${dir} существует и не является Git-репозиторием"
        return 1
    fi

    info "Клонирование tmux plugin $name..."
    git_clone_at_revision "$repo" "$dir" "" || return 1
    tmux_plugin_executables_ready "$name" "$dir" true || return 1
    success "tmux plugin $name установлен"
}

tmux_write_config() {
    local conf="$1" tmp mode
    local plugin_dir_q log_path_q tpm_q

    mkdir -p "$(dirname "$conf")"
    [ -f "$conf" ] || : > "$conf"
    mode=$(stat -c '%a' "$conf" 2>/dev/null || echo 600)
    tmp=$(mktemp "${conf}.prepare.XXXXXX")

    # Удаляем только предыдущий управляемый блок. Пользовательские настройки,
    # включая совпадающие параметры вне блока, сохраняются без фильтрации.
    if ! awk '
        $0 == "# BEGIN prepare.sh: tmux" {
            if (managed) exit 42
            managed=1
            next
        }
        $0 == "# END prepare.sh: tmux" {
            if (!managed) exit 42
            managed=0
            next
        }
        managed { next }
        { lines[++count]=$0 }
        END {
            if (managed) exit 42
            while (count > 0 && lines[count] ~ /^[[:space:]]*$/) count--
            for (i=1; i<=count; i++) print lines[i]
        }
    ' "$conf" > "$tmp"; then
        rm -f -- "$tmp"
        error "tmux: повреждён управляемый блок в $conf; исходный файл сохранён"
        return 1
    fi

    plugin_dir_q=$(tmux_quote "${TMUX_PLUGIN_DIR}/")
    log_path_q=$(tmux_quote "${TMUX_LOG_DIR}/%Y-%m-%d")
    tpm_q=$(tmux_quote "${TMUX_PLUGIN_DIR}/tpm/tpm")
    {
        [ ! -s "$tmp" ] || echo ""
        echo "# BEGIN prepare.sh: tmux"
        echo "set -g history-limit 100000"
        echo "set -g mouse on"
        echo "set-environment -g TMUX_PLUGIN_MANAGER_PATH ${plugin_dir_q}"
        echo "set -g @plugin 'tmux-plugins/tpm'"
        echo "set -g @plugin 'tmux-plugins/tmux-sensible'"
        echo "set -g @plugin 'ShAmRoWw/tmux-logging'"
        echo "set -g @logging-path ${log_path_q}"
        echo "run-shell ${tpm_q}"
        echo "# END prepare.sh: tmux"
    } >> "$tmp"

    chmod "$mode" "$tmp"
    if ! tmux_validate_config "$tmp"; then
        rm -f -- "$tmp"
        error "Конфигурация tmux не прошла проверку; исходный файл сохранён: $conf"
        return 1
    fi
    mv "$tmp" "$conf"
}

tmux_configured() {
    local conf="$1"
    [ -f "$conf" ] &&
        grep -Fqx "set -g history-limit 100000" "$conf" &&
        grep -Fqx "set -g mouse on" "$conf" &&
        grep -Fqx "set -g @plugin 'tmux-plugins/tpm'" "$conf" &&
        grep -Fqx "set -g @plugin 'tmux-plugins/tmux-sensible'" "$conf" &&
        grep -Fqx "set -g @plugin 'ShAmRoWw/tmux-logging'" "$conf" &&
        grep -Fqx "set -g @logging-path $(tmux_quote "${TMUX_LOG_DIR}/%Y-%m-%d")" "$conf" &&
        grep -Fqx "run-shell $(tmux_quote "${TMUX_PLUGIN_DIR}/tpm/tpm")" "$conf"
}

tmux_validate_config() {
    local conf="$1" socket="prepare-$UID-$$-$RANDOM"
    local output="" failure_reason="" validation_root validation_conf
    local actual_value bindings plugin
    local validation_status=0

    # Одна привязка клавиши ещё не гарантирует, что её обработчик запускается.
    for plugin in tpm tmux-sensible tmux-logging; do
        tmux_plugin_executables_ready "$plugin" "${TMUX_PLUGIN_DIR}/${plugin}" || return 1
    done

    # TPM не использует путь из `tmux -f`: он самостоятельно перечитывает
    # ~/.tmux.conf или XDG_CONFIG_HOME/tmux/tmux.conf. Помещаем проверяемый
    # кандидат в изолированный XDG-каталог, иначе TPM увидит старый файл и
    # проверка ложно сообщит, что tmux-logging не загрузился.
    validation_root=$(mktemp -d "${TMPDIR:-/tmp}/prepare-tmux-config.XXXXXX") || {
        error "tmux: не удалось создать временный каталог для проверки"
        return 1
    }
    validation_conf="${validation_root}/tmux/tmux.conf"
    if ! mkdir -p "$(dirname "$validation_conf")" \
        || ! cp -- "$conf" "$validation_conf"; then
        rm -rf -- "$validation_root"
        error "tmux: не удалось подготовить изолированную проверку конфигурации"
        return 1
    fi

    output=$(XDG_CONFIG_HOME="$validation_root" TMUX='' \
        tmux -L "$socket" -f "$validation_conf" \
        new-session -d -s prepare-config 2>&1) || validation_status=$?

    if [ "$validation_status" -eq 0 ]; then
        actual_value=$(XDG_CONFIG_HOME="$validation_root" TMUX='' \
            tmux -L "$socket" show-options -gv history-limit 2>&1) || {
            validation_status=1
            failure_reason="не удалось прочитать history-limit: $actual_value"
        }
        if [ "$validation_status" -eq 0 ] && [ "$actual_value" != "100000" ]; then
            validation_status=1
            failure_reason="history-limit: ожидалось 100000, получено ${actual_value:-пустое значение}"
        fi

        if [ "$validation_status" -eq 0 ]; then
            actual_value=$(XDG_CONFIG_HOME="$validation_root" TMUX='' \
                tmux -L "$socket" show-options -gv mouse 2>&1) || {
                validation_status=1
                failure_reason="не удалось прочитать mouse: $actual_value"
            }
        fi
        if [ "$validation_status" -eq 0 ] && [ "$actual_value" != "on" ]; then
            validation_status=1
            failure_reason="mouse: ожидалось on, получено ${actual_value:-пустое значение}"
        fi

        if [ "$validation_status" -eq 0 ]; then
            actual_value=$(XDG_CONFIG_HOME="$validation_root" TMUX='' \
                tmux -L "$socket" show-options -gqv @logging-path 2>&1) || {
                validation_status=1
                failure_reason="не удалось прочитать @logging-path: $actual_value"
            }
        fi
        if [ "$validation_status" -eq 0 ] \
            && [ "$actual_value" != "${TMUX_LOG_DIR}/%Y-%m-%d" ]; then
            validation_status=1
            failure_reason="@logging-path: ожидалось ${TMUX_LOG_DIR}/%Y-%m-%d, получено ${actual_value:-пустое значение}"
        fi

        if [ "$validation_status" -eq 0 ]; then
            bindings=$(XDG_CONFIG_HOME="$validation_root" TMUX='' \
                tmux -L "$socket" list-keys -T prefix 2>&1) || {
                validation_status=1
                failure_reason="не удалось прочитать таблицу клавиш: $bindings"
            }
        fi
        if [ "$validation_status" -eq 0 ] \
            && ! grep -q 'toggle_logging\.sh' <<< "$bindings"; then
            validation_status=1
            failure_reason="tmux-logging не создал клавишу toggle_logging.sh"
        fi
    fi

    XDG_CONFIG_HOME="$validation_root" TMUX='' \
        tmux -L "$socket" kill-server 2>/dev/null || true
    rm -rf -- "$validation_root"

    if [ "$validation_status" -ne 0 ]; then
        [ -n "$output" ] && error "tmux: ${output}"
        [ -n "$failure_reason" ] && error "tmux: ${failure_reason}"
        return 1
    fi
}

# Проверяет, установлен ли инструмент через uv.
# Совпадение по имени бинарника ("- certipy") ИЛИ по имени пакета ("impacket v0.14"),
# т.к. имя пакета и бинарника могут не совпадать в обе стороны:
#   certipy-ad → бинарник certipy, impacket → бинарники secretsdump.py и т.д.
is_uv_tool_installed() {
    uv_tool_list_entry "$1" >/dev/null
}

# Определяет источник установки uv-инструмента: uv, pipx, system, ""
# Для пакетов без одноимённого бинарника (impacket) проверяет также pipx list
# и наличие характерных бинарников в PATH.
uv_tool_source() {
    local name="$1"
    if is_uv_tool_installed "$name"; then
        echo "uv"
    elif [ -x "${LOCAL_BIN}/${name}" ]; then
        # бинарник в ~/.local/bin, но не через uv — скорее всего pipx (apt на Kali)
        if cmd_exists pipx && pipx list 2>/dev/null | grep -qi "package ${name} "; then
            echo "pipx"
        else
            echo "system"
        fi
    elif cmd_exists pipx && pipx list 2>/dev/null | grep -qi "package ${name} "; then
        echo "pipx"
    elif cmd_exists "$name"; then
        echo "system"
    elif [[ -v "KNOWN_BINARIES[$name]" ]]; then
        # Пакет с бинарниками, отличающимися от имени пакета (напр. impacket → secretsdump.py)
        local IFS=','
        for bin in ${KNOWN_BINARIES[$name]}; do
            if cmd_exists "$bin"; then
                echo "system"
                return
            fi
        done
    fi
}

# Основной distribution и версия из uv tool list: package|version.
# Имена CLI могут отличаться от distribution (manspider -> man-spider).
uv_tool_list_entry() {
    local name="$1" uv_list
    cmd_exists uv || return 1
    uv_list=$(uv tool list 2>/dev/null) || return 1
    awk -v wanted="$name" -v commands="${name},${KNOWN_BINARIES[$name]:-}" '
        function normalize(value) {
            value=tolower(value); gsub(/[-_.]+/, "-", value); return value
        }
        BEGIN { wanted=normalize(wanted); split(tolower(commands), binaries, ",") }
        $1 != "-" && $2 ~ /^v[0-9]/ {
            package=tolower($1)
            version=$2
            if (normalize(package) == wanted) {
                print package "|" version
                found=1
                exit
            }
            next
        }
        $1 == "-" && package != "" {
            for (i in binaries) {
                if (tolower($2) == binaries[i]) {
                    print package "|" version
                    found=1
                    exit
                }
            }
        }
        END { if (!found) exit 1 }
    ' <<< "$uv_list"
}

uv_tool_installed_version() {
    local entry
    entry=$(uv_tool_list_entry "$1") || return 1
    printf '%s' "${entry#*|}"
}

# Только PEP 610 основного distribution и только ожидаемый репозиторий.
# Возвращает commit|requested_tag. Метаданные зависимостей, форков и локальных
# каталогов не являются ревизией настроенного upstream.
uv_tool_git_metadata() {
    local name="$1" entry repo_url
    local uv_root="${UV_TOOL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/uv/tools}"
    [ -d "$uv_root" ] && cmd_exists python3 || return 1
    entry=$(uv_tool_list_entry "$name") || return 1
    repo_url=$(uv_tool_url "${UV_TOOLS[$name]}")

    python3 - "$uv_root" "${entry%%|*}" "$repo_url" <<'PY'
from pathlib import Path
from email.parser import Parser
import json
import re
import sys
from urllib.parse import urlsplit

def normalize(value):
    return re.sub(r"[-_.]+", "-", value).casefold()

def repository(value):
    if not isinstance(value, str):
        return None
    url = urlsplit(value.removeprefix("git+"))
    if url.scheme not in {"https", "http", "ssh", "git"} or not url.hostname:
        return None
    path = url.path.rstrip("/").removesuffix(".git")
    if url.hostname.casefold() == "github.com":
        path = path.casefold()
    return url.hostname.casefold(), path

root = Path(sys.argv[1])
package = normalize(sys.argv[2])
expected_repo = repository(sys.argv[3])

for env in sorted(root.iterdir()):
    if not env.is_dir() or normalize(env.name) != package:
        continue
    for receipt in env.glob("lib/python*/site-packages/*.dist-info/direct_url.json"):
        try:
            metadata = Parser().parsestr((receipt.parent / "METADATA").read_text())
            if normalize(metadata.get("Name", "")) != package:
                continue
            data = json.loads(receipt.read_text())
            if not isinstance(data, dict) or repository(data.get("url")) != expected_repo:
                continue
            vcs = data.get("vcs_info", {})
            if not isinstance(vcs, dict) or vcs.get("vcs") != "git":
                continue
            commit = vcs.get("commit_id", "")
            requested = vcs.get("requested_revision", "")
        except (OSError, ValueError, TypeError):
            continue
        if isinstance(commit, str) and re.fullmatch(r"[0-9a-f]{40}", commit):
            tag = requested if isinstance(requested, str) and re.fullmatch(r"v?\d+\.\d+\.\d+", requested) else ""
            print(f"{commit}|{tag}")
            raise SystemExit(0)
raise SystemExit(1)
PY
}

uv_tool_installed_commit() {
    local metadata
    metadata=$(uv_tool_git_metadata "$1") || return 1
    printf '%s' "${metadata%%|*}"
}

local_git_head() {
    local dir="$1"
    [ -d "$dir/.git" ] || return 1
    git -C "$dir" rev-parse HEAD 2>/dev/null | grep -E '^[0-9a-f]{40}$'
}

go_binary_module_version() {
    local binary="$1"
    [ -x "$binary" ] || return 1
    go version -m "$binary" 2>/dev/null \
        | awk '$1 == "mod" && $3 != "" { print $3; exit }'
}

go_tool_cli_version() {
    local binary="$1"
    [ -x "$binary" ] || return 1

    local temp_dir output version
    temp_dir=$(mktemp -d)
    output=$(XDG_CONFIG_HOME="${temp_dir}/config" \
        XDG_CACHE_HOME="${temp_dir}/cache" \
        "$binary" -version -duc 2>&1 || true)
    rm -rf -- "$temp_dir"
    version=$(grep -Eo 'v?[0-9]+\.[0-9]+\.[0-9]+' <<< "$output" | head -1)
    [ -n "$version" ] || return 1
    printf '%s' "$version"
}

go_tool_installed_version() {
    local name="$1" binary="$2"
    local version

    version=$(go_binary_module_version "$binary" || true)
    if is_stable_version_tag "$version"; then
        printf '%s' "$version"
        return 0
    fi
    if [[ -v "GO_RELEASE_REPOS[$name]" ]]; then
        go_tool_cli_version "$binary"
        return
    fi
    [ -n "$version" ] || return 1
    printf '%s' "$version"
}

go_tool_module() {
    local spec="${1%@*}"
    printf '%s' "${spec%%/cmd/*}"
}

# Квитанция связывает версию скачанного release с содержимым файла. Она
# записывается только при новой установке, а замена файла делает её невалидной.
record_binary_version() {
    local name="$1" binary="$2" version="$3" digest tmp
    is_stable_version_tag "$version" || return 1
    digest=$(sha256sum "$binary" | awk '{print $1}') || return 1
    mkdir -p "${LOG_DIR}/binary-versions"
    tmp=$(mktemp "${LOG_DIR}/binary-versions/.${name}.XXXXXX") || return 1
    printf '%s|%s\n' "$version" "$digest" > "$tmp"
    mv -- "$tmp" "${LOG_DIR}/binary-versions/${name}"
}

recorded_binary_version() {
    local name="$1" binary="$2" version digest actual
    [ -s "$binary" ] && [ -r "${LOG_DIR}/binary-versions/${name}" ] || return 1
    IFS='|' read -r version digest < "${LOG_DIR}/binary-versions/${name}" || return 1
    is_stable_version_tag "$version" && [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    actual=$(sha256sum "$binary" | awk '{print $1}') || return 1
    [ "$actual" = "$digest" ] || return 1
    printf '%s' "$version"
}

binary_tool_installed_version() {
    local name="$1" binary output
    local args=()
    binary=$(command -v "$name" 2>/dev/null) || return 1
    [ -f "$binary" ] && [ -x "$binary" ] || return 1
    # Запрос версии не должен запускать sudo-обёртку.
    if grep -Fqx "# Managed by prepare.sh: sudo wrapper for ${name}" "$binary"; then
        binary="${binary}.orig"
        [ -x "$binary" ] || return 1
    fi
    if recorded_binary_version "$name" "$binary"; then
        return 0
    fi
    case "$name" in
        pretender|flashingestor|rusthound-ce|legba|trufflehog) args=(--version) ;;
        gowitness|kerbrute) args=(version) ;;
        bettercap) args=(-version) ;;
        *) return 1 ;;
    esac
    output=$(timeout 5s "$binary" "${args[@]}" </dev/null 2>&1) || return 1
    # Не принимаем версию Go из build info, номер зависимости или часть
    # prerelease за версию самого инструмента.
    python3 - "$name" "$output" <<'PY'
import re
import sys
name, output = sys.argv[1:]
output = re.sub(r"\x1b\[[0-9;]*m", "", output)
prefix = rf"(?:(?:{re.escape(name)})(?:\s+version)?\s*:?\s*|version\s*:?\s*)?"
pattern = re.compile(rf"^\s*{prefix}(v?[0-9]+\.[0-9]+\.[0-9]+)(?![\w.+-])", re.I)
for line in output.splitlines():
    match = pattern.match(line)
    if match:
        print(match[1])
        raise SystemExit(0)
raise SystemExit(1)
PY
}

chisel_installed_version() {
    local binary="${TOOLS_DIR}/chisel/chisel"
    [ -x "$binary" ] && [ -s "$binary" ] || return 1
    "$binary" --version 2>/dev/null \
        | grep -Eo 'v?[0-9]+\.[0-9]+\.[0-9]+' \
        | head -1
}

refs_equivalent() {
    local local_ref="$1" configured_ref="$2" configured_commit="${3:-}"

    if is_commit_ref "$local_ref" && is_commit_ref "$configured_ref"; then
        hashes_match "$local_ref" "$configured_ref"
    elif is_stable_version_tag "$local_ref" && is_stable_version_tag "$configured_ref"; then
        [ "${local_ref#v}" = "${configured_ref#v}" ]
    elif is_commit_ref "$local_ref" && is_full_commit "$configured_commit"; then
        hashes_match "$local_ref" "$configured_commit"
    else
        return 2
    fi
}

# Общий выбор локальной базы и канала remote для отчёта и --skip.
# UPDATE_* объявляются local в вызывающей функции (динамическая область Bash).
tool_update_context() {
    local name="$1" source metadata commit requested dir url remainder
    UPDATE_REPO="" UPDATE_BRANCH="" UPDATE_BASELINE="" UPDATE_CONFIGURED=""
    UPDATE_LOCAL="" UPDATE_STATE="missing" UPDATE_CHANNEL="head"

    if [[ -v "UV_TOOLS[$name]" ]]; then
        UPDATE_REPO=$(uv_tool_url "${UV_TOOLS[$name]}")
        UPDATE_CONFIGURED=$(uv_tool_ref "${UV_TOOLS[$name]}")
        UPDATE_BRANCH=$(uv_tool_update_branch "${UV_TOOLS[$name]}")
        is_commit_ref "$UPDATE_CONFIGURED" || UPDATE_CHANNEL="tag"
        source=$(uv_tool_source "$name")
        case "$source" in
            uv)
                UPDATE_STATE="present"
                UPDATE_LOCAL=$(uv_tool_installed_version "$name" || true)
                metadata=$(uv_tool_git_metadata "$name" || true)
                commit="${metadata%%|*}"
                requested="${metadata#*|}"
                if is_full_commit "$commit"; then
                    UPDATE_BASELINE="$commit"
                    UPDATE_LOCAL="$commit"
                    if [ "$UPDATE_CHANNEL" = tag ] && is_stable_version_tag "$requested"; then
                        UPDATE_BASELINE="$requested"
                        UPDATE_LOCAL="$requested"
                    fi
                fi
                ;;
            pipx|system) UPDATE_STATE="external" ;;
        esac
    elif [[ -v "GIT_REPOS[$name]" || -v "VENV_REPOS[$name]" ]]; then
        if [[ -v "GIT_REPOS[$name]" ]]; then
            IFS='|' read -r UPDATE_REPO UPDATE_CONFIGURED remainder <<< "${GIT_REPOS[$name]}"
        else
            IFS='|' read -r UPDATE_REPO UPDATE_CONFIGURED remainder <<< "${VENV_REPOS[$name]}"
        fi
        dir="${TOOLS_DIR}/${name}"
        UPDATE_LOCAL=$(local_git_head "$dir" || true)
        if is_full_commit "$UPDATE_LOCAL"; then
            UPDATE_BASELINE="$UPDATE_LOCAL"
            UPDATE_STATE="present"
            if [[ -v "VENV_REPOS[$name]" ]] && ! venv_repo_complete "$name" "$dir"; then
                UPDATE_STATE="incomplete"
            fi
        fi
    elif [[ -v "BINARY_TOOLS[$name]" ]]; then
        UPDATE_CHANNEL="tag"
        UPDATE_REPO=$(github_repo_from_url "$(binary_tool_url "${BINARY_TOOLS[$name]}")")
        UPDATE_CONFIGURED=$(binary_tool_version "${BINARY_TOOLS[$name]}")
        UPDATE_LOCAL=$(binary_tool_installed_version "$name" || true)
        UPDATE_BASELINE="$UPDATE_LOCAL"
        if binary_tool_commands_present "$name"; then
            UPDATE_STATE="present"
        elif [ -n "$UPDATE_LOCAL" ]; then
            UPDATE_STATE="incomplete"
        fi
    elif [[ -v "WIN_TOOLS[$name]" ]]; then
        UPDATE_CHANNEL="tag"
        url="${WIN_TOOLS[$name]}"
        UPDATE_REPO=$(github_repo_from_url "$url")
        UPDATE_CONFIGURED=$(printf '%s' "$url" | grep -oP '/download/\K[^/]+' || true)
        if is_valid_windows_binary "${TOOLS_DIR}/for_windows/${name}"; then
            UPDATE_STATE="present"
            UPDATE_LOCAL=$(recorded_binary_version "$name" "${TOOLS_DIR}/for_windows/${name}" || true)
            UPDATE_BASELINE="$UPDATE_LOCAL"
        fi
    elif [[ -v "TMUX_PLUGINS[$name]" ]]; then
        UPDATE_REPO="${TMUX_PLUGINS[$name]}"
        UPDATE_LOCAL=$(local_git_head "${TMUX_PLUGIN_DIR}/${name}" || true)
        if is_full_commit "$UPDATE_LOCAL"; then
            UPDATE_STATE="present"
            UPDATE_BASELINE="$UPDATE_LOCAL"
        fi
    elif [ "$name" = chisel ]; then
        UPDATE_CHANNEL="tag"
        UPDATE_REPO="https://github.com/jpillora/chisel"
        UPDATE_CONFIGURED="v${CHISEL_VERSION}"
        UPDATE_LOCAL=$(chisel_installed_version || true)
        if is_stable_version_tag "$UPDATE_LOCAL"; then
            UPDATE_STATE="present"
            UPDATE_BASELINE="$UPDATE_LOCAL"
        fi
    else
        return 1
    fi
    [ -n "$UPDATE_REPO" ]
}

dpkg_package_installed() {
    local package="$1" status
    status=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)
    [ "$status" = "installed" ]
}

kali_package_command_path() {
    local package="$1" name="$2" candidate

    while IFS= read -r candidate; do
        case "$candidate" in
            "/bin/${name}"|"/sbin/${name}"|"/usr/bin/${name}"|"/usr/sbin/${name}")
                [ -x "$candidate" ] || continue
                printf '%s\n' "$candidate"
                return 0
                ;;
        esac
    done < <(dpkg-query -L "$package" 2>/dev/null || true)

    return 1
}

list_kali_preinstalled_candidates() {
    local name cmd_path expected_pkg

    for name in "${KALI_PREINSTALLED_TOOLS[@]}"; do
        expected_pkg="${KALI_SYSTEM_PACKAGES[$name]:-}"
        [ -n "$expected_pkg" ] || continue
        dpkg_package_installed "$expected_pkg" || continue

        cmd_path=$(kali_package_command_path "$expected_pkg" "$name" || true)
        printf '%s|system|%s|%s\n' "$name" "$cmd_path" "$expected_pkg"
    done
}

handle_first_install_kali_tools() {
    is_first_install_run || return 0
    is_kali || return 0

    local candidates=()
    local packages=()
    local line candidate_package name src cmd_path package details
    local answer normalized
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        candidates+=("$line")
        candidate_package="${line##*|}"
        [ -n "$candidate_package" ] && packages+=("$candidate_package")
    done < <(list_kali_preinstalled_candidates)

    [ ${#candidates[@]} -gt 0 ] || return 0

    warn "Обнаружены предустановленные системные компоненты Kali:"
    for line in "${candidates[@]}"; do
        details=""
        IFS='|' read -r name src cmd_path package <<< "$line"
        details="$src"
        [ -n "$cmd_path" ] && details+="; ${cmd_path}"
        [ -n "$package" ] && details+="; пакет ${package}"
        echo -e "  ${YELLOW}-${NC} ${name} ${DIM}(${details})${NC}"
    done

    if [ "$AUTO_MODE" = true ]; then
        info "Автоматический режим: предустановленные компоненты Kali будут удалены"
        answer="y"
    else
        answer=""
        if ! prompt_read answer "Удалить эти системные пакеты перед установкой закреплённых uv-копий? (рекомендуется удаление) [Y/n]: "; then
            warn "Ответ не получен; удаление пропущено"
            return 0
        fi
    fi

    while true; do
        normalized="${answer,,}"
        case "$normalized" in
            ""|y|yes|д|да)
                info "Удаление системных пакетов: ${packages[*]}"
                if ! sudo_with_proxy DEBIAN_FRONTEND=noninteractive \
                    apt-get remove -y --no-auto-remove "${packages[@]}"; then
                    error "Не удалось удалить предустановленные компоненты Kali"
                    return 1
                fi
                hash -r

                local remaining=()
                local installed_package
                for installed_package in "${packages[@]}"; do
                    if dpkg_package_installed "$installed_package"; then
                        remaining+=("$installed_package")
                    fi
                done
                if [ ${#remaining[@]} -gt 0 ]; then
                    error "Пакеты остались установлены: ${remaining[*]}"
                    return 1
                fi
                success "Предустановленные компоненты Kali удалены"
                return 0
                ;;
            n|no|н|нет|s|skip|п|пропустить)
                info "Удаление пропущено; предустановленные компоненты Kali остаются без изменений"
                return 0
                ;;
            *)
                warn "Введите 'y' для удаления или 'n' для пропуска"
                answer=""
                if ! prompt_read answer "Удалить эти системные пакеты? [Y/n]: "; then
                    warn "Ответ не получен; удаление пропущено"
                    return 0
                fi
                ;;
        esac
    done
}

# ─── Проверка remote через git ls-remote (локальные копии не меняются) ────────

tag_commit_from_refs() {
    local all_refs="$1" tag="$2" alternate
    if [[ "$tag" == v* ]]; then
        alternate="${tag#v}"
    else
        alternate="v${tag}"
    fi
    awk -v direct="refs/tags/${tag}" -v peeled="refs/tags/${tag}^{}" \
        -v alt_direct="refs/tags/${alternate}" -v alt_peeled="refs/tags/${alternate}^{}" '
        $2 == direct { direct_commit=$1 }
        $2 == peeled { peeled_commit=$1 }
        $2 == alt_direct { alt_direct_commit=$1 }
        $2 == alt_peeled { alt_peeled_commit=$1 }
        END {
            if (peeled_commit != "") print peeled_commit
            else if (direct_commit != "") print direct_commit
            else if (alt_peeled_commit != "") print alt_peeled_commit
            else print alt_direct_commit
        }
    ' <<< "$all_refs"
}

latest_stable_tag_from_refs() {
    local all_refs="$1"
    awk '
        $2 ~ /^refs\/tags\// && $2 !~ /\^\{\}$/ {
            sub(/^refs\/tags\//, "", $2)
            if ($2 ~ /^v?[0-9]+\.[0-9]+\.[0-9]+$/) print $2
        }
    ' <<< "$all_refs" \
        | sort -u \
        | while IFS= read -r tag; do
            printf '%s\t%s\n' "${tag#v}" "$tag"
        done \
        | LC_ALL=C sort -t $'\t' -k1,1V \
        | tail -1 \
        | cut -f2
}

# Результат содержит remote-commit — одну и ту же ревизию для отчёта и --skip.
# unknown означает, что remote получен, но установленная база неизвестна.
# Для закреплённого коммита различие с HEAD не называется более новой
# ревизией: ls-remote не содержит данных о направлении истории.
# Для тегов учитываются только полные стабильные версии x.y.z.
check_remote_updates() {
    local repo_url="$1" baseline_ref="$2" branch="${3:-}"
    local channel="${4:-}" configured_ref="${5:-$2}"
    local target_ref="HEAD"
    [ -n "$branch" ] && target_ref="refs/heads/${branch}"
    if [ -z "$channel" ]; then
        if is_commit_ref "$baseline_ref"; then channel="head"; else channel="tag"; fi
    fi

    local all_refs head_commit pin_commit suffix=""
    if ! all_refs=$(git ls-remote "$repo_url" "$target_ref" 'refs/tags/*' 2>/dev/null); then
        echo "error"
        return 0
    fi
    pin_commit=$(tag_commit_from_refs "$all_refs" "$configured_ref")
    if is_full_commit "$pin_commit"; then
        suffix=";pin-commit:${pin_commit}"
    fi

    if [ "$channel" = head ]; then
        head_commit=$(awk -v ref="$target_ref" '$2 == ref { print $1; exit }' <<< "$all_refs")
        if ! is_full_commit "$head_commit"; then
            echo "error"
            return 0
        fi
        suffix+=";remote-commit:${head_commit}"
        if ! is_commit_ref "$baseline_ref"; then
            echo "unknown;remote-head:${head_commit}${suffix}"
        elif hashes_match "$head_commit" "$baseline_ref"; then
            echo "up-to-date${suffix}"
        else
            echo "different-head:${head_commit}${suffix}"
        fi
        return 0
    fi

    local latest_tag latest_commit
    latest_tag=$(latest_stable_tag_from_refs "$all_refs")
    if [ -z "$latest_tag" ]; then
        echo "no-stable-tags${suffix}"
        return 0
    fi
    latest_commit=$(tag_commit_from_refs "$all_refs" "$latest_tag")
    if ! is_full_commit "$latest_commit"; then
        echo "error"
        return 0
    fi
    suffix+=";remote-commit:${latest_commit}"

    # Числовое сравнение не требует существования тега установленной версии.
    if is_stable_version_tag "$baseline_ref"; then
        if version_tag_is_newer "$latest_tag" "$baseline_ref"; then
            echo "new-tag:${latest_tag}:${latest_commit}${suffix}"
        elif version_tag_is_newer "$baseline_ref" "$latest_tag"; then
            echo "local-newer;remote-tag:${latest_tag}:${latest_commit}${suffix}"
        else
            echo "up-to-date${suffix}"
        fi
    elif is_commit_ref "$baseline_ref" && hashes_match "$baseline_ref" "$latest_commit"; then
        echo "up-to-date${suffix}"
    else
        echo "unknown;remote-tag:${latest_tag}:${latest_commit}${suffix}"
    fi
}

# URL корневого GitHub-репозитория для Go CLI. Суффикс major-версии модуля
# (например /v3 у nuclei) не является частью имени репозитория.
go_tool_repo_url() {
    local module
    module=$(go_tool_module "$1")
    if [[ "$module" =~ ^github\.com/([^/]+/[^/]+)(/v[0-9]+)?$ ]]; then
        printf 'https://github.com/%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# Возвращает версию модуля @latest и commit соответствующего Git-тега:
# version|40-hex. Один и тот же commit используется --check-updates и --skip.
go_tool_remote_state() {
    local spec="$1" version repo_url alternate all_refs commit

    version=$(resolve_go_tool_version "$spec") || return 1
    is_stable_version_tag "$version" || return 1
    repo_url=$(go_tool_repo_url "$spec") || return 1
    if [[ "$version" == v* ]]; then
        alternate="${version#v}"
    else
        alternate="v${version}"
    fi
    all_refs=$(git ls-remote --tags "$repo_url" \
        "refs/tags/${version}" "refs/tags/${version}^{}" \
        "refs/tags/${alternate}" "refs/tags/${alternate}^{}" 2>/dev/null) \
        || return 1
    commit=$(tag_commit_from_refs "$all_refs" "$version")
    is_full_commit "$commit" || return 1
    printf '%s|%s\n' "$version" "$commit"
}


# Неинтерактивный режим (--auto): применяет действия по умолчанию без вопросов
AUTO_MODE=false

# Настройки хранятся отдельно от окружения, пока не выбрана их область действия.
configure_proxy() {
    local context="${1:-install}"
    local current_http current_https selected_http selected_https http_answer https_answer

    initialize_proxy_settings
    # В режиме по умолчанию проверка обновлений и работа со skip-списком
    # выполняются напрямую и не задают неиспользуемых вопросов о proxy.
    if [ "$PROXY_SCOPE" != all ] && [ "$context" != install ]; then
        return 0
    fi

    current_http="${PROXY_SETTINGS[http]}"
    current_https="${PROXY_SETTINGS[https]}"
    selected_http="$current_http"
    selected_https="$current_https"

    if [ "$AUTO_MODE" = true ]; then
        if [ -z "$selected_https" ]; then
            selected_https="$selected_http"
        fi
    else
        if [ "$PROXY_SCOPE" = all ]; then
            info "Proxy будет использоваться для всех сетевых операций (--proxy-all)"
        else
            info "Proxy будет использоваться только для bloodhound-automation"
        fi

        if [ -n "$current_http" ]; then
            prompt_read http_answer "HTTP proxy [${current_http}] (Enter — оставить, '-' — убрать): "
        else
            prompt_read http_answer "HTTP proxy (например http://127.0.0.1:8080, Enter — без proxy): "
        fi
        case "$http_answer" in
            "") ;;
            "-") selected_http="" ;;
            *) selected_http="$http_answer" ;;
        esac

        if [ -n "$current_https" ]; then
            prompt_read https_answer "HTTPS proxy [${current_https}] (Enter — оставить, '=' — как HTTP, '-' — убрать): "
        else
            prompt_read https_answer "HTTPS proxy (Enter — как HTTP proxy, '-' — без proxy): "
        fi
        case "$https_answer" in
            "")
                if [ -z "$current_https" ]; then
                    selected_https="$selected_http"
                fi
                ;;
            "=") selected_https="$selected_http" ;;
            "-") selected_https="" ;;
            *) selected_https="$https_answer" ;;
        esac
    fi

    PROXY_SETTINGS[http]="$selected_http"
    PROXY_SETTINGS[https]="$selected_https"
    apply_proxy_scope

    if [ -n "$selected_http" ] || [ -n "$selected_https" ] || [ -n "${PROXY_SETTINGS[all]}" ]; then
        if [ "$PROXY_SCOPE" = all ]; then
            success "Proxy: все сетевые операции (--proxy-all)"
        else
            success "Proxy: только bloodhound-automation"
        fi
    else
        info "Proxy не задан"
    fi
    echo ""
}

# ─── Skip-механизм ────────────────────────────────────────────────────────────

is_skip_supported_tool() {
    local name="$1"
    [[ -v "UV_TOOLS[$name]" ]] \
        || [[ -v "GO_TOOLS[$name]" ]] \
        || [[ -v "GO_TOOLS_CGO[$name]" ]] \
        || [[ -v "GIT_REPOS[$name]" ]] \
        || [[ -v "VENV_REPOS[$name]" ]] \
        || [[ -v "BINARY_TOOLS[$name]" ]] \
        || [[ -v "WIN_TOOLS[$name]" ]] \
        || [[ -v "TMUX_PLUGINS[$name]" ]] \
        || [ "$name" = "chisel" ]
}

skip_record_valid() {
    local name="$1" commit="$2"
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] \
        && is_skip_supported_tool "$name" \
        && is_full_commit "$commit"
}

validate_skip_file() {
    local file="$1" line name commit rest
    local -A seen=()

    [ -f "$file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" == *=* ]] || return 1
        name="${line%%=*}"
        rest="${line#*=}"
        [[ "$rest" != *=* ]] || return 1
        commit="$rest"
        skip_record_valid "$name" "$commit" || return 1
        [[ ! -v "seen[$name]" ]] || return 1
        seen["$name"]=1
    done < "$file"
}

# Возвращает пропущенный коммит для инструмента (или пустую строку)
get_skip() {
    local name="$1"
    acquire_state_lock || return 1
    [ -f "$SKIP_FILE" ] || return 0
    awk -F= -v wanted="$name" '$1 == wanted { print $2; exit }' "$SKIP_FILE"
}

# Сохраняет коммит как пропущенный для инструмента
set_skip() {
    local name="$1" commit="$2"
    skip_record_valid "$name" "$commit" || {
        error "Недопустимая запись пропуска: $name"
        return 1
    }
    acquire_state_lock || return 1
    mkdir -p "$(dirname "$SKIP_FILE")"
    local tmp
    tmp=$(mktemp "${SKIP_FILE}.prepare.XXXXXX")
    if [ -f "$SKIP_FILE" ]; then
        awk -F= -v wanted="$name" '$1 != wanted' "$SKIP_FILE" > "$tmp"
    fi
    printf '%s=%s\n' "$name" "$commit" >> "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$SKIP_FILE"
}

# Удаляет skip для инструмента
clear_skip() {
    local name="$1"
    is_skip_supported_tool "$name" || {
        error "Инструмент '$name' не найден в конфигурации"
        return 1
    }
    acquire_state_lock || return 1
    [ -f "$SKIP_FILE" ] || return 0
    local tmp
    tmp=$(mktemp "${SKIP_FILE}.prepare.XXXXXX")
    awk -F= -v wanted="$name" '$1 != wanted' "$SKIP_FILE" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$SKIP_FILE"
}

# Записи пропусков всегда содержат полный хеш; префиксы не принимаются.
is_skipped() {
    local name="$1" remote_commit="$2"
    local skipped
    is_full_commit "$remote_commit" || return 1
    skipped=$(get_skip "$name")
    is_full_commit "$skipped" && [ "$remote_commit" = "$skipped" ]
}

# ─── Remote Gist: pull / push ────────────────────────────────────────────────

GIST_PUSH_STAMP="$HOME/.local/share/prepare/.gist_push_ts"

# Скачивает skip-файл из Gist и полностью заменяет локальный
gist_pull() {
    [ -z "$SKIP_GIST_ID" ] && return 0
    acquire_state_lock || return 1

    # Если недавно был push — пропускаем pull (кэш GitHub ещё не обновился)
    if [ -f "$GIST_PUSH_STAMP" ]; then
        local push_ts now_ts
        push_ts=$(cat "$GIST_PUSH_STAMP")
        now_ts=$(date +%s)
        if (( now_ts - push_ts < 120 )); then
            info "Skip-список: используется локальная версия (недавний push, кэш GitHub ещё не обновился)"
            return 0
        fi
    fi

    local tmp
    tmp=$(mktemp)
    # Читаем через API (работает без токена для secret gists)
    if curl -fsSL -H "Cache-Control: no-cache" -H "If-None-Match: \"\"" \
        "https://api.github.com/gists/${SKIP_GIST_ID}" -o "$tmp" 2>/dev/null; then
        local content_file
        mkdir -p "$(dirname "$SKIP_FILE")"
        content_file=$(mktemp "${SKIP_FILE}.gist.XXXXXX")
        if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
content = data.get('files', {}).get(sys.argv[2], {}).get('content', '')
print(content, end='')
" "$tmp" "$SKIP_GIST_FILE" > "$content_file" 2>/dev/null; then
            if validate_skip_file "$content_file"; then
                chmod 600 "$content_file"
                mv "$content_file" "$SKIP_FILE"
                info "Skip-список загружен из Gist"
            else
                rm -f -- "$content_file"
                warn "Полученный skip-список имеет неверный формат; локальный файл сохранён"
            fi
        else
            rm -f -- "$content_file"
            warn "Не удалось разобрать ответ Gist API"
        fi
    else
        warn "Не удалось загрузить skip-список из Gist"
    fi
    rm -f "$tmp"
}

# Отправляет локальный skip-файл в Gist (интерактивный запрос токена)
gist_push() {
    [ -z "$SKIP_GIST_ID" ] && return 0
    acquire_state_lock || return 1
    [ ! -f "$SKIP_FILE" ] && return 0

    # Без терминала — push невозможен
    if [ ! -t 0 ]; then
        warn "Нет терминала — skip-изменения сохранены только локально"
        return 0
    fi

    prompt_read_secret token "GitHub Token (scope: gist) для push в Gist (Enter — пропустить): "
    echo ""
    [ -z "$token" ] && { warn "Токен не указан — skip-изменения сохранены только локально"; return 0; }

    local content
    content=$(sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' "$SKIP_FILE" | awk '{printf "%s\\n", $0}')
    local payload
    payload=$(printf '{"files":{"%s":{"content":"%s"}}}' "$SKIP_GIST_FILE" "$content")

    local http_code
    http_code=$(curl -s -o /dev/null -w '%{http_code}' \
        -X PATCH "https://api.github.com/gists/${SKIP_GIST_ID}" \
        -H "Authorization: token ${token}" \
        -H "Content-Type: application/json" \
        -d "$payload")

    if [ "$http_code" = "200" ]; then
        success "Skip-список отправлен в Gist"
        mkdir -p "$(dirname "$GIST_PUSH_STAMP")"
        local stamp_tmp
        stamp_tmp=$(mktemp "${GIST_PUSH_STAMP}.prepare.XXXXXX")
        date +%s > "$stamp_tmp"
        chmod 600 "$stamp_tmp"
        mv "$stamp_tmp" "$GIST_PUSH_STAMP"
    else
        error "Не удалось обновить Gist (HTTP $http_code)"
        return 1
    fi
}

# ─── Счётчики ─────────────────────────────────────────────────────────────────
COUNT_OK=0
COUNT_MISSING=0
COUNT_WARN=0

count_ok()   { ((COUNT_OK++))      || true; }
count_miss() { ((COUNT_MISSING++)) || true; }
count_warn() { ((COUNT_WARN++))    || true; }

print_summary() {
    echo ""
    echo -e "${CYAN}──────────────────────────────────────────${NC}"
    echo -e "  ${GREEN}✓ ${COUNT_OK}${NC}    ${RED}✗ ${COUNT_MISSING}${NC}    ${YELLOW}! ${COUNT_WARN}${NC}"
    echo -e "${CYAN}──────────────────────────────────────────${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  По умолчанию: проверка наличия инструментов (локально, без сети)
# ═══════════════════════════════════════════════════════════════════════════════

cmd_status() {
    COUNT_OK=0
    COUNT_MISSING=0
    COUNT_WARN=0

    header "Статус инструментов"
    info "Проверяется только наличие инструментов, не их версии."
    info "Для проверки версий используйте: $0 --check-updates"
    echo ""

    # ── Системные зависимости ─────────────────────────────────────────────────
    info "Системные зависимости"
    for dep in git curl wget python3 unzip cargo dig flock; do
        if cmd_exists "$dep"; then
            echo -e "  ${GREEN}✓${NC} $dep ${DIM}$(command -v "$dep")${NC}"; count_ok
        else
            echo -e "  ${RED}✗${NC} $dep"; count_miss
        fi
    done
    for pkg in seclists libpcap-dev libkrb5-dev wmctrl libsqlite3-dev bind9-dnsutils \
        tesseract-ocr libreoffice; do
        if dpkg -s "$pkg" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $pkg ${DIM}(dpkg)${NC}"; count_ok
        else
            echo -e "  ${RED}✗${NC} $pkg"; count_miss
        fi
    done
    local browser_path
    if browser_path=$(gowitness_browser); then
        echo -e "  ${GREEN}✓${NC} browser-for-gowitness ${DIM}${browser_path}${NC}"; count_ok
    else
        echo -e "  ${RED}✗${NC} browser-for-gowitness"; count_miss
    fi

    # ── Docker ─────────────────────────────────────────────────────────────
    echo ""
    info "Docker"
    if cmd_exists docker && docker --version &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} docker ${DIM}$(command -v docker)${NC}"; count_ok
    else
        echo -e "  ${RED}✗${NC} docker"; count_miss
    fi
    if cmd_exists docker && docker --version &>/dev/null \
        && { docker compose version &>/dev/null \
            || { cmd_exists docker-compose && docker-compose version &>/dev/null; }; }; then
        echo -e "  ${GREEN}✓${NC} docker compose"; count_ok
    else
        echo -e "  ${RED}✗${NC} docker compose"; count_miss
    fi

    # ── Go ────────────────────────────────────────────────────────────────────
    echo ""
    info "Go"
    if cmd_exists go && go version &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} go ${DIM}$(command -v go)${NC}"; count_ok
    else
        echo -e "  ${RED}✗${NC} go"; count_miss
    fi

    # ── uv ────────────────────────────────────────────────────────────────────
    echo ""
    info "uv"
    if cmd_exists uv && uv --version &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} uv ${DIM}$(command -v uv)${NC}"; count_ok
    else
        echo -e "  ${RED}✗${NC} uv"; count_miss
    fi

    # ── Go-утилиты ────────────────────────────────────────────────────────────
    echo ""
    info "Go-утилиты"
    for name in "${!GO_TOOLS[@]}"; do
        if is_go_tool "$name"; then
            echo -e "  ${GREEN}✓${NC} $name ${DIM}$(command -v "$name")${NC}"; count_ok
        else
            echo -e "  ${RED}✗${NC} $name"; count_miss
        fi
    done
    for name in "${!GO_TOOLS_CGO[@]}"; do
        if is_go_tool "$name"; then
            echo -e "  ${GREEN}✓${NC} $name ${DIM}$(command -v "$name")${NC}"; count_ok
        else
            echo -e "  ${RED}✗${NC} $name"; count_miss
        fi
    done

    # ── uv tools ──────────────────────────────────────────────────────────────
    echo ""
    info "uv tools"
    for name in "${!UV_TOOLS[@]}"; do
        local src
        src=$(uv_tool_source "$name")
        case "$src" in
            uv)
                echo -e "  ${GREEN}✓${NC} $name ${DIM}(uv)${NC}"; count_ok ;;
            pipx)
                echo -e "  ${YELLOW}~${NC} $name ${DIM}(pipx — существующая копия сохранена)${NC}"; count_warn ;;
            system)
                echo -e "  ${YELLOW}~${NC} $name ${DIM}(системный — существующая копия сохранена)${NC}"; count_warn ;;
            *)
                echo -e "  ${RED}✗${NC} $name"; count_miss ;;
        esac
    done

    # ── Бинарные утилиты ──────────────────────────────────────────────────────
    echo ""
    info "Бинарные утилиты"
    for name in "${!BINARY_TOOLS[@]}"; do
        local command_name source_path installed_path
        while IFS='|' read -r command_name source_path; do
            installed_path=$(command -v "$command_name" 2>/dev/null || true)
            if [ -n "$installed_path" ] && [ -s "$installed_path" ]; then
                echo -e "  ${GREEN}✓${NC} $command_name ${DIM}${installed_path}${NC}"; count_ok
            else
                echo -e "  ${RED}✗${NC} $command_name"; count_miss
            fi
        done < <(binary_tool_command_specs "$name")
    done

    # ── Chisel ────────────────────────────────────────────────────────────────
    echo ""
    info "Chisel"
    if [ -x "${TOOLS_DIR}/chisel/chisel" ] && [ -s "${TOOLS_DIR}/chisel/chisel" ]; then
        echo -e "  ${GREEN}✓${NC} chisel ${DIM}${TOOLS_DIR}/chisel/chisel${NC}"; count_ok
    else
        echo -e "  ${RED}✗${NC} chisel"; count_miss
    fi

    # ── Git-репозитории ───────────────────────────────────────────────────────
    echo ""
    info "Git-репозитории (~/tools)"
    for name in "${!GIT_REPOS[@]}"; do
        local dir="${TOOLS_DIR}/${name}"
        if [ -d "$dir/.git" ] && git -C "$dir" rev-parse HEAD &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $name ${DIM}${dir}${NC}"; count_ok
        else
            echo -e "  ${RED}✗${NC} $name"; count_miss
        fi
    done

    # ── Venv-репозитории ──────────────────────────────────────────────────────
    echo ""
    info "Venv-репозитории (~/tools)"
    for name in "${!VENV_REPOS[@]}"; do
        local dir="${TOOLS_DIR}/${name}"
        local venv_dir entrypoint command_name command_entrypoint command_wrapper
        venv_dir=$(venv_path_for "$name" "$dir")
        entrypoint=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f3)
        if [ -d "$dir/.git" ] && git -C "$dir" rev-parse HEAD &>/dev/null; then
            local extras=""
            local complete=true
            if [ -x "${venv_dir}/bin/python" ] && [ -f "${venv_dir}/.prepare_complete" ]; then
                extras+=" [venv ✓]"
            else
                extras+=" ${YELLOW}[venv ✗]${NC}"
                complete=false
            fi
            while IFS='|' read -r command_name command_entrypoint; do
                command_wrapper="${LOCAL_BIN}/${command_name}"
                if [ -f "${dir}/${command_entrypoint}" ] \
                    && [ -x "$command_wrapper" ] \
                    && prepare_venv_wrapper_matches "$command_name" "$command_wrapper" \
                        "${venv_dir}/bin/python" "${dir}/${command_entrypoint}"; then
                    extras+=" [${command_name} ✓]"
                else
                    extras+=" ${YELLOW}[${command_name} ✗]${NC}"
                    complete=false
                fi
            done < <(venv_command_specs "$name" "$entrypoint")
            if [ "$complete" = true ] && venv_repo_complete "$name" "$dir"; then
                echo -e "  ${GREEN}✓${NC} $name ${DIM}${dir}${NC}${extras}"; count_ok
            else
                echo -e "  ${YELLOW}!${NC} $name ${DIM}${dir}${NC}${extras}"; count_miss
            fi
        else
            echo -e "  ${RED}✗${NC} $name"; count_miss
        fi
    done

    # ── Windows-утилиты ───────────────────────────────────────────────────────
    echo ""
    info "Windows-утилиты (~/tools/for_windows)"
    for name in "${!WIN_TOOLS[@]}"; do
        if is_valid_windows_binary "${TOOLS_DIR}/for_windows/${name}"; then
            echo -e "  ${GREEN}✓${NC} $name ${DIM}${TOOLS_DIR}/for_windows/${name}${NC}"; count_ok
        else
            echo -e "  ${RED}✗${NC} $name"; count_miss
        fi
    done

    # ── tmux ─────────────────────────────────────────────────────────────────
    echo ""
    info "tmux + tmux-logging"
    local tmux_conf
    tmux_conf=$(tmux_config_file)
    if cmd_exists tmux; then
        echo -e "  ${GREEN}✓${NC} tmux ${DIM}$(command -v tmux)${NC}"; count_ok
    else
        echo -e "  ${RED}✗${NC} tmux"; count_miss
    fi
    local tmux_plugin
    for tmux_plugin in "${!TMUX_PLUGINS[@]}"; do
        if [ -d "${TMUX_PLUGIN_DIR}/${tmux_plugin}/.git" ] \
            && git -C "${TMUX_PLUGIN_DIR}/${tmux_plugin}" rev-parse HEAD &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $tmux_plugin ${DIM}${TMUX_PLUGIN_DIR}/${tmux_plugin}${NC}"; count_ok
        else
            echo -e "  ${RED}✗${NC} $tmux_plugin"; count_miss
        fi
    done
    if tmux_configured "$tmux_conf"; then
        echo -e "  ${GREEN}✓${NC} $tmux_conf ${DIM}(логирование настроено)${NC}"; count_ok
    else
        echo -e "  ${YELLOW}!${NC} $tmux_conf ${DIM}(логирование не настроено)${NC}"; count_warn
    fi
    if [ -d "$TMUX_LOG_DIR" ]; then
        echo -e "  ${GREEN}✓${NC} каталог логов ${DIM}${TMUX_LOG_DIR}${NC}"; count_ok
    else
        echo -e "  ${RED}✗${NC} каталог логов ${DIM}${TMUX_LOG_DIR}${NC}"; count_miss
    fi

    print_summary

    if [ "$COUNT_MISSING" -gt 0 ] || [ "$COUNT_WARN" -gt 0 ]; then
        echo ""
        info "Установить автоматически: sudo -v && $0 --auto"
        info "Интерактивная установка:    $0 --install"
        info "Отчёт о новых версиях:       $0 --check-updates"
        return 1
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
#  --check-updates: проверка remote относительно установленной версии/ревизии
# ═══════════════════════════════════════════════════════════════════════════════

# Краткий результат проверки; * отмечает сравнение с версией из скрипта.
# Аргументы: name local_state local_ref configured_ref result
# local_state: present | external | incomplete | missing
CHECK_UPDATE_ERRORS=0

print_update_line() {
    local color="$1" symbol="$2" details="$3" status="$4"
    # Один цвет от символа до конца строки, включая имя инструмента.
    # %s сохраняет текст как есть; только цветовые константы трактуются как ANSI.
    printf '  %b%s %s %s%b\n' "$color" "$symbol" "$details" "$status" "$NC"
}

display_update_result() {
    local name="$1" local_ref="$3" configured_ref="$4" result="$5"
    local baseline="$local_ref" marker="" details="$name"
    if result_has "$result" unknown; then
        baseline="$configured_ref"
        [ -z "$baseline" ] || marker="*"
    fi
    if is_commit_ref "$baseline"; then
        baseline="${baseline:0:12}"
    fi
    [ -z "$baseline" ] || details+=" (${baseline}${marker})"

    if [ "$result" = "error" ] || [ -z "$result" ]; then
        CHECK_UPDATE_ERRORS=$((CHECK_UPDATE_ERRORS + 1))
        print_update_line "$RED" '?' "$name" '— ошибка проверки'
        return 0
    fi
    if [ "$result" = "not-checked" ]; then
        print_update_line "$GRAY" '−' "$name" '— проверка пропущена'
        return 0
    fi

    local tag_payload="" tag="" tag_commit="" remote_head="" event_commit=""
    local new_tag=false different_head=false
    tag_payload=$(result_field "$result" "new-tag" 2>/dev/null || true)
    if [ -n "$tag_payload" ]; then
        new_tag=true
    else
        tag_payload=$(result_field "$result" "remote-tag" 2>/dev/null || true)
    fi
    remote_head=$(result_field "$result" "different-head" 2>/dev/null || true)
    if [ -n "$remote_head" ]; then
        different_head=true
    else
        remote_head=$(result_field "$result" "remote-head" 2>/dev/null || true)
    fi
    if [ -n "$tag_payload" ]; then
        tag="${tag_payload%%:*}"
        tag_commit="${tag_payload##*:}"
        is_full_commit "$tag_commit" || {
            CHECK_UPDATE_ERRORS=$((CHECK_UPDATE_ERRORS + 1))
            print_update_line "$RED" '?' "$name" '— неверный ответ remote'
            return 0
        }
        event_commit="$tag_commit"
    elif [ -n "$remote_head" ]; then
        is_full_commit "$remote_head" || {
            CHECK_UPDATE_ERRORS=$((CHECK_UPDATE_ERRORS + 1))
            print_update_line "$RED" '?' "$name" '— неверный ответ remote'
            return 0
        }
        event_commit="$remote_head"
    fi

    if [ -n "$event_commit" ] && is_skipped "$name" "$event_commit"; then
        print_update_line "$GRAY" '−' "$name" "— скрыто: ${tag:-${event_commit:0:12}}"
    elif [ "$new_tag" = true ]; then
        print_update_line "$CYAN" '↑' "$details" "→ ${tag}"
    elif [ "$different_head" = true ]; then
        print_update_line "$YELLOW" '↔' "$details" "↔ ${remote_head:0:12}"
    elif result_has "$result" "local-newer"; then
        print_update_line "$GREEN" '✓' "$details" '— без обновлений'
    elif [ -n "$tag" ]; then
        # Для закрепления используется та же цветовая схема; база отмечена *.
        if is_stable_version_tag "$configured_ref"; then
            if version_tag_is_newer "$tag" "$configured_ref"; then
                print_update_line "$CYAN" '↑' "$details" "→ ${tag}"
            else
                print_update_line "$GREEN" '✓' "$details" '— без обновлений'
            fi
        else
            print_update_line "$YELLOW" '?' "$name" "— remote: ${tag}; нет базы сравнения"
        fi
    elif [ -n "$remote_head" ]; then
        if hashes_match "$remote_head" "$configured_ref"; then
            print_update_line "$GREEN" '✓' "$details" '— без обновлений'
        elif is_commit_ref "$configured_ref"; then
            print_update_line "$YELLOW" '↔' "$details" "↔ ${remote_head:0:12}"
        else
            print_update_line "$YELLOW" '?' "$name" "— HEAD: ${remote_head:0:12}; нет базы сравнения"
        fi
    elif result_has "$result" "no-stable-tags"; then
        print_update_line "$YELLOW" '?' "$name" '— нет стабильных тегов'
    elif result_has "$result" "up-to-date"; then
        print_update_line "$GREEN" '✓' "$details" '— без обновлений'
    else
        CHECK_UPDATE_ERRORS=$((CHECK_UPDATE_ERRORS + 1))
        print_update_line "$RED" '?' "$name" '— неверный ответ remote'
    fi
}

cmd_check_updates() {
    header "Проверка обновлений"
    printf '  %b✓ актуально%b  %b↑ новая версия%b  %b↔/? различия/неизвестно%b  %b− пропуск%b  %b? ошибка%b\n' \
        "$GREEN" "$NC" "$CYAN" "$NC" "$YELLOW" "$NC" "$GRAY" "$NC" "$RED" "$NC"
    info "* — версия из скрипта; ↔ — коммиты различаются, порядок неизвестен."
    configure_install_jobs || return 1
    configure_proxy check-updates
    acquire_state_lock || return 1
    gist_pull
    CHECK_UPDATE_ERRORS=0

    # ── Фаза 1: параллельный запрос всех remote ─────────────────────────────
    local _chk_dir
    _chk_dir=$(mktemp -d)
    register_exit_hook "rm -rf '$_chk_dir'"

    CHECK_UPDATE_JOB_PIDS=()
    info "Запрос remote (до ${INSTALL_JOBS} одновременно)..."

    local -A _check_state=() _check_local=() _check_configured=()
    local UPDATE_REPO UPDATE_BRANCH UPDATE_BASELINE UPDATE_CHANNEL
    local UPDATE_CONFIGURED UPDATE_LOCAL UPDATE_STATE name

    for name in "${!UV_TOOLS[@]}" "${!GIT_REPOS[@]}" "${!VENV_REPOS[@]}" \
        "${!BINARY_TOOLS[@]}" chisel "${!WIN_TOOLS[@]}" "${!TMUX_PLUGINS[@]}"; do
        if ! tool_update_context "$name"; then
            printf 'error\n' > "${_chk_dir}/tool_${name}"
        elif [[ -v "TMUX_PLUGINS[$name]" ]] && [ "$UPDATE_STATE" = missing ]; then
            printf 'not-checked\n' > "${_chk_dir}/tool_${name}"
        else
            ( check_remote_updates "$UPDATE_REPO" "$UPDATE_BASELINE" "$UPDATE_BRANCH" \
                "$UPDATE_CHANNEL" "$UPDATE_CONFIGURED" > "${_chk_dir}/tool_${name}" ) &
            track_check_update_job "$!"
        fi
        _check_state["$name"]="$UPDATE_STATE"
        _check_local["$name"]="$UPDATE_LOCAL"
        _check_configured["$name"]="$UPDATE_CONFIGURED"
    done

    # Go
    (
        local latest
        if latest=$(git ls-remote --tags https://go.googlesource.com/go 2>/dev/null \
            | awk '$2 ~ /^refs\/tags\/go[0-9]+\.[0-9]+\.[0-9]+$/ {
                sub(/^refs\/tags\/go/, "", $2); print $2
            }' \
            | LC_ALL=C sort -V \
            | tail -1) && is_stable_version_tag "$latest"; then
            printf '%s\n' "$latest"
        else
            printf 'error\n'
        fi
    ) > "${_chk_dir}/go_latest" &
    track_check_update_job "$!"

    # Все Go-утилиты, включая варианты с CGO.
    for name in "${!GO_TOOLS[@]}" "${!GO_TOOLS_CGO[@]}"; do
        local spec
        if [[ -v "GO_TOOLS[$name]" ]]; then
            spec="${GO_TOOLS[$name]}"
        else
            spec="${GO_TOOLS_CGO[$name]}"
        fi
        (
            local remote_state
            if cmd_exists go && remote_state=$(go_tool_remote_state "$spec"); then
                printf '%s\n' "$remote_state"
            else
                printf 'error\n'
            fi
        ) > "${_chk_dir}/gotool_${name}" &
        track_check_update_job "$!"
    done

    wait_check_update_jobs
    info "Готово."

    # ── Фаза 2: отображение результатов ──────────────────────────────────────
    local _result

    local group label
    local group_names=()
    for group in uv git venv binary chisel windows; do
        case "$group" in
            uv) label="uv tools"; group_names=("${!UV_TOOLS[@]}") ;;
            git) label="Git-репозитории"; group_names=("${!GIT_REPOS[@]}") ;;
            venv) label="Venv-репозитории"; group_names=("${!VENV_REPOS[@]}") ;;
            binary) label="Бинарные утилиты"; group_names=("${!BINARY_TOOLS[@]}") ;;
            chisel) label="Chisel"; group_names=(chisel) ;;
            windows) label="Windows-утилиты"; group_names=("${!WIN_TOOLS[@]}") ;;
        esac
        echo ""
        info "$label"
        for name in "${group_names[@]}"; do
            _result=$(cat "${_chk_dir}/tool_${name}" 2>/dev/null) || _result="error"
            display_update_result "$name" "${_check_state[$name]}" \
                "${_check_local[$name]}" "${_check_configured[$name]}" "$_result"
        done
    done

    # ── Go
    echo ""
    info "Go"
    local latest_go current_go=""
    latest_go=$(cat "${_chk_dir}/go_latest" 2>/dev/null)
    if cmd_exists go && go version &>/dev/null; then
        current_go=$(go version | grep -oP 'go\K[0-9.]+' | head -1 || true)
    fi
    local go_details="go (${current_go:-${GO_VERSION}*})"
    if [ "$latest_go" = "error" ] || [ -z "$latest_go" ]; then
        CHECK_UPDATE_ERRORS=$((CHECK_UPDATE_ERRORS + 1))
        print_update_line "$RED" '?' go '— ошибка проверки'
    elif [ -z "$current_go" ]; then
        if version_tag_is_newer "$latest_go" "$GO_VERSION"; then
            print_update_line "$CYAN" '↑' "$go_details" "→ ${latest_go}"
        else
            print_update_line "$GREEN" '✓' "$go_details" '— без обновлений'
        fi
    elif [ "$latest_go" = "$current_go" ]; then
        print_update_line "$GREEN" '✓' "$go_details" '— без обновлений'
    elif version_tag_is_newer "v${latest_go}" "v${current_go}"; then
        print_update_line "$CYAN" '↑' "$go_details" "→ ${latest_go}"
    elif version_tag_is_newer "v${current_go}" "v${latest_go}"; then
        print_update_line "$GREEN" '✓' "$go_details" '— без обновлений'
    else
        print_update_line "$YELLOW" '?' "$go_details" "— remote: ${latest_go}; сравнение недоступно"
    fi

    # ── Go-утилиты
    echo ""
    info "Go-утилиты"
    for name in "${!GO_TOOLS[@]}" "${!GO_TOOLS_CGO[@]}"; do
        local actual latest remote_commit remote_state
        if is_go_tool "$name"; then
            actual=$(go_tool_installed_version "$name" "${GO_BIN_DIR}/${name}" || true)
        else
            actual=""
        fi
        remote_state=$(cat "${_chk_dir}/gotool_${name}" 2>/dev/null) || remote_state="error"
        latest=""
        remote_commit=""
        if [[ "$remote_state" == *"|"* ]]; then
            latest="${remote_state%%|*}"
            remote_commit="${remote_state#*|}"
        fi
        local tool_details="$name"
        [ -z "$actual" ] || tool_details+=" (${actual})"
        if ! is_stable_version_tag "$latest" || ! is_full_commit "$remote_commit"; then
            CHECK_UPDATE_ERRORS=$((CHECK_UPDATE_ERRORS + 1))
            print_update_line "$RED" '?' "$name" '— ошибка проверки'
        elif [ -n "$actual" ] && [ "${actual#v}" = "${latest#v}" ]; then
            print_update_line "$GREEN" '✓' "$tool_details" '— без обновлений'
        elif is_skipped "$name" "$remote_commit"; then
            print_update_line "$GRAY" '−' "$name" "— скрыто: ${latest}"
        elif version_tag_is_newer "$actual" "$latest"; then
            print_update_line "$GREEN" '✓' "$tool_details" '— без обновлений'
        elif version_tag_is_newer "$latest" "$actual"; then
            print_update_line "$CYAN" '↑' "$tool_details" "→ ${latest}"
        else
            print_update_line "$YELLOW" '?' "$tool_details" "— remote: ${latest}; нет базы сравнения"
        fi
    done

    # ── tmux plugins
    echo ""
    info "tmux plugins"
    for name in "${!TMUX_PLUGINS[@]}"; do
        _result=$(cat "${_chk_dir}/tool_${name}" 2>/dev/null) || _result="error"
        [ -n "$_result" ] || _result="error"
        display_update_result "$name" "${_check_state[$name]}" \
            "${_check_local[$name]}" "" "$_result"
    done

    echo ""
    info "Скрыть обновление: $0 --skip <инструмент>"

    if [ "$CHECK_UPDATE_ERRORS" -gt 0 ]; then
        error "Ошибок проверки: ${CHECK_UPDATE_ERRORS}"
        return 1
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
#  --skip <tool>: скрыть текущую remote-ревизию в отчёте
# ═══════════════════════════════════════════════════════════════════════════════

cmd_skip() {
    local name="$1"
    is_skip_supported_tool "$name" || {
        error "Инструмент '$name' не найден в конфигурации"
        return 1
    }
    configure_proxy skip
    acquire_state_lock || return 1
    gist_pull

    local go_spec=""
    if [[ -v "GO_TOOLS[$name]" ]]; then
        go_spec="${GO_TOOLS[$name]}"
    elif [[ -v "GO_TOOLS_CGO[$name]" ]]; then
        go_spec="${GO_TOOLS_CGO[$name]}"
    fi

    if [ -n "$go_spec" ]; then
        local remote_state remote_version remote_commit
        if ! remote_state=$(go_tool_remote_state "$go_spec"); then
            error "Не удалось определить remote-версию Go-инструмента $name"
            return 1
        fi
        IFS='|' read -r remote_version remote_commit <<< "$remote_state"
        if ! is_stable_version_tag "$remote_version" \
            || ! is_full_commit "$remote_commit"; then
            error "Remote вернул неверную версию или ревизию для $name"
            return 1
        fi
        set_skip "$name" "$remote_commit"
        success "Текущая remote-версия $name скрыта (${remote_version}, ${remote_commit:0:12})"
        info "Другая remote-версия снова будет отображаться"
        info "Отменить: $0 --unskip $name"
        gist_push
        return 0
    fi

    local UPDATE_REPO UPDATE_BRANCH UPDATE_BASELINE UPDATE_CHANNEL
    local UPDATE_CONFIGURED UPDATE_LOCAL UPDATE_STATE result event_commit
    tool_update_context "$name" || return 1
    result=$(check_remote_updates "$UPDATE_REPO" "$UPDATE_BASELINE" "$UPDATE_BRANCH" \
        "$UPDATE_CHANNEL" "$UPDATE_CONFIGURED")
    event_commit=$(result_field "$result" "remote-commit" 2>/dev/null || true)
    if ! is_full_commit "$event_commit"; then
        error "Не удалось определить remote-ревизию для $name"
        return 1
    fi

    set_skip "$name" "$event_commit"
    success "Текущая remote-ревизия $name скрыта (${event_commit:0:12})"
    info "Другая remote-ревизия снова будет отображаться"
    info "Отменить: $0 --unskip $name"
    gist_push
}

# ═══════════════════════════════════════════════════════════════════════════════
#  --unskip <tool>: убрать пропуск для инструмента
# ═══════════════════════════════════════════════════════════════════════════════

cmd_unskip() {
    local name="$1"
    is_skip_supported_tool "$name" || {
        error "Инструмент '$name' не найден в конфигурации"
        return 1
    }
    acquire_state_lock || return 1
    gist_pull
    local skipped
    skipped=$(get_skip "$name")
    if [ -z "$skipped" ]; then
        warn "$name не в списке пропущенных"
        return
    fi
    clear_skip "$name"
    success "Пропуск для $name снят (был: ${skipped:0:8})"
    gist_push
}

# ═══════════════════════════════════════════════════════════════════════════════
#  --skip-list: показать все скрытые remote-ревизии
# ═══════════════════════════════════════════════════════════════════════════════

cmd_skip_list() {
    acquire_state_lock || return 1
    header "Скрытые remote-ревизии"
    if [ ! -f "$SKIP_FILE" ] || [ ! -s "$SKIP_FILE" ]; then
        info "Нет скрытых remote-ревизий"
        return
    fi
    if ! validate_skip_file "$SKIP_FILE"; then
        error "Файл пропусков имеет неверный формат: $SKIP_FILE"
        return 1
    fi
    while IFS='=' read -r name commit; do
        [[ -z "$name" || "$name" =~ ^[[:space:]]*# ]] && continue
        echo -e "  ${YELLOW}⊘${NC} $name ${DIM}(${commit:0:8})${NC}"
    done < "$SKIP_FILE"
    echo ""
    info "Отменить пропуск: $0 --unskip <имя>"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  --skip-export: вывести skipped.conf в stdout (для переноса на другую машину)
#  --skip-import: импортировать skip-записи из файла или stdin (слияние)
#
#  Примеры:
#    ./prepare.sh --skip-export > skips.conf          # экспорт в файл
#    scp skips.conf user@host2:~/                      # перенос
#    ./prepare.sh --skip-import skips.conf             # импорт из файла
#
#    ssh host1 './prepare.sh --skip-export' | ./prepare.sh --skip-import  # через pipe
# ═══════════════════════════════════════════════════════════════════════════════

cmd_skip_export() {
    acquire_state_lock || return 1
    if [ ! -f "$SKIP_FILE" ] || [ ! -s "$SKIP_FILE" ]; then
        error "Нет скрытых remote-ревизий для экспорта"
        return 1
    fi
    if ! validate_skip_file "$SKIP_FILE"; then
        error "Файл пропусков имеет неверный формат: $SKIP_FILE"
        return 1
    fi
    cat "$SKIP_FILE"
}

cmd_skip_import() {
    local input="${1:--}"  # файл или "-" (stdin)
    local count=0 line_no=0 line name commit rest invalid_reason=""
    local source_tmp records_tmp merged_tmp
    local -A seen=()

    source_tmp=$(mktemp)
    records_tmp=$(mktemp)
    if [ "$input" = "-" ]; then
        if ! cat > "$source_tmp"; then
            rm -f -- "$source_tmp" "$records_tmp"
            error "Не удалось прочитать stdin"
            return 1
        fi
    else
        if [ ! -r "$input" ]; then
            rm -f -- "$source_tmp" "$records_tmp"
            error "Не удалось прочитать файл: $input"
            return 1
        fi
        if ! cp -- "$input" "$source_tmp"; then
            rm -f -- "$source_tmp" "$records_tmp"
            error "Не удалось скопировать файл для проверки: $input"
            return 1
        fi
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        line_no=$((line_no + 1))
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" != *=* ]]; then
            invalid_reason="ожидается формат имя=40-символьный-хеш"
            break
        fi
        name="${line%%=*}"
        rest="${line#*=}"
        if [[ "$rest" == *=* ]]; then
            invalid_reason="лишний разделитель '='"
            break
        fi
        commit="$rest"
        if ! skip_record_valid "$name" "$commit"; then
            invalid_reason="неизвестное имя или неверный полный хеш"
            break
        fi
        if [[ -v "seen[$name]" ]]; then
            invalid_reason="повторная запись для $name"
            break
        fi
        seen["$name"]=1
        printf '%s=%s\n' "$name" "$commit" >> "$records_tmp"
        count=$((count + 1))
    done < "$source_tmp"
    rm -f -- "$source_tmp"
    if [ -n "$invalid_reason" ]; then
        rm -f -- "$records_tmp"
        error "Строка ${line_no}: ${invalid_reason}"
        return 1
    fi

    if [ "$count" -gt 0 ]; then
        acquire_state_lock || {
            rm -f -- "$records_tmp"
            return 1
        }
        mkdir -p "$(dirname "$SKIP_FILE")"
        if [ -f "$SKIP_FILE" ] && ! validate_skip_file "$SKIP_FILE"; then
            rm -f -- "$records_tmp"
            error "Текущий файл пропусков имеет неверный формат: $SKIP_FILE"
            return 1
        fi
        merged_tmp=$(mktemp "${SKIP_FILE}.import.XXXXXX")
        if [ -f "$SKIP_FILE" ]; then
            awk -F= '
                NR == FNR { replacement[$1]=1; next }
                !($1 in replacement)
            ' "$records_tmp" "$SKIP_FILE" > "$merged_tmp"
        fi
        cat "$records_tmp" >> "$merged_tmp"
        chmod 600 "$merged_tmp"
        mv "$merged_tmp" "$SKIP_FILE"
    fi
    rm -f -- "$records_tmp"

    success "Импортировано записей: $count"
    info "Проверить: $0 --skip-list"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  --install: установка отсутствующих инструментов (без обновления имеющихся)
# ═══════════════════════════════════════════════════════════════════════════════

configure_uv_tool_runtime() {
    local name="$1"
    [[ -v "UV_SYSTEM_IMPORTS[$name]" ]] || return 0

    local tool_root normalized_name env_dir config_file config_tmp python_bin
    local module imports
    tool_root=$(uv tool dir 2>/dev/null) || {
        error "$name: uv не сообщил каталог окружений инструментов"
        return 1
    }
    normalized_name=$(printf '%s' "$name" | tr '[:upper:]_' '[:lower:]-')
    env_dir="${tool_root}/${normalized_name}"
    config_file="${env_dir}/pyvenv.cfg"
    python_bin="${env_dir}/bin/python"

    if [ ! -f "$config_file" ] || [ ! -x "$python_bin" ]; then
        error "$name: не найдено окружение uv: $env_dir"
        return 1
    fi

    if ! grep -Eqi '^[[:space:]]*include-system-site-packages[[:space:]]*=[[:space:]]*true[[:space:]]*$' \
        "$config_file"; then
        config_tmp=$(mktemp "${config_file}.prepare.XXXXXX")
        if ! awk '
            BEGIN { replaced=0 }
            /^[[:space:]]*include-system-site-packages[[:space:]]*=/ {
                if (!replaced) {
                    print "include-system-site-packages = true"
                    replaced=1
                }
                next
            }
            { print }
            END {
                if (!replaced) print "include-system-site-packages = true"
            }
        ' "$config_file" > "$config_tmp"; then
            rm -f -- "$config_tmp"
            error "$name: не удалось включить системные Python-пакеты"
            return 1
        fi
        chmod --reference="$config_file" "$config_tmp"
        mv "$config_tmp" "$config_file"
    fi

    imports="${UV_SYSTEM_IMPORTS[$name]}"
    local import_modules=()
    IFS=',' read -r -a import_modules <<< "$imports"
    for module in "${import_modules[@]}"; do
        if ! "$python_bin" -c \
            'import importlib, sys; importlib.import_module(sys.argv[1])' "$module"; then
            error "$name: системный Python-модуль недоступен в окружении uv: $module"
            return 1
        fi
    done
    success "$name: системные Python-модули доступны (${imports})"
}

ensure_uv_sudo_wrapper() {
    local name="$1"
    local command_csv="${SUDO_UV_COMMANDS[$name]:-$name}"
    local commands=()
    local command_name installed_cmd

    IFS=',' read -r -a commands <<< "$command_csv"
    for command_name in "${commands[@]}"; do
        installed_cmd="${LOCAL_BIN}/${command_name}"
        if [ ! -f "$installed_cmd" ] && [ ! -f "${installed_cmd}.orig" ]; then
            installed_cmd="${LOCAL_BIN}/$(echo "$command_name" | tr '[:upper:]' '[:lower:]')"
        fi
        if [ -f "${installed_cmd}.orig" ]; then
            wrap_with_sudo "$installed_cmd" "$name"
        elif [ -f "$installed_cmd" ] \
            && grep -Fqx "# Managed by prepare.sh: sudo wrapper for ${name}" "$installed_cmd"; then
            error "$name: управляемая sudo-обёртка не содержит исходный файл: $installed_cmd"
            return 1
        elif [ -f "$installed_cmd" ]; then
            wrap_with_sudo "$installed_cmd" "$name"
        else
            error "$name: uv сообщает об установке, но команда не найдена: $command_name"
            return 1
        fi
    done
}

install_uv_tool_package() (
    local name="$1" source="$2" display_version="$3"
    local install_args=(tool install)

    if [[ -v "UV_SYSTEM_PYTHON[$name]" ]]; then
        if [ ! -x "${UV_SYSTEM_PYTHON[$name]}" ]; then
            error "$name: системный Python не найден: ${UV_SYSTEM_PYTHON[$name]}"
            return 1
        fi
        install_args+=(--python "${UV_SYSTEM_PYTHON[$name]}")
    elif [[ -v "UV_TOOL_PYTHON[$name]" ]]; then
        install_args+=(--python "${UV_TOOL_PYTHON[$name]}")
    fi

    info "Установка $name ($display_version)..."
    if [ "$name" = manspider ]; then
        # Как install.sh форка: CLI + web и зависимости из uv.lock.
        # Сам пакет ставим по Git URL, чтобы проверка обновлений видела commit.
        local install_tmp repo_url ref
        install_tmp=$(mktemp -d -t prepare-manspider.XXXXXXXX) || return 1
        trap 'rm -rf -- "$install_tmp"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        repo_url=$(uv_tool_url "${UV_TOOLS[$name]}")
        ref=$(uv_tool_ref "${UV_TOOLS[$name]}")
        if ! git_clone_at_revision "$repo_url" "$install_tmp/source" "$ref"; then
            error "$name: не удалось получить закреплённую версию форка"
            return 1
        fi
        if ! uv export --directory "$install_tmp/source" --locked --no-dev --extra web \
            --python "${UV_TOOL_PYTHON[$name]}" --no-emit-project --no-hashes \
            --no-annotate --no-header --format requirements.txt \
            --output-file "$install_tmp/constraints.txt" >/dev/null; then
            error "$name: не удалось прочитать закреплённые зависимости из uv.lock"
            return 1
        fi
        install_args+=(--constraints "$install_tmp/constraints.txt")
        source="man-spider[web] @ ${source}"
    fi
    if ! uv "${install_args[@]}" "$source"; then
        error "Не удалось установить $name"
        return 1
    fi
    configure_uv_tool_runtime "$name" || return 1
    success "$name установлен через uv"
)

install_binary_tool() {
    local name="$1"

    if needs_sudo "$name" \
        && [ -f "${LOCAL_BIN}/${name}.orig" ] \
        && [ ! -e "${LOCAL_BIN}/${name}" ]; then
        info "$name: восстанавливаем незавершённую sudo-обёртку"
        wrap_with_sudo "${LOCAL_BIN}/${name}" "$name" || return 1
        success "$name уже установлен; обёртка восстановлена"
    fi
    if needs_sudo "$name" \
        && [ -f "${LOCAL_BIN}/${name}" ] \
        && grep -Fqx "# Managed by prepare.sh: sudo wrapper for ${name}" "${LOCAL_BIN}/${name}" \
        && [ ! -f "${LOCAL_BIN}/${name}.orig" ]; then
        error "$name: управляемая sudo-обёртка не содержит исходный файл"
        return 1
    fi
    if binary_tool_commands_present "$name"; then
        local configured_version
        configured_version=$(binary_tool_version "${BINARY_TOOLS[$name]}")
        success "$name и все команды пакета уже установлены; существующие версии не изменяются (настройка: $configured_version)"
        return 0
    fi

    local configured_version url archive_type bin_path expected_sha256
    configured_version=$(binary_tool_version "${BINARY_TOOLS[$name]}")
    url=$(binary_tool_url "${BINARY_TOOLS[$name]}")
    archive_type=$(binary_tool_type "${BINARY_TOOLS[$name]}")
    bin_path=$(binary_tool_path "${BINARY_TOOLS[$name]}")
    expected_sha256=$(binary_tool_sha256 "${BINARY_TOOLS[$name]}")

    local tmpdir source_file dest_tmp command_name command_source installed_path
    tmpdir=$(mktemp -d)
    info "Установка $name ($configured_version)..."

    case "$archive_type" in
        tar.gz)
            if ! wget -q "$url" -O "${tmpdir}/archive.tar.gz" \
                || ! tar -tzf "${tmpdir}/archive.tar.gz" >/dev/null \
                || ! tar --no-same-owner --no-same-permissions \
                    -xzf "${tmpdir}/archive.tar.gz" -C "$tmpdir"; then
                rm -rf -- "$tmpdir"
                error "Не удалось подготовить архив $name"
                return 1
            fi
            source_file="${tmpdir}/${bin_path}"
            ;;
        gz)
            if ! wget -q "$url" -O "${tmpdir}/${name}.gz" \
                || ! gzip -t "${tmpdir}/${name}.gz" \
                || ! gunzip "${tmpdir}/${name}.gz"; then
                rm -rf -- "$tmpdir"
                error "Не удалось подготовить архив $name"
                return 1
            fi
            source_file="${tmpdir}/${name}"
            ;;
        zip)
            if ! wget -q "$url" -O "${tmpdir}/archive.zip" \
                || ! unzip -tq "${tmpdir}/archive.zip" >/dev/null \
                || ! unzip -q "${tmpdir}/archive.zip" -d "$tmpdir"; then
                rm -rf -- "$tmpdir"
                error "Не удалось подготовить архив $name"
                return 1
            fi
            source_file="${tmpdir}/${bin_path}"
            ;;
        binary)
            source_file="${tmpdir}/${name}"
            if ! wget -q "$url" -O "$source_file"; then
                rm -rf -- "$tmpdir"
                error "Не удалось скачать $name"
                return 1
            fi
            ;;
        *)
            rm -rf -- "$tmpdir"
            error "$name: неизвестный тип архива: $archive_type"
            return 1
            ;;
    esac

    # Проверяем весь заявленный набор до публикации первого файла.
    while IFS='|' read -r command_name command_source; do
        if [ ! -s "${tmpdir}/${command_source}" ]; then
            rm -rf -- "$tmpdir"
            error "$name: в пакете отсутствует ожидаемый файл для $command_name: $command_source"
            return 1
        fi
    done < <(binary_tool_command_specs "$name")

    if [ -n "$expected_sha256" ]; then
        local actual_sha256
        if [[ ! "$expected_sha256" =~ ^[0-9a-f]{64}$ ]]; then
            rm -rf -- "$tmpdir"
            error "$name: в конфигурации указан неверный SHA-256"
            return 1
        fi
        actual_sha256=$(sha256sum "$source_file" 2>/dev/null | awk '{print $1}') || {
            rm -rf -- "$tmpdir"
            error "$name: не удалось вычислить SHA-256"
            return 1
        }
        if [ "$actual_sha256" != "$expected_sha256" ]; then
            rm -rf -- "$tmpdir"
            error "$name: SHA-256 скачанного бинарника не совпадает"
            return 1
        fi
    fi

    while IFS='|' read -r command_name command_source; do
        installed_path=$(command -v "$command_name" 2>/dev/null || true)
        if [ -n "$installed_path" ] && [ -s "$installed_path" ]; then
            success "$command_name уже установлен; существующая копия не изменяется"
            continue
        fi

        if [ -e "${LOCAL_BIN}/${command_name}" ] \
            || [ -L "${LOCAL_BIN}/${command_name}" ]; then
            backup_incomplete_path "${LOCAL_BIN}/${command_name}"
        fi
        dest_tmp=$(mktemp "${LOCAL_BIN}/.${command_name}.prepare.XXXXXX")
        if ! install -m 0755 "${tmpdir}/${command_source}" "$dest_tmp"; then
            rm -f -- "$dest_tmp"
            rm -rf -- "$tmpdir"
            error "Не удалось подготовить исполняемый файл $command_name"
            return 1
        fi
        mv "$dest_tmp" "${LOCAL_BIN}/${command_name}"
        success "$command_name → ${LOCAL_BIN}/${command_name}"

        if [ "$command_name" = "$name" ]; then
            record_binary_version "$name" "${LOCAL_BIN}/${command_name}" "$configured_version" || {
                rm -rf -- "$tmpdir"
                return 1
            }
        fi
        if [ "$command_name" = "$name" ] && needs_sudo "$name"; then
            if ! wrap_with_sudo "${LOCAL_BIN}/${name}" "$name"; then
                rm -rf -- "$tmpdir"
                return 1
            fi
        fi
    done < <(binary_tool_command_specs "$name")

    rm -rf -- "$tmpdir"
    binary_tool_commands_present "$name" || {
        error "$name: после установки доступен не весь набор команд"
        return 1
    }
}

install_venv_repo() {
    local name="$1"
    local url commit entrypoint extra_deps dir
    url=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f1)
    commit=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f2)
    entrypoint=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f3)
    extra_deps=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f4)
    dir="${TOOLS_DIR}/${name}"

    if [ -d "$dir/.git" ]; then
        success "$name уже клонирован"
        local current
        current=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)
        if [ -z "$current" ]; then
            error "$name: существующий Git-репозиторий повреждён: $dir"
            return 1
        fi
        if [ -n "$commit" ] && ! hashes_match "$current" "$commit"; then
            warn "$name: ревизия отличается от ${commit:0:8} (установлена: ${current:0:8}); существующая копия не изменяется"
        fi
    elif [ -e "$dir" ] || [ -L "$dir" ]; then
        error "$name: путь существует, но не содержит готовый Git-репозиторий: $dir"
        return 1
    else
        info "Клонирование $name..."
        git_clone_at_revision "$url" "$dir" "$commit"
        success "$name клонирован"
    fi

    if [ "$name" = "bloodhound-automation" ]; then
        patch_bloodhound_automation_install "$dir"
    elif [ "$name" = "CVE-2025-33073" ]; then
        patch_cve_2025_install "$dir"
    fi

    if [ ! -f "${dir}/${entrypoint}" ]; then
        error "$name: не найдена точка входа: ${dir}/${entrypoint}"
        return 1
    fi

    local venv_dir complete_marker needs_venv_setup=false
    venv_dir=$(venv_path_for "$name" "$dir")
    complete_marker="${venv_dir}/.prepare_complete"

    if [ "$name" = "bloodhound-automation" ] \
        && bloodhound_venv_has_legacy_packages "$venv_dir"; then
        warn "$name: старое окружение сохранено и будет заменено минимальным"
        backup_incomplete_path "$venv_dir"
    fi

    if [ "$name" = "CVE-2025-33073" ] \
        && [ -f "$complete_marker" ] \
        && ! cve_2025_venv_ready "$venv_dir"; then
        warn "$name: окружение не содержит закреплённый вариант Impacket; выполняется донастройка"
        rm -f -- "$complete_marker"
    fi

    if [ "$name" = "bloodhound-automation" ] \
        && [ -f "$complete_marker" ] \
        && ! bloodhound_venv_ready "$venv_dir"; then
        info "$name: устанавливаем недостающие зависимости для проверки портов"
        rm -f -- "$complete_marker"
    fi

    if [ -e "$venv_dir" ] || [ -L "$venv_dir" ]; then
        if [ ! -d "$venv_dir" ] || [ ! -x "${venv_dir}/bin/python" ]; then
            backup_incomplete_path "$venv_dir"
            needs_venv_setup=true
        elif [ -f "$complete_marker" ]; then
            success "venv для $name уже настроен; существующие пакеты не изменяются"
        else
            info "$name: завершаем ранее созданный venv без обновления уже подходящих пакетов"
            needs_venv_setup=true
        fi
    else
        needs_venv_setup=true
    fi

    if [ "$needs_venv_setup" = true ]; then
        if [ ! -d "$venv_dir" ]; then
            info "Создание venv для $name..."
        fi
        local python_args=()
        if [[ -v "VENV_PYTHON[$name]" ]]; then
            python_args+=(--python "${VENV_PYTHON[$name]}")
        fi
        if [ ! -d "$venv_dir" ]; then
            uv venv "${python_args[@]}" "$venv_dir"
        fi
        if [ ! -x "${venv_dir}/bin/python" ]; then
            error "$name: venv не содержит исполняемый Python: $venv_dir"
            return 1
        fi

        # Один resolver/install на окружение быстрее и не допускает появления
        # конфликтов, возможных при последовательной установке зависимостей.
        local install_args=()
        if [ -f "${dir}/requirements.txt" ]; then
            install_args+=(-r "${dir}/requirements.txt")
        fi
        if [ -n "$extra_deps" ]; then
            local deps=()
            IFS=',' read -r -a deps <<< "$extra_deps"
            install_args+=("${deps[@]}")
        fi
        if [ "${#install_args[@]}" -gt 0 ]; then
            VIRTUAL_ENV="$venv_dir" uv pip install "${install_args[@]}"
        fi
        if [ "$name" = "CVE-2025-33073" ]; then
            # Impacket объявляет ldap3, а проекту нужен его bleeding-edge
            # вариант с тем же import-пакетом. Переустановка последней гарантирует
            # согласованный набор файлов после общего resolver/install.
            VIRTUAL_ENV="$venv_dir" uv pip install --reinstall \
                "ldap3-bleeding-edge==2.10.1.1337"
        fi
        VIRTUAL_ENV="$venv_dir" uv pip check
        if [ "$name" = "CVE-2025-33073" ] && ! cve_2025_venv_ready "$venv_dir"; then
            error "$name: ntlmrelayx.py не содержит ожидаемый параметр"
            return 1
        fi
        local marker_tmp
        marker_tmp=$(mktemp "${venv_dir}/.prepare_complete.XXXXXX")
        printf 'prepared-by=prepare.sh\n' > "$marker_tmp"
        mv "$marker_tmp" "$complete_marker"
        success "venv для $name настроен"
    fi

    write_venv_wrapper "$name" "$dir" "$venv_dir" "$entrypoint"
}

install_windows_tool() {
    local name="$1"
    local dest="${TOOLS_DIR}/for_windows/${name}"

    if is_valid_windows_binary "$dest"; then
        success "$name уже скачан"
        return 0
    fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        backup_incomplete_path "$dest"
    fi

    local win_tmp
    win_tmp=$(mktemp "${dest}.prepare.XXXXXX")
    info "Скачивание $name..."
    if ! wget -q "${WIN_TOOLS[$name]}" -O "$win_tmp" \
        || ! is_valid_windows_binary "$win_tmp"; then
        rm -f -- "$win_tmp"
        error "$name: скачанный файл не прошёл проверку"
        return 1
    fi
    mv "$win_tmp" "$dest"
    local installed_version
    installed_version=$(printf '%s' "${WIN_TOOLS[$name]}" | grep -oP '/download/\K[^/]+')
    record_binary_version "$name" "$dest" "$installed_version" || return 1
    success "$name → $dest"
}

cmd_install() {
    local install_phase_total=14
    require_kali_amd64 || return 1
    acquire_install_lock || return 1
    configure_install_jobs || return 1

    # ── Логирование ───────────────────────────────────────────────────────────
    mkdir -p "$LOG_DIR"
    LOG_FILE="${LOG_DIR}/install_$(date '+%Y-%m-%d_%H-%M-%S').log"
    exec 3>&1
    register_exit_hook "exec 3>&-"
    exec > >(stdbuf -o0 tee >(perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e[78]//g' >> "$LOG_FILE")) 2>&1
    info "Лог: ${LOG_FILE}"

    # ── 0. Предварительные проверки ───────────────────────────────────────────
    header "Установка инструментов"
    if [ "$(id -u)" -eq 0 ]; then
        error "Не запускайте этот скрипт от root. sudo будет запрошен где нужно."
        exit 1
    fi

    # Проверяем sudo-доступ заранее (при curl|bash stdin занят, sudo не сможет спросить пароль)
    if ! sudo -n true 2>/dev/null; then
        if [ "$AUTO_MODE" = true ]; then
            error "Автоматический режим требует беспарольного sudo (NOPASSWD) или предварительного sudo -v"
            exit 1
        fi
        info "Запрашиваем sudo-доступ..."
        sudo -v
    fi

    # Фоновое обновление метки sudo каждые 50 секунд
    ( while true; do sleep 50; sudo -n -v 2>/dev/null; done ) &
    SUDO_KEEPALIVE_PID=$!
    register_exit_hook "kill $SUDO_KEEPALIVE_PID 2>/dev/null"

    configure_proxy
    progress_start "$install_phase_total" "Подготовка"
    info "Параллельные установки: до ${INSTALL_JOBS} одновременно"

    # ── 1. apt: ставим только отсутствующие пакеты ─────────────────────────────
    install_phase "Системные пакеты (apt)"
    local apt_packages=(
        git curl wget python3-pip libpcap-dev libkrb5-dev seclists wmctrl \
        tmux unzip libsqlite3-dev build-essential cargo bind9-dnsutils util-linux \
        nftables python3-nftables tesseract-ocr libreoffice
    )
    if ! gowitness_browser &>/dev/null; then
        apt_packages+=(chromium)
    fi
    if ! cmd_exists docker || ! docker --version &>/dev/null; then
        apt_packages+=(docker.io)
    fi
    if ! { docker compose version &>/dev/null \
        || { cmd_exists docker-compose && docker-compose version &>/dev/null; }; }; then
        apt_packages+=(docker-compose)
    fi
    install_missing_apt_packages "${apt_packages[@]}"
    if ! gowitness_browser &>/dev/null; then
        error "Для gowitness не найден Chromium или Google Chrome"
        return 1
    fi

    # ── 1.1 Docker ─────────────────────────────────────────────────────────
    install_phase "Docker"
    if ! cmd_exists docker || ! docker --version &>/dev/null; then
        error "docker не найден после установки пакета"
        return 1
    fi
    if ! docker compose version &>/dev/null \
        && ! { cmd_exists docker-compose && docker-compose version &>/dev/null; }; then
        error "Docker Compose не найден после установки пакета"
        return 1
    fi
    if ! systemctl is-enabled docker &>/dev/null || ! systemctl is-active docker &>/dev/null; then
        sudo systemctl enable docker --now
    fi
    success "Docker доступен; существующая версия оставлена без изменений"
    DOCKER_GROUP_FRESH=false
    if ! groups "$USER" | grep -q '\bdocker\b'; then
        info "Добавление $USER в группу docker..."
        sudo usermod -aG docker "$USER"
        DOCKER_GROUP_FRESH=true
        info "Группа docker добавлена, для команд docker в этом сеансе будет использоваться sg"
    elif ! id -Gn | grep -q '\bdocker\b'; then
        # Пользователь в группе docker (предыдущий запуск), но сессия не обновлена
        DOCKER_GROUP_FRESH=true
        info "Группа docker есть, но не активна в текущей сессии — будет использоваться sg"
    fi

    # ── 1.2 tmux + tmux-logging ──────────────────────────────────────────────
    install_phase "tmux + tmux-logging"
    local conf
    conf=$(tmux_config_file)

    mkdir -p "$TMUX_PLUGIN_DIR" "$TMUX_LOG_DIR"
    local tmux_plugin
    for tmux_plugin in "${!TMUX_PLUGINS[@]}"; do
        queue_install_job "tmux:${tmux_plugin}" \
            tmux_install_plugin "$tmux_plugin" "${TMUX_PLUGINS[$tmux_plugin]}"
    done
    wait_install_jobs

    tmux_write_config "$conf"

    if tmux list-sessions &>/dev/null; then
        tmux source-file "$conf"
        success "Конфигурация загружена в работающий tmux"
    fi
    success "tmux настроен (${conf}); логи: ${TMUX_LOG_DIR}/%Y-%m-%d"

    # Проверка версии Git (--revision= требует >= 2.49)
    USE_REVISION=false
    if cmd_exists git; then
        local git_ver
        git_ver=$(git version | grep -oP '[0-9]+\.[0-9]+' | head -1)
        local git_major git_minor
        git_major=$(echo "$git_ver" | cut -d. -f1)
        git_minor=$(echo "$git_ver" | cut -d. -f2)
        if [ "$git_major" -gt 2 ] || { [ "$git_major" -eq 2 ] && [ "$git_minor" -ge 49 ]; }; then
            USE_REVISION=true
            info "Git >= 2.49 — используем --revision"
        else
            warn "Git $(git version) — --revision недоступен, fallback на clone+checkout"
        fi
    fi

    # ── 2. uv ─────────────────────────────────────────────────────────────────
    install_phase "uv"
    if cmd_exists uv && uv --version &>/dev/null; then
        success "uv уже установлен: $(uv --version 2>/dev/null)"
    elif cmd_exists uv; then
        error "Найден неработоспособный uv: $(command -v uv); существующий файл оставлен без изменений"
        return 1
    else
        info "Установка uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
        if cmd_exists uv; then
            success "uv установлен: $(uv --version 2>/dev/null)"
        else
            error "uv не найден после установки"
            exit 1
        fi
    fi
    ensure_path_entry "$HOME/.local/bin"

    # ── 3. Go ─────────────────────────────────────────────────────────────────
    install_phase "Go ${GO_VERSION}"
    if cmd_exists go; then
        local current_go
        if ! go version &>/dev/null; then
            error "Найден неработоспособный go: $(command -v go); существующая копия оставлена без изменений"
            return 1
        fi
        current_go=$(go version | grep -oP 'go\K[0-9.]+' || true)
        if [ "$current_go" = "$GO_VERSION" ]; then
            success "Go ${GO_VERSION} уже установлен"
        else
            warn "Go ${current_go:-неизвестной версии} уже установлен; скрипт его не заменяет (настройка: ${GO_VERSION})"
        fi
    else
        info "Установка Go ${GO_VERSION}..."
        install_go_fresh
    fi
    ensure_path_entry "/usr/local/go/bin"
    ensure_path_entry "$GO_BIN_DIR"

    # ── 4. Директории ─────────────────────────────────────────────────────────
    mkdir -p "$TOOLS_DIR" "$LOCAL_BIN" "${TOOLS_DIR}/for_windows"

    # ── 5. Go-утилиты ─────────────────────────────────────────────────────────
    install_phase "Go-утилиты"
    for name in "${!GO_TOOLS[@]}"; do
        if is_go_tool "$name"; then
            success "$name уже установлен"
        else
            info "Установка $name..."
            install_go_tool "$name" "${GO_TOOLS[$name]}"
        fi
    done
    for name in "${!GO_TOOLS_CGO[@]}"; do
        if is_go_tool "$name"; then
            success "$name уже установлен"
        else
            info "Установка $name (CGO_ENABLED=1)..."
            GOBIN="$GO_BIN_DIR" CGO_ENABLED=1 go install -v "${GO_TOOLS_CGO[$name]}"
            success "$name установлен"
        fi
    done

    # ── 6. Git-репозитории ────────────────────────────────────────────────────
    install_phase "Git-репозитории (~/tools)"
    for name in "${!GIT_REPOS[@]}"; do
        local url commit
        url=$(echo "${GIT_REPOS[$name]}" | cut -d'|' -f1)
        commit=$(echo "${GIT_REPOS[$name]}" | cut -d'|' -f2)
        local dir="${TOOLS_DIR}/${name}"

        if [ -d "$dir/.git" ]; then
            success "$name уже клонирован"
            local current
            current=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)
            if [ -z "$current" ]; then
                error "$name: существующий Git-репозиторий повреждён: $dir"
                return 1
            fi
            if [ -n "$commit" ]; then
                if ! hashes_match "$current" "$commit"; then
                    warn "$name: ревизия отличается от ${commit:0:8} (установлена: ${current:0:8}); существующая копия не изменяется"
                fi
            fi
        elif [ -e "$dir" ] || [ -L "$dir" ]; then
            error "$name: путь существует, но не содержит готовый Git-репозиторий: $dir"
            return 1
        else
            info "Клонирование $name..."
            git_clone_at_revision "$url" "$dir" "$commit"
            success "$name клонирован"
        fi
    done

    # ── 7. Chisel ─────────────────────────────────────────────────────────────
    install_phase "Chisel v${CHISEL_VERSION}"
    local chisel_dir="${TOOLS_DIR}/chisel"
    if [ -x "${chisel_dir}/chisel" ] && [ -s "${chisel_dir}/chisel" ]; then
        success "chisel уже установлен"
    else
        local chisel_tmp chisel_dest_tmp
        chisel_tmp=$(mktemp -d)
        info "Скачивание chisel..."
        if ! wget -q "$CHISEL_URL" -O "${chisel_tmp}/chisel.gz" \
            || ! gzip -t "${chisel_tmp}/chisel.gz" \
            || ! gunzip "${chisel_tmp}/chisel.gz" \
            || [ ! -s "${chisel_tmp}/chisel" ]; then
            rm -rf -- "$chisel_tmp"
            error "Не удалось подготовить chisel"
            return 1
        fi

        if [ -e "$chisel_dir" ] && [ ! -d "$chisel_dir" ]; then
            backup_incomplete_path "$chisel_dir"
        fi
        mkdir -p "$chisel_dir"
        if [ -e "${chisel_dir}/chisel" ] || [ -L "${chisel_dir}/chisel" ]; then
            backup_incomplete_path "${chisel_dir}/chisel"
        fi
        chisel_dest_tmp=$(mktemp "${chisel_dir}/.chisel.prepare.XXXXXX")
        if ! install -m 0755 "${chisel_tmp}/chisel" "$chisel_dest_tmp"; then
            rm -f -- "$chisel_dest_tmp"
            rm -rf -- "$chisel_tmp"
            error "Не удалось подготовить исполняемый файл chisel"
            return 1
        fi
        mv "$chisel_dest_tmp" "${chisel_dir}/chisel"
        rm -rf -- "$chisel_tmp"
        success "chisel → ${chisel_dir}/chisel"
    fi

    handle_first_install_kali_tools

    # ── 8. uv tools ──────────────────────────────────────────────────────────
    install_phase "uv tool install (Python-утилиты)"
    local queued_uv_tools=()
    for name in "${!UV_TOOLS[@]}"; do
        local ref repo_url dv source
        ref=$(uv_tool_ref "${UV_TOOLS[$name]}")
        repo_url=$(uv_tool_url "${UV_TOOLS[$name]}")
        dv=$(uv_tool_display_version "${UV_TOOLS[$name]}")
        source="git+${repo_url}@${ref}"

        if is_uv_tool_installed "$name"; then
            configure_uv_tool_runtime "$name" || return 1
            if needs_sudo "$name"; then
                ensure_uv_sudo_wrapper "$name" || return 1
            fi
            success "$name уже установлен через uv ($dv)"
            continue
        fi

        # Проверка: инструмент есть в системе, но не через uv (apt/pipx и т.п.)
        local src
        src=$(uv_tool_source "$name")
        if [[ "$src" == "pipx" || "$src" == "system" ]]; then
            local sys_bin
            sys_bin=$(command -v "$name" 2>/dev/null) || true
            if [ "$src" = "pipx" ] || [[ "$sys_bin" == "${LOCAL_BIN}/"* ]]; then
                warn "$name уже установлен (${src}: ${sys_bin:-путь неизвестен}); существующий файл не изменяется"
                continue
            fi
            info "$name: системная копия остаётся без изменений; устанавливается отдельная закреплённая копия uv"
        fi

        queued_uv_tools+=("$name")
        queue_install_job "uv:${name}" \
            install_uv_tool_package "$name" "$source" "$dv"
    done
    wait_install_jobs

    # Управляемые sudo-обёртки создаём последовательно после завершения всех
    # установок uv.
    for name in "${queued_uv_tools[@]}"; do
        if ! is_uv_tool_installed "$name"; then
            error "$name: uv не подтверждает завершённую установку"
            return 1
        fi
        configure_uv_tool_runtime "$name" || return 1
        if needs_sudo "$name"; then
            ensure_uv_sudo_wrapper "$name" || return 1
        fi
    done

    # ── 9. Бинарные утилиты ──────────────────────────────────────────────────
    install_phase "Бинарные утилиты (→ ~/.local/bin)"
    for name in "${!BINARY_TOOLS[@]}"; do
        queue_install_job "binary:${name}" install_binary_tool "$name"
    done
    wait_install_jobs

    # ── 10. Venv-репозитории ─────────────────────────────────────────────────
    install_phase "Venv-репозитории (~/tools + обёртки)"
    for name in "${!VENV_REPOS[@]}"; do
        if [ "$name" = bloodhound-automation ]; then
            queue_install_job "venv:${name}" with_bloodhound_proxy install_venv_repo "$name"
        else
            queue_install_job "venv:${name}" install_venv_repo "$name"
        fi
    done
    wait_install_jobs

    # ── 11. Windows-утилиты ──────────────────────────────────────────────────
    install_phase "Windows-утилиты (~/tools/for_windows)"
    for name in "${!WIN_TOOLS[@]}"; do
        queue_install_job "windows:${name}" install_windows_tool "$name"
    done
    wait_install_jobs

    # ── 12. Шаблоны Nuclei ──────────────────────────────────────────────────
    install_phase "Шаблоны Nuclei"
    local nuclei_templates="${TOOLS_DIR}/nuclei-templates"
    if nuclei_templates_dir_complete "$nuclei_templates"; then
        if nuclei_templates_config_matches "$nuclei_templates"; then
            success "Шаблоны nuclei уже установлены; существующая копия не изменяется"
        else
            info "Исправление сохранённого пути к шаблонам nuclei..."
            # -update-template-dir меняет путь только в памяти процесса. Если
            # версия шаблонов уже актуальна, Nuclei 3.11.0 ничего не скачивает
            # и не записывает новый путь в .templates-config.json.
            if ! nuclei_templates_config_set_dir "$nuclei_templates"; then
                if ! cmd_exists nuclei; then
                    error "nuclei не найден, восстановление конфигурации шаблонов невозможно"
                    return 1
                fi
                warn "Конфигурация шаблонов отсутствует или повреждена; Nuclei создаст её заново"
                if ! nuclei -update-templates -update-template-dir "$nuclei_templates"; then
                    error "Не удалось восстановить конфигурацию шаблонов nuclei"
                    return 1
                fi
            fi
            if ! nuclei_templates_config_matches "$nuclei_templates"; then
                error "Не удалось сохранить путь к шаблонам в $(nuclei_templates_config_file)"
                return 1
            fi
            success "Путь к шаблонам nuclei исправлен"
        fi
    else
        if ! cmd_exists nuclei; then
            error "nuclei не найден, первоначальная установка шаблонов невозможна"
            return 1
        fi
        if [ -e "$nuclei_templates" ] || [ -L "$nuclei_templates" ]; then
            backup_incomplete_path "$nuclei_templates"
        fi
        if [[ "${DISABLE_NUCLEI_TEMPLATES_PUBLIC_DOWNLOAD:-}" =~ ^([Tt]([Rr][Uu][Ee])?|1)$ ]]; then
            error "Публичные шаблоны nuclei отключены переменной DISABLE_NUCLEI_TEMPLATES_PUBLIC_DOWNLOAD"
            return 1
        fi
        info "Первоначальная установка шаблонов nuclei..."
        # Встроенный загрузчик Nuclei 3.11.0 может скрыть ошибку GitHub API и
        # завершиться с кодом 0, оставив пустой каталог. Для первоначальной
        # установки сразу используем официальный release с проверкой SHA-256.
        install_nuclei_templates_release "$nuclei_templates" || return 1
        if ! nuclei_templates_dir_complete "$nuclei_templates"; then
            error "Установленный release nuclei-templates не прошёл итоговую проверку"
            return 1
        fi
        if ! nuclei_templates_config_matches "$nuclei_templates"; then
            error "В конфигурации nuclei сохранён неверный путь к шаблонам: $(nuclei_templates_config_file)"
            return 1
        fi
        success "Шаблоны nuclei установлены"
    fi

    # ── 13. BloodHound (через bloodhound-automation) ─────────────────────────
    install_phase "BloodHound (bloodhound-automation)"
    local bha_dir="${TOOLS_DIR}/bloodhound-automation"
    local bha_venv="${bha_dir}/.venv/bin/python"
    local bha_script="${bha_dir}/bloodhound-automation.py"
    if [ -x "$bha_venv" ] && [ -f "$bha_script" ]; then
        # Функция для запуска команды с правами docker (sg если группа свежая)
        run_bha() {
            if [ "$DOCKER_GROUP_FRESH" = true ]; then
                local _args
                _args=$(printf ' %q' "$@")
                sg docker -c "cd $(printf '%q' "$bha_dir") && $(printf '%q' "$bha_venv") $(printf '%q' "$bha_script")${_args}"
            else
                (cd "$bha_dir" && "$bha_venv" "$bha_script" "$@")
            fi
        }

        local bha_project="${bha_dir}/projects/my_project"
        if [ -e "$bha_project" ] || [ -L "$bha_project" ]; then
            info "Запускаем my_project или продолжаем его незавершённую инициализацию..."
        else
            info "Запуск bloodhound-automation start my_project (может занять длительное время)..."
        fi
        with_bloodhound_proxy run_bha start my_project -t 1200
        success "BloodHound запущен (проект my_project)"
    else
        error "bloodhound-automation установлен не полностью"
        return 1
    fi

    # ── Готово ────────────────────────────────────────────────────────────────
    progress_finish "Завершение"
    mark_first_install_done
    header "Установка завершена!"
    echo ""
    info "Перезагрузите оболочку или выполните:"
    echo -e "  ${CYAN}source ~/.bashrc${NC}  или  ${CYAN}source ~/.zshrc${NC}"
    echo ""
    info "Проверка статуса:      $0"
    info "Отчёт о новых версиях: $0 --check-updates"
}

parse_cli_options() {
    local argument literal=false
    CLI_ARGUMENTS=()
    PROXY_SCOPE=bloodhound
    for argument in "$@"; do
        if [ "$literal" = false ] && [ "$argument" = --proxy-all ]; then
            PROXY_SCOPE=all
        elif [ "$literal" = false ] && [ "$argument" = -- ]; then
            literal=true
        else
            CLI_ARGUMENTS+=("$argument")
        fi
    done

    local count=${#CLI_ARGUMENTS[@]}
    case "${CLI_ARGUMENTS[0]:-}" in
        "") [ "$count" -eq 0 ] && return 0 ;;
        --auto|--install|--check-updates|--skip-list|--skip-export|--help|-h)
            [ "$count" -eq 1 ] && return 0 ;;
        --skip|--unskip)
            [ "$count" -eq 2 ] && [ -n "${CLI_ARGUMENTS[1]}" ] && return 0 ;;
        --skip-import)
            [ "$count" -le 2 ] && return 0 ;;
        *)
            error "Неизвестный параметр: ${CLI_ARGUMENTS[0]}"
            return 1 ;;
    esac
    error "Неверные аргументы. Используйте $0 --help"
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Точка входа
# ═══════════════════════════════════════════════════════════════════════════════

parse_cli_options "$@" || exit 1
set -- "${CLI_ARGUMENTS[@]}"
# Даже команды без интерактивной настройки (например --unskip) должны
# соблюдать область действия proxy, унаследованного из оболочки.
initialize_proxy_settings

case "${1:-}" in
    --auto)
        AUTO_MODE=true
        cmd_install
        ;;
    --check-updates)
        cmd_check_updates
        ;;
    --install)
        cmd_install
        ;;
    --skip)
        [ -z "${2:-}" ] && { error "Укажите имя инструмента: $0 --skip <имя>"; exit 1; }
        cmd_skip "$2"
        ;;
    --unskip)
        [ -z "${2:-}" ] && { error "Укажите имя инструмента: $0 --unskip <имя>"; exit 1; }
        cmd_unskip "$2"
        ;;
    --skip-list)
        cmd_skip_list
        ;;
    --skip-export)
        cmd_skip_export
        ;;
    --skip-import)
        cmd_skip_import "${2:--}"
        ;;
    --help|-h)
        echo "Использование:"
        echo "  $0                  — проверить наличие инструментов (без сети)"
        echo "  $0 --auto           — автоустановка; конфликтующие пакеты Kali удаляются"
        echo "  $0 --check-updates  — только отчёт о новых версиях; установленные копии не изменяются"
        echo "  $0 --install        — интерактивная установка; удаление пакетов по умолчанию"
        echo "  $0 --skip <имя>     — скрыть текущую remote-ревизию в отчёте"
        echo "  $0 --unskip <имя>   — снова показывать remote-ревизию"
        echo "  $0 --skip-list      — показать скрытые remote-ревизии"
        echo "  $0 --skip-export    — экспорт пропусков в stdout"
        echo "  $0 --skip-import <файл>  — импорт пропусков из файла (или stdin)"
        echo "  $0 --help           — эта справка"
        echo ""
        echo "Proxy:"
        echo "  По умолчанию — только установка и запуск bloodhound-automation"
        echo "  --proxy-all         — прежний режим: proxy для всех сетевых операций"
        echo "  Примеры: $0 --auto --proxy-all; $0 --check-updates --proxy-all"
        echo "  HTTP_PROXY / HTTPS_PROXY / ALL_PROXY — адреса proxy; NO_PROXY — исключения"
        echo "  Поддерживаются и строчные имена; --auto берёт настройки из окружения"
        echo "  Без --proxy-all проверка обновлений выполняется напрямую, без запроса proxy"
        echo ""
        echo "Окружение:"
        echo "  Платформа установки: Kali Linux AMD64 (x86_64)"
        echo "  PREPARE_INSTALL_JOBS=1..16  — число параллельных установок/remote-запросов (по умолчанию 4)"
        ;;
    "")
        cmd_status
        ;;
    *)
        error "Неизвестный параметр: $1"
        echo "Используйте $0 --help"
        exit 1
        ;;
esac
