#!/usr/bin/env bash
# ==============================================================================
#  X-UI SANAEI MANAGEMENT PANEL - پنل مدیریت X-UI سنایی
#  Version: 3.0.0
#  Author:  DevOps Expert Panel
#  License: MIT
#  Target:  Ubuntu 20.04 / 22.04 / 24.04
# ==============================================================================
set -euo pipefail
IFS=$'\n\t'

# ─── STRICT ROOT CHECK ────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[1;31m[خطا] این اسکریپت باید با دسترسی root اجرا شود.\033[0m"
    echo -e "\033[1;33m  sudo bash $0\033[0m"
    exit 1
fi

# ==============================================================================
# SECTION 1: GLOBAL CONSTANTS & CONFIGURATION
# ==============================================================================

readonly PANEL_VERSION="3.0.0"
readonly PANEL_NAME="پنل مدیریت X-UI سنایی"
readonly SCRIPT_PATH="$(realpath "$0")"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly LOG_FILE="/var/log/xui-panel.log"
readonly CONFIG_FILE="/etc/xui-panel/config.env"
readonly BACKUP_DIR="/var/backups/xui-panel"
readonly SUBSCRIPTION_DIR="/var/www/xui-subs"
readonly ACME_DIR="/root/.acme.sh"

# X-UI Paths (Sanaei Fork)
readonly XUI_DB="/etc/x-ui/x-ui.db"
readonly XUI_CONFIG="/etc/x-ui/config.json"
readonly XUI_BIN="/usr/local/x-ui/x-ui"
readonly XUI_SERVICE="x-ui"

# GitHub for self-update
readonly GITHUB_REPO="https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main/xui-panel.sh"

# Cloudflare Clean IP defaults (well-known ranges)
readonly -a CF_CLEAN_IPS=(
    "104.16.0.0"
    "104.17.0.0"
    "104.18.0.0"
    "104.19.0.0"
    "104.20.0.0"
    "172.64.0.0"
    "172.65.0.0"
    "162.158.0.0"
    "188.114.96.0"
    "188.114.97.0"
)

# SNI whitelist for CDN configs
readonly -a DEFAULT_SNIS=(
    "www.speedtest.net"
    "www.cloudflare.com"
    "discord.com"
    "telegram.org"
    "www.google.com"
    "cdn.jsdelivr.net"
    "cdnjs.cloudflare.com"
    "ajax.googleapis.com"
)

# ==============================================================================
# SECTION 2: ANSI COLOR PALETTE
# ==============================================================================

# Reset
R="\033[0m"
# Bold
B="\033[1m"
# Colors
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"
# Dim
DIM="\033[2m"
# Background
BG_RED="\033[41m"
BG_GREEN="\033[42m"
BG_BLUE="\033[44m"
BG_MAGENTA="\033[45m"
BG_CYAN="\033[46m"

# ==============================================================================
# SECTION 3: LOGGING ENGINE
# ==============================================================================

log_info()    { echo -e "${GREEN}[INFO]${R}  $*" | tee -a "$LOG_FILE"; }
log_warn()    { echo -e "${YELLOW}[هشدار]${R} $*" | tee -a "$LOG_FILE"; }
log_error()   { echo -e "${RED}[خطا]${R}  $*" | tee -a "$LOG_FILE"; }
log_debug()   { echo -e "${DIM}[DEBUG] $*${R}" >> "$LOG_FILE"; }
log_success() { echo -e "${GREEN}${B}[✓]${R} ${GREEN}$*${R}" | tee -a "$LOG_FILE"; }

# ==============================================================================
# SECTION 4: TUI DRAWING FUNCTIONS
# ==============================================================================

get_terminal_width() {
    tput cols 2>/dev/null || echo 80
}

draw_line() {
    local char="${1:-─}"
    local color="${2:-$CYAN}"
    local width
    width=$(get_terminal_width)
    echo -e "${color}$(printf "%${width}s" | tr ' ' "$char")${R}"
}

draw_double_line() {
    draw_line "═" "$MAGENTA"
}

draw_header() {
    local title="$1"
    local subtitle="${2:-}"
    local width
    width=$(get_terminal_width)
    local inner=$((width - 4))

    clear
    echo ""
    draw_double_line
    printf "${MAGENTA}║${R}%*s${MAGENTA}║${R}\n" "$((width - 2))" ""
    # Center the title
    local title_len=${#title}
    local pad_left=$(( (inner - title_len) / 2 ))
    local pad_right=$(( inner - title_len - pad_left ))
    printf "${MAGENTA}║${R}  ${B}${CYAN}%*s%s%*s${R}  ${MAGENTA}║${R}\n" \
        "$pad_left" "" "$title" "$pad_right" ""
    if [[ -n "$subtitle" ]]; then
        local sub_len=${#subtitle}
        local sub_pad_left=$(( (inner - sub_len) / 2 ))
        local sub_pad_right=$(( inner - sub_len - sub_pad_left ))
        printf "${MAGENTA}║${R}  ${DIM}%*s%s%*s${R}  ${MAGENTA}║${R}\n" \
            "$sub_pad_left" "" "$subtitle" "$sub_pad_right" ""
    fi
    printf "${MAGENTA}║${R}%*s${MAGENTA}║${R}\n" "$((width - 2))" ""
    draw_double_line
    echo ""
}

draw_section() {
    local title="$1"
    echo ""
    echo -e "${CYAN}┌─ ${B}${WHITE}${title}${R} ${CYAN}$(printf '%0.s─' $(seq 1 $(($(get_terminal_width) - ${#title} - 5))))${R}"
}

draw_menu_item() {
    local num="$1"
    local icon="$2"
    local label="$3"
    local desc="${4:-}"
    printf "  ${CYAN}│${R}  ${BG_BLUE}${WHITE} %2s ${R}  ${icon}  ${B}${WHITE}%-35s${R}  ${DIM}%s${R}\n" \
        "$num" "$label" "$desc"
}

draw_menu_item_warn() {
    local num="$1"
    local icon="$2"
    local label="$3"
    local desc="${4:-}"
    printf "  ${CYAN}│${R}  ${BG_RED}${WHITE} %2s ${R}  ${icon}  ${B}${RED}%-35s${R}  ${DIM}%s${R}\n" \
        "$num" "$label" "$desc"
}

draw_menu_footer() {
    echo -e "  ${CYAN}└$(printf '%0.s─' $(seq 1 $(($(get_terminal_width) - 4))))${R}"
    echo ""
}

draw_status_bar() {
    local server_ip panel_port xui_status panel_version_str
    server_ip=$(get_public_ip)
    panel_port=$(get_xui_port)
    xui_status=$(systemctl is-active x-ui 2>/dev/null || echo "غیرفعال")

    local status_color="$GREEN"
    [[ "$xui_status" != "active" ]] && status_color="$RED"

    draw_line "─" "$DIM"
    printf "  ${DIM}🌐 IP: ${WHITE}%-20s${R}  " "$server_ip"
    printf "${DIM}🔌 پورت: ${WHITE}%-8s${R}  "  "$panel_port"
    printf "${DIM}⚡ X-UI: ${status_color}%-10s${R}  " "$xui_status"
    printf "${DIM}📦 نسخه پنل: ${WHITE}%s${R}\n"   "$PANEL_VERSION"
    draw_line "─" "$DIM"
}

show_spinner() {
    local pid=$1
    local msg="${2:-در حال پردازش...}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        local c="${spin:$((i % ${#spin})):1}"
        printf "\r  ${CYAN}${c}${R}  ${DIM}${msg}${R}"
        sleep 0.1
        ((i++))
    done
    printf "\r  ${GREEN}✓${R}  ${msg}\n"
}

press_enter() {
    echo ""
    echo -e "  ${DIM}[ برای بازگشت به منو، Enter را بفشارید... ]${R}"
    read -r
}

confirm_action() {
    local msg="$1"
    echo -e "\n  ${YELLOW}⚠  ${msg}${R}"
    echo -ne "  ${B}تایید؟ (بله/خیر): ${R}"
    read -r answer
    [[ "$answer" =~ ^(بله|yes|y|Y)$ ]]
}

prompt_input() {
    local label="$1"
    local default="${2:-}"
    local var_ref="$3"
    if [[ -n "$default" ]]; then
        echo -ne "  ${CYAN}➤${R} ${B}${label}${R} ${DIM}[پیش‌فرض: ${default}]${R}: "
    else
        echo -ne "  ${CYAN}➤${R} ${B}${label}${R}: "
    fi
    read -r input
    if [[ -z "$input" && -n "$default" ]]; then
        input="$default"
    fi
    printf -v "$var_ref" '%s' "$input"
}

prompt_password() {
    local label="$1"
    local var_ref="$2"
    echo -ne "  ${CYAN}➤${R} ${B}${label}${R}: "
    read -rs input
    echo ""
    printf -v "$var_ref" '%s' "$input"
}

# ==============================================================================
# SECTION 5: SYSTEM UTILITY FUNCTIONS
# ==============================================================================

get_public_ip() {
    local ip
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
        || curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
        || curl -s --max-time 5 https://icanhazip.com 2>/dev/null \
        || echo "نامشخص")
    echo "$ip"
}

get_public_ipv6() {
    local ipv6
    ipv6=$(curl -6 -s --max-time 5 https://api6.ipify.org 2>/dev/null || echo "")
    echo "$ipv6"
}

get_xui_port() {
    if [[ -f "$XUI_DB" ]]; then
        sqlite3 "$XUI_DB" "SELECT value FROM settings WHERE key='webPort' LIMIT 1;" 2>/dev/null || echo "54321"
    else
        echo "54321"
    fi
}

get_xui_base_path() {
    if [[ -f "$XUI_DB" ]]; then
        sqlite3 "$XUI_DB" "SELECT value FROM settings WHERE key='webBasePath' LIMIT 1;" 2>/dev/null || echo "/"
    else
        echo "/"
    fi
}

generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

generate_password() {
    local length="${1:-16}"
    tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length"
}

generate_short_id() {
    openssl rand -hex 8
}

base64_encode() {
    echo -n "$1" | base64 -w 0
}

base64_url_encode() {
    echo -n "$1" | base64 -w 0 | tr '+/' '-_' | tr -d '='
}

timestamp_to_date() {
    local ts="${1:-0}"
    if [[ "$ts" -gt 0 ]]; then
        date -d "@$((ts / 1000))" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "نامشخص"
    else
        echo "بدون محدودیت"
    fi
}

bytes_to_human() {
    local bytes="${1:-0}"
    if   [[ "$bytes" -ge 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
    elif [[ "$bytes" -ge 1048576 ]]; then
        echo "$(echo "scale=2; $bytes/1048576" | bc) MB"
    elif [[ "$bytes" -ge 1024 ]]; then
        echo "$(echo "scale=2; $bytes/1024" | bc) KB"
    else
        echo "${bytes} B"
    fi
}

gb_to_bytes() {
    echo $(( ${1:-0} * 1024 * 1024 * 1024 ))
}

days_to_ms() {
    local days="${1:-0}"
    if [[ "$days" -eq 0 ]]; then
        echo 0
    else
        echo $(( ($(date +%s) + days * 86400) * 1000 ))
    fi
}

ensure_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || mkdir -p "$dir"
}

# ==============================================================================
# SECTION 6: DEPENDENCY MANAGEMENT
# ==============================================================================

declare -A REQUIRED_PACKAGES=(
    [curl]="curl"
    [jq]="jq"
    [sqlite3]="sqlite3"
    [openssl]="openssl"
    [uuidgen]="uuid-runtime"
    [qrencode]="qrencode"
    [cron]="cron"
    [bc]="bc"
    [socat]="socat"
    [unzip]="unzip"
    [wget]="wget"
    [netstat]="net-tools"
    [ss]="iproute2"
)

check_and_install_dependencies() {
    draw_header "بررسی و نصب وابستگی‌ها" "Dependency Check & Installation"
    draw_section "بررسی پکیج‌های مورد نیاز"

    local missing=()
    for cmd in "${!REQUIRED_PACKAGES[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("${REQUIRED_PACKAGES[$cmd]}")
            echo -e "  ${RED}✗${R}  ${cmd} ${DIM}(${REQUIRED_PACKAGES[$cmd]})${R}"
        else
            echo -e "  ${GREEN}✓${R}  ${cmd}"
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        log_warn "نصب پکیج‌های ناموجود: ${missing[*]}"
        echo -e "  ${YELLOW}⟳${R}  در حال بروزرسانی apt..."
        apt-get update -qq &>/dev/null
        echo -e "  ${YELLOW}⟳${R}  در حال نصب: ${missing[*]}"
        apt-get install -y -qq "${missing[@]}" &>/dev/null \
            && log_success "تمام وابستگی‌ها نصب شدند." \
            || { log_error "نصب ناموفق بود."; return 1; }
    else
        log_success "تمام وابستگی‌ها موجود هستند."
    fi

    # Check acme.sh
    if [[ ! -f "${ACME_DIR}/acme.sh" ]]; then
        echo -e "  ${YELLOW}⟳${R}  نصب acme.sh..."
        curl -s https://get.acme.sh | sh -s email="admin@$(hostname -f)" &>/dev/null \
            && log_success "acme.sh نصب شد." \
            || log_warn "نصب acme.sh ناموفق بود (برای SSL لازم است)."
    else
        echo -e "  ${GREEN}✓${R}  acme.sh"
    fi

    # Verify X-UI
    if ! command -v x-ui &>/dev/null && [[ ! -f "$XUI_BIN" ]]; then
        log_warn "X-UI Sanaei نصب نشده است."
        echo -ne "  ${YELLOW}آیا می‌خواهید X-UI را نصب کنید؟ (بله/خیر): ${R}"
        read -r answer
        [[ "$answer" =~ ^(بله|yes|y)$ ]] && install_xui
    else
        echo -e "  ${GREEN}✓${R}  X-UI Sanaei"
    fi

    ensure_dir "$BACKUP_DIR"
    ensure_dir "$SUBSCRIPTION_DIR"
    ensure_dir "$(dirname "$CONFIG_FILE")"
    ensure_dir "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    press_enter
}

install_xui() {
    draw_section "نصب X-UI Sanaei"
    log_info "دانلود و نصب X-UI Sanaei..."
    bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh) \
        && log_success "X-UI با موفقیت نصب شد." \
        || { log_error "نصب X-UI ناموفق."; return 1; }
}

# ==============================================================================
# SECTION 7: CONFIGURATION LOADER & SAVER
# ==============================================================================

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi
    # Set defaults if not defined
    PANEL_CF_DOMAIN="${PANEL_CF_DOMAIN:-}"
    PANEL_TG_TOKEN="${PANEL_TG_TOKEN:-}"
    PANEL_TG_CHAT_ID="${PANEL_TG_CHAT_ID:-}"
    PANEL_PUBLIC_IP="${PANEL_PUBLIC_IP:-$(get_public_ip)}"
    PANEL_BACKUP_INTERVAL="${PANEL_BACKUP_INTERVAL:-daily}"
    PANEL_SUB_PORT="${PANEL_SUB_PORT:-8080}"
    PANEL_CUSTOM_SNIS="${PANEL_CUSTOM_SNIS:-}"
    PANEL_CF_CLEAN_IPS="${PANEL_CF_CLEAN_IPS:-}"
}

save_config() {
    ensure_dir "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" <<EOF
# XUI Panel Configuration - Auto-generated
# تاریخ آخرین ویرایش: $(date '+%Y-%m-%d %H:%M:%S')

PANEL_CF_DOMAIN="${PANEL_CF_DOMAIN:-}"
PANEL_TG_TOKEN="${PANEL_TG_TOKEN:-}"
PANEL_TG_CHAT_ID="${PANEL_TG_CHAT_ID:-}"
PANEL_PUBLIC_IP="${PANEL_PUBLIC_IP:-}"
PANEL_BACKUP_INTERVAL="${PANEL_BACKUP_INTERVAL:-daily}"
PANEL_SUB_PORT="${PANEL_SUB_PORT:-8080}"
PANEL_CUSTOM_SNIS="${PANEL_CUSTOM_SNIS:-}"
PANEL_CF_CLEAN_IPS="${PANEL_CF_CLEAN_IPS:-}"
PANEL_SSL_DOMAIN="${PANEL_SSL_DOMAIN:-}"
PANEL_SSL_CERT="${PANEL_SSL_CERT:-}"
PANEL_SSL_KEY="${PANEL_SSL_KEY:-}"
EOF
    chmod 600 "$CONFIG_FILE"
    log_success "تنظیمات ذخیره شدند."
}

# ==============================================================================
# SECTION 8: DATABASE INTERACTION ENGINE (X-UI Sanaei Schema)
# ==============================================================================

db_query() {
    local query="$1"
    sqlite3 "$XUI_DB" "$query" 2>/dev/null
}

db_query_or_die() {
    local query="$1"
    local result
    result=$(sqlite3 "$XUI_DB" "$query" 2>&1) || {
        log_error "خطای پایگاه داده: $result"
        return 1
    }
    echo "$result"
}

get_all_inbounds() {
    db_query "SELECT id, remark, protocol, port, enable, up, down, total, expiry_time FROM inbounds ORDER BY id;"
}

get_inbound_by_id() {
    local id="$1"
    db_query "SELECT * FROM inbounds WHERE id=$id LIMIT 1;"
}

get_inbound_settings() {
    local id="$1"
    db_query "SELECT settings FROM inbounds WHERE id=$id LIMIT 1;"
}

get_inbound_stream_settings() {
    local id="$1"
    db_query "SELECT stream_settings FROM inbounds WHERE id=$id LIMIT 1;"
}

get_all_client_traffics() {
    db_query "SELECT id, inbound_id, enable, email, up, down, expiry_time, total, reset FROM client_traffics ORDER BY id;"
}

get_client_traffic_by_email() {
    local email="$1"
    db_query "SELECT * FROM client_traffics WHERE email='${email}' LIMIT 1;"
}

get_clients_by_inbound() {
    local inbound_id="$1"
    db_query "SELECT id, email, enable, up, down, total, expiry_time FROM client_traffics WHERE inbound_id=${inbound_id} ORDER BY id;"
}

update_inbound_settings() {
    local inbound_id="$1"
    local new_settings="$2"
    db_query "UPDATE inbounds SET settings='$(echo "$new_settings" | sed "s/'/''/g")' WHERE id=${inbound_id};"
}

disable_client_by_email() {
    local email="$1"
    db_query "UPDATE client_traffics SET enable=0 WHERE email='${email}';"
}

enable_client_by_email() {
    local email="$1"
    db_query "UPDATE client_traffics SET enable=1 WHERE email='${email}';"
}

reset_client_traffic() {
    local email="$1"
    db_query "UPDATE client_traffics SET up=0, down=0 WHERE email='${email}';"
}

delete_client_traffic_by_email() {
    local email="$1"
    db_query "DELETE FROM client_traffics WHERE email='${email}';"
}

get_xui_setting() {
    local key="$1"
    db_query "SELECT value FROM settings WHERE key='${key}' LIMIT 1;"
}

set_xui_setting() {
    local key="$1"
    local value="$2"
    local exists
    exists=$(db_query "SELECT count(*) FROM settings WHERE key='${key}';")
    if [[ "$exists" -gt 0 ]]; then
        db_query "UPDATE settings SET value='${value}' WHERE key='${key}';"
    else
        db_query "INSERT INTO settings (key, value) VALUES ('${key}', '${value}');"
    fi
}

# ==============================================================================
# SECTION 9: INBOUND LISTING & DISPLAY
# ==============================================================================

list_inbounds_table() {
    draw_section "لیست اینباند‌های فعال"
    echo ""
    printf "  ${CYAN}%-4s %-20s %-12s %-6s %-8s %-15s %-15s %-12s${R}\n" \
        "ID" "نام" "پروتکل" "پورت" "وضعیت" "آپلود" "دانلود" "انقضا"
    draw_line "─" "$DIM"

    local data
    data=$(get_all_inbounds)
    if [[ -z "$data" ]]; then
        echo -e "  ${YELLOW}هیچ اینباندی یافت نشد.${R}"
        return
    fi

    while IFS='|' read -r id remark protocol port enable up down total expiry; do
        local status_icon status_color
        if [[ "$enable" == "1" ]]; then
            status_icon="✓ فعال"
            status_color="$GREEN"
        else
            status_icon="✗ غیرفعال"
            status_color="$RED"
        fi
        local exp_str
        exp_str=$(timestamp_to_date "$expiry")
        local up_h down_h
        up_h=$(bytes_to_human "$up")
        down_h=$(bytes_to_human "$down")

        printf "  ${WHITE}%-4s${R} ${CYAN}%-20s${R} ${MAGENTA}%-12s${R} ${YELLOW}%-6s${R} ${status_color}%-8s${R} ${GREEN}%-15s${R} ${RED}%-15s${R} ${DIM}%-12s${R}\n" \
            "$id" "$remark" "$protocol" "$port" "$status_icon" "$up_h" "$down_h" "$exp_str"
    done <<< "$data"
    echo ""
}

list_clients_table() {
    local inbound_id="$1"
    draw_section "لیست کلاینت‌های اینباند #${inbound_id}"
    echo ""
    printf "  ${CYAN}%-4s %-25s %-8s %-12s %-12s %-12s %-15s${R}\n" \
        "ID" "ایمیل/نام" "وضعیت" "آپلود" "دانلود" "حجم کل" "انقضا"
    draw_line "─" "$DIM"

    local data
    data=$(get_clients_by_inbound "$inbound_id")
    if [[ -z "$data" ]]; then
        echo -e "  ${YELLOW}هیچ کلاینتی یافت نشد.${R}"
        return
    fi

    while IFS='|' read -r id email enable up down total expiry; do
        local status_icon status_color
        if [[ "$enable" == "1" ]]; then
            status_icon="فعال"
            status_color="$GREEN"
        else
            status_icon="غیرفعال"
            status_color="$RED"
        fi
        local exp_str up_h down_h total_h
        exp_str=$(timestamp_to_date "$expiry")
        up_h=$(bytes_to_human "$up")
        down_h=$(bytes_to_human "$down")
        total_h=$(bytes_to_human "$total")

        printf "  ${WHITE}%-4s${R} ${CYAN}%-25s${R} ${status_color}%-8s${R} ${GREEN}%-12s${R} ${RED}%-12s${R} ${YELLOW}%-12s${R} ${DIM}%-15s${R}\n" \
            "$id" "$email" "$status_icon" "$up_h" "$down_h" "$total_h" "$exp_str"
    done <<< "$data"
    echo ""
}

# ==============================================================================
# SECTION 10: USER MANAGEMENT (CRUD)
# ==============================================================================

user_management_menu() {
    while true; do
        draw_header "مدیریت کاربران" "User Management (CRUD)"
        draw_status_bar
        draw_section "عملیات کاربران"
        echo ""
        draw_menu_item  "1"  "➕"  "افزودن کاربر جدید"           "ساخت کلاینت در اینباند موجود"
        draw_menu_item  "2"  "📋"  "لیست تمام کاربران"            "مشاهده اطلاعات کلاینت‌ها"
        draw_menu_item  "3"  "✏️"  "ویرایش کاربر"                 "تغییر حجم، انقضا، وضعیت"
        draw_menu_item  "4"  "🗑️"  "حذف کاربر"                    "حذف کامل از دیتابیس"
        draw_menu_item  "5"  "🔄"  "ریست ترافیک کاربر"            "صفر کردن آمار مصرف"
        draw_menu_item  "6"  "🔒"  "فعال/غیرفعال کردن کاربر"      "تغییر وضعیت سریع"
        draw_menu_item  "7"  "🔗"  "دریافت لینک اتصال کاربر"      "نمایش کانفیگ و QR Code"
        draw_menu_item  "8"  "📊"  "آمار مصرف کاربران"            "بیشترین مصرف، نزدیک به اتمام"
        draw_menu_item  "9"  "📅"  "کاربران منقضی‌شده"            "لیست و حذف منقضی‌شده‌ها"
        draw_menu_footer
        echo -ne "  ${B}${CYAN}انتخاب: ${R}"
        read -r choice
        case "$choice" in
            1) add_user_interactive ;;
            2) list_all_users_detailed ;;
            3) edit_user_interactive ;;
            4) delete_user_interactive ;;
            5) reset_user_traffic ;;
            6) toggle_user_status ;;
            7) get_user_config_link ;;
            8) show_traffic_statistics ;;
            9) manage_expired_users ;;
            0|"") return ;;
            *)  log_warn "گزینه نامعتبر." ; sleep 1 ;;
        esac
    done
}

add_user_interactive() {
    draw_header "افزودن کاربر جدید" "Add New Client"

    # Show inbounds
    list_inbounds_table

    local inbound_id
    prompt_input "شماره اینباند" "" inbound_id
    [[ -z "$inbound_id" ]] && return

    # Validate inbound exists
    local inbound_data
    inbound_data=$(db_query "SELECT id, remark, protocol FROM inbounds WHERE id=${inbound_id} LIMIT 1;")
    if [[ -z "$inbound_data" ]]; then
        log_error "اینباند با ID '${inbound_id}' یافت نشد."
        press_enter; return
    fi

    local inbound_remark inbound_protocol
    IFS='|' read -r _ inbound_remark inbound_protocol <<< "$inbound_data"

    echo -e "\n  ${GREEN}اینباند انتخابی: ${B}${inbound_remark}${R} ${DIM}(${inbound_protocol})${R}\n"

    local email
    prompt_input "ایمیل/نام کاربری (بدون فاصله)" "user_$(date +%s)" email
    email=$(echo "$email" | tr ' ' '_' | tr -cd '[:alnum:]._-')

    # Check duplicate
    local exists
    exists=$(db_query "SELECT count(*) FROM client_traffics WHERE email='${email}' AND inbound_id=${inbound_id};")
    if [[ "$exists" -gt 0 ]]; then
        log_error "کاربری با این ایمیل در این اینباند وجود دارد."
        press_enter; return
    fi

    local traffic_gb
    prompt_input "محدودیت ترافیک (گیگابایت، 0=بی‌نهایت)" "0" traffic_gb
    [[ ! "$traffic_gb" =~ ^[0-9]+$ ]] && traffic_gb=0

    local expire_days
    prompt_input "تعداد روز انقضا (0=بی‌نهایت)" "30" expire_days
    [[ ! "$expire_days" =~ ^[0-9]+$ ]] && expire_days=30

    local total_bytes expire_ms
    total_bytes=$(gb_to_bytes "$traffic_gb")
    expire_ms=$(days_to_ms "$expire_days")

    # Generate UUID or password based on protocol
    local new_uuid new_password
    new_uuid=$(generate_uuid)
    new_password=$(generate_password 16)

    # Get current settings JSON and inject new client
    local current_settings
    current_settings=$(get_inbound_settings "$inbound_id")

    # Build new client object based on protocol
    local new_client_json
    case "${inbound_protocol,,}" in
        vless)
            new_client_json=$(jq -n \
                --arg id "$new_uuid" \
                --arg email "$email" \
                --argjson total "$total_bytes" \
                --argjson expiry "$expire_ms" \
                '{id: $id, email: $email, limitIp: 0, totalGB: $total,
                  expiryTime: $expiry, enable: true, tgId: "", subId: "",
                  comment: "", reset: 0, flow: ""}')
            ;;
        vmess)
            new_client_json=$(jq -n \
                --arg id "$new_uuid" \
                --arg email "$email" \
                --argjson total "$total_bytes" \
                --argjson expiry "$expire_ms" \
                '{id: $id, alterId: 0, email: $email, limitIp: 0,
                  totalGB: $total, expiryTime: $expiry, enable: true,
                  tgId: "", subId: "", comment: "", reset: 0}')
            ;;
        trojan)
            new_client_json=$(jq -n \
                --arg password "$new_password" \
                --arg email "$email" \
                --argjson total "$total_bytes" \
                --argjson expiry "$expire_ms" \
                '{password: $password, email: $email, limitIp: 0,
                  totalGB: $total, expiryTime: $expiry, enable: true,
                  tgId: "", subId: "", comment: "", reset: 0}')
            ;;
        shadowsocks)
            new_client_json=$(jq -n \
                --arg password "$new_password" \
                --arg email "$email" \
                --argjson total "$total_bytes" \
                --argjson expiry "$expire_ms" \
                '{password: $password, email: $email, limitIp: 0,
                  totalGB: $total, expiryTime: $expiry, enable: true,
                  tgId: "", subId: "", comment: "", reset: 0}')
            ;;
        *)
            new_client_json=$(jq -n \
                --arg id "$new_uuid" \
                --arg email "$email" \
                --argjson total "$total_bytes" \
                --argjson expiry "$expire_ms" \
                '{id: $id, email: $email, limitIp: 0, totalGB: $total,
                  expiryTime: $expiry, enable: true, tgId: "", subId: "",
                  comment: "", reset: 0}')
            ;;
    esac

    # Merge into inbound settings
    local updated_settings
    updated_settings=$(echo "$current_settings" | jq --argjson client "$new_client_json" \
        '.clients += [$client]' 2>/dev/null)

    if [[ -z "$updated_settings" ]]; then
        log_error "خطا در پردازش JSON تنظیمات اینباند."
        press_enter; return
    fi

    # Update inbounds table
    local escaped_settings
    escaped_settings="${updated_settings//\'/\'\'}"
    db_query "UPDATE inbounds SET settings='${escaped_settings}' WHERE id=${inbound_id};"

    # Insert into client_traffics table
    db_query "INSERT INTO client_traffics
        (inbound_id, enable, email, up, down, expiry_time, total, reset)
        VALUES (${inbound_id}, 1, '${email}', 0, 0, ${expire_ms}, ${total_bytes}, 0);"

    # Restart X-UI to apply changes
    restart_xui_service

    echo ""
    log_success "کاربر '${email}' با موفقیت ایجاد شد!"
    echo ""
    echo -e "  ${CYAN}┌─ اطلاعات کاربر جدید ──────────────────────────${R}"
    echo -e "  ${CYAN}│${R}  ${DIM}ایمیل:${R}    ${B}${email}${R}"
    case "${inbound_protocol,,}" in
        vless|vmess) echo -e "  ${CYAN}│${R}  ${DIM}UUID:${R}     ${B}${new_uuid}${R}" ;;
        trojan|shadowsocks) echo -e "  ${CYAN}│${R}  ${DIM}پسورد:${R}    ${B}${new_password}${R}" ;;
    esac
    local traffic_display expire_display
    [[ "$traffic_gb" -eq 0 ]] && traffic_display="بی‌نهایت" || traffic_display="${traffic_gb} GB"
    [[ "$expire_days" -eq 0 ]] && expire_display="بی‌نهایت" || expire_display="${expire_days} روز"
    echo -e "  ${CYAN}│${R}  ${DIM}ترافیک:${R}   ${B}${traffic_display}${R}"
    echo -e "  ${CYAN}│${R}  ${DIM}انقضا:${R}    ${B}${expire_display}${R}"
    echo -e "  ${CYAN}└────────────────────────────────────────────────${R}"

    # Offer to show config link
    echo -ne "\n  آیا می‌خواهید لینک کانفیگ نمایش داده شود؟ (بله/خیر): "
    read -r show_config
    if [[ "$show_config" =~ ^(بله|yes|y)$ ]]; then
        generate_config_link_for_email "$inbound_id" "$email"
    fi

    press_enter
}

list_all_users_detailed() {
    draw_header "لیست تمام کاربران" "All Clients"
    list_inbounds_table

    local inbound_id
    prompt_input "شماره اینباند (0=همه)" "0" inbound_id

    if [[ "$inbound_id" == "0" ]]; then
        local all_inbounds
        all_inbounds=$(db_query "SELECT id FROM inbounds;")
        while IFS= read -r iid; do
            list_clients_table "$iid"
        done <<< "$all_inbounds"
    else
        list_clients_table "$inbound_id"
    fi
    press_enter
}

edit_user_interactive() {
    draw_header "ویرایش کاربر" "Edit Client"
    list_inbounds_table
    local inbound_id
    prompt_input "شماره اینباند" "" inbound_id
    [[ -z "$inbound_id" ]] && return
    list_clients_table "$inbound_id"
    local email
    prompt_input "ایمیل کاربر جهت ویرایش" "" email
    [[ -z "$email" ]] && return

    local client_data
    client_data=$(db_query "SELECT * FROM client_traffics WHERE email='${email}' AND inbound_id=${inbound_id} LIMIT 1;")
    if [[ -z "$client_data" ]]; then
        log_error "کاربر '${email}' یافت نشد."
        press_enter; return
    fi

    echo -e "\n  ${YELLOW}اطلاعات فعلی:${R}"
    local ct_id ct_inbound ct_enable ct_email ct_up ct_down ct_expiry ct_total ct_reset
    IFS='|' read -r ct_id ct_inbound ct_enable ct_email ct_up ct_down ct_expiry ct_total ct_reset <<< "$client_data"
    echo -e "  ${DIM}ترافیک: $(bytes_to_human "$ct_total")  |  انقضا: $(timestamp_to_date "$ct_expiry")${R}"
    echo ""

    local new_traffic_gb
    prompt_input "حجم ترافیک جدید (GB، Enter=بدون تغییر)" "" new_traffic_gb
    local new_days
    prompt_input "روزهای جدید از امروز (Enter=بدون تغییر)" "" new_days

    local update_parts=()
    if [[ -n "$new_traffic_gb" && "$new_traffic_gb" =~ ^[0-9]+$ ]]; then
        local new_bytes
        new_bytes=$(gb_to_bytes "$new_traffic_gb")
        update_parts+=("total=${new_bytes}")
    fi
    if [[ -n "$new_days" && "$new_days" =~ ^[0-9]+$ ]]; then
        local new_expiry
        new_expiry=$(days_to_ms "$new_days")
        update_parts+=("expiry_time=${new_expiry}")
    fi

    if [[ ${#update_parts[@]} -gt 0 ]]; then
        local set_clause
        set_clause=$(IFS=','; echo "${update_parts[*]}")
        db_query "UPDATE client_traffics SET ${set_clause} WHERE email='${email}' AND inbound_id=${inbound_id};"

        # Also update the JSON in inbounds
        local current_settings
        current_settings=$(get_inbound_settings "$inbound_id")
        local updated_settings
        updated_settings=$(echo "$current_settings" | jq \
            --arg email "$email" \
            --argjson total "${new_bytes:-$ct_total}" \
            --argjson expiry "${new_expiry:-$ct_expiry}" \
            '(.clients[] | select(.email == $email)) |= . + {totalGB: $total, expiryTime: $expiry}' 2>/dev/null)
        if [[ -n "$updated_settings" ]]; then
            local escaped="${updated_settings//\'/\'\'}"
            db_query "UPDATE inbounds SET settings='${escaped}' WHERE id=${inbound_id};"
        fi

        restart_xui_service
        log_success "کاربر '${email}' بروزرسانی شد."
    else
        log_warn "هیچ تغییری اعمال نشد."
    fi
    press_enter
}

delete_user_interactive() {
    draw_header "حذف کاربر" "Delete Client"
    list_inbounds_table
    local inbound_id
    prompt_input "شماره اینباند" "" inbound_id
    [[ -z "$inbound_id" ]] && return
    list_clients_table "$inbound_id"
    local email
    prompt_input "ایمیل کاربر جهت حذف" "" email
    [[ -z "$email" ]] && return

    if ! confirm_action "کاربر '${email}' به صورت کامل حذف خواهد شد!"; then
        return
    fi

    # Remove from client_traffics
    db_query "DELETE FROM client_traffics WHERE email='${email}' AND inbound_id=${inbound_id};"

    # Remove from inbound settings JSON
    local current_settings
    current_settings=$(get_inbound_settings "$inbound_id")
    local updated_settings
    updated_settings=$(echo "$current_settings" | jq \
        --arg email "$email" \
        'del(.clients[] | select(.email == $email))' 2>/dev/null)
    if [[ -n "$updated_settings" ]]; then
        local escaped="${updated_settings//\'/\'\'}"
        db_query "UPDATE inbounds SET settings='${escaped}' WHERE id=${inbound_id};"
    fi

    restart_xui_service
    log_success "کاربر '${email}' حذف شد."
    press_enter
}

reset_user_traffic() {
    draw_header "ریست ترافیک کاربر" "Reset Client Traffic"
    list_inbounds_table
    local inbound_id
    prompt_input "شماره اینباند" "" inbound_id
    [[ -z "$inbound_id" ]] && return
    list_clients_table "$inbound_id"
    local email
    prompt_input "ایمیل کاربر" "" email
    [[ -z "$email" ]] && return

    if confirm_action "ترافیک '${email}' ریست می‌شود؟"; then
        db_query "UPDATE client_traffics SET up=0, down=0 WHERE email='${email}' AND inbound_id=${inbound_id};"
        restart_xui_service
        log_success "ترافیک '${email}' ریست شد."
    fi
    press_enter
}

toggle_user_status() {
    draw_header "فعال/غیرفعال کردن کاربر" "Toggle Client Status"
    list_inbounds_table
    local inbound_id
    prompt_input "شماره اینباند" "" inbound_id
    [[ -z "$inbound_id" ]] && return
    list_clients_table "$inbound_id"
    local email
    prompt_input "ایمیل کاربر" "" email
    [[ -z "$email" ]] && return

    local current_enable
    current_enable=$(db_query "SELECT enable FROM client_traffics WHERE email='${email}' AND inbound_id=${inbound_id} LIMIT 1;")
    local new_enable new_status
    if [[ "$current_enable" == "1" ]]; then
        new_enable=0; new_status="غیرفعال"
    else
        new_enable=1; new_status="فعال"
    fi

    db_query "UPDATE client_traffics SET enable=${new_enable} WHERE email='${email}' AND inbound_id=${inbound_id};"

    # Update JSON in settings
    local current_settings updated_settings
    current_settings=$(get_inbound_settings "$inbound_id")
    updated_settings=$(echo "$current_settings" | jq \
        --arg email "$email" \
        --argjson enable "$new_enable" \
        '(.clients[] | select(.email == $email)).enable = ($enable == 1)' 2>/dev/null)
    if [[ -n "$updated_settings" ]]; then
        local escaped="${updated_settings//\'/\'\'}"
        db_query "UPDATE inbounds SET settings='${escaped}' WHERE id=${inbound_id};"
    fi

    restart_xui_service
    log_success "کاربر '${email}' ${new_status} شد."
    press_enter
}

show_traffic_statistics() {
    draw_header "آمار ترافیک کاربران" "Traffic Statistics"
    draw_section "۱۰ کاربر با بیشترین مصرف"
    echo ""
    printf "  ${CYAN}%-5s %-25s %-12s %-12s %-12s${R}\n" "رتبه" "ایمیل" "آپلود" "دانلود" "جمع کل"
    draw_line "─" "$DIM"

    local data rank=1
    data=$(db_query "SELECT email, up, down, (up+down) as total FROM client_traffics ORDER BY total DESC LIMIT 10;")
    while IFS='|' read -r email up down total; do
        printf "  ${YELLOW}%-5s${R} ${CYAN}%-25s${R} ${GREEN}%-12s${R} ${RED}%-12s${R} ${B}%-12s${R}\n" \
            "${rank}." "$email" "$(bytes_to_human "$up")" "$(bytes_to_human "$down")" "$(bytes_to_human "$total")"
        ((rank++))
    done <<< "$data"

    draw_section "کاربران نزدیک به اتمام ترافیک (بیش از ۸۰٪ مصرف)"
    echo ""
    local near_limit
    near_limit=$(db_query "SELECT email, up, down, total FROM client_traffics WHERE total > 0 AND (up+down)*100/total >= 80 ORDER BY (up+down)*1.0/total DESC;")
    if [[ -z "$near_limit" ]]; then
        echo -e "  ${GREEN}هیچ کاربری در آستانه اتمام ترافیک نیست.${R}"
    else
        printf "  ${CYAN}%-25s %-12s %-12s %-8s${R}\n" "ایمیل" "مصرف" "محدودیت" "درصد"
        while IFS='|' read -r email up down total; do
            local used pct
            used=$((up + down))
            pct=$(echo "scale=1; $used*100/$total" | bc 2>/dev/null || echo "??")
            printf "  ${RED}%-25s${R} ${YELLOW}%-12s${R} ${DIM}%-12s${R} ${RED}%-8s${R}\n" \
                "$email" "$(bytes_to_human "$used")" "$(bytes_to_human "$total")" "${pct}%"
        done <<< "$near_limit"
    fi
    press_enter
}

manage_expired_users() {
    draw_header "مدیریت کاربران منقضی‌شده" "Expired Users"
    local now_ms
    now_ms=$(( $(date +%s) * 1000 ))

    local expired
    expired=$(db_query "SELECT email, inbound_id, expiry_time FROM client_traffics WHERE expiry_time > 0 AND expiry_time < ${now_ms};")

    if [[ -z "$expired" ]]; then
        echo -e "\n  ${GREEN}هیچ کاربر منقضی‌شده‌ای یافت نشد.${R}"
        press_enter; return
    fi

    echo ""
    draw_section "کاربران منقضی‌شده"
    printf "  ${CYAN}%-25s %-12s %-20s${R}\n" "ایمیل" "اینباند" "تاریخ انقضا"
    draw_line "─" "$DIM"

    while IFS='|' read -r email iid expiry; do
        printf "  ${RED}%-25s${R} ${DIM}%-12s${R} ${YELLOW}%-20s${R}\n" \
            "$email" "#${iid}" "$(timestamp_to_date "$expiry")"
    done <<< "$expired"

    echo ""
    echo -e "  ${YELLOW}گزینه‌ها:${R}"
    echo -e "  ${CYAN}1${R}) غیرفعال کردن همه"
    echo -e "  ${CYAN}2${R}) حذف همه"
    echo -e "  ${CYAN}0${R}) بازگشت"
    echo -ne "  انتخاب: "
    read -r choice

    case "$choice" in
        1)
            db_query "UPDATE client_traffics SET enable=0 WHERE expiry_time > 0 AND expiry_time < ${now_ms};"
            restart_xui_service
            log_success "تمام کاربران منقضی غیرفعال شدند."
            ;;
        2)
            if confirm_action "تمام کاربران منقضی حذف خواهند شد!"; then
                while IFS='|' read -r email iid _; do
                    local cs us
                    cs=$(get_inbound_settings "$iid")
                    us=$(echo "$cs" | jq --arg em "$email" 'del(.clients[] | select(.email == $em))' 2>/dev/null)
                    if [[ -n "$us" ]]; then
                        local esc="${us//\'/\'\'}"
                        db_query "UPDATE inbounds SET settings='${esc}' WHERE id=${iid};"
                    fi
                done <<< "$expired"
                db_query "DELETE FROM client_traffics WHERE expiry_time > 0 AND expiry_time < ${now_ms};"
                restart_xui_service
                log_success "کاربران منقضی حذف شدند."
            fi
            ;;
        *) return ;;
    esac
    press_enter
}

# ==============================================================================
# SECTION 11: SERVICE MANAGEMENT
# ==============================================================================

restart_xui_service() {
    log_debug "Restarting x-ui service..."
    systemctl restart "$XUI_SERVICE" &>/dev/null \
        && log_debug "x-ui restarted successfully." \
        || log_warn "بازراه‌اندازی x-ui ناموفق بود."
    sleep 1
}

service_management_menu() {
    while true; do
        draw_header "مدیریت سرویس X-UI" "Service Management"

        local status
        status=$(systemctl is-active x-ui 2>/dev/null || echo "inactive")
        local status_color="$GREEN"
        [[ "$status" != "active" ]] && status_color="$RED"

        echo -e "\n  ${DIM}وضعیت سرویس:${R} ${status_color}${B}${status}${R}\n"

        draw_menu_item "1" "▶️"  "شروع سرویس X-UI"        ""
        draw_menu_item "2" "⏹️"  "توقف سرویس X-UI"         ""
        draw_menu_item "3" "🔄"  "راه‌اندازی مجدد"          ""
        draw_menu_item "4" "📋"  "وضعیت کامل سرویس"        "systemctl status"
        draw_menu_item "5" "📜"  "لاگ‌های X-UI"             "journalctl"
        draw_menu_item "6" "🔧"  "تغییر پورت پنل"           ""
        draw_menu_item "7" "🔑"  "تغییر رمز پنل"            ""
        draw_menu_item "8" "🛤️"  "تغییر Base Path"          ""
        draw_menu_footer

        echo -ne "  ${B}${CYAN}انتخاب: ${R}"
        read -r choice
        case "$choice" in
            1) systemctl start x-ui && log_success "سرویس شروع شد." ;;
            2) systemctl stop x-ui && log_success "سرویس متوقف شد." ;;
            3) restart_xui_service && log_success "سرویس راه‌اندازی مجدد شد." ;;
            4) systemctl status x-ui --no-pager; press_enter ;;
            5) journalctl -u x-ui -n 50 --no-pager; press_enter ;;
            6) change_panel_port ;;
            7) change_panel_password ;;
            8) change_base_path ;;
            0|"") return ;;
            *) log_warn "گزینه نامعتبر."; sleep 1 ;;
        esac
    done
}

change_panel_port() {
    local current_port
    current_port=$(get_xui_port)
    local new_port
    prompt_input "پورت جدید پنل" "$current_port" new_port
    if [[ "$new_port" =~ ^[0-9]+$ && "$new_port" -ge 1 && "$new_port" -le 65535 ]]; then
        set_xui_setting "webPort" "$new_port"
        restart_xui_service
        log_success "پورت پنل به ${new_port} تغییر یافت."
    else
        log_error "پورت نامعتبر."
    fi
    press_enter
}

change_panel_password() {
    local new_pass
    prompt_password "رمز عبور جدید پنل" new_pass
    if [[ -n "$new_pass" ]]; then
        set_xui_setting "webPassword" "$new_pass"
        restart_xui_service
        log_success "رمز پنل تغییر یافت."
    fi
    press_enter
}

change_base_path() {
    local current_path
    current_path=$(get_xui_base_path)
    local new_path
    prompt_input "Base Path جدید (مثال: /admin/)" "$current_path" new_path
    if [[ -n "$new_path" ]]; then
        set_xui_setting "webBasePath" "$new_path"
        restart_xui_service
        log_success "Base Path به '${new_path}' تغییر یافت."
    fi
    press_enter
}

# ==============================================================================
# SECTION 12: PANEL SETTINGS MENU
# ==============================================================================

panel_settings_menu() {
    while true; do
        draw_header "تنظیمات پنل" "Panel Settings"
        draw_status_bar
        draw_section "پیکربندی اصلی"
        echo ""
        draw_menu_item "1" "🌐"  "تنظیم دامنه Cloudflare"       "دامنه پشت CDN"
        draw_menu_item "2" "🤖"  "تنظیم ربات تلگرام"            "توکن و Chat ID"
        draw_menu_item "3" "🔒"  "SSL سرور (sslip.io)"          "گواهی رایگان روی IP"
        draw_menu_item "4" "📡"  "سرور ساب‌اسکریپشن"            "پورت و مسیر"
        draw_menu_item "5" "🌍"  "IP تمیز Cloudflare"           "ویرایش لیست آی‌پی"
        draw_menu_item "6" "🔗"  "SNI های سفارشی"               "لیست SNI برای کانفیگ"
        draw_menu_item "7" "💾"  "ذخیره تنظیمات"                ""
        draw_menu_footer
        echo -ne "  ${B}${CYAN}انتخاب: ${R}"
        read -r choice
        case "$choice" in
            1) configure_cloudflare_domain ;;
            2) configure_telegram_bot ;;
            3) setup_ssl_sslip ;;
            4) configure_subscription_server ;;
            5) configure_clean_ips ;;
            6) configure_custom_snis ;;
            7) save_config && press_enter ;;
            0|"") return ;;
            *) log_warn "گزینه نامعتبر."; sleep 1 ;;
        esac
    done
}

configure_cloudflare_domain() {
    draw_header "تنظیم دامنه Cloudflare" "Cloudflare Domain"
    echo -e "  ${DIM}دامنه یا ساب‌دامنه‌ای که پشت CDN Cloudflare است را وارد کنید.${R}"
    echo -e "  ${DIM}مثال: vpn.example.com یا cdn.mydomain.ir${R}\n"
    prompt_input "دامنه Cloudflare" "${PANEL_CF_DOMAIN:-}" PANEL_CF_DOMAIN
    save_config
    log_success "دامنه Cloudflare ذخیره شد: ${PANEL_CF_DOMAIN}"
    press_enter
}

configure_telegram_bot() {
    draw_header "تنظیم ربات تلگرام" "Telegram Bot Configuration"
    echo -e "  ${DIM}برای دریافت توکن: @BotFather در تلگرام${R}\n"
    prompt_input "توکن ربات" "${PANEL_TG_TOKEN:-}" PANEL_TG_TOKEN
    prompt_input "Chat ID ادمین" "${PANEL_TG_CHAT_ID:-}" PANEL_TG_CHAT_ID

    if [[ -n "$PANEL_TG_TOKEN" && -n "$PANEL_TG_CHAT_ID" ]]; then
        echo -ne "  ${YELLOW}⟳${R}  در حال تست اتصال..."
        local test_result
        test_result=$(curl -s --max-time 10 \
            "https://api.telegram.org/bot${PANEL_TG_TOKEN}/sendMessage" \
            -d "chat_id=${PANEL_TG_CHAT_ID}&text=✅ پنل X-UI سنایی به ربات متصل شد!" \
            2>/dev/null)
        if echo "$test_result" | jq -e '.ok' &>/dev/null; then
            log_success "اتصال ربات موفق! پیام تست ارسال شد."
        else
            log_error "اتصال ناموفق. توکن یا Chat ID را بررسی کنید."
        fi
    fi
    save_config
    press_enter
}

configure_clean_ips() {
    draw_header "IP تمیز Cloudflare" "Clean IP Configuration"
    echo -e "  ${DIM}آی‌پی‌های تمیز را با Enter جدا کنید (یک در هر خط).${R}"
    echo -e "  ${DIM}برای پایان خط خالی + Enter را بفشارید.${R}"
    echo -e "  ${YELLOW}آی‌پی‌های پیش‌فرض:${R}"
    for ip in "${CF_CLEAN_IPS[@]}"; do echo -e "    ${DIM}${ip}${R}"; done
    echo ""
    echo -e "  ${CYAN}آی‌پی‌های سفارشی (یکی در هر خط، خالی=استفاده از پیش‌فرض):${R}"
    local custom_ips=()
    while IFS= read -r line && [[ -n "$line" ]]; do
        custom_ips+=("$line")
    done
    if [[ ${#custom_ips[@]} -gt 0 ]]; then
        PANEL_CF_CLEAN_IPS=$(IFS=','; echo "${custom_ips[*]}")
    fi
    save_config
    log_success "لیست IP تمیز ذخیره شد."
    press_enter
}

configure_custom_snis() {
    draw_header "SNI های سفارشی" "Custom SNI List"
    echo -e "  ${DIM}SNI های پیش‌فرض:${R}"
    for sni in "${DEFAULT_SNIS[@]}"; do echo -e "    ${DIM}${sni}${R}"; done
    echo ""
    echo -e "  ${CYAN}SNI های سفارشی (یکی در هر خط):${R}"
    local custom_snis=()
    while IFS= read -r line && [[ -n "$line" ]]; do
        custom_snis+=("$line")
    done
    if [[ ${#custom_snis[@]} -gt 0 ]]; then
        PANEL_CUSTOM_SNIS=$(IFS=','; echo "${custom_snis[*]}")
    fi
    save_config
    log_success "SNI های سفارشی ذخیره شد."
    press_enter
}

configure_subscription_server() {
    draw_header "سرور ساب‌اسکریپشن" "Subscription Server"
    prompt_input "پورت سرور ساب‌اسکریپشن" "${PANEL_SUB_PORT:-8080}" PANEL_SUB_PORT
    save_config
    setup_subscription_server
    press_enter
}

# ==============================================================================
# SECTION 13: MAIN MENU
# ==============================================================================

main_menu() {
    while true; do
        draw_header "🛡  ${PANEL_NAME}" "v${PANEL_VERSION} | مدیریت حرفه‌ای X-UI Sanaei"
        draw_status_bar
        echo ""
        draw_section "منوی اصلی"
        echo ""
        draw_menu_item  "1"  "👥"  "مدیریت کاربران"              "افزودن، ویرایش، حذف، آمار"
        draw_menu_item  "2"  "⚙️"  "مدیریت اینباند‌ها"           "پروتکل‌ها و تنظیمات"
        draw_menu_item  "3"  "🔧"  "تولید کانفیگ"                "VLESS، VMess، Trojan، HY2، XHTTP"
        draw_menu_item  "4"  "☁️"  "یکپارچه‌سازی Cloudflare"     "CDN، IP تمیز، دامنه"
        draw_menu_item  "5"  "🔗"  "سیستم ساب‌اسکریپشن"          "لینک اشتراک کلاینت‌ها"
        draw_menu_item  "6"  "🤖"  "ربات تلگرام"                 "بکاپ، نوتیف، مانیتورینگ"
        draw_menu_item  "7"  "💾"  "سیستم بکاپ"                  "ذخیره و بازیابی دیتابیس"
        draw_menu_item  "8"  "🔒"  "SSL و امنیت پنل"             "sslip.io، Let's Encrypt"
        draw_menu_item  "9"  "🔌"  "مدیریت سرویس X-UI"           "شروع، توقف، لاگ"
        draw_menu_item "10"  "🛠️"  "تنظیمات پنل"                 "پیکربندی کلی"
        draw_menu_item "11"  "📦"  "بررسی وابستگی‌ها"            "نصب پکیج‌های مورد نیاز"
        draw_menu_item_warn "12" "🔄" "بروزرسانی اسکریپت"        "دریافت آخرین نسخه از GitHub"
        draw_menu_item_warn  "0"  "🚪"  "خروج"                   ""
        draw_menu_footer
        echo -ne "  ${B}${CYAN}انتخاب: ${R}"
        read -r choice
        case "$choice" in
            1)  user_management_menu ;;
            2)  inbound_management_menu ;;
            3)  config_generation_menu ;;
            4)  cloudflare_menu ;;
            5)  subscription_menu ;;
            6)  telegram_bot_menu ;;
            7)  backup_menu ;;
            8)  ssl_menu ;;
            9)  service_management_menu ;;
            10) panel_settings_menu ;;
            11) check_and_install_dependencies ;;
            12) self_update ;;
            0|"exit"|"quit") clear; echo -e "${GREEN}خداحافظ!${R}"; exit 0 ;;
            *)  log_warn "گزینه نامعتبر است."; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# SECTION 14: INITIALIZATION
# ==============================================================================

initialize() {
    ensure_dir "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    load_config

    if [[ ! -f "$XUI_DB" ]]; then
        echo -e "${YELLOW}[هشدار] دیتابیس X-UI یافت نشد: ${XUI_DB}${R}"
        echo -e "${DIM}مطمئن شوید X-UI Sanaei نصب شده است.${R}"
    fi
}

# ==============================================================================
# ENTRY POINT - After sourcing all modules
# ==============================================================================

# Source the second part of the script if it exists (modular loading)
PART2="${SCRIPT_DIR}/xui-panel-part2.sh"
if [[ -f "$PART2" ]]; then
    # shellcheck source=/dev/null
    source "$PART2"
fi

initialize
main_menu
