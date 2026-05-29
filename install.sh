#!/bin/bash
# ============================================================
#   MasterPanel Installer v2.0
#   Protocols: Xray + TUIC v5 + Hysteria2
#   Language: English (system) | Persian (panel UI)
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

PANEL_DIR="/opt/masterpanel"
PANEL_PORT=9090
XRAY_DIR="/usr/local/bin"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
SERVICE_NAME="masterpanel"

print_banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║       MasterPanel Installer v2.0          ║"
    echo "  ║   Xray + TUIC v5 + Hysteria2 + More       ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Run as root: sudo bash install.sh"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS."
        exit 1
    fi
    . /etc/os-release
    log_info "Detected OS: $NAME $VERSION_ID"
}

get_user_input() {
    echo ""
    echo -e "${WHITE}=== Configuration ===${NC}"
    echo ""

    while true; do
        echo -ne "${CYAN}Enter your domain (e.g. vpn.example.com): ${NC}"
        read DOMAIN
        [[ -n "$DOMAIN" ]] && break
        log_warn "Domain cannot be empty."
    done

    while true; do
        echo -ne "${CYAN}Panel admin username (min 4 chars): ${NC}"
        read PANEL_USER
        [[ ${#PANEL_USER} -ge 4 ]] && break
        log_warn "Username must be at least 4 characters."
    done

    while true; do
        echo -ne "${CYAN}Panel admin password (min 8 chars): ${NC}"
        read -s PANEL_PASS
        echo ""
        [[ ${#PANEL_PASS} -ge 8 ]] && break
        log_warn "Password must be at least 8 characters."
    done

    echo ""
    log_info "Domain   : $DOMAIN"
    log_info "Username : $PANEL_USER"
    log_info "Port     : $PANEL_PORT"
    echo ""
    echo -ne "${YELLOW}Continue? [y/N]: ${NC}"
    read CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        log_warn "Installation cancelled."
        exit 0
    fi
}

install_dependencies() {
    log_step "Installing system dependencies..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl wget unzip python3 python3-pip python3-venv \
        certbot ufw openssl uuid-runtime jq net-tools \
        qrencode ca-certificates 2>/dev/null || true
    log_info "Dependencies installed."
}

install_xray() {
    log_step "Installing Xray-core (latest)..."
    XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest \
        | jq -r '.tag_name' 2>/dev/null || echo "v1.8.13")
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
    rm -rf /tmp/xray.zip /tmp/xray_tmp/
    mkdir -p "$XRAY_CONFIG_DIR"
    log_info "Xray installed: $($XRAY_DIR/xray version | head -1)"
}

install_tuic() {
    log_step "Installing TUIC v5..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  TUIC_ARCH="x86_64-unknown-linux-gnu" ;;
        aarch64) TUIC_ARCH="aarch64-unknown-linux-gnu" ;;
        *)       TUIC_ARCH="x86_64-unknown-linux-gnu" ;;
    esac

    TUIC_VER=$(curl -s https://api.github.com/repos/EAimTY/tuic/releases/latest \
        | jq -r '.tag_name' 2>/dev/null || echo "tuic-server-1.0.0")
    TUIC_URL="https://github.com/EAimTY/tuic/releases/download/${TUIC_VER}/tuic-server-${TUIC_ARCH}"

    if wget -q "$TUIC_URL" -O /tmp/tuic-server 2>/dev/null; then
        mv /tmp/tuic-server /usr/local/bin/tuic-server
        chmod +x /usr/local/bin/tuic-server
        log_info "TUIC v5 installed."
    else
        log_warn "TUIC download failed — will skip TUIC configs."
        touch /tmp/tuic_failed
    fi
}

install_hysteria2() {
    log_step "Installing Hysteria2..."
    HY2_INSTALL=$(curl -fsSL https://get.hy2.sh/ 2>/dev/null)
    if [[ -n "$HY2_INSTALL" ]]; then
        bash <(echo "$HY2_INSTALL") --version latest 2>&1 | tail -3
        if command -v hysteria &>/dev/null; then
            log_info "Hysteria2 installed: $(hysteria version 2>/dev/null | head -1)"
        else
            log_warn "Hysteria2 install may have failed — checking..."
            # fallback: direct binary
            ARCH=$(uname -m)
            case $ARCH in
                x86_64)  HY2_ARCH="amd64" ;;
                aarch64) HY2_ARCH="arm64" ;;
                *)       HY2_ARCH="amd64" ;;
            esac
            HY2_VER=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest \
                | jq -r '.tag_name' 2>/dev/null | sed 's/app\///' || echo "v2.4.5")
            wget -q "https://github.com/apernet/hysteria/releases/download/app%2F${HY2_VER}/hysteria-linux-${HY2_ARCH}" \
                -O /usr/local/bin/hysteria 2>/dev/null || true
            chmod +x /usr/local/bin/hysteria 2>/dev/null || true
            log_info "Hysteria2 fallback install done."
        fi
    else
        log_warn "Could not reach Hysteria2 installer. Trying direct download..."
        ARCH=$(uname -m)
        [[ "$ARCH" == "aarch64" ]] && HY2_ARCH="arm64" || HY2_ARCH="amd64"
        wget -q "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-${HY2_ARCH}" \
            -O /usr/local/bin/hysteria 2>/dev/null || touch /tmp/hy2_failed
        chmod +x /usr/local/bin/hysteria 2>/dev/null || true
    fi
}

obtain_ssl() {
    log_step "Obtaining SSL certificate for $DOMAIN..."
    systemctl stop masterpanel 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true
    sleep 1

    certbot certonly --standalone \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        -d "$DOMAIN" \
        --preferred-challenges http \
        2>&1 | tail -5

    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

    if [[ ! -f "$CERT_PATH" ]]; then
        log_error "SSL certificate not obtained. Make sure:"
        log_error "  1. Domain DNS A record points to this server IP"
        log_error "  2. Port 80 is open and not blocked"
        exit 1
    fi
    # Make certs readable by services
    chmod 644 "$CERT_PATH" "$KEY_PATH"
    log_info "SSL certificate obtained successfully."
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
TUIC_BIN=/usr/local/bin/tuic-server
HY2_BIN=/usr/local/bin/hysteria
CONF

    log_info "Panel configured."
}

copy_panel_files() {
    log_step "Installing panel application files..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    for FILE in masterpanel.py index.html; do
        if [[ -f "$SCRIPT_DIR/$FILE" ]]; then
            if [[ "$FILE" == "index.html" ]]; then
                cp "$SCRIPT_DIR/$FILE" "$PANEL_DIR/templates/$FILE"
            else
                cp "$SCRIPT_DIR/$FILE" "$PANEL_DIR/$FILE"
            fi
            log_info "Installed: $FILE"
        else
            log_error "$FILE not found in $SCRIPT_DIR"
            exit 1
        fi
    done
}

setup_firewall() {
    log_step "Configuring firewall..."
    declare -a PORTS=(
        "22/tcp" "80/tcp" "443/tcp" "443/udp"
        "9090/tcp"
        "2053/tcp" "2053/udp"
        "2083/tcp" "2083/udp"
        "2087/tcp" "2087/udp"
        "2096/tcp" "2096/udp"
        "8443/tcp" "8443/udp"
        "10086/tcp" "10087/tcp"
        "8388/tcp" "8388/udp"
        "8389/tcp" "8389/udp"
        "8390/tcp" "8390/udp"
        "8391/tcp" "8391/udp"
        "19999/udp"
        "51820/udp"
    )
    for PORT in "${PORTS[@]}"; do
        ufw allow "$PORT" > /dev/null 2>&1 || true
    done
    ufw --force enable > /dev/null 2>&1 || true
    log_info "Firewall configured ($(echo ${#PORTS[@]}) rules added)."
}

create_services() {
    log_step "Creating systemd services..."

    # ── MasterPanel panel service ──────────────────────────
    cat > "/etc/systemd/system/masterpanel.service" << SVC
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

    # ── TUIC service ──────────────────────────────────────
    if [[ -f /usr/local/bin/tuic-server ]] && [[ ! -f /tmp/tuic_failed ]]; then
        cat > "/etc/systemd/system/tuic-server.service" << SVC
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

    # ── Hysteria2 service ─────────────────────────────────
    if [[ -f /usr/local/bin/hysteria ]] && [[ ! -f /tmp/hy2_failed ]]; then
        mkdir -p /etc/hysteria
        cat > "/etc/systemd/system/hysteria2.service" << SVC
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

    # Start panel
    systemctl enable masterpanel > /dev/null 2>&1
    systemctl start masterpanel
    sleep 2

    if systemctl is-active --quiet masterpanel; then
        log_info "MasterPanel started successfully."
    else
        log_error "Panel failed. Check: journalctl -u masterpanel -n 30"
    fi
}

setup_ssl_renewal() {
    log_step "Setting up SSL auto-renewal..."
    CRON_CMD="0 3 * * * certbot renew --quiet --pre-hook 'systemctl stop masterpanel' --post-hook 'systemctl start masterpanel && systemctl restart tuic-server 2>/dev/null; systemctl restart hysteria2 2>/dev/null'"
    (crontab -l 2>/dev/null | grep -v certbot; echo "$CRON_CMD") | crontab -
    log_info "SSL auto-renewal configured."
}

print_summary() {
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Installation Complete! ✓  v2.0       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${WHITE}Panel URL   :${NC} ${CYAN}http://$SERVER_IP:$PANEL_PORT${NC}"
    echo -e "  ${WHITE}Username    :${NC} ${CYAN}$PANEL_USER${NC}"
    echo -e "  ${WHITE}Domain      :${NC} ${CYAN}$DOMAIN${NC}"
    echo -e "  ${WHITE}Server IP   :${NC} ${CYAN}$SERVER_IP${NC}"
    echo ""
    echo -e "  ${WHITE}Installed:${NC}"
    echo -ne "  Xray     : "; $XRAY_DIR/xray version 2>/dev/null | head -1 || echo "installed"
    echo -ne "  TUIC v5  : "
    [[ -f /usr/local/bin/tuic-server ]] && echo "installed ✓" || echo "skipped ✗"
    echo -ne "  Hysteria2: "
    [[ -f /usr/local/bin/hysteria ]] && /usr/local/bin/hysteria version 2>/dev/null | head -1 || echo "skipped ✗"
    echo ""
    echo -e "  ${YELLOW}Next steps:${NC}"
    echo -e "  1. Go to panel → click 'ساخت همه پروتکل‌ها'"
    echo -e "  2. Test configs from the 'تست اتصال' page"
    echo -e "  3. Download your subscription link"
    echo ""
    echo -e "  ${YELLOW}Manage:${NC}"
    echo -e "  bash /opt/masterpanel/mp.sh status"
    echo -e "  bash /opt/masterpanel/mp.sh restart"
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
copy_panel_files
setup_firewall
create_services
setup_ssl_renewal
print_summary
