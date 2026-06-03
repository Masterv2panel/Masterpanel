#!/bin/bash
# ============================================================
#   MasterPanel Installer v4.0
#   Protocols: Xray + TUIC v5 + Hysteria2
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

PANEL_DIR="/opt/masterpanel"
PANEL_PORT=9090
XRAY_DIR="/usr/local/bin"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
GITHUB_RAW="https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main"

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║       MasterPanel Installer v4.0          ║"
    echo "  ║   Xray + TUIC v5 + Hysteria2              ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    [[ $EUID -ne 0 ]] && { log_error "Run as root!"; exit 1; }
}

check_os() {
    [[ -f /etc/os-release ]] && . /etc/os-release || { log_error "Cannot detect OS"; exit 1; }
    log_info "OS: $NAME $VERSION_ID"
}

get_user_input() {
    echo ""
    echo -e "${WHITE}=== Configuration ===${NC}"
    echo ""
    while true; do
        echo -ne "${CYAN}Domain (e.g. vpn.example.com): ${NC}"
        read DOMAIN; [[ -n "$DOMAIN" ]] && break
        log_warn "Domain cannot be empty."
    done
    while true; do
        echo -ne "${CYAN}Admin username (min 4 chars): ${NC}"
        read PANEL_USER; [[ ${#PANEL_USER} -ge 4 ]] && break
        log_warn "Min 4 characters."
    done
    while true; do
        echo -ne "${CYAN}Admin password (min 8 chars): ${NC}"
        read -s PANEL_PASS; echo ""
        [[ ${#PANEL_PASS} -ge 8 ]] && break
        log_warn "Min 8 characters."
    done
    echo ""
    log_info "Domain : $DOMAIN"
    log_info "User   : $PANEL_USER"
    log_info "Port   : $PANEL_PORT"
    echo ""
    echo -ne "${YELLOW}Continue? [y/N]: ${NC}"; read CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && { log_warn "Cancelled."; exit 0; }
}

install_dependencies() {
    log_step "Installing dependencies..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl wget unzip python3 python3-pip python3-venv \
        certbot ufw openssl uuid-runtime jq net-tools ca-certificates 2>/dev/null || true
    log_info "Dependencies installed."
}

install_xray() {
    log_step "Installing Xray-core..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  XRAY_ARCH="64" ;;
        aarch64) XRAY_ARCH="arm64-v8a" ;;
        armv7l)  XRAY_ARCH="arm32-v7a" ;;
        *)       XRAY_ARCH="64" ;;
    esac

    XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest \
        | jq -r '.tag_name' 2>/dev/null || echo "v1.8.13")
    log_info "Downloading Xray ${XRAY_VERSION}..."
    wget -q "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip" -O /tmp/xray.zip
    unzip -o /tmp/xray.zip -d /tmp/xray_tmp/ > /dev/null
    mv /tmp/xray_tmp/xray "$XRAY_DIR/xray"
    chmod +x "$XRAY_DIR/xray"
    rm -rf /tmp/xray.zip /tmp/xray_tmp/
    mkdir -p "$XRAY_CONFIG_DIR"

    # ── Xray systemd service ──────────────────────────────
    cat > /etc/systemd/system/xray.service << 'SVC'
[Unit]
Description=Xray Service
Documentation=https://xtls.github.io
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
SVC
    systemctl daemon-reload
    systemctl enable xray > /dev/null 2>&1

    # ── GeoIP + GeoSite data ──────────────────────────────
    log_info "Downloading geoip.dat and geosite.dat..."
    wget -q "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" \
        -O "$XRAY_DIR/geoip.dat" || log_warn "geoip.dat download failed"
    wget -q "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
        -O "$XRAY_DIR/geosite.dat" || log_warn "geosite.dat download failed"

    log_info "Xray installed: $($XRAY_DIR/xray version | head -1)"
}

install_tuic() {
    log_step "Installing TUIC v5..."
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && TUIC_ARCH="aarch64-unknown-linux-gnu" || TUIC_ARCH="x86_64-unknown-linux-gnu"

    TUIC_VER=$(curl -s https://api.github.com/repos/EAimTY/tuic/releases/latest \
        | jq -r '.tag_name' 2>/dev/null || echo "tuic-server-1.0.0")
    TUIC_URL="https://github.com/EAimTY/tuic/releases/download/${TUIC_VER}/tuic-server-${TUIC_ARCH}"

    if wget -q "$TUIC_URL" -O /tmp/tuic-server 2>/dev/null; then
        mv /tmp/tuic-server /usr/local/bin/tuic-server
        chmod +x /usr/local/bin/tuic-server
        log_info "TUIC v5 installed."
    else
        log_warn "TUIC download failed — skipping."
        touch /tmp/tuic_failed
    fi
}

install_hysteria2() {
    log_step "Installing Hysteria2..."
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && HY2_ARCH="arm64" || HY2_ARCH="amd64"

    # Method 1: official installer (without --version flag)
    if curl -fsSL https://get.hy2.sh/ -o /tmp/hy2_install.sh 2>/dev/null; then
        bash /tmp/hy2_install.sh 2>&1 | tail -3
        if command -v hysteria &>/dev/null || [[ -f /usr/local/bin/hysteria ]]; then
            log_info "Hysteria2 installed: $(hysteria version 2>/dev/null | head -1 || echo 'OK')"
            return
        fi
    fi

    # Method 2: direct binary from GitHub
    log_warn "Trying direct download..."
    HY2_VER=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest \
        | jq -r '.tag_name' 2>/dev/null | sed 's|app/||' || echo "v2.4.5")
    HY2_URL="https://github.com/apernet/hysteria/releases/download/app%2F${HY2_VER}/hysteria-linux-${HY2_ARCH}"
    if wget -q "$HY2_URL" -O /usr/local/bin/hysteria 2>/dev/null; then
        chmod +x /usr/local/bin/hysteria
        log_info "Hysteria2 installed (direct): $(/usr/local/bin/hysteria version 2>/dev/null | head -1 || echo 'OK')"
    else
        log_warn "Hysteria2 installation failed — skipping."
        touch /tmp/hy2_failed
    fi
}

obtain_ssl() {
    log_step "Obtaining SSL for $DOMAIN..."
    systemctl stop masterpanel 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true
    sleep 1

    certbot certonly --standalone \
        --non-interactive --agree-tos \
        --register-unsafely-without-email \
        -d "$DOMAIN" 2>&1 | tail -5

    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

    if [[ ! -f "$CERT_PATH" ]]; then
        log_error "SSL failed. Check DNS and port 80."
        exit 1
    fi
    chmod 644 "$CERT_PATH" "$KEY_PATH" 2>/dev/null || true
    log_info "SSL obtained."
}

setup_panel() {
    log_step "Setting up MasterPanel..."
    mkdir -p "$PANEL_DIR"/{templates,static,configs,logs}

    python3 -m venv "$PANEL_DIR/venv"
    "$PANEL_DIR/venv/bin/pip" install -q --upgrade pip
    "$PANEL_DIR/venv/bin/pip" install -q flask requests

    cat > "$PANEL_DIR/panel.conf" << CONF
DOMAIN=$DOMAIN
PANEL_USER=$PANEL_USER
PANEL_PASS=$PANEL_PASS
PANEL_PORT=$PANEL_PORT
CERT_PATH=/etc/letsencrypt/live/$DOMAIN/fullchain.pem
KEY_PATH=/etc/letsencrypt/live/$DOMAIN/privkey.pem
XRAY_CONFIG_DIR=$XRAY_CONFIG_DIR
XRAY_BIN=$XRAY_DIR/xray
CONF

    # Write version file
    echo "4.0.0" > "$PANEL_DIR/version.txt"
    log_info "Panel configured."
}

download_panel_files() {
    log_step "Downloading panel files from GitHub..."

    # First try local files (if install.sh is run from downloaded folder)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -f "$SCRIPT_DIR/masterpanel.py" ]] && [[ -f "$SCRIPT_DIR/index.html" ]]; then
        log_info "Using local files..."
        cp "$SCRIPT_DIR/masterpanel.py" "$PANEL_DIR/masterpanel.py"
        cp "$SCRIPT_DIR/index.html" "$PANEL_DIR/templates/index.html"
        log_info "Local files installed."
    else
        # Download from GitHub
        log_info "Downloading from GitHub..."
        for FILE in masterpanel.py index.html; do
            DEST="$PANEL_DIR/masterpanel.py"
            [[ "$FILE" == "index.html" ]] && DEST="$PANEL_DIR/templates/index.html"
            if wget -q "$GITHUB_RAW/$FILE" -O "$DEST"; then
                log_info "Downloaded: $FILE"
            else
                log_error "Failed to download $FILE from GitHub"
                log_error "Make sure files are uploaded to: $GITHUB_RAW"
                exit 1
            fi
        done
    fi
}

setup_firewall() {
    log_step "Configuring firewall..."
    for PORT in 22/tcp 80/tcp 443/tcp 443/udp 9090/tcp \
                2053/tcp 2053/udp 2083/tcp 2083/udp \
                2087/tcp 2087/udp 2096/tcp 2096/udp \
                8443/tcp 8443/udp 8444/udp \
                10086/tcp 10087/tcp \
                8388/tcp 8389/tcp 8390/tcp 8391/tcp 8392/tcp 8393/tcp \
                19999/udp 51820/udp; do
        ufw allow "$PORT" > /dev/null 2>&1 || true
    done
    ufw --force enable > /dev/null 2>&1 || true
    log_info "Firewall configured."
}

create_services() {
    log_step "Creating systemd services..."

    # MasterPanel
    cat > /etc/systemd/system/masterpanel.service << SVC
[Unit]
Description=MasterPanel - Xray Control Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PANEL_DIR
ExecStart=$PANEL_DIR/venv/bin/python3 $PANEL_DIR/masterpanel.py
Restart=always
RestartSec=5
StandardOutput=append:$PANEL_DIR/logs/panel.log
StandardError=append:$PANEL_DIR/logs/panel.log

[Install]
WantedBy=multi-user.target
SVC

    # TUIC
    if [[ -f /usr/local/bin/tuic-server && ! -f /tmp/tuic_failed ]]; then
        cat > /etc/systemd/system/tuic-server.service << SVC
[Unit]
Description=TUIC v5 Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/tuic-server -c $PANEL_DIR/configs/tuic_config.json
Restart=always
RestartSec=5
StandardOutput=append:$PANEL_DIR/logs/tuic.log
StandardError=append:$PANEL_DIR/logs/tuic.log

[Install]
WantedBy=multi-user.target
SVC
        systemctl enable tuic-server > /dev/null 2>&1 || true
        log_info "TUIC service created."
    fi

    # Hysteria2
    if [[ -f /usr/local/bin/hysteria && ! -f /tmp/hy2_failed ]]; then
        cat > /etc/systemd/system/hysteria2.service << SVC
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/hysteria server -c $PANEL_DIR/configs/hysteria2_config.yaml
Restart=always
RestartSec=5
StandardOutput=append:$PANEL_DIR/logs/hysteria2.log
StandardError=append:$PANEL_DIR/logs/hysteria2.log

[Install]
WantedBy=multi-user.target
SVC
        systemctl enable hysteria2 > /dev/null 2>&1 || true
        log_info "Hysteria2 service created."
    fi

    systemctl daemon-reload

    # Start MasterPanel
    systemctl enable masterpanel > /dev/null 2>&1
    systemctl start masterpanel
    sleep 3

    # Start Xray (will start properly after first config generation)
    systemctl enable xray > /dev/null 2>&1 || true

    if systemctl is-active --quiet masterpanel; then
        log_info "MasterPanel started."
    else
        log_error "Panel failed. Check: journalctl -u masterpanel -n 30"
        journalctl -u masterpanel -n 20 --no-pager
    fi
}

setup_ssl_renewal() {
    log_step "SSL auto-renewal..."
    (crontab -l 2>/dev/null | grep -v certbot
    echo "0 3 * * * certbot renew --quiet --deploy-hook 'systemctl restart xray 2>/dev/null; systemctl restart tuic-server 2>/dev/null; systemctl restart hysteria2 2>/dev/null; systemctl restart masterpanel'"
    ) | crontab -
    log_info "Auto-renewal configured."
}

print_summary() {
    SERVER_IP=$(curl -4 -s https://api4.ipify.org 2>/dev/null \
        || curl -4 -s https://ipv4.icanhazip.com 2>/dev/null \
        || hostname -I | awk '{for(i=1;i<=NF;i++) if($i !~ /:/) {print $i; exit}}')

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      MasterPanel v4.0 — Installed! ✓           ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${WHITE}Panel URL :${NC} ${CYAN}http://$SERVER_IP:$PANEL_PORT${NC}"
    echo -e "  ${WHITE}Username  :${NC} ${CYAN}$PANEL_USER${NC}"
    echo -e "  ${WHITE}Domain    :${NC} ${CYAN}$DOMAIN${NC}"
    echo ""
    echo -e "  ${YELLOW}⚠  Open panel with IP, NOT domain (CF blocks port 9090)${NC}"
    echo -e "  ${GREEN}→  http://$SERVER_IP:$PANEL_PORT${NC}"
    echo ""
    echo -e "  ${WHITE}Installed:${NC}"
    echo -ne "  Xray      : "; $XRAY_DIR/xray version 2>/dev/null | head -1 || echo "OK"
    echo -ne "  TUIC v5   : "; [[ -f /usr/local/bin/tuic-server ]] && echo "✓" || echo "skipped"
    echo -ne "  Hysteria2 : "; [[ -f /usr/local/bin/hysteria ]] && (hysteria version 2>/dev/null | head -1 || echo "✓") || echo "skipped"
    echo ""
    echo -e "  ${YELLOW}Next steps:${NC}"
    echo -e "  1. Open panel → click 'ساخت همه پروتکل‌ها'"
    echo -e "  2. Test configs from 'تست اتصال'"
    echo -e "  3. Future updates: Panel → Update button"
    echo ""
    echo -e "  ${WHITE}Manage:${NC}"
    echo -e "  bash /opt/masterpanel/mp.sh status"
    echo -e "  bash /opt/masterpanel/mp.sh restart-all"
    echo ""
}

# ══ MAIN ══════════════════════════════════════════════════════
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
download_panel_files
setup_firewall
create_services
setup_ssl_renewal
print_summary
