#!/bin/bash
# ============================================================
#   MasterPanel - Xray Auto Configurator
#   Installer Script v1.0
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
    echo "  ║         MasterPanel Installer v1.0        ║"
    echo "  ║       Xray Auto Protocol Configurator     ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${BLUE}[STEP]${NC}  $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root."
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
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        log_warn "This script is tested on Ubuntu/Debian. Proceed with caution."
    fi
}

get_user_input() {
    echo ""
    echo -e "${WHITE}=== Configuration ===${NC}"
    echo ""

    # Domain
    while true; do
        read -p "$(echo -e ${CYAN}Enter your domain (e.g. vpn.example.com): ${NC})" DOMAIN
        if [[ -n "$DOMAIN" ]]; then
            break
        fi
        log_warn "Domain cannot be empty."
    done

    # Panel username
    while true; do
        read -p "$(echo -e ${CYAN}Panel admin username: ${NC})" PANEL_USER
        if [[ ${#PANEL_USER} -ge 4 ]]; then
            break
        fi
        log_warn "Username must be at least 4 characters."
    done

    # Panel password
    while true; do
        read -s -p "$(echo -e ${CYAN}Panel admin password: ${NC})" PANEL_PASS
        echo ""
        if [[ ${#PANEL_PASS} -ge 8 ]]; then
            break
        fi
        log_warn "Password must be at least 8 characters."
    done

    echo ""
    log_info "Domain   : $DOMAIN"
    log_info "Username : $PANEL_USER"
    log_info "Port     : $PANEL_PORT"
    echo ""
    read -p "$(echo -e ${YELLOW}Continue? [y/N]: ${NC})" CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        log_warn "Installation cancelled."
        exit 0
    fi
}

install_dependencies() {
    log_step "Installing system dependencies..."
    apt-get update -qq
    apt-get install -y -qq \
        curl wget unzip python3 python3-pip python3-venv \
        certbot ufw openssl uuid-runtime jq net-tools \
        qrencode 2>/dev/null || true
    log_info "Dependencies installed."
}

install_xray() {
    log_step "Installing Xray-core..."
    XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name' 2>/dev/null || echo "v1.8.10")
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  XRAY_ARCH="64" ;;
        aarch64) XRAY_ARCH="arm64-v8a" ;;
        *)       XRAY_ARCH="64" ;;
    esac

    XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"
    log_info "Downloading Xray ${XRAY_VERSION}..."
    wget -q "$XRAY_URL" -O /tmp/xray.zip
    unzip -o /tmp/xray.zip -d /tmp/xray_extract/ > /dev/null
    mv /tmp/xray_extract/xray "$XRAY_DIR/xray"
    chmod +x "$XRAY_DIR/xray"
    rm -rf /tmp/xray.zip /tmp/xray_extract/

    mkdir -p "$XRAY_CONFIG_DIR"
    log_info "Xray installed: $($XRAY_DIR/xray version | head -1)"
}

obtain_ssl() {
    log_step "Obtaining SSL certificate for $DOMAIN..."

    # Stop any service on port 80 temporarily
    systemctl stop masterpanel 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true

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
        log_error "SSL certificate not obtained. Check DNS and try again."
        exit 1
    fi
    log_info "SSL certificate obtained successfully."
}

setup_panel() {
    log_step "Setting up MasterPanel..."
    mkdir -p "$PANEL_DIR"/{templates,static,configs,logs}

    # Create Python virtual environment
    python3 -m venv "$PANEL_DIR/venv"
    "$PANEL_DIR/venv/bin/pip" install -q flask flask-login requests

    # Save config
    cat > "$PANEL_DIR/panel.conf" <<EOF
DOMAIN=$DOMAIN
PANEL_USER=$PANEL_USER
PANEL_PASS=$PANEL_PASS
PANEL_PORT=$PANEL_PORT
CERT_PATH=/etc/letsencrypt/live/$DOMAIN/fullchain.pem
KEY_PATH=/etc/letsencrypt/live/$DOMAIN/privkey.pem
XRAY_CONFIG_DIR=$XRAY_CONFIG_DIR
XRAY_BIN=$XRAY_DIR/xray
EOF

    log_info "Panel directory: $PANEL_DIR"
}

copy_panel_files() {
    log_step "Installing panel application files..."

    # Copy files from same directory as install.sh
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -f "$SCRIPT_DIR/masterpanel.py" ]]; then
        cp "$SCRIPT_DIR/masterpanel.py" "$PANEL_DIR/masterpanel.py"
    else
        log_error "masterpanel.py not found in $SCRIPT_DIR"
        log_error "Make sure install.sh and masterpanel.py are in the same directory."
        exit 1
    fi

    if [[ -f "$SCRIPT_DIR/index.html" ]]; then
        cp "$SCRIPT_DIR/index.html" "$PANEL_DIR/templates/index.html"
    else
        log_error "index.html not found in $SCRIPT_DIR"
        exit 1
    fi

    log_info "Panel files installed."
}

setup_firewall() {
    log_step "Configuring firewall..."
    ufw allow 22/tcp   > /dev/null 2>&1 || true
    ufw allow 80/tcp   > /dev/null 2>&1 || true
    ufw allow 443/tcp  > /dev/null 2>&1 || true
    ufw allow 9090/tcp > /dev/null 2>&1 || true
    ufw allow 8443/tcp > /dev/null 2>&1 || true
    ufw allow 2053/tcp > /dev/null 2>&1 || true
    ufw allow 2083/tcp > /dev/null 2>&1 || true
    ufw --force enable > /dev/null 2>&1 || true
    log_info "Firewall configured."
}

create_service() {
    log_step "Creating systemd service..."
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
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
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" > /dev/null 2>&1
    systemctl start "$SERVICE_NAME"
    sleep 2

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "MasterPanel service started successfully."
    else
        log_error "Service failed to start. Check: journalctl -u masterpanel -n 50"
    fi
}

setup_ssl_renewal() {
    log_step "Setting up SSL auto-renewal..."
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --pre-hook 'systemctl stop masterpanel' --post-hook 'systemctl start masterpanel'") | crontab -
    log_info "Auto-renewal cron job added."
}

print_summary() {
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Installation Complete! ✓              ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${WHITE}Panel URL  :${NC} ${CYAN}http://$SERVER_IP:$PANEL_PORT${NC}"
    echo -e "  ${WHITE}Username   :${NC} ${CYAN}$PANEL_USER${NC}"
    echo -e "  ${WHITE}Domain     :${NC} ${CYAN}$DOMAIN${NC}"
    echo -e "  ${WHITE}Xray       :${NC} ${CYAN}$($XRAY_DIR/xray version | head -1)${NC}"
    echo ""
    echo -e "  ${YELLOW}Manage service:${NC}"
    echo -e "  systemctl status masterpanel"
    echo -e "  systemctl restart masterpanel"
    echo -e "  tail -f $PANEL_DIR/logs/panel.log"
    echo ""
}

# === MAIN ===
print_banner
check_root
check_os
get_user_input
install_dependencies
install_xray
obtain_ssl
setup_panel
copy_panel_files
setup_firewall
create_service
setup_ssl_renewal
print_summary
