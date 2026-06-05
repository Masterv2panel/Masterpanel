#!/bin/bash
# ============================================================
#   MasterPanel Installer v3.0  —  Advanced Edition
#   Protocols: Xray (VLESS/VMess/Trojan/SS/REALITY/XHTTP)
#              TUIC v5 + Hysteria2
#   Features:  Multi-user SQLite | Ad-Block | Iran Bypass
#              Telegram Bot | GitHub Auto-Update
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

PANEL_DIR="/opt/masterpanel"
PANEL_PORT=9090
XRAY_DIR="/usr/local/bin"
XRAY_CONFIG_DIR="/usr/local/etc/xray"

print_banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║      MasterPanel Installer  v3.0 Advanced         ║"
    echo "  ║  Xray + TUIC v5 + Hysteria2 · Ad-Block · Bypass  ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }

check_root() {
    [[ $EUID -ne 0 ]] && log_error "Run as root: sudo bash install.sh" && exit 1
}

check_os() {
    [[ ! -f /etc/os-release ]] && log_error "Cannot detect OS." && exit 1
    . /etc/os-release
    log_info "OS: $NAME $VERSION_ID"
    [[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && \
        log_warn "Tested on Ubuntu/Debian — proceeding anyway."
}

get_user_input() {
    echo ""; echo -e "${WHITE}═══ Configuration ════════════════════════════════${NC}"; echo ""
    while true; do
        echo -ne "${CYAN}Domain (e.g. vpn.example.com): ${NC}"; read DOMAIN
        [[ -n "$DOMAIN" ]] && break; log_warn "Domain cannot be empty."
    done
    while true; do
        echo -ne "${CYAN}Admin username (min 4 chars): ${NC}"; read PANEL_USER
        [[ ${#PANEL_USER} -ge 4 ]] && break; log_warn "At least 4 characters."
    done
    while true; do
        echo -ne "${CYAN}Admin password (min 8 chars): ${NC}"; read -s PANEL_PASS; echo ""
        [[ ${#PANEL_PASS} -ge 8 ]] && break; log_warn "At least 8 characters."
    done
    echo ""
    log_info "Domain: $DOMAIN  |  User: $PANEL_USER  |  Port: $PANEL_PORT"
    echo ""
    echo -ne "${YELLOW}Continue? [y/N]: ${NC}"; read CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && log_warn "Cancelled." && exit 0
}

install_dependencies() {
    log_step "Installing system dependencies..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl wget git unzip python3 python3-pip python3-venv \
        certbot ufw openssl uuid-runtime jq net-tools \
        qrencode ca-certificates sqlite3 2>/dev/null || true
    log_info "Dependencies installed (including git, wget, curl)."
}

install_xray() {
    log_step "Installing Xray-core (latest)..."
    XRAY_VERSION=$(curl -s \
        https://api.github.com/repos/XTLS/Xray-core/releases/latest \
        | jq -r '.tag_name' 2>/dev/null || echo "v25.6.8")
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  XRAY_ARCH="64" ;;
        aarch64) XRAY_ARCH="arm64-v8a" ;;
        armv7l)  XRAY_ARCH="arm32-v7a" ;;
        *)       XRAY_ARCH="64" ;;
    esac
    XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"
    log_info "Downloading Xray ${XRAY_VERSION} (${XRAY_ARCH})..."
    wget -q "$XRAY_URL" -O /tmp/xray.zip
    unzip -o /tmp/xray.zip -d /tmp/xray_tmp/ > /dev/null

    mv /tmp/xray_tmp/xray "$XRAY_DIR/xray"
    chmod +x "$XRAY_DIR/xray"

    # Copy geo databases bundled with Xray (needed for routing rules)
    mkdir -p "$XRAY_CONFIG_DIR"
    for GEOFILE in geoip.dat geosite.dat; do
        if [[ -f "/tmp/xray_tmp/$GEOFILE" ]]; then
            cp "/tmp/xray_tmp/$GEOFILE" "$XRAY_CONFIG_DIR/$GEOFILE"
            log_info "Geo database bundled: $GEOFILE ✓"
        fi
    done

    rm -rf /tmp/xray.zip /tmp/xray_tmp/

    # Ensure geo databases exist (fallback: download from Loyalsoldier repo)
    _ensure_geo_databases

    log_info "Xray installed: $($XRAY_DIR/xray version 2>/dev/null | head -1)"
}

_ensure_geo_databases() {
    local MISSING=0
    [[ ! -f "$XRAY_CONFIG_DIR/geoip.dat"   ]] && MISSING=1
    [[ ! -f "$XRAY_CONFIG_DIR/geosite.dat" ]] && MISSING=1
    if [[ $MISSING -eq 1 ]]; then
        log_info "Downloading enhanced geo databases (Loyalsoldier/v2ray-rules-dat)..."
        local BASE="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"
        wget -q "$BASE/geoip.dat"   -O "$XRAY_CONFIG_DIR/geoip.dat"   2>/dev/null \
            || log_warn "geoip.dat download failed — Iran bypass may not work"
        wget -q "$BASE/geosite.dat" -O "$XRAY_CONFIG_DIR/geosite.dat" 2>/dev/null \
            || log_warn "geosite.dat download failed — Ad-Block may not work"
    fi
}

install_tuic() {
    log_step "Installing TUIC v5..."
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && TA="aarch64-unknown-linux-gnu" || TA="x86_64-unknown-linux-gnu"
    VER=$(curl -s https://api.github.com/repos/EAimTY/tuic/releases/latest \
        | jq -r '.tag_name' 2>/dev/null || echo "tuic-server-1.0.0")
    if wget -q \
        "https://github.com/EAimTY/tuic/releases/download/${VER}/tuic-server-${TA}" \
        -O /tmp/tuic-server 2>/dev/null; then
        mv /tmp/tuic-server /usr/local/bin/tuic-server
        chmod +x /usr/local/bin/tuic-server
        log_info "TUIC v5 installed."
    else
        log_warn "TUIC download failed — TUIC configs will be skipped."
        touch /tmp/tuic_failed
    fi
}

install_hysteria2() {
    log_step "Installing Hysteria2..."
    if curl -fsSL https://get.hy2.sh/ | bash 2>&1 | tail -3; then
        command -v hysteria &>/dev/null && \
            log_info "Hysteria2: $(hysteria version 2>/dev/null | head -1)" || \
            _install_hy2_direct
    else
        log_warn "Hysteria2 installer unreachable — trying direct download..."
        _install_hy2_direct
    fi
}

_install_hy2_direct() {
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && HY2A="arm64" || HY2A="amd64"
    HY2V=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest \
        | jq -r '.tag_name' 2>/dev/null | sed 's/app\///' || echo "v2.6.1")
    wget -q \
        "https://github.com/apernet/hysteria/releases/download/app%2F${HY2V}/hysteria-linux-${HY2A}" \
        -O /usr/local/bin/hysteria 2>/dev/null && chmod +x /usr/local/bin/hysteria \
        || { log_warn "Hysteria2 fallback failed."; touch /tmp/hy2_failed; }
}

obtain_ssl() {
    log_step "Obtaining SSL certificate for $DOMAIN..."
    systemctl stop masterpanel 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true
    sleep 1
    certbot certonly --standalone \
        --non-interactive --agree-tos \
        --register-unsafely-without-email \
        -d "$DOMAIN" --preferred-challenges http 2>&1 | tail -5
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    if [[ ! -f "$CERT_PATH" ]]; then
        log_error "SSL certificate not obtained. Verify DNS A record and port 80."
        exit 1
    fi
    chmod 644 "$CERT_PATH" "$KEY_PATH"
    log_info "SSL certificate obtained."
}

setup_panel() {
    log_step "Setting up MasterPanel v3.0..."
    mkdir -p "$PANEL_DIR"/{templates,static,configs,logs}
    python3 -m venv "$PANEL_DIR/venv"
    "$PANEL_DIR/venv/bin/pip" install -q --upgrade pip
    "$PANEL_DIR/venv/bin/pip" install -q flask requests apscheduler
    log_info "Python deps: flask + requests + apscheduler ✓"

    cat > "$PANEL_DIR/panel.conf" << PANELCONF
DOMAIN=$DOMAIN
PANEL_USER=$PANEL_USER
PANEL_PASS=$PANEL_PASS
PANEL_PORT=$PANEL_PORT
CERT_PATH=/etc/letsencrypt/live/$DOMAIN/fullchain.pem
KEY_PATH=/etc/letsencrypt/live/$DOMAIN/privkey.pem
XRAY_CONFIG_DIR=$XRAY_CONFIG_DIR
XRAY_BIN=$XRAY_DIR/xray
TUIC_BIN=/usr/local/bin/tuic-server
HY2_BIN=/usr/local/bin/hysteria
PANELCONF
    log_info "Panel configured."
}

copy_panel_files() {
    log_step "Installing panel application files..."

    local GH_REPO="Masterv2panel/Masterpanel"
    local GH_BRANCH="main"
    local GH_RAW="https://raw.githubusercontent.com/${GH_REPO}/${GH_BRANCH}"

    # ── Detect execution mode ─────────────────────────────────────
    # When run via  bash <(curl ...)  BASH_SOURCE[0] is empty, "bash",
    # or "/dev/fd/N" — none of those are real local paths.
    local SCRIPT_PATH="${BASH_SOURCE[0]:-}"
    local SCRIPT_DIR=""
    local IS_LOCAL=0

    if [[ -n "$SCRIPT_PATH" ]] && \
       [[ "$SCRIPT_PATH" != "bash" ]] && \
       [[ "$SCRIPT_PATH" != /dev/fd/* ]] && \
       [[ "$SCRIPT_PATH" != /proc/* ]] && \
       [[ -f "$SCRIPT_PATH" ]]; then
        SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
        IS_LOCAL=1
        log_info "Running from local directory: $SCRIPT_DIR"
    else
        log_info "Running via pipe/curl — files will be downloaded from GitHub."
    fi

    # ── File fetcher ──────────────────────────────────────────────
    _get_file() {
        local SRC="$1"   # filename in repo root
        local DST="$2"   # absolute destination path

        # 1. Try local directory (git clone / manual download)
        if [[ $IS_LOCAL -eq 1 ]] && [[ -f "$SCRIPT_DIR/$SRC" ]]; then
            cp "$SCRIPT_DIR/$SRC" "$DST"
            log_info "Installed (local): $SRC ✓"
            return 0
        fi

        # 2. wget from GitHub
        log_info "Downloading: $SRC ..."
        local TMP; TMP="/tmp/_mp_dl_$$_${SRC//\//_}"
        if wget -q --timeout=30 --tries=3 "${GH_RAW}/${SRC}" -O "$TMP" 2>/dev/null \
           && [[ -s "$TMP" ]]; then
            mv "$TMP" "$DST"
            log_info "Downloaded (wget): $SRC ✓"
            return 0
        fi
        rm -f "$TMP"

        # 3. curl fallback
        log_warn "wget failed — trying curl..."
        if curl -fsSL --max-time 30 "${GH_RAW}/${SRC}" -o "$DST" 2>/dev/null \
           && [[ -s "$DST" ]]; then
            log_info "Downloaded (curl): $SRC ✓"
            return 0
        fi

        # All methods failed
        log_error "Cannot download '${SRC}' from GitHub."
        log_error "Ensure the file exists at:"
        log_error "  https://github.com/${GH_REPO}/blob/${GH_BRANCH}/${SRC}"
        exit 1
    }

    mkdir -p "$PANEL_DIR/templates"
    _get_file "masterpanel.py" "$PANEL_DIR/masterpanel.py"
    _get_file "index.html"     "$PANEL_DIR/templates/index.html"
    _get_file "mp.sh"          "$PANEL_DIR/mp.sh"
    chmod +x "$PANEL_DIR/mp.sh"
}

# ══════════════════════════════════════════════════════════════════
#  inject_routing_rules
#
#  Patches write_xray_config() in masterpanel.py to add:
#
#  1. Ad-Block (outboundTag "blocked" → blackhole):
#     • geosite:youtube-ads        — YouTube ad domains
#     • geosite:category-ads-all   — General ads & trackers
#     • exoclick.com / juicyads.com / trafficjunky.com/.net
#
#  2. Iran Bypass (outboundTag "direct"):
#     • geosite:ir                 — Registered Iranian sites
#     • regexp:^.*\.ir$            — Any .ir subdomain/domain
#     • geoip:ir                   — Iranian IP address ranges
#
#  domainStrategy "IPIfNonMatch" enables hybrid domain+IP matching
#  for maximum routing accuracy with minimal latency overhead.
# ══════════════════════════════════════════════════════════════════
inject_routing_rules() {
    log_step "Injecting advanced routing rules..."

    local MPY="$PANEL_DIR/masterpanel.py"

    # Idempotent check
    if grep -q "geosite:ir\|geoip:ir\|youtube-ads" "$MPY" 2>/dev/null; then
        log_info "Advanced routing rules already present — skipping."
        return 0
    fi

    # Write patcher to a temp file (avoids heredoc nesting conflicts)
    local PATCHER="/tmp/_mp_routing_patcher_$$.py"
    cat > "$PATCHER" << 'PATCHEREOF'
import sys

path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as fh:
        src = fh.read()
except Exception as exc:
    print(f"[WARN] Cannot read {path}: {exc}")
    sys.exit(0)

# Exact string that exists in write_xray_config() routing section
OLD = (
    '        "routing": {\n'
    '            "rules": [\n'
    '                {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},\n'
    '                {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"},\n'
    '                {"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "blocked"},\n'
    '            ]\n'
    '        },'
)

NEW = (
    '        "routing": {\n'
    '            "domainStrategy": "IPIfNonMatch",\n'
    '            "rules": [\n'
    '                # ── Internal API — must be first ─────────────────────────\n'
    '                {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},\n'
    '                # ── Block private / LAN IPs ───────────────────────────────\n'
    '                {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"},\n'
    '                # ── Ad-Block: YouTube ad domains ──────────────────────────\n'
    '                {"type": "field", "domain": ["geosite:youtube-ads"], "outboundTag": "blocked"},\n'
    '                # ── Ad-Block: general ad & tracker category ───────────────\n'
    '                {"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "blocked"},\n'
    '                # ── Ad-Block: adult ad networks ───────────────────────────\n'
    '                {"type": "field", "domain": [\n'
    '                    "domain:exoclick.com",\n'
    '                    "domain:juicyads.com",\n'
    '                    "domain:trafficjunky.com",\n'
    '                    "domain:trafficjunky.net",\n'
    '                ], "outboundTag": "blocked"},\n'
    '                # ── Iran Bypass: .ir TLD + domestic sites ─────────────────\n'
    '                {"type": "field", "domain": [\n'
    '                    "geosite:ir",\n'
    '                    "regexp:^.*\\\\.ir$",\n'
    '                ], "outboundTag": "direct"},\n'
    '                # ── Iran Bypass: Iranian IP ranges ────────────────────────\n'
    '                {"type": "field", "ip": ["geoip:ir"], "outboundTag": "direct"},\n'
    '            ]\n'
    '        },'
)

if OLD in src:
    with open(path + '.pre_routing.bak', 'w', encoding='utf-8') as bk:
        bk.write(src)
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(src.replace(OLD, NEW, 1))
    print("[OK] Advanced routing rules injected successfully.")
    print("     Ad-Block  : youtube-ads | category-ads-all | adult networks")
    print("     Iran Bypass: geosite:ir + regexp:.ir + geoip:ir  → direct")
    print("     Strategy  : IPIfNonMatch (hybrid domain+IP resolution)")
else:
    print("[WARN] Could not find routing target in masterpanel.py")
    print("       Locate write_xray_config() and update routing rules manually.")
    sys.exit(1)
PATCHEREOF

    "$PANEL_DIR/venv/bin/python3" "$PATCHER" "$MPY"
    local RC=$?
    rm -f "$PATCHER"

    if [[ $RC -eq 0 ]]; then
        log_info "Routing injection complete ✓"
    else
        log_warn "Routing injection had issues — see output above."
    fi
}

# ── Weekly geo database auto-update cron ──────────────────────────
setup_geo_update_cron() {
    log_step "Configuring weekly geo database auto-update..."
    local GEO_SCRIPT="$PANEL_DIR/update_geo.sh"
    cat > "$GEO_SCRIPT" << 'GEOSCRIPT'
#!/bin/bash
# MasterPanel — Geo DB auto-updater (runs weekly via cron)
XRAY_DIR="/usr/local/etc/xray"
BASE="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"
TMP="/tmp/geo_mp_$$"
mkdir -p "$TMP"
wget -q "$BASE/geoip.dat"   -O "$TMP/geoip.dat"   2>/dev/null && mv "$TMP/geoip.dat"   "$XRAY_DIR/"
wget -q "$BASE/geosite.dat" -O "$TMP/geosite.dat"  2>/dev/null && mv "$TMP/geosite.dat" "$XRAY_DIR/"
rm -rf "$TMP"
systemctl restart xray 2>/dev/null || true
echo "[$(date '+%Y-%m-%d %H:%M')] Geo databases updated." >> /opt/masterpanel/logs/geo_update.log
GEOSCRIPT
    chmod +x "$GEO_SCRIPT"
    (crontab -l 2>/dev/null | grep -v update_geo; \
     echo "0 4 * * 0 bash $GEO_SCRIPT >> /opt/masterpanel/logs/geo_update.log 2>&1") | crontab -
    log_info "Geo auto-update cron: Sundays 04:00 ✓"
}

setup_firewall() {
    log_step "Configuring firewall (UFW)..."
    declare -a PORTS=(
        "22/tcp" "80/tcp" "9090/tcp"
        "443/tcp" "2053/tcp" "2083/tcp" "2087/tcp" "2096/tcp" "8443/tcp"
        "9443/tcp" "9444/tcp" "9445/tcp" "9446/tcp"
        "9447/tcp" "9448/tcp" "9449/tcp"
        "8388/tcp" "8388/udp" "8389/tcp" "8389/udp"
        "443/udp" "2053/udp" "51820/udp"
    )
    for PORT in "${PORTS[@]}"; do
        ufw allow "$PORT" > /dev/null 2>&1 || true
    done
    ufw --force enable > /dev/null 2>&1 || true
    log_info "Firewall: ${#PORTS[@]} rules applied ✓"
}

create_services() {
    log_step "Creating systemd services..."

    cat > "/etc/systemd/system/masterpanel.service" << 'MSVC'
[Unit]
Description=MasterPanel v3.0 - Xray Multi-User Control Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/masterpanel
ExecStart=/opt/masterpanel/venv/bin/python3 /opt/masterpanel/masterpanel.py
Restart=always
RestartSec=5
StandardOutput=append:/opt/masterpanel/logs/panel.log
StandardError=append:/opt/masterpanel/logs/panel.log

[Install]
WantedBy=multi-user.target
MSVC

    # Xray needs its own service so Stats API (port 10085) is accessible
    cat > "/etc/systemd/system/xray.service" << XSVC
[Unit]
Description=Xray-core (MasterPanel managed)
After=network.target masterpanel.service

[Service]
Type=simple
User=root
ExecStart=$XRAY_DIR/xray run -c $XRAY_CONFIG_DIR/config.json
Restart=on-failure
RestartSec=5
StandardOutput=append:$PANEL_DIR/logs/xray-access.log
StandardError=append:$PANEL_DIR/logs/xray-error.log
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
XSVC
    systemctl enable xray > /dev/null 2>&1 || true
    log_info "Xray service created ✓"

    if [[ -f /usr/local/bin/tuic-server ]] && [[ ! -f /tmp/tuic_failed ]]; then
        cat > "/etc/systemd/system/tuic-server.service" << TSVC
[Unit]
Description=TUIC v5 Server (MasterPanel managed)
After=network.target masterpanel.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/tuic-server -c $PANEL_DIR/configs/tuic_config.json
Restart=on-failure
RestartSec=5
StandardOutput=append:$PANEL_DIR/logs/tuic.log
StandardError=append:$PANEL_DIR/logs/tuic.log

[Install]
WantedBy=multi-user.target
TSVC
        systemctl enable tuic-server > /dev/null 2>&1 || true
        log_info "TUIC service created ✓"
    fi

    if [[ -f /usr/local/bin/hysteria ]] && [[ ! -f /tmp/hy2_failed ]]; then
        mkdir -p /etc/hysteria
        cat > "/etc/systemd/system/hysteria2.service" << HSVC
[Unit]
Description=Hysteria2 Server (MasterPanel managed)
After=network.target masterpanel.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/hysteria server -c $PANEL_DIR/configs/hysteria2_config.yaml
Restart=on-failure
RestartSec=5
StandardOutput=append:$PANEL_DIR/logs/hysteria2.log
StandardError=append:$PANEL_DIR/logs/hysteria2.log

[Install]
WantedBy=multi-user.target
HSVC
        systemctl enable hysteria2 > /dev/null 2>&1 || true
        log_info "Hysteria2 service created ✓"
    fi

    systemctl daemon-reload

    # Panel starts first — writes the initial Xray config from DB on boot
    systemctl enable masterpanel > /dev/null 2>&1
    systemctl start masterpanel
    sleep 4

    if systemctl is-active --quiet masterpanel; then
        log_info "MasterPanel started ✓"
    else
        log_error "Panel failed to start. Check: journalctl -u masterpanel -n 30"
    fi
}

setup_ssl_renewal() {
    log_step "Configuring SSL auto-renewal..."
    local PRE="systemctl stop masterpanel xray"
    local POST="systemctl start masterpanel; sleep 4; systemctl restart xray; systemctl restart tuic-server 2>/dev/null; systemctl restart hysteria2 2>/dev/null"
    local CRON="0 3 * * * certbot renew --quiet --pre-hook '$PRE' --post-hook '$POST'"
    (crontab -l 2>/dev/null | grep -v certbot; echo "$CRON") | crontab -
    log_info "SSL auto-renewal cron: daily 03:00 ✓"
}

print_summary() {
    SERVER_IP=$(curl -4 -s https://api4.ipify.org 2>/dev/null \
        || curl -4 -s https://ipv4.icanhazip.com 2>/dev/null \
        || hostname -I | awk '{for(i=1;i<=NF;i++) if($i !~ /:/) {print $i; exit}}')

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     MasterPanel v3.0 Advanced — Installation Complete! ✓  ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${WHITE}Panel URL   :${NC} ${CYAN}http://$SERVER_IP:$PANEL_PORT${NC}"
    echo -e "  ${WHITE}Username    :${NC} ${CYAN}$PANEL_USER${NC}"
    echo -e "  ${WHITE}Domain      :${NC} ${CYAN}$DOMAIN${NC}"
    echo -e "  ${WHITE}Server IP   :${NC} ${CYAN}$SERVER_IP${NC}"
    echo ""
    echo -e "  ${YELLOW}⚠  Open via IP, NOT domain (CF blocks port 9090):${NC}"
    echo -e "  ${GREEN}→ http://$SERVER_IP:$PANEL_PORT${NC}"
    echo ""
    echo -e "  ${WHITE}Installed components:${NC}"
    echo -ne "  Xray      : "; $XRAY_DIR/xray version 2>/dev/null | head -1 || echo "installed"
    echo -ne "  TUIC v5   : "
    [[ -f /usr/local/bin/tuic-server ]] && echo "installed ✓" || echo "skipped ✗"
    echo -ne "  Hysteria2 : "
    [[ -f /usr/local/bin/hysteria ]] \
        && (/usr/local/bin/hysteria version 2>/dev/null | head -1) \
        || echo "skipped ✗"
    echo ""
    echo -e "  ${WHITE}Premium routing active:${NC}"
    echo -e "  ${GREEN}✓${NC} Ad-Block    : YouTube ads + category-ads-all + adult ad networks"
    echo -e "  ${GREEN}✓${NC} Iran Bypass : geosite:ir + regexp:*.ir + geoip:ir → direct"
    echo -e "  ${GREEN}✓${NC} Geo DB      : Weekly auto-update (Sundays 04:00)"
    echo ""
    echo -e "  ${YELLOW}Next steps:${NC}"
    echo -e "  1. Open panel → «مدیریت کاربران» → add your first user"
    echo -e "  2. Click «مشاهده کانفیگ‌ها» → copy subscription link"
    echo -e "  3. (Optional) Configure Telegram bot in «تنظیمات»"
    echo ""
    echo -e "  ${YELLOW}Management CLI:${NC}"
    echo -e "  bash $PANEL_DIR/mp.sh status"
    echo -e "  bash $PANEL_DIR/mp.sh users"
    echo -e "  bash $PANEL_DIR/mp.sh add-user"
    echo ""
    echo -e "  ${YELLOW}GitHub:${NC}"
    echo -e "  https://github.com/Masterv2panel/Masterpanel"
    echo ""
}

# ══ MAIN ════════════════════════════════════════════════════════════
print_banner
check_root
check_os
get_user_input
install_dependencies
install_xray
install_tuic
install_hysteria2
obtain_ssl
setup_panel
copy_panel_files
inject_routing_rules
setup_geo_update_cron
setup_firewall
create_services
setup_ssl_renewal
print_summary
