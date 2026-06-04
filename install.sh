#!/bin/bash
# ============================================================
#   MasterPanel Installer v3.0 - Enterprise Edition
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

PANEL_DIR="/opt/masterpanel"
PANEL_PORT=9090
XRAY_DIR="/usr/local/bin"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
GITHUB_REPO="Masterv2panel/Masterpanel"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/main"

# مسیر فایل‌های محلی (کنار install.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo /tmp)"

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }

print_banner(){
  echo -e "${CYAN}"
  echo "  ╔═══════════════════════════════════════════════╗"
  echo "  ║    MasterPanel Installer v3.0 Enterprise      ║"
  echo "  ║  Xray Multi-User + TUIC v5 + Hysteria2        ║"
  echo "  ╚═══════════════════════════════════════════════╝"
  echo -e "${NC}"
}

check_root(){
  if [[ $EUID -ne 0 ]]; then
    log_error "به عنوان root اجرا کنید: sudo bash install.sh"
    exit 1
  fi
  log_ok "دسترسی root تأیید شد"
}

check_os(){
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    log_info "سیستم‌عامل: $NAME $VERSION_ID"
  else
    log_warn "سیستم‌عامل شناخته نشد — ادامه می‌دهیم"
  fi
}

get_user_input(){
  echo ""
  echo -e "${WHITE}=== تنظیمات نصب ===${NC}"
  echo ""

  while true; do
    echo -ne "${CYAN}دامنه سرور (مثال: vpn.example.com): ${NC}"
    read -r DOMAIN
    if [[ -n "$DOMAIN" ]]; then break; fi
    log_warn "دامنه نمی‌تواند خالی باشد"
  done

  while true; do
    echo -ne "${CYAN}نام کاربری پنل (حداقل ۴ کاراکتر): ${NC}"
    read -r PANEL_USER
    if [[ ${#PANEL_USER} -ge 4 ]]; then break; fi
    log_warn "نام کاربری باید حداقل ۴ کاراکتر باشد"
  done

  while true; do
    echo -ne "${CYAN}رمز عبور پنل (حداقل ۸ کاراکتر): ${NC}"
    read -rs PANEL_PASS
    echo ""
    if [[ ${#PANEL_PASS} -ge 8 ]]; then break; fi
    log_warn "رمز عبور باید حداقل ۸ کاراکتر باشد"
  done

  echo ""
  log_info "دامنه   : $DOMAIN"
  log_info "کاربری : $PANEL_USER"
  log_info "پورت   : $PANEL_PORT"
  echo ""
  echo -ne "${YELLOW}آیا ادامه می‌دهید؟ [y/N]: ${NC}"
  read -r CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    log_warn "نصب لغو شد"
    exit 0
  fi
}

install_dependencies(){
  log_step "نصب وابستگی‌های سیستم..."
  apt-get update -qq 2>/dev/null || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget unzip \
    python3 python3-pip python3-venv \
    certbot ufw openssl uuid-runtime jq net-tools \
    ca-certificates sqlite3 2>/dev/null || true
  log_ok "وابستگی‌ها نصب شدند"
}

setup_panel_dirs(){
  log_step "ساخت ساختار دایرکتوری‌ها..."
  mkdir -p "$PANEL_DIR"/{templates,configs,logs,backups}
  log_ok "دایرکتوری‌ها ساخته شدند: $PANEL_DIR"
}

install_python_deps(){
  log_step "ساخت محیط Python (venv) و نصب Flask..."

  # ساخت venv
  python3 -m venv "$PANEL_DIR/venv"
  if [[ ! -f "$PANEL_DIR/venv/bin/python3" ]]; then
    log_error "ساخت venv ناموفق بود!"
    exit 1
  fi

  # upgrade pip
  "$PANEL_DIR/venv/bin/pip" install --upgrade pip --quiet 2>/dev/null || true

  # نصب فقط flask — بدون پکیج‌های اضافه
  "$PANEL_DIR/venv/bin/pip" install flask --quiet
  if [[ $? -ne 0 ]]; then
    log_error "نصب Flask ناموفق!"
    exit 1
  fi

  FLASK_VER=$("$PANEL_DIR/venv/bin/pip" show flask 2>/dev/null | grep Version | cut -d' ' -f2)
  log_ok "Flask $FLASK_VER نصب شد"
}

write_panel_conf(){
  log_step "نوشتن فایل تنظیمات..."
  cat > "$PANEL_DIR/panel.conf" << CONF
DOMAIN=${DOMAIN}
PANEL_USER=${PANEL_USER}
PANEL_PASS=${PANEL_PASS}
PANEL_PORT=${PANEL_PORT}
CERT_PATH=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
KEY_PATH=/etc/letsencrypt/live/${DOMAIN}/privkey.pem
XRAY_CONFIG_DIR=${XRAY_CONFIG_DIR}
XRAY_BIN=${XRAY_DIR}/xray
TUIC_BIN=/usr/local/bin/tuic-server
HY2_BIN=/usr/local/bin/hysteria
CONF
  log_ok "فایل panel.conf نوشته شد"
}

copy_panel_files(){
  log_step "کپی فایل‌های پنل..."

  # masterpanel.py
  if [[ -f "$SCRIPT_DIR/masterpanel.py" ]]; then
    cp "$SCRIPT_DIR/masterpanel.py" "$PANEL_DIR/masterpanel.py"
    log_ok "masterpanel.py کپی شد (محلی)"
  else
    log_info "دانلود masterpanel.py از GitHub..."
    wget -q "$GITHUB_RAW/masterpanel.py" -O "$PANEL_DIR/masterpanel.py" || {
      log_error "دانلود masterpanel.py ناموفق!"
      exit 1
    }
    log_ok "masterpanel.py دانلود شد"
  fi
  chmod +x "$PANEL_DIR/masterpanel.py"

  # index.html
  if [[ -f "$SCRIPT_DIR/index.html" ]]; then
    cp "$SCRIPT_DIR/index.html" "$PANEL_DIR/templates/index.html"
    log_ok "index.html کپی شد (محلی)"
  else
    log_info "دانلود index.html از GitHub..."
    wget -q "$GITHUB_RAW/index.html" -O "$PANEL_DIR/templates/index.html" || {
      log_error "دانلود index.html ناموفق!"
      exit 1
    }
    log_ok "index.html دانلود شد"
  fi

  # mp.sh
  if [[ -f "$SCRIPT_DIR/mp.sh" ]]; then
    cp "$SCRIPT_DIR/mp.sh" "$PANEL_DIR/mp.sh"
    log_ok "mp.sh کپی شد (محلی)"
  else
    log_info "دانلود mp.sh از GitHub..."
    wget -q "$GITHUB_RAW/mp.sh" -O "$PANEL_DIR/mp.sh" || log_warn "mp.sh دانلود نشد"
  fi
  chmod +x "$PANEL_DIR/mp.sh" 2>/dev/null || true
}

install_xray(){
  log_step "نصب Xray-core..."
  
  XRAY_VERSION=$(curl -s --max-time 10 \
    https://api.github.com/repos/XTLS/Xray-core/releases/latest \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4 2>/dev/null)
  
  [[ -z "$XRAY_VERSION" ]] && XRAY_VERSION="v1.8.24"
  
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)  XRAY_ARCH="64" ;;
    aarch64) XRAY_ARCH="arm64-v8a" ;;
    *)       XRAY_ARCH="64" ;;
  esac

  XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"
  log_info "دانلود Xray ${XRAY_VERSION}..."

  if wget -q "$XRAY_URL" -O /tmp/xray.zip; then
    mkdir -p /tmp/xray_tmp
    unzip -o /tmp/xray.zip -d /tmp/xray_tmp/ > /dev/null 2>&1
    mv /tmp/xray_tmp/xray "$XRAY_DIR/xray"
    chmod +x "$XRAY_DIR/xray"
    rm -rf /tmp/xray.zip /tmp/xray_tmp/
    mkdir -p "$XRAY_CONFIG_DIR"
    log_ok "Xray نصب شد: $($XRAY_DIR/xray version 2>/dev/null | head -1)"
  else
    log_error "دانلود Xray ناموفق!"
    exit 1
  fi
}

install_tuic(){
  log_step "نصب TUIC v5..."
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && TA="aarch64-unknown-linux-gnu" || TA="x86_64-unknown-linux-gnu"

  VER=$(curl -s --max-time 10 \
    https://api.github.com/repos/EAimTY/tuic/releases/latest \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4 2>/dev/null || echo "tuic-server-1.0.0")

  URL="https://github.com/EAimTY/tuic/releases/download/${VER}/tuic-server-${TA}"
  if wget -q --max-time 60 "$URL" -O /tmp/tuic-server 2>/dev/null; then
    mv /tmp/tuic-server /usr/local/bin/tuic-server
    chmod +x /usr/local/bin/tuic-server
    log_ok "TUIC v5 نصب شد"
  else
    log_warn "TUIC دانلود نشد — نادیده گرفته می‌شود"
  fi
}

install_hysteria2(){
  log_step "نصب Hysteria2..."
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && HY2_ARCH="arm64" || HY2_ARCH="amd64"

  VER=$(curl -s --max-time 10 \
    https://api.github.com/repos/apernet/hysteria/releases/latest \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4 | sed 's/app\///' 2>/dev/null || echo "v2.6.0")

  URL="https://github.com/apernet/hysteria/releases/download/app%2F${VER}/hysteria-linux-${HY2_ARCH}"
  if wget -q --max-time 60 "$URL" -O /usr/local/bin/hysteria 2>/dev/null; then
    chmod +x /usr/local/bin/hysteria
    log_ok "Hysteria2 نصب شد: $(hysteria version 2>/dev/null | head -1)"
  else
    log_warn "Hysteria2 دانلود نشد — نادیده گرفته می‌شود"
  fi
}

obtain_ssl(){
  log_step "دریافت گواهی SSL برای $DOMAIN..."

  # آزاد کردن پورت 80
  systemctl stop nginx apache2 masterpanel 2>/dev/null || true
  fuser -k 80/tcp 2>/dev/null || true
  sleep 2

  certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    --register-unsafely-without-email \
    -d "$DOMAIN" \
    --preferred-challenges http \
    2>&1 | tail -5

  CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
  KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

  if [[ ! -f "$CERT_PATH" ]]; then
    log_error "گواهی SSL دریافت نشد!"
    log_error "  ۱. DNS دامنه باید به IP این سرور اشاره کند"
    log_error "  ۲. پورت ۸۰ باید باز باشد"
    log_error "دستور دستی: certbot certonly --standalone -d $DOMAIN"
    exit 1
  fi

  chmod 644 "$CERT_PATH" "$KEY_PATH" 2>/dev/null || true
  log_ok "گواهی SSL دریافت شد ✓"
}

setup_firewall(){
  log_step "تنظیم فایروال (ufw)..."
  ufw allow 22/tcp  > /dev/null 2>&1 || true
  ufw allow 80/tcp  > /dev/null 2>&1 || true
  ufw allow 443/tcp > /dev/null 2>&1 || true
  ufw allow 443/udp > /dev/null 2>&1 || true
  ufw allow ${PANEL_PORT}/tcp > /dev/null 2>&1 || true
  ufw allow 2052/tcp > /dev/null 2>&1 || true
  ufw allow 2053/tcp > /dev/null 2>&1 || true
  ufw allow 2082/tcp > /dev/null 2>&1 || true
  ufw allow 2083/tcp > /dev/null 2>&1 || true
  ufw allow 2087/tcp > /dev/null 2>&1 || true
  ufw allow 2096/tcp > /dev/null 2>&1 || true
  ufw allow 8388/tcp > /dev/null 2>&1 || true
  ufw allow 8388/udp > /dev/null 2>&1 || true
  ufw allow 8389/tcp > /dev/null 2>&1 || true
  ufw allow 8389/udp > /dev/null 2>&1 || true
  ufw allow 8443/tcp > /dev/null 2>&1 || true
  ufw allow 8443/udp > /dev/null 2>&1 || true
  ufw allow 19443/udp > /dev/null 2>&1 || true
  ufw allow 19444/udp > /dev/null 2>&1 || true
  ufw --force enable > /dev/null 2>&1 || true
  log_ok "فایروال تنظیم شد"
}

create_systemd_services(){
  log_step "ساخت سرویس‌های systemd..."

  # MasterPanel
  cat > /etc/systemd/system/masterpanel.service << SVC
[Unit]
Description=MasterPanel v3
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${PANEL_DIR}
ExecStart=${PANEL_DIR}/venv/bin/python3 ${PANEL_DIR}/masterpanel.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
StandardOutput=append:${PANEL_DIR}/logs/panel.log
StandardError=append:${PANEL_DIR}/logs/panel.log

[Install]
WantedBy=multi-user.target
SVC

  # Xray
  cat > /etc/systemd/system/xray.service << SVC
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -c /usr/local/etc/xray/config.json
Restart=always
RestartSec=5
LimitNOFILE=65535
StandardOutput=append:${PANEL_DIR}/logs/xray-access.log
StandardError=append:${PANEL_DIR}/logs/xray-error.log

[Install]
WantedBy=multi-user.target
SVC

  # TUIC
  if [[ -f /usr/local/bin/tuic-server ]]; then
    cat > /etc/systemd/system/tuic-server.service << SVC
[Unit]
Description=TUIC v5 Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/tuic-server -c ${PANEL_DIR}/configs/tuic_config.json
Restart=always
RestartSec=5
StandardOutput=append:${PANEL_DIR}/logs/tuic.log
StandardError=append:${PANEL_DIR}/logs/tuic.log

[Install]
WantedBy=multi-user.target
SVC
    systemctl enable tuic-server > /dev/null 2>&1 || true
    log_ok "سرویس TUIC ساخته شد"
  fi

  # Hysteria2
  if [[ -f /usr/local/bin/hysteria ]]; then
    cat > /etc/systemd/system/hysteria2.service << SVC
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/hysteria server -c ${PANEL_DIR}/configs/hysteria2_config.json
Restart=always
RestartSec=5
StandardOutput=append:${PANEL_DIR}/logs/hysteria2.log
StandardError=append:${PANEL_DIR}/logs/hysteria2.log

[Install]
WantedBy=multi-user.target
SVC
    systemctl enable hysteria2 > /dev/null 2>&1 || true
    log_ok "سرویس Hysteria2 ساخته شد"
  fi

  systemctl daemon-reload
  systemctl enable xray > /dev/null 2>&1 || true
  systemctl enable masterpanel > /dev/null 2>&1 || true

  log_info "شروع MasterPanel..."
  systemctl start masterpanel
  sleep 4

  if systemctl is-active --quiet masterpanel; then
    log_ok "MasterPanel شروع شد ✓"
  else
    log_error "پنل شروع نشد. لاگ:"
    journalctl -u masterpanel -n 30 --no-pager 2>/dev/null || \
      tail -30 "$PANEL_DIR/logs/panel.log" 2>/dev/null || true
  fi
}

setup_ssl_renewal(){
  log_step "تنظیم تجدید خودکار SSL..."
  (crontab -l 2>/dev/null | grep -v certbot; \
   echo "0 3 * * * certbot renew --quiet && systemctl restart xray masterpanel 2>/dev/null") \
   | crontab - 2>/dev/null || true
  log_ok "تجدید SSL تنظیم شد"
}

print_summary(){
  SERVER_IP=$(curl -4 -s --max-time 8 https://api4.ipify.org 2>/dev/null \
    || curl -4 -s --max-time 8 https://ipv4.icanhazip.com 2>/dev/null \
    || hostname -I 2>/dev/null | awk '{print $1}')

  echo ""
  echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║    نصب MasterPanel v3.0 با موفقیت انجام شد ✓     ║${NC}"
  echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${WHITE}آدرس پنل   :${NC} ${CYAN}http://$SERVER_IP:$PANEL_PORT${NC}"
  echo -e "  ${WHITE}نام کاربری :${NC} ${CYAN}$PANEL_USER${NC}"
  echo -e "  ${WHITE}رمز عبور  :${NC} ${CYAN}$PANEL_PASS${NC}"
  echo -e "  ${WHITE}دامنه      :${NC} ${CYAN}$DOMAIN${NC}"
  echo ""
  echo -e "  ${YELLOW}⚠  از IP باز کنید، نه دامنه:${NC}"
  echo -e "  ${GREEN}→  http://$SERVER_IP:$PANEL_PORT${NC}"
  echo ""
  echo -e "  ${WHITE}مدیریت:${NC}"
  echo -e "  bash $PANEL_DIR/mp.sh status"
  echo -e "  bash $PANEL_DIR/mp.sh users"
  echo -e "  bash $PANEL_DIR/mp.sh logs panel"
  echo ""
}

# ══════════════════════════════════════════════════════════════
#  اجرای اصلی — هر مرحله جداگانه با خطایابی
# ══════════════════════════════════════════════════════════════
print_banner
check_root
check_os
get_user_input

log_info "شروع نصب..."
echo ""

install_dependencies
setup_panel_dirs
install_python_deps
write_panel_conf
install_xray
install_tuic
install_hysteria2
obtain_ssl
copy_panel_files
setup_firewall
create_systemd_services
setup_ssl_renewal
print_summary
