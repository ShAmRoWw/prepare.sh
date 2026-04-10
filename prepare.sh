#!/usr/bin/env bash
#
# prepare.sh — установка инструментов для внутреннего пентеста
#
# Использование:
#   ./prepare.sh                — проверить наличие установленных инструментов
#   ./prepare.sh --install       — установить отсутствующие инструменты
#   ./prepare.sh --auto          — полностью автоматическая установка (без вопросов)
#   ./prepare.sh --check-updates — сверить, есть ли новые версии на remote
#
# ВАЖНО: --install, --auto и --check-updates выполнять с включенным VPN.
#
# Быстрый старт (curl):
#   curl -fsSL https://raw.githubusercontent.com/ShAmRoWw/prepare.sh/refs/heads/main/prepare.sh | bash -s -- --auto

set -euo pipefail

# ─── Цвета ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
GRAY='\033[38;5;242m'
NC='\033[0m' # No Color

# ─── Конфигурация ─────────────────────────────────────────────────────────────
TOOLS_DIR="$HOME/tools"
LOCAL_BIN="$HOME/.local/bin"
LOG_DIR="$HOME/.local/share/prepare"
SKIP_FILE="$HOME/.local/share/prepare/skipped.conf"

# ─── Remote-синхронизация skip-списка через GitHub Gist ───────────────────────
# Заполните SKIP_GIST_ID идентификатором приватного гиста для синхронизации
# между устройствами. Если пусто — работает только локально.
SKIP_GIST_ID="87ba4463703d9c46cf2c969091992e28"
SKIP_GIST_FILE="skipped.conf"

# ─── PATH: добавляем директории инструментов (bash не читает .bashrc) ─────────
for _p in "$HOME/.local/bin" "/usr/local/go/bin" "$HOME/go/bin"; do
    case ":$PATH:" in
        *":$_p:"*) ;;
        *) export PATH="$_p:$PATH" ;;
    esac
done
unset _p

# Версия Go (обновить при необходимости)
GO_VERSION="1.25.8"

# uv tools: [имя]="версия|URL_репозитория"
# Устанавливается как: uv tool install "git+${URL}@${версия}"
declare -A UV_TOOLS=(
    [penelope]="v0.19.1|https://github.com/brightio/penelope"
    [netexec]="67d90e0227dab0e1ba57d3a027fc821ee7c20bd3|https://github.com/Pennyw0rth/NetExec"
    [bloodyAD]="3ee204d11d8ce658b3e9c79080543d28f925520b|https://github.com/CravateRouge/bloodyAD"
    [pre2k]="fa816f5a411208d0f9445b181248bedadcfedf05|https://github.com/garrettfoster13/pre2k"
    [smbclientng]="3.0.0|https://github.com/p0dalirius/smbclient-ng"
    [AD-Miner]="v1.9.0|https://github.com/AD-Security/AD_Miner"
    [conpass]="8b22245cb0cf22bb63b27a85c64a23eb1848be17|https://github.com/login-securite/conpass"
    [ldeep]="89abc02e7f99fdf0df8b37e0f15849263d2e6cce|https://github.com/franc-pentest/ldeep"
    [certipy]="5.0.4|https://github.com/ly4k/Certipy"
    [dnsrecon]="1.6.0|https://github.com/darkoperator/dnsrecon"
    [msldap]="46d4dc60dc2e4739c188a848b090dcc064d7888d|https://github.com/skelsec/msldap"
    [RITM]="e442b5c9b85c0a6a387491182472e3d3fbcf97fb|https://github.com/Tw1sm/RITM"
    [impacket]="7fc084ad199bf5c2fb1c513544bee914117aab42|https://github.com/fortra/impacket"
)

# Go-утилиты
declare -A GO_TOOLS=(
    [httpx]="github.com/projectdiscovery/httpx/cmd/httpx@latest"
    [nuclei]="github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
)

# git clone --revision (в ~/tools): [имя]="URL|коммит"
declare -A GIT_REPOS=(
    [ntlmv1-multi]="https://github.com/evilmog/ntlmv1-multi.git|2654aa71e3c5ee7a0a594d43034dce520206eefb"
)

# Бинарники: [имя]="версия|URL|тип_архива|путь_к_бинарнику"
declare -A BINARY_TOOLS=(
    [pretender]="v1.3.2|https://github.com/RedTeamPentesting/pretender/releases/download/v1.3.2/pretender_Linux_x86_64.tar.gz|tar.gz|pretender"
    [rusthound-ce]="v2.4.7|https://github.com/g0h4n/RustHound-CE/releases/download/v2.4.7/rusthound-ce-Linux-gnu-x86_64.tar.gz|tar.gz|rusthound-ce"
    [kerbrute]="v1.0.3|https://github.com/ropnop/kerbrute/releases/download/v1.0.3/kerbrute_linux_amd64|binary|kerbrute"
    [legba]="1.2.0|https://github.com/evilsocket/legba/releases/download/1.2.0/legba-1.2.0-linux-x86_64.tar.gz|tar.gz|legba-1.2.0-linux-x86_64/legba"
)

# Chisel
CHISEL_VERSION="1.11.5"
CHISEL_URL="https://github.com/jpillora/chisel/releases/download/v${CHISEL_VERSION}/chisel_${CHISEL_VERSION}_linux_amd64.gz"

# Git-репо с venv: [имя]="URL|коммит|точка_входа.py|доп_pip_пакеты"
declare -A VENV_REPOS=(
    [krbrelayx]="https://github.com/dirkjanm/krbrelayx.git|10b45a33bc4361ec4a5546eea62db2e4244d3255|krbrelayx.py|dnspython,impacket,ldap3"
    [bloodhound-automation]="https://github.com/Tanguy-Boisset/bloodhound-automation.git|92a1b6ccb3c2968359992d16fb15bae7f51e61b2|bloodhound-automation.py|"
    [targetedKerberoast]="https://github.com/ShutdownRepo/targetedKerberoast.git|ebed0790002dfae503eb5e5525a0630f131fa117|targetedKerberoast.py|"
    [pyLDAPWordlistHarvester]="https://github.com/p0dalirius/pyLDAPWordlistHarvester.git|78cd116f56554b0fface83f4074a29447fa35c54|pyLDAPWordlistHarvester.py|"
    [ASRepCatcher]="https://github.com/Yaxxine7/ASRepCatcher.git|4b70dcaf09dc75b4c1b60965c883ada2128adf8c|ASRepCatcher/ASRepCatcher.py|"
    [PCredz]="https://github.com/lgandx/PCredz.git|a07051d392b50bded1a19734cb70f97010cd90a5|Pcredz|pcapy-ng"
)

# Windows-утилиты
declare -A WIN_TOOLS=(
    [Group3r.exe]="https://github.com/Group3r/Group3r/releases/download/1.0.69/Group3r.exe"
    [Snaffler.exe]="https://github.com/SnaffCon/Snaffler/releases/download/1.0.244/Snaffler.exe"
)

# Инструменты, требующие запуска с sudo
declare -A SUDO_REQUIRED=( [RITM]=1 [pretender]=1 [PCredz]=1 [ASRepCatcher]=1 )

# Маппинг пакетов, чей бинарник не совпадает с именем пакета: [пакет]="бинарник1,бинарник2"
declare -A KNOWN_BINARIES=(
    [impacket]="secretsdump.py,ntlmrelayx.py"
    [certipy]="certipy"
    [AD-Miner]="AD-Miner"
)

# ─── Вспомогательные функции ──────────────────────────────────────────────────

info()    { echo -e "${BLUE}[*]${NC} $*"; }
success() { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[-]${NC} $*"; }
header()  { echo -e "\n${CYAN}══════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════════${NC}"; }

cmd_exists() { command -v "$1" &>/dev/null; }

# Экранирует строку для безопасного использования в grep-regex
regex_escape() { printf '%s' "$1" | sed 's/[][\\.^$*+?{}()|]/\\&/g'; }

# Сравнивает два хеша коммитов: обрезает оба до длины более короткого
hashes_match() {
    local a="$1" b="$2"
    [[ -n "$a" && -n "$b" ]] || return 1
    local len=${#a}
    [[ ${#b} -lt $len ]] && len=${#b}
    [[ "${a:0:$len}" == "${b:0:$len}" ]]
}

# Проверяет, что Go-утилита установлена именно из ~/go/bin (а не системный омоним, например python-httpx на Kali)
is_go_tool() {
    local name="$1"
    local bin_path
    bin_path=$(command -v "$name" 2>/dev/null) || return 1
    [[ "$bin_path" == "$HOME/go/bin/"* ]]
}

needs_sudo() { [[ -v "SUDO_REQUIRED[$1]" ]]; }

# Оборачивает бинарник в sudo-обёртку: переименовывает оригинал в .name.orig
wrap_with_sudo() {
    local bin_path="$1" name="$2"
    if [ ! -f "$bin_path" ]; then
        warn "sudo-обёртка: файл не найден: ${bin_path}"
        return 0
    fi
    local orig="${bin_path}.orig"
    if [ -f "$orig" ]; then
        # .orig exists — check if bin_path is already our wrapper or a fresh binary (reinstall)
        if head -c2 "$bin_path" | grep -q '#!'; then
            return 0  # уже обёрнут
        fi
        # Свежий бинарник после переустановки — перезаписываем .orig
        mv "$bin_path" "$orig"
    else
        mv "$bin_path" "$orig"
    fi
    cat > "$bin_path" <<SUDO_EOF
#!/usr/bin/env bash
exec sudo "$orig" "\$@"
SUDO_EOF
    chmod +x "$bin_path"
    success "sudo-обёртка: ${bin_path}"
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

# Определяет, является ли ref коммитом (hex 40 символов полный или >= 8 символов с хотя бы одной буквой a-f)
is_commit_ref() {
    [[ ${#1} -eq 40 && "$1" =~ ^[0-9a-f]{40}$ ]] && return 0
    [[ ${#1} -ge 8 && "$1" =~ ^[0-9a-f]+$ && "$1" =~ [a-f] ]]
}

# Извлекает версию (ref) из записи UV_TOOLS
uv_tool_ref() {
    echo "$1" | cut -d'|' -f1
}

# Извлекает URL репозитория из записи UV_TOOLS
uv_tool_url() {
    echo "$1" | cut -d'|' -f2
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

# Извлекает GitHub repo URL из URL релиза/скачивания
# https://github.com/owner/repo/releases/download/... → https://github.com/owner/repo
github_repo_from_url() {
    echo "$1" | grep -oP 'https://github\.com/[^/]+/[^/]+' || true
}


# Клонирует репо. Использует --revision= (Git >= 2.49), иначе clone+checkout.
git_clone_at_revision() {
    local url="$1" dir="$2" commit="$3"
    if [ -n "$commit" ] && [ "${USE_REVISION:-false}" = true ]; then
        git clone --revision="$commit" "$url" "$dir"
    elif [ -n "$commit" ]; then
        git clone "$url" "$dir"
        git -C "$dir" checkout "$commit"
    else
        git clone "$url" "$dir"
    fi
}

# Проверяет, установлен ли инструмент через uv.
# Совпадение по имени бинарника ("- certipy") ИЛИ по имени пакета ("impacket v0.14"),
# т.к. имя пакета и бинарника могут не совпадать в обе стороны:
#   certipy-ad → бинарник certipy, impacket → бинарники secretsdump.py и т.д.
is_uv_tool_installed() {
    local name="$1"
    cmd_exists uv || return 1
    local uv_list
    uv_list=$(uv tool list 2>/dev/null) || return 1
    local ename
    ename=$(regex_escape "$name")
    echo "$uv_list" | grep -qi "^- ${ename}$" && return 0
    echo "$uv_list" | grep -qi "^${ename} " && return 0
    return 1
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

# ─── Проверка обновлений через git ls-remote (без локального репо) ────────────
#
# Один сетевой запрос на инструмент: git ls-remote $url HEAD 'refs/tags/*'
# Возвращает: up-to-date | new-commits:<HEAD> | new-tag:<тег> | new-tag:<тег>;new-commits:<HEAD> | error
check_remote_updates() {
    local repo_url="$1" pinned_ref="$2"

    # ── Единственный сетевой вызов: HEAD + все теги ──────────────────────────
    local all_refs
    all_refs=$(git ls-remote "$repo_url" HEAD 'refs/tags/*' 2>/dev/null) || { echo "error"; return; }

    local head_commit
    head_commit=$(awk '$2 == "HEAD" { print $1 }' <<< "$all_refs")
    if [ -z "$head_commit" ]; then
        echo "error"
        return
    fi

    # Извлекает коммит для конкретного тега (учитывает аннотированные через ^{})
    _tag_commit_from_refs() {
        local tag="$1"
        awk -v t="refs/tags/${tag}" -v d="refs/tags/${tag}^{}" \
            '$2 == t || $2 == d { last=$1 } END { print last }' <<< "$all_refs"
    }

    # Определяет последний версионный тег из кеша refs
    _latest_version_tag() {
        grep -oP 'refs/tags/\K[^\^{}]+$' <<< "$all_refs" \
            | grep -P '^v?[0-9]' \
            | while IFS= read -r t; do echo "${t#v} $t"; done \
            | sort -V -k1,1 \
            | tail -1 \
            | cut -d' ' -f2
    }

    if is_commit_ref "$pinned_ref"; then
        # Закреплён на коммит — проверяем HEAD и новые теги
        local parts=()
        local has_new_commits=false

        if ! hashes_match "$head_commit" "$pinned_ref"; then
            has_new_commits=true
        fi

        # Проверяем теги только если HEAD сдвинулся
        if $has_new_commits; then
            local latest_tag
            latest_tag=$(_latest_version_tag) || true
            if [ -n "$latest_tag" ]; then
                local tag_commit
                tag_commit=$(_tag_commit_from_refs "$latest_tag")
                if [ -n "$tag_commit" ] && [[ "$tag_commit" == "$head_commit" ]]; then
                    parts+=("new-tag:${latest_tag}")
                fi
            fi
            parts+=("new-commits:${head_commit:0:8}")
        fi

        if [ ${#parts[@]} -eq 0 ]; then
            echo "up-to-date"
        else
            local IFS=';'
            echo "${parts[*]}"
        fi
    else
        # Закреплён на тег — проверяем И новые теги, И новые коммиты
        local parts=()

        local latest_tag
        latest_tag=$(_latest_version_tag) || true
        if [ -n "$latest_tag" ]; then
            local norm_pinned="${pinned_ref#v}"
            local norm_latest="${latest_tag#v}"
            if [ "$norm_pinned" != "$norm_latest" ]; then
                parts+=("new-tag:${latest_tag}")
            fi
        fi

        local tag_commit
        tag_commit=$(_tag_commit_from_refs "$pinned_ref")
        if [ -n "$tag_commit" ] && [ "$tag_commit" != "$head_commit" ]; then
            parts+=("new-commits:${head_commit:0:8}")
        fi

        if [ ${#parts[@]} -eq 0 ]; then
            echo "up-to-date"
        else
            local IFS=';'
            echo "${parts[*]}"
        fi
    fi
}


# Неинтерактивный режим (--auto): пропускает все подтверждения
AUTO_MODE=false

# Запрос подтверждения VPN
confirm_vpn() {
    if [ "$AUTO_MODE" = true ]; then
        info "Автоматический режим: VPN-подтверждение пропущено"
        return 0
    fi
    warn "Для этого режима нужен VPN и доступ в сеть"
    echo ""
    read -rp "VPN включен? [y/N]: " vpn_answer
    if [[ ! "$vpn_answer" =~ ^[Yy]$ ]]; then
        error "Операция прервана. Включите VPN и запустите скрипт снова."
        exit 1
    fi
    echo ""
}

# ─── Skip-механизм ────────────────────────────────────────────────────────────

# Возвращает пропущенный коммит для инструмента (или пустую строку)
get_skip() {
    local name="$1"
    [ -f "$SKIP_FILE" ] || return 0
    local ename
    ename=$(regex_escape "$name")
    grep -m1 "^${ename}=" "$SKIP_FILE" 2>/dev/null | cut -d'=' -f2 || true
}

# Сохраняет коммит как пропущенный для инструмента
set_skip() {
    local name="$1" commit="$2"
    mkdir -p "$(dirname "$SKIP_FILE")"
    local ename
    ename=$(regex_escape "$name")
    # Удалить старую запись, добавить новую
    if [ -f "$SKIP_FILE" ]; then
        grep -v "^${ename}=" "$SKIP_FILE" > "${SKIP_FILE}.tmp" 2>/dev/null || true
        mv "${SKIP_FILE}.tmp" "$SKIP_FILE"
    fi
    echo "${name}=${commit}" >> "$SKIP_FILE"
}

# Удаляет skip для инструмента
clear_skip() {
    local name="$1"
    [ -f "$SKIP_FILE" ] || return 0
    local ename
    ename=$(regex_escape "$name")
    grep -v "^${ename}=" "$SKIP_FILE" > "${SKIP_FILE}.tmp" 2>/dev/null || true
    mv "${SKIP_FILE}.tmp" "$SKIP_FILE"
}

# Проверяет, пропущен ли данный remote HEAD для инструмента
is_skipped() {
    local name="$1" remote_head="$2"
    local skipped
    skipped=$(get_skip "$name")
    [ -n "$skipped" ] && hashes_match "$remote_head" "$skipped"
}

# ─── Remote Gist: pull / push ────────────────────────────────────────────────

GIST_PUSH_STAMP="$HOME/.local/share/prepare/.gist_push_ts"

# Скачивает skip-файл из Gist и полностью заменяет локальный
gist_pull() {
    [ -z "$SKIP_GIST_ID" ] && return 0

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
        content_file=$(mktemp)
        if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
content = data.get('files', {}).get(sys.argv[2], {}).get('content', '')
print(content, end='')
" "$tmp" "$SKIP_GIST_FILE" > "$content_file" 2>/dev/null; then
            mkdir -p "$(dirname "$SKIP_FILE")"
            mv "$content_file" "$SKIP_FILE"
            info "Skip-список загружен из Gist"
        else
            rm -f "$content_file"
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
    [ ! -f "$SKIP_FILE" ] && return 0

    # Без терминала — push невозможен
    if [ ! -t 0 ]; then
        warn "Нет терминала — skip-изменения сохранены только локально"
        return 0
    fi

    read -rsp "GitHub Token (scope: gist) для push в Gist (Enter — пропустить): " token
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
        date +%s > "$GIST_PUSH_STAMP"
    else
        error "Не удалось обновить Gist (HTTP $http_code)"
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
    header "Статус инструментов"
    info "Проверяется только наличие инструментов, не их версии."
    info "Для проверки версий используйте: $0 --check-updates"
    echo ""

    # ── Системные зависимости ─────────────────────────────────────────────────
    info "Системные зависимости"
    for dep in git curl wget python3; do
        if cmd_exists "$dep"; then
            echo -e "  ${GREEN}✓${NC} $dep ${DIM}$(command -v "$dep")${NC}"; count_ok
        else
            echo -e "  ${RED}✗${NC} $dep"; count_miss
        fi
    done
    for pkg in seclists libpcap-dev libkrb5-dev wmctrl; do
        if dpkg -s "$pkg" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $pkg ${DIM}(dpkg)${NC}"; count_ok
        else
            echo -e "  ${RED}✗${NC} $pkg"; count_miss
        fi
    done

    # ── Docker ─────────────────────────────────────────────────────────────
    echo ""
    info "Docker"
    if cmd_exists docker && docker --version &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} docker ${DIM}$(command -v docker)${NC}"; count_ok
    else
        echo -e "  ${RED}✗${NC} docker"; count_miss
    fi
    if cmd_exists docker && docker --version &>/dev/null && docker compose version &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} docker compose ${DIM}(docker compose version)${NC}"; count_ok
    else
        echo -e "  ${RED}✗${NC} docker compose"; count_miss
    fi

    # ── Go ────────────────────────────────────────────────────────────────────
    echo ""
    info "Go"
    if cmd_exists go; then
        echo -e "  ${GREEN}✓${NC} go ${DIM}$(command -v go)${NC}"; count_ok
    else
        echo -e "  ${RED}✗${NC} go"; count_miss
    fi

    # ── uv ────────────────────────────────────────────────────────────────────
    echo ""
    info "uv"
    if cmd_exists uv; then
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
                echo -e "  ${YELLOW}~${NC} $name ${DIM}(pipx/apt — не uv)${NC}"; count_miss ;;
            system)
                echo -e "  ${YELLOW}~${NC} $name ${DIM}(системный — не uv)${NC}"; count_miss ;;
            *)
                echo -e "  ${RED}✗${NC} $name"; count_miss ;;
        esac
    done

    # ── Бинарные утилиты ──────────────────────────────────────────────────────
    echo ""
    info "Бинарные утилиты"
    for name in "${!BINARY_TOOLS[@]}"; do
        if cmd_exists "$name"; then
            echo -e "  ${GREEN}✓${NC} $name ${DIM}$(command -v "$name")${NC}"; count_ok
        else
            echo -e "  ${RED}✗${NC} $name"; count_miss
        fi
    done

    # ── Chisel ────────────────────────────────────────────────────────────────
    echo ""
    info "Chisel"
    if [ -x "${TOOLS_DIR}/chisel/chisel" ]; then
        echo -e "  ${GREEN}✓${NC} chisel ${DIM}${TOOLS_DIR}/chisel/chisel${NC}"; count_ok
    else
        echo -e "  ${RED}✗${NC} chisel"; count_miss
    fi

    # ── Git-репозитории ───────────────────────────────────────────────────────
    echo ""
    info "Git-репозитории (~/tools)"
    for name in "${!GIT_REPOS[@]}"; do
        local dir="${TOOLS_DIR}/${name}"
        if [ -d "$dir/.git" ]; then
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
        if [ -d "$dir/.git" ]; then
            local extras=""
            [ -d "${dir}/.venv" ]        && extras+=" [venv ✓]" || extras+=" ${YELLOW}[venv ✗]${NC}"
            [ -x "${LOCAL_BIN}/${name}" ] && extras+=" [wrapper ✓]" || extras+=" ${YELLOW}[wrapper ✗]${NC}"
            echo -e "  ${GREEN}✓${NC} $name ${DIM}${dir}${NC}${extras}"; count_ok
        else
            echo -e "  ${RED}✗${NC} $name"; count_miss
        fi
    done

    # ── Windows-утилиты ───────────────────────────────────────────────────────
    echo ""
    info "Windows-утилиты (~/tools/for_windows)"
    for name in "${!WIN_TOOLS[@]}"; do
        if [ -f "${TOOLS_DIR}/for_windows/${name}" ]; then
            echo -e "  ${GREEN}✓${NC} $name ${DIM}${TOOLS_DIR}/for_windows/${name}${NC}"; count_ok
        else
            echo -e "  ${RED}✗${NC} $name"; count_miss
        fi
    done

    print_summary

    if [ "$COUNT_MISSING" -gt 0 ] || [ "$COUNT_WARN" -gt 0 ]; then
        echo ""
        info "Установить отсутствующее:   $0 --install"
        info "Проверить обновления:       $0 --check-updates"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  --check-updates: проверка новых версий относительно версий в скрипте
#                   (через git ls-remote, без зависимости от локальных репо)
# ═══════════════════════════════════════════════════════════════════════════════

# Отображает результат проверки обновления для одного инструмента.
# Аргументы: name display_ver icon_ok icon_update result
#   icon_ok     — иконка для статуса «актуально» (✓ / ~ / ✗)
#   icon_update — иконка для статуса «есть обновления» (↑ / тот же icon_ok)
display_update_result() {
    local name="$1" dv="$2" icon_ok="$3" icon_upd="$4" result="$5"

    case "$result" in
        up-to-date)
            echo -e "  ${icon_ok} $name ($dv) ${GREEN}(актуально)${NC}"
            ;;
        error)
            echo -e "  ${icon_ok} $name ($dv) ${YELLOW}(не удалось проверить)${NC}"
            ;;
        *)
            local remote_head=""
            if [[ "$result" == *"new-commits:"* ]]; then
                remote_head="${result#*new-commits:}"
                remote_head="${remote_head%%;*}"
            fi

            if [ -n "$remote_head" ] && is_skipped "$name" "$remote_head"; then
                echo -e "  ${icon_ok} $name ($dv) ${GREEN}(актуально)${NC} ${GRAY}(пропущено: ${remote_head})${NC}"
            else
                local line="  ${icon_upd} $name ($dv)"
                if [[ "$result" == *"new-tag:"* ]]; then
                    local tag="${result#*new-tag:}"
                    tag="${tag%%;*}"
                    line+=" ${CYAN}→ новый тег: ${tag}${NC}"
                fi
                if [ -n "$remote_head" ]; then
                    line+=" ${CYAN}→ новые коммиты (HEAD: ${remote_head})${NC}"
                fi
                echo -e "$line"
            fi
            ;;
    esac
}

cmd_check_updates() {
    header "Проверка обновлений (remote)"
    confirm_vpn
    gist_pull

    # ── Фаза 1: параллельный запрос всех remote ─────────────────────────────
    local _chk_dir
    _chk_dir=$(mktemp -d)
    trap "rm -rf '$_chk_dir'" EXIT

    info "Запрос remote (параллельно)..."

    # uv tools
    for name in "${!UV_TOOLS[@]}"; do
        local ref repo_url
        ref=$(uv_tool_ref "${UV_TOOLS[$name]}")
        repo_url=$(uv_tool_url "${UV_TOOLS[$name]}")
        ( check_remote_updates "$repo_url" "$ref" > "${_chk_dir}/uv_${name}" ) &
    done

    # Git-репозитории
    for name in "${!GIT_REPOS[@]}"; do
        local url commit
        url=$(echo "${GIT_REPOS[$name]}" | cut -d'|' -f1)
        commit=$(echo "${GIT_REPOS[$name]}" | cut -d'|' -f2)
        ( check_remote_updates "$url" "$commit" > "${_chk_dir}/git_${name}" ) &
    done

    # Venv-репозитории
    for name in "${!VENV_REPOS[@]}"; do
        local url commit
        url=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f1)
        commit=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f2)
        ( check_remote_updates "$url" "$commit" > "${_chk_dir}/venv_${name}" ) &
    done

    # Бинарные утилиты
    for name in "${!BINARY_TOOLS[@]}"; do
        local pinned repo_url
        pinned=$(binary_tool_version "${BINARY_TOOLS[$name]}")
        repo_url=$(github_repo_from_url "$(binary_tool_url "${BINARY_TOOLS[$name]}")")
        if [ -n "$repo_url" ]; then
            ( check_remote_updates "$repo_url" "$pinned" > "${_chk_dir}/bin_${name}" ) &
        fi
    done

    # Chisel
    ( check_remote_updates "https://github.com/jpillora/chisel" "v${CHISEL_VERSION}" \
        > "${_chk_dir}/chisel" ) &

    # Windows-утилиты
    for name in "${!WIN_TOOLS[@]}"; do
        local url repo_url pinned
        url="${WIN_TOOLS[$name]}"
        repo_url=$(github_repo_from_url "$url")
        pinned=$(echo "$url" | grep -oP '/download/\K[^/]+' || true)
        if [ -n "$repo_url" ]; then
            ( check_remote_updates "$repo_url" "$pinned" > "${_chk_dir}/win_${name}" ) &
        fi
    done

    # Go
    ( git ls-remote --tags https://go.googlesource.com/go 2>/dev/null \
        | grep -oP 'refs/tags/go\K[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V | tail -1 > "${_chk_dir}/go_latest" ) &

    wait
    info "Готово."

    # ── Фаза 2: отображение результатов ──────────────────────────────────────
    local _icon_ok _icon_upd _result

    # ── uv tools
    echo ""
    info "uv tools"
    for name in "${!UV_TOOLS[@]}"; do
        local dv src
        dv=$(uv_tool_display_version "${UV_TOOLS[$name]}")
        src=$(uv_tool_source "$name")
        case "$src" in
            uv)          _icon_ok="${GREEN}✓${NC}" ;;
            pipx|system) _icon_ok="${YELLOW}~${NC}" ;;
            *)           _icon_ok="${RED}✗${NC}" ;;
        esac
        _result=$(cat "${_chk_dir}/uv_${name}" 2>/dev/null) || _result="error"
        display_update_result "$name" "$dv" "$_icon_ok" "$_icon_ok" "$_result"
    done

    # ── Git-репозитории
    echo ""
    info "Git-репозитории"
    for name in "${!GIT_REPOS[@]}"; do
        local expected_commit
        expected_commit=$(echo "${GIT_REPOS[$name]}" | cut -d'|' -f2)
        _result=$(cat "${_chk_dir}/git_${name}" 2>/dev/null) || _result="error"
        display_update_result "$name" "${expected_commit:0:8}" "${GREEN}✓${NC}" "${CYAN}↑${NC}" "$_result"
    done

    # ── Venv-репозитории
    echo ""
    info "Venv-репозитории"
    for name in "${!VENV_REPOS[@]}"; do
        local expected_commit
        expected_commit=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f2)
        _result=$(cat "${_chk_dir}/venv_${name}" 2>/dev/null) || _result="error"
        display_update_result "$name" "${expected_commit:0:8}" "${GREEN}✓${NC}" "${CYAN}↑${NC}" "$_result"
    done

    # ── Бинарные утилиты
    echo ""
    info "Бинарные утилиты"
    for name in "${!BINARY_TOOLS[@]}"; do
        local pinned repo_url
        pinned=$(binary_tool_version "${BINARY_TOOLS[$name]}")
        repo_url=$(github_repo_from_url "$(binary_tool_url "${BINARY_TOOLS[$name]}")")
        if [ -z "$repo_url" ]; then
            echo -e "  ${YELLOW}?${NC} $name ($pinned) (не удалось определить репозиторий)"
            continue
        fi
        _result=$(cat "${_chk_dir}/bin_${name}" 2>/dev/null) || _result="error"
        display_update_result "$name" "$pinned" "${GREEN}✓${NC}" "${CYAN}↑${NC}" "$_result"
    done

    # ── Chisel
    echo ""
    info "Chisel"
    _result=$(cat "${_chk_dir}/chisel" 2>/dev/null) || _result="error"
    display_update_result "chisel" "$CHISEL_VERSION" "${GREEN}✓${NC}" "${CYAN}↑${NC}" "$_result"

    # ── Windows-утилиты
    echo ""
    info "Windows-утилиты"
    for name in "${!WIN_TOOLS[@]}"; do
        local url repo_url pinned
        url="${WIN_TOOLS[$name]}"
        repo_url=$(github_repo_from_url "$url")
        if [ -z "$repo_url" ]; then
            echo -e "  ${YELLOW}?${NC} $name (не удалось определить репозиторий)"
            continue
        fi
        pinned=$(echo "$url" | grep -oP '/download/\K[^/]+' || true)
        _result=$(cat "${_chk_dir}/win_${name}" 2>/dev/null) || _result="error"
        display_update_result "$name" "$pinned" "${GREEN}✓${NC}" "${CYAN}↑${NC}" "$_result"
    done

    # ── Go
    echo ""
    info "Go"
    local latest_go
    latest_go=$(cat "${_chk_dir}/go_latest" 2>/dev/null)
    if [ -n "$latest_go" ]; then
        if [ "$latest_go" = "$GO_VERSION" ]; then
            echo -e "  ${GREEN}✓${NC} go $GO_VERSION (актуально)"
        else
            echo -e "  ${CYAN}↑${NC} go $GO_VERSION ${CYAN}→ доступна: $latest_go${NC}"
        fi
    else
        echo -e "  ${YELLOW}?${NC} не удалось проверить"
    fi

    echo ""
    info "Чтобы обновить версии — измените конфигурацию в начале скрипта,"
    info "затем запустите:  $0 --install"
    info "Пропустить обновление:  $0 --skip <имя_инструмента>"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  --skip <tool>: пропустить текущее обновление для инструмента
# ═══════════════════════════════════════════════════════════════════════════════

cmd_skip() {
    local name="$1"
    gist_pull

    # Найти repo URL для инструмента
    local repo_url=""
    if [[ -v "UV_TOOLS[$name]" ]]; then
        repo_url=$(uv_tool_url "${UV_TOOLS[$name]}")
    elif [[ -v "GIT_REPOS[$name]" ]]; then
        repo_url=$(echo "${GIT_REPOS[$name]}" | cut -d'|' -f1)
    elif [[ -v "VENV_REPOS[$name]" ]]; then
        repo_url=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f1)
    elif [[ -v "BINARY_TOOLS[$name]" ]]; then
        repo_url=$(github_repo_from_url "$(binary_tool_url "${BINARY_TOOLS[$name]}")")
    elif [[ -v "WIN_TOOLS[$name]" ]]; then
        repo_url=$(github_repo_from_url "${WIN_TOOLS[$name]}")
    elif [[ "$name" == "chisel" ]]; then
        repo_url="https://github.com/jpillora/chisel"
    else
        error "Инструмент '$name' не найден в конфигурации"
        exit 1
    fi

    local head_commit
    head_commit=$(git ls-remote "$repo_url" HEAD 2>/dev/null | awk '$2 == "HEAD" {print $1}')
    if [ -z "$head_commit" ]; then
        error "Не удалось получить HEAD для $name ($repo_url)"
        exit 1
    fi

    set_skip "$name" "$head_commit"
    success "Пропущен $name (HEAD: ${head_commit:0:8})"
    info "Следующие обновления после ${head_commit:0:8} будут отображаться"
    info "Отменить: $0 --unskip $name"
    gist_push
}

# ═══════════════════════════════════════════════════════════════════════════════
#  --unskip <tool>: убрать пропуск для инструмента
# ═══════════════════════════════════════════════════════════════════════════════

cmd_unskip() {
    local name="$1"
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
#  --skip-list: показать все пропущенные обновления
# ═══════════════════════════════════════════════════════════════════════════════

cmd_skip_list() {
    header "Пропущенные обновления"
    if [ ! -f "$SKIP_FILE" ] || [ ! -s "$SKIP_FILE" ]; then
        info "Нет пропущенных обновлений"
        return
    fi
    while IFS='=' read -r name commit; do
        [ -z "$name" ] && continue
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
    if [ ! -f "$SKIP_FILE" ] || [ ! -s "$SKIP_FILE" ]; then
        error "Нет пропущенных обновлений для экспорта"
        exit 1
    fi
    cat "$SKIP_FILE"
}

cmd_skip_import() {
    local input="${1:--}"  # файл или "-" (stdin)
    local count=0

    mkdir -p "$(dirname "$SKIP_FILE")"

    while IFS='=' read -r name commit; do
        # пропускаем пустые строки и комментарии
        [[ -z "$name" || "$name" == \#* ]] && continue
        set_skip "$name" "$commit"
        count=$((count + 1))
    done < <(if [ "$input" = "-" ]; then cat; else cat "$input"; fi)

    success "Импортировано записей: $count"
    info "Проверить: $0 --skip-list"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  --install: установка отсутствующих инструментов (без обновления имеющихся)
# ═══════════════════════════════════════════════════════════════════════════════

cmd_install() {

    # ── Логирование ───────────────────────────────────────────────────────────
    mkdir -p "$LOG_DIR"
    LOG_FILE="${LOG_DIR}/install_$(date '+%Y-%m-%d_%H-%M-%S').log"
    exec > >(tee -a "$LOG_FILE") 2>&1
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
    trap "kill $SUDO_KEEPALIVE_PID 2>/dev/null" EXIT

    confirm_vpn

    # ── 1. apt (обновляем Git в первую очередь для --revision) ────────────────
    header "Системные пакеты (apt)"
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" git curl wget python3-pip libpcap-dev libkrb5-dev seclists wmctrl

    # ── 1.1 Docker ─────────────────────────────────────────────────────────
    header "Docker"
    if cmd_exists docker && docker --version &>/dev/null; then
        success "docker уже установлен"
    else
        info "Установка docker.io и docker-compose..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" docker.io docker-compose
        sudo systemctl enable docker --now
        success "Docker установлен и запущен"
    fi
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
    header "uv"
    if cmd_exists uv; then
        success "uv уже установлен: $(uv --version 2>/dev/null)"
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
    header "Go ${GO_VERSION}"
    if cmd_exists go; then
        local current_go
        current_go=$(go version | grep -oP 'go\K[0-9.]+')
        if [ "$current_go" = "$GO_VERSION" ]; then
            success "Go ${GO_VERSION} уже установлен"
        else
            warn "Go ${current_go} установлен (ожидается ${GO_VERSION})"
        fi
    else
        info "Установка Go ${GO_VERSION}..."
        local go_archive="go${GO_VERSION}.linux-amd64.tar.gz"
        wget -q "https://go.dev/dl/${go_archive}" -O "/tmp/${go_archive}"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "/tmp/${go_archive}"
        rm -f "/tmp/${go_archive}"
        success "Go ${GO_VERSION} установлен"
    fi
    ensure_path_entry "/usr/local/go/bin"
    ensure_path_entry "$HOME/go/bin"

    # ── 4. Директории ─────────────────────────────────────────────────────────
    mkdir -p "$TOOLS_DIR" "$LOCAL_BIN" "${TOOLS_DIR}/for_windows"

    # ── 5. Go-утилиты ─────────────────────────────────────────────────────────
    header "Go-утилиты"
    for name in "${!GO_TOOLS[@]}"; do
        if is_go_tool "$name"; then
            success "$name уже установлен"
        else
            info "Установка $name..."
            go install -v "${GO_TOOLS[$name]}"
            success "$name установлен"
        fi
    done

    # ── 6. Git-репозитории ────────────────────────────────────────────────────
    header "Git-репозитории (~/tools)"
    for name in "${!GIT_REPOS[@]}"; do
        local url commit
        url=$(echo "${GIT_REPOS[$name]}" | cut -d'|' -f1)
        commit=$(echo "${GIT_REPOS[$name]}" | cut -d'|' -f2)
        local dir="${TOOLS_DIR}/${name}"

        if [ -d "$dir/.git" ]; then
            success "$name уже клонирован"
            if [ -n "$commit" ]; then
                local current
                current=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
                if ! hashes_match "$current" "$commit"; then
                    warn "$name: коммит отличается от ${commit:0:8} (установлен: ${current:0:8})"
                fi
            fi
        else
            info "Клонирование $name..."
            git_clone_at_revision "$url" "$dir" "$commit"
            success "$name клонирован"
        fi
    done

    # ── 7. Chisel ─────────────────────────────────────────────────────────────
    header "Chisel v${CHISEL_VERSION}"
    local chisel_dir="${TOOLS_DIR}/chisel"
    mkdir -p "$chisel_dir"
    if [ -x "${chisel_dir}/chisel" ]; then
        success "chisel уже установлен"
    else
        info "Скачивание chisel..."
        wget -q "$CHISEL_URL" -O "${chisel_dir}/chisel.gz"
        gunzip "${chisel_dir}/chisel.gz"
        chmod +x "${chisel_dir}/chisel"
        success "chisel → ${chisel_dir}/chisel"
    fi

    # ── 8. uv tools ──────────────────────────────────────────────────────────
    header "uv tool install (Python-утилиты)"
    for name in "${!UV_TOOLS[@]}"; do
        local ref repo_url dv source
        ref=$(uv_tool_ref "${UV_TOOLS[$name]}")
        repo_url=$(uv_tool_url "${UV_TOOLS[$name]}")
        dv=$(uv_tool_display_version "${UV_TOOLS[$name]}")
        source="git+${repo_url}@${ref}"

        if is_uv_tool_installed "$name"; then
            success "$name уже установлен через uv ($dv)"
            continue
        fi

        # Проверка: инструмент есть в системе, но не через uv (apt/pipx и т.п.)
        local src
        src=$(uv_tool_source "$name")
        if [[ "$src" == "pipx" || "$src" == "system" ]]; then
            local sys_bin
            sys_bin=$(command -v "$name" 2>/dev/null) || true
            if [ "$AUTO_MODE" = true ]; then
                warn "$name установлен не через uv ($sys_bin), используется как есть"
                continue
            else
                warn "$name найден в системе: $sys_bin (источник: $src)"
                warn "Рекомендуется установить через uv для единообразного управления версиями"
                read -rp "Установить $name через uv (--force)? [y/N]: " replace_answer
                if [[ ! "$replace_answer" =~ ^[Yy]$ ]]; then
                    info "Пропуск $name"
                    continue
                fi
            fi
        fi

        info "Установка $name ($dv)..."
        if uv tool install --force "$source"; then
            success "$name установлен через uv"
        else
            error "Не удалось установить $name"
        fi

        # sudo-обёртка (если требуется)
        if needs_sudo "$name"; then
            local cmd_path="${LOCAL_BIN}/${name}"
            # uv может создать бинарник в lowercase
            if [ ! -f "$cmd_path" ]; then
                cmd_path="${LOCAL_BIN}/$(echo "$name" | tr '[:upper:]' '[:lower:]')"
            fi
            wrap_with_sudo "$cmd_path" "$name"
        fi
    done

    # ── 9. Бинарные утилиты ──────────────────────────────────────────────────
    header "Бинарные утилиты (→ ~/.local/bin)"
    for name in "${!BINARY_TOOLS[@]}"; do
        if cmd_exists "$name"; then
            local ev
            ev=$(binary_tool_version "${BINARY_TOOLS[$name]}")
            success "$name уже установлен ($ev)"
            # Проверяем sudo-обёртку для уже установленных
            if needs_sudo "$name"; then
                wrap_with_sudo "${LOCAL_BIN}/${name}" "$name"
            fi
            continue
        fi

        local ev url archive_type bin_path
        ev=$(binary_tool_version "${BINARY_TOOLS[$name]}")
        url=$(binary_tool_url "${BINARY_TOOLS[$name]}")
        archive_type=$(binary_tool_type "${BINARY_TOOLS[$name]}")
        bin_path=$(binary_tool_path "${BINARY_TOOLS[$name]}")

        local tmpdir
        tmpdir=$(mktemp -d)
        info "Установка $name ($ev)..."

        case "$archive_type" in
            tar.gz)
                wget -q "$url" -O "${tmpdir}/archive.tar.gz"
                tar -xzf "${tmpdir}/archive.tar.gz" -C "$tmpdir"
                cp "${tmpdir}/${bin_path}" "${LOCAL_BIN}/${name}"
                ;;
            gz)
                wget -q "$url" -O "${tmpdir}/${name}.gz"
                gunzip "${tmpdir}/${name}.gz"
                cp "${tmpdir}/${name}" "${LOCAL_BIN}/${name}"
                ;;
            binary)
                wget -q "$url" -O "${LOCAL_BIN}/${name}"
                ;;
        esac

        chmod +x "${LOCAL_BIN}/${name}"
        rm -rf "$tmpdir"
        success "$name → ${LOCAL_BIN}/${name}"

        # sudo-обёртка (если требуется)
        if needs_sudo "$name"; then
            wrap_with_sudo "${LOCAL_BIN}/${name}" "$name"
        fi
    done

    # ── 10. Venv-репозитории ─────────────────────────────────────────────────
    header "Venv-репозитории (~/tools + обёртки)"
    for name in "${!VENV_REPOS[@]}"; do
        local url commit entrypoint extra_deps
        url=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f1)
        commit=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f2)
        entrypoint=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f3)
        extra_deps=$(echo "${VENV_REPOS[$name]}" | cut -d'|' -f4)
        local dir="${TOOLS_DIR}/${name}"

        # Клонирование
        if [ -d "$dir/.git" ]; then
            success "$name уже клонирован"
            if [ -n "$commit" ]; then
                local current
                current=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
                if ! hashes_match "$current" "$commit"; then
                    warn "$name: коммит отличается от ${commit:0:8} (установлен: ${current:0:8})"
                fi
            fi
        else
            info "Клонирование $name..."
            git_clone_at_revision "$url" "$dir" "$commit"
            success "$name клонирован"
        fi

        # venv + зависимости
        if [ ! -d "${dir}/.venv" ]; then
            info "Создание venv для $name..."
            uv venv "${dir}/.venv"
            if [ -f "${dir}/requirements.txt" ]; then
                VIRTUAL_ENV="${dir}/.venv" uv pip install -r "${dir}/requirements.txt"
            fi
            if [ -n "$extra_deps" ]; then
                local IFS=','
                for dep in $extra_deps; do
                    VIRTUAL_ENV="${dir}/.venv" uv pip install "$dep"
                done
                unset IFS
            fi
            success "venv для $name настроен"
        else
            success "venv для $name уже существует"
        fi

        # Обёртка в ~/.local/bin
        local wrapper="${LOCAL_BIN}/${name}"
        if [ ! -x "$wrapper" ]; then
            if needs_sudo "$name"; then
                cat > "$wrapper" <<WRAPPER_EOF
#!/usr/bin/env bash
# Обёртка для $name (требует sudo)
exec sudo "${dir}/.venv/bin/python" "${dir}/${entrypoint}" "\$@"
WRAPPER_EOF
            else
                cat > "$wrapper" <<WRAPPER_EOF
#!/usr/bin/env bash
# Обёртка для $name — запуск из любой директории
exec "${dir}/.venv/bin/python" "${dir}/${entrypoint}" "\$@"
WRAPPER_EOF
            fi
            chmod +x "$wrapper"
            success "Обёртка: ${wrapper}"
        else
            success "Обёртка $name уже существует"
        fi
    done

    # ── 11. Windows-утилиты ──────────────────────────────────────────────────
    header "Windows-утилиты (~/tools/for_windows)"
    for name in "${!WIN_TOOLS[@]}"; do
        local dest="${TOOLS_DIR}/for_windows/${name}"
        if [ -f "$dest" ]; then
            success "$name уже скачан"
        else
            info "Скачивание $name..."
            wget -q "${WIN_TOOLS[$name]}" -O "$dest"
            success "$name → $dest"
        fi
    done

    # ── 12. Шаблоны Nuclei ──────────────────────────────────────────────────
    header "Шаблоны Nuclei"
    if cmd_exists nuclei; then
        info "Обновление шаблонов nuclei..."
        nuclei -update-templates -update-template-dir "${TOOLS_DIR}/nuclei-templates" 2>/dev/null || warn "Не удалось обновить шаблоны nuclei"
    fi

    # ── 13. BloodHound (через bloodhound-automation) ─────────────────────────
    header "BloodHound (bloodhound-automation)"
    local bha_dir="${TOOLS_DIR}/bloodhound-automation"
    local bha_venv="${bha_dir}/.venv/bin/python"
    local bha_script="${bha_dir}/bloodhound-automation.py"
    if [ -x "$bha_venv" ] && [ -f "$bha_script" ]; then
        # Увеличиваем таймауты healthcheck для Neo4j в шаблоне:
        # плагин graph-data-science (~250 МБ) скачивается при первом запуске,
        # стандартных 80 с (start_period 30 + 5×10) недостаточно.
        local bha_tpl="${bha_dir}/templates/docker-compose.yml"
        if [ -f "$bha_tpl" ]; then
            sed -i '/^  graph-db:/,/^  [a-z]/ {
                s/retries: 5/retries: 10/
                s/start_period: 30s/start_period: 120s/
            }' "$bha_tpl"
        fi
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
        if run_bha list 2>/dev/null | grep -q 'my_project'; then
            success "Проект my_project уже существует"
        else
            info "Запуск bloodhound-automation start my_project (может занять длительное время)..."
            run_bha start my_project -t 1200
            success "BloodHound установлен (проект my_project)"
        fi
    else
        warn "bloodhound-automation не установлен, пропуск"
    fi

    # ── Готово ────────────────────────────────────────────────────────────────
    header "Установка завершена!"
    echo ""
    info "Перезагрузите оболочку или выполните:"
    echo -e "  ${CYAN}source ~/.bashrc${NC}  или  ${CYAN}source ~/.zshrc${NC}"
    echo ""
    info "Проверка статуса:      $0"
    info "Проверка обновлений:   $0 --check-updates"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Точка входа
# ═══════════════════════════════════════════════════════════════════════════════

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
        echo "  $0 --auto           — полностью автоматическая установка без вопросов (для curl | bash)"
        echo "  $0 --check-updates  — проверить наличие новых версий относительно заданных в скрипте (рекомендуется VPN)"
        echo "  $0 --install        — установить отсутствующие инструменты (нужен VPN)"
        echo "  $0 --skip <имя>     — пропустить текущее обновление для инструмента"
        echo "  $0 --unskip <имя>   — отменить пропуск обновления"
        echo "  $0 --skip-list      — показать пропущенные обновления"
        echo "  $0 --skip-export    — экспорт пропусков в stdout"
        echo "  $0 --skip-import <файл>  — импорт пропусков из файла (или stdin)"
        echo "  $0 --help           — эта справка"
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
