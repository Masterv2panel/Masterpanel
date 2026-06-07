#!/bin/bash
# ============================================================
#   MasterPanel Installer v4.0
#   Protocols: Xray
# ============================================================

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
    echo "  ║   Xray + Multi-Protocol                   ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    [[ $EUID -ne 0 ]] && { log_error "Run as root!"; exit 1; }
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        log_info "OS: ${NAME:-Linux} ${VERSION_ID:-}"
    else
        log_warn "Cannot detect OS — continuing anyway"
    fi
}

get_user_input() {
    echo ""
    echo -e "${WHITE}=== Configuration ===${NC}"
    echo ""
    while true; do
        echo -ne "${CYAN}Domain (for VPN configs, e.g. vpn.example.com): ${NC}"
        read DOMAIN; [[ -n "$DOMAIN" ]] && break
        log_warn "Domain cannot be empty."
    done
    echo ""
    echo -e "${WHITE}Panel access:${NC} to open the panel over real HTTPS (no browser"
    echo -e "warning), use a subdomain set to ${YELLOW}DNS only${NC} (grey cloud) in Cloudflare,"
    echo -e "pointing straight to this server's IP. Leave blank to reuse the main domain."
    echo -ne "${CYAN}Panel domain (e.g. panel.example.com) [blank = $DOMAIN]: ${NC}"
    read PANEL_DOMAIN
    [[ -z "$PANEL_DOMAIN" ]] && PANEL_DOMAIN="$DOMAIN"
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
    log_info "Domain       : $DOMAIN"
    log_info "Panel domain : $PANEL_DOMAIN"
    log_info "User         : $PANEL_USER"
    log_info "Port         : $PANEL_PORT"
    echo ""
    echo -e "${YELLOW}Make sure DNS A records for BOTH '$DOMAIN' and '$PANEL_DOMAIN'"
    echo -e "point to this server, and are 'DNS only' (grey cloud) during install.${NC}"
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

    # ── GeoIP + GeoSite data (Iranian rules — has category-ir, ir, ads) ──
    log_info "Downloading Iranian geoip.dat and geosite.dat..."
    # Chocolate4U/Iran-v2ray-rules has: geosite:category-ir, geosite:ir,
    # geosite:category-ads-all, geoip:ir — required for ad-block + IR bypass
    IRAN_RULES="https://github.com/Chocolate4U/Iran-v2ray-rules/releases/latest/download"
    wget -q "$IRAN_RULES/geoip.dat"   -O "$XRAY_DIR/geoip.dat"   || log_warn "geoip.dat download failed"
    wget -q "$IRAN_RULES/geosite.dat" -O "$XRAY_DIR/geosite.dat" || log_warn "geosite.dat download failed"
    # Also copy to share dir (Xray checks both locations)
    mkdir -p /usr/local/share/xray
    cp -f "$XRAY_DIR/geoip.dat"   /usr/local/share/xray/geoip.dat   2>/dev/null || true
    cp -f "$XRAY_DIR/geosite.dat" /usr/local/share/xray/geosite.dat 2>/dev/null || true

    log_info "Xray installed: $($XRAY_DIR/xray version | head -1)"
}

obtain_ssl() {
    systemctl stop masterpanel 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true
    sleep 1

    # ── Cert for the VPN domain (used by Xray inbounds) ──
    log_step "Obtaining SSL for VPN domain: $DOMAIN..."
    certbot certonly --standalone \
        --non-interactive --agree-tos \
        --register-unsafely-without-email \
        -d "$DOMAIN" 2>&1 | tail -5

    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    if [[ -f "$CERT_PATH" ]]; then
        chmod 644 "$CERT_PATH" "$KEY_PATH" 2>/dev/null || true
        SSL_OK=1
        log_info "VPN domain SSL obtained."
    else
        log_warn "VPN domain SSL failed (Cloudflare proxy or DNS/port 80)."
        SSL_OK=0
    fi

    # ── Cert for the PANEL domain (real HTTPS, no browser warning) ──
    if [[ "$PANEL_DOMAIN" == "$DOMAIN" ]]; then
        # Same hostname — reuse the cert we just got
        PANEL_CERT_PATH="$CERT_PATH"
        PANEL_KEY_PATH="$KEY_PATH"
        PANEL_SSL_OK="$SSL_OK"
    else
        log_step "Obtaining SSL for PANEL domain: $PANEL_DOMAIN..."
        fuser -k 80/tcp 2>/dev/null || true
        sleep 1
        certbot certonly --standalone \
            --non-interactive --agree-tos \
            --register-unsafely-without-email \
            -d "$PANEL_DOMAIN" 2>&1 | tail -5
        PANEL_CERT_PATH="/etc/letsencrypt/live/$PANEL_DOMAIN/fullchain.pem"
        PANEL_KEY_PATH="/etc/letsencrypt/live/$PANEL_DOMAIN/privkey.pem"
        if [[ -f "$PANEL_CERT_PATH" ]]; then
            chmod 644 "$PANEL_CERT_PATH" "$PANEL_KEY_PATH" 2>/dev/null || true
            PANEL_SSL_OK=1
            log_info "Panel domain SSL obtained — open: https://$PANEL_DOMAIN:$PANEL_PORT"
        else
            log_warn "Panel domain SSL failed. Panel will use self-signed cert."
            log_warn "Fix: set '$PANEL_DOMAIN' to DNS-only in Cloudflare, then:"
            log_warn "  bash /opt/masterpanel/mp.sh renew-ssl"
            PANEL_SSL_OK=0
            PANEL_CERT_PATH=""
            PANEL_KEY_PATH=""
        fi
    fi
}

setup_panel() {
    log_step "Setting up MasterPanel..."
    mkdir -p "$PANEL_DIR"/{templates,static,configs,logs}

    python3 -m venv "$PANEL_DIR/venv"
    "$PANEL_DIR/venv/bin/pip" install -q --upgrade pip
    "$PANEL_DIR/venv/bin/pip" install -q flask requests

    cat > "$PANEL_DIR/panel.conf" << CONF
DOMAIN=$DOMAIN
PANEL_DOMAIN=$PANEL_DOMAIN
PANEL_USER=$PANEL_USER
PANEL_PASS=$PANEL_PASS
PANEL_PORT=$PANEL_PORT
CERT_PATH=/etc/letsencrypt/live/$DOMAIN/fullchain.pem
KEY_PATH=/etc/letsencrypt/live/$DOMAIN/privkey.pem
PANEL_CERT_PATH=$PANEL_CERT_PATH
PANEL_KEY_PATH=$PANEL_KEY_PATH
XRAY_CONFIG_DIR=$XRAY_CONFIG_DIR
XRAY_BIN=$XRAY_DIR/xray
CONF

    # Write version file
    echo "4.7.0" > "$PANEL_DIR/version.txt"
    log_info "Panel configured."
}

download_panel_files() {
    log_step "Downloading panel files from GitHub..."

    # First try local files (if running from extracted zip folder)
    # NOTE: bash <(curl ...) sets BASH_SOURCE[0] to /dev/fd/N — not a real path.
    # So we check if BASH_SOURCE is a real file before trusting SCRIPT_DIR.
    SCRIPT_DIR=""
    if [[ -f "${BASH_SOURCE[0]}" ]]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi

    if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/masterpanel.py" && -f "$SCRIPT_DIR/index.html" ]]; then
        log_info "Using local files from $SCRIPT_DIR..."
        cp "$SCRIPT_DIR/masterpanel.py" "$PANEL_DIR/masterpanel.py"
        cp "$SCRIPT_DIR/index.html"     "$PANEL_DIR/templates/index.html"
        [[ -f "$SCRIPT_DIR/bot.py" ]]   && cp "$SCRIPT_DIR/bot.py"   "$PANEL_DIR/bot.py"
        [[ -f "$SCRIPT_DIR/mp.sh"  ]]   && cp "$SCRIPT_DIR/mp.sh"    "$PANEL_DIR/mp.sh" && chmod +x "$PANEL_DIR/mp.sh"
        log_info "Local files installed."
    else
        # Download from GitHub
        log_info "Downloading from GitHub..."
        declare -A FILE_DEST=(
            ["masterpanel.py"]="$PANEL_DIR/masterpanel.py"
            ["index.html"]="$PANEL_DIR/templates/index.html"
            ["bot.py"]="$PANEL_DIR/bot.py"
            ["mp.sh"]="$PANEL_DIR/mp.sh"
        )
        for FILE in masterpanel.py index.html; do
            DEST="${FILE_DEST[$FILE]}"
            if wget -q "$GITHUB_RAW/$FILE" -O "$DEST"; then
                log_info "Downloaded: $FILE"
            else
                log_error "Failed to download $FILE — check: $GITHUB_RAW"
                exit 1
            fi
        done
        # Optional files
        wget -q "$GITHUB_RAW/bot.py" -O "$PANEL_DIR/bot.py" \
            && log_info "Downloaded: bot.py" \
            || log_warn "bot.py not found on GitHub (optional)"
        wget -q "$GITHUB_RAW/mp.sh" -O "$PANEL_DIR/mp.sh" \
            && { chmod +x "$PANEL_DIR/mp.sh"; log_info "Downloaded: mp.sh"; } \
            || log_warn "mp.sh not found on GitHub (optional)"
    fi

    # Install Python dependencies
    "$PANEL_DIR/venv/bin/pip" install -q requests 2>/dev/null || true
}

setup_firewall() {
    log_step "Configuring firewall..."
    for PORT in 22/tcp 80/tcp 443/tcp 443/udp 9090/tcp \
                2052/tcp 2053/tcp 2082/tcp 2083/tcp \
                2086/tcp 2087/tcp 2095/tcp 2096/tcp \
                8443/tcp \
                4431/tcp 4432/tcp 4433/tcp 4434/tcp \
                4435/tcp 4436/tcp 4437/tcp 4438/tcp \
                4451/tcp 4452/tcp 4453/tcp 4454/tcp \
                10086/tcp 10087/tcp \
                8388/tcp 8389/tcp 8390/tcp 8392/tcp \
                8401/tcp 8402/tcp 8403/tcp 8404/tcp \
                51820/udp 8081/tcp; do
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

    # MasterBot (Telegram) — enabled later when token is set via panel
    cat > /etc/systemd/system/masterbot.service << SVC
[Unit]
Description=MasterPanel Telegram Bot
After=network.target masterpanel.service

[Service]
Type=simple
User=root
WorkingDirectory=$PANEL_DIR
ExecStart=$PANEL_DIR/venv/bin/python3 $PANEL_DIR/bot.py
Restart=always
RestartSec=5
StandardOutput=append:$PANEL_DIR/logs/bot.log
StandardError=append:$PANEL_DIR/logs/bot.log

[Install]
WantedBy=multi-user.target
SVC

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

setup_nginx_sub() {
    log_step "Setting up HTTPS subscription via Nginx..."

    CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

    # اگه SSL نگرفتیم nginx رو بدون TLS راه نمیندازیم
    if [[ ! -f "$CERT" ]]; then
        log_warn "No SSL cert for $DOMAIN — skipping Nginx subscription setup."
        log_warn "After fixing SSL, run: bash $PANEL_DIR/mp.sh renew-ssl"
        return
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx 2>/dev/null || {
        log_warn "Nginx install failed — subscription will work via panel port only"
        return
    }

    # Nginx serves HTTPS on 8443 and proxies /sub/ to the panel (port 9090).
    # Note: 8443 is also used by Xray for some inbounds, so we use 2087... no —
    # use a dedicated subscription port that nothing else uses: 8443 conflicts,
    # so use port 8081 over TLS for subscription.
    SUB_PORT=8081
    cat > /etc/nginx/sites-available/masterpanel-sub << NGINX
server {
    listen ${SUB_PORT} ssl;
    server_name ${DOMAIN};

    ssl_certificate     ${CERT};
    ssl_certificate_key ${KEY};
    ssl_protocols TLSv1.2 TLSv1.3;

    location /sub/ {
        proxy_pass http://127.0.0.1:9090;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location / {
        return 404;
    }
}
NGINX

    ln -sf /etc/nginx/sites-available/masterpanel-sub /etc/nginx/sites-enabled/masterpanel-sub
    # Remove default site to avoid port conflicts
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    ufw allow ${SUB_PORT}/tcp > /dev/null 2>&1 || true

    if nginx -t 2>/dev/null; then
        systemctl enable nginx > /dev/null 2>&1
        systemctl restart nginx
        echo "SUB_PORT=${SUB_PORT}" >> "$PANEL_DIR/panel.conf"
        log_info "HTTPS subscription ready on port ${SUB_PORT}"
    else
        log_warn "Nginx config test failed — check manually"
    fi
}

setup_ssl_renewal() {
    log_step "SSL auto-renewal + traffic enforcement..."
    (crontab -l 2>/dev/null | grep -v certbot | grep -v "api/enforce"
    echo "0 3 * * * certbot renew --quiet --deploy-hook 'systemctl restart xray 2>/dev/null; systemctl restart masterpanel'"
    echo "*/10 * * * * curl -sk -X POST https://127.0.0.1:9090/api/enforce -H 'X-Internal: 1' > /dev/null 2>&1"
    ) | crontab -
    log_info "Auto-renewal + enforcement configured."
}

print_summary() {
    SERVER_IP=$(curl -4 -s https://api4.ipify.org 2>/dev/null \
        || curl -4 -s https://ipv4.icanhazip.com 2>/dev/null \
        || hostname -I | awk '{for(i=1;i<=NF;i++) if($i !~ /:/) {print $i; exit}}')

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      MasterPanel v4.7 — Installed! ✓           ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    if [[ "${PANEL_SSL_OK:-0}" == "1" ]]; then
        echo -e "  ${WHITE}Panel URL :${NC} ${GREEN}https://$PANEL_DOMAIN:$PANEL_PORT${NC}  ${WHITE}(real cert, no warning)${NC}"
    else
        echo -e "  ${WHITE}Panel URL :${NC} ${CYAN}https://$SERVER_IP:$PANEL_PORT${NC}"
        echo -e "  ${YELLOW}   Panel cert is self-signed — accept the browser warning once.${NC}"
        echo -e "  ${YELLOW}   For a real cert: set '$PANEL_DOMAIN' to DNS-only in Cloudflare, then${NC}"
        echo -e "  ${YELLOW}   run: bash /opt/masterpanel/mp.sh renew-ssl${NC}"
    fi
    echo -e "  ${WHITE}Username  :${NC} ${CYAN}$PANEL_USER${NC}"
    echo -e "  ${WHITE}VPN Domain:${NC} ${CYAN}$DOMAIN${NC}"
    echo ""
    echo -e "  ${YELLOW}⚠  The panel domain '$PANEL_DOMAIN' must stay DNS-only (grey cloud).${NC}"
    echo -e "  ${YELLOW}   Cloudflare does not proxy port $PANEL_PORT.${NC}"
    echo ""
    echo -e "  ${WHITE}Installed:${NC}"
    echo -ne "  Xray      : "; $XRAY_DIR/xray version 2>/dev/null | head -1 || echo "OK"
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
obtain_ssl
setup_panel
download_panel_files
setup_firewall
setup_nginx_sub
create_services
setup_ssl_renewal
print_summary
