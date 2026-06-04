#!/bin/bash
# ============================================================
#   MasterPanel Installer v3.0 - Enterprise Edition
#   نصب‌کننده کامل با SQLite و مدیریت کاربران
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

PANEL_DIR="/opt/masterpanel"
PANEL_PORT=9090
XRAY_DIR="/usr/local/bin"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
GITHUB_REPO="Masterv2panel/Masterpanel"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/main"

print_banner(){
  echo -e "${CYAN}"
  echo "  ╔═══════════════════════════════════════════════╗"
  echo "  ║    MasterPanel Installer v3.0 Enterprise      ║"
  echo "  ║  Xray Multi-User + TUIC v5 + Hysteria2        ║"
  echo "  ╚═══════════════════════════════════════════════╝"
  echo -e "${NC}"
}

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }

check_root(){
  [[ $EUID -ne 0 ]] && log_error "به عنوان root اجرا کنید: sudo bash install.sh" && exit 1
}

check_os(){
  [[ ! -f /etc/os-release ]] && log_error "سیستم‌عامل شناخته نشد" && exit 1
  . /etc/os-release
  log_info "سیستم‌عامل: $NAME $VERSION_ID"
  # بررسی حداقل Ubuntu 20 یا Debian 10
  if [[ "$ID" == "ubuntu" && "${VERSION_ID%%.*}" -lt 20 ]]; then
    log_error "حداقل Ubuntu 20.04 لازم است"; exit 1
  fi
}

get_user_input(){
  echo ""
  echo -e "${WHITE}=== تنظیمات نصب ===${NC}"
  echo ""
  while true; do
    echo -ne "${CYAN}دامنه سرور (مثال: vpn.example.com): ${NC}"; read DOMAIN
    [[ -n "$DOMAIN" ]] && break; log_warn "دامنه نمی‌تواند خالی باشد"
  done
  while true; do
    echo -ne "${CYAN}نام کاربری پنل (حداقل ۴ کاراکتر): ${NC}"; read PANEL_USER
    [[ ${#PANEL_USER} -ge 4 ]] && break; log_warn "نام کاربری باید حداقل ۴ کاراکتر باشد"
  done
  while true; do
    echo -ne "${CYAN}رمز عبور پنل (حداقل ۸ کاراکتر): ${NC}"; read -s PANEL_PASS; echo ""
    [[ ${#PANEL_PASS} -ge 8 ]] && break; log_warn "رمز عبور باید حداقل ۸ کاراکتر باشد"
  done
  echo ""
  log_info "دامنه   : $DOMAIN"
  log_info "کاربری : $PANEL_USER"
  log_info "پورت   : $PANEL_PORT"
  echo ""
  echo -ne "${YELLOW}آیا ادامه می‌دهید؟ [y/N]: ${NC}"; read CONFIRM
  [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && log_warn "نصب لغو شد" && exit 0
}

install_dependencies(){
  log_step "نصب وابستگی‌های سیستم..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl wget unzip \
    python3 python3-pip python3-venv python3-dev \
    certbot ufw openssl uuid-runtime jq net-tools \
    ca-certificates sqlite3 build-essential 2>/dev/null || true
  log_info "وابستگی‌ها نصب شدند"
}

install_python_deps(){
  log_step "نصب کتابخانه‌های Python داخل venv..."
  # ساخت محیط مجازی Python — جدا از سیستم
  python3 -m venv "$PANEL_DIR/venv"

  # upgrade pip داخل venv
  "$PANEL_DIR/venv/bin/pip" install --upgrade pip --quiet

  # نصب flask — فقط داخل venv، بدون openssl (پایتون SSL داخلی دارد)
  "$PANEL_DIR/venv/bin/pip" install flask --quiet

  log_info "Flask نصب شد: $("$PANEL_DIR/venv/bin/pip" show flask | grep Version)"
}

install_xray(){
  log_step "نصب Xray-core (آخرین نسخه)..."
  XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4 2>/dev/null || echo "v1.8.24")
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)  XRAY_ARCH="64" ;;
    aarch64) XRAY_ARCH="arm64-v8a" ;;
    armv7l)  XRAY_ARCH="arm32-v7a" ;;
    *)       XRAY_ARCH="64" ;;
  esac

  XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"
  log_info "دانلود Xray ${XRAY_VERSION}..."

  wget -q --show-progress "$XRAY_URL" -O /tmp/xray.zip
  unzip -o /tmp/xray.zip -d /tmp/xray_tmp/ > /dev/null 2>&1
  mv /tmp/xray_tmp/xray "$XRAY_DIR/xray"
  chmod +x "$XRAY_DIR/xray"
  rm -rf /tmp/xray.zip /tmp/xray_tmp/
  mkdir -p "$XRAY_CONFIG_DIR"
  log_info "Xray نصب شد: $($XRAY_DIR/xray version 2>/dev/null | head -1)"
}

install_tuic(){
  log_step "نصب TUIC v5..."
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && TA="aarch64-unknown-linux-gnu" || TA="x86_64-unknown-linux-gnu"
  VER=$(curl -s https://api.github.com/repos/EAimTY/tuic/releases/latest \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4 2>/dev/null || echo "tuic-server-1.0.0")
  URL="https://github.com/EAimTY/tuic/releases/download/${VER}/tuic-server-${TA}"
  if wget -q "$URL" -O /tmp/tuic-server 2>/dev/null; then
    mv /tmp/tuic-server /usr/local/bin/tuic-server
    chmod +x /usr/local/bin/tuic-server
    log_info "TUIC v5 نصب شد"
  else
    log_warn "TUIC دانلود نشد — نادیده گرفته می‌شود"
    touch /tmp/tuic_failed
  fi
}

install_hysteria2(){
  log_step "نصب Hysteria2..."
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && HY2_ARCH="arm64" || HY2_ARCH="amd64"

  # روش اول: اسکریپت رسمی
  HY2_INSTALL=$(curl -fsSL https://get.hy2.sh/ 2>/dev/null || true)
  if [[ -n "$HY2_INSTALL" ]]; then
    bash <(echo "$HY2_INSTALL") 2>&1 | tail -3
    if command -v hysteria &>/dev/null; then
      log_info "Hysteria2 نصب شد: $(hysteria version 2>/dev/null | head -1)"
      return
    fi
  fi

  # روش دوم: دانلود مستقیم
  VER=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4 | sed 's/app\///' 2>/dev/null || echo "v2.6.0")
  URL="https://github.com/apernet/hysteria/releases/download/app%2F${VER}/hysteria-linux-${HY2_ARCH}"
  if wget -q "$URL" -O /usr/local/bin/hysteria 2>/dev/null; then
    chmod +x /usr/local/bin/hysteria
    log_info "Hysteria2 نصب شد: $(hysteria version 2>/dev/null | head -1)"
  else
    log_warn "Hysteria2 دانلود نشد"
    touch /tmp/hy2_failed
  fi
}

obtain_ssl(){
  log_step "دریافت گواهی SSL برای $DOMAIN..."
  systemctl stop masterpanel 2>/dev/null || true

  # آزاد کردن پورت 80
  for pid in $(lsof -ti:80 2>/dev/null); do kill -9 "$pid" 2>/dev/null || true; done
  sleep 1

  certbot certonly --standalone \
    --non-interactive --agree-tos \
    --register-unsafely-without-email \
    -d "$DOMAIN" --preferred-challenges http 2>&1 | tail -8

  CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
  KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

  if [[ ! -f "$CERT_PATH" ]]; then
    log_error "گواهی SSL دریافت نشد!"
    log_error "  ۱. مطمئن شوید DNS دامنه به IP این سرور اشاره می‌کند"
    log_error "  ۲. پورت ۸۰ باز باشد (ufw allow 80)"
    log_error "  ۳. دستور: certbot certonly --standalone -d $DOMAIN"
    exit 1
  fi
  chmod 644 "$CERT_PATH" "$KEY_PATH" 2>/dev/null || true
  log_info "گواهی SSL دریافت شد ✓"
}

setup_panel(){
  log_step "راه‌اندازی MasterPanel..."
  mkdir -p "$PANEL_DIR"/{templates,configs,logs,backups}

  # فایل تنظیمات
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

  log_info "پنل تنظیم شد"
}

copy_panel_files(){
  log_step "کپی فایل‌های پنل..."
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # اگر فایل‌ها کنار install.sh باشند از آن‌ها استفاده می‌کنیم
  # وگرنه از GitHub دانلود می‌کنیم
  for FILE in masterpanel.py mp.sh quickinstall.sh; do
    if [[ -f "$SCRIPT_DIR/$FILE" ]]; then
      cp "$SCRIPT_DIR/$FILE" "$PANEL_DIR/$FILE"
      chmod +x "$PANEL_DIR/$FILE"
      log_info "کپی شد (محلی): $FILE"
    else
      log_info "دانلود از GitHub: $FILE"
      if wget -q "$GITHUB_RAW/$FILE" -O "$PANEL_DIR/$FILE" 2>/dev/null; then
        chmod +x "$PANEL_DIR/$FILE"
        log_info "دانلود شد: $FILE"
      else
        log_warn "$FILE دانلود نشد"
      fi
    fi
  done

  # index.html → داخل templates
  if [[ -f "$SCRIPT_DIR/index.html" ]]; then
    cp "$SCRIPT_DIR/index.html" "$PANEL_DIR/templates/index.html"
    log_info "کپی شد (محلی): index.html"
  else
    log_info "دانلود از GitHub: index.html"
    if wget -q "$GITHUB_RAW/index.html" -O "$PANEL_DIR/templates/index.html" 2>/dev/null; then
      log_info "دانلود شد: index.html"
    else
      log_error "index.html دانلود نشد!"
      exit 1
    fi
  fi
}

install_python_venv_and_flask(){
  log_step "ساخت محیط Python و نصب Flask..."
  install_python_deps
}

setup_firewall(){
  log_step "تنظیم فایروال..."
  declare -a PORTS=(
    "22/tcp" "80/tcp" "443/tcp" "443/udp"
    "${PANEL_PORT}/tcp"
    "2052/tcp" "2053/tcp" "2082/tcp" "2083/tcp" "2087/tcp" "2096/tcp"
    "8388/tcp" "8388/udp" "8389/tcp" "8389/udp"
    "8443/tcp" "8443/udp"
    "19443/tcp" "19443/udp" "19444/udp"
  )
  for PORT in "${PORTS[@]}"; do
    ufw allow "$PORT" > /dev/null 2>&1 || true
  done
  ufw --force enable > /dev/null 2>&1 || true
  log_info "فایروال تنظیم شد (${#PORTS[@]} قانون)"
}

create_services(){
  log_step "ساخت سرویس‌های systemd..."

  # ── MasterPanel ────────────────────────────────────────────
  cat > "/etc/systemd/system/masterpanel.service" << SVC
[Unit]
Description=MasterPanel v3 - Enterprise Xray Control Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${PANEL_DIR}
ExecStart=${PANEL_DIR}/venv/bin/python3 ${PANEL_DIR}/masterpanel.py
Restart=always
RestartSec=5
StandardOutput=append:${PANEL_DIR}/logs/panel.log
StandardError=append:${PANEL_DIR}/logs/panel.log
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SVC

  # ── Xray ───────────────────────────────────────────────────
  cat > "/etc/systemd/system/xray.service" << SVC
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
  systemctl enable xray > /dev/null 2>&1 || true

  # ── TUIC ───────────────────────────────────────────────────
  if [[ -f /usr/local/bin/tuic-server && ! -f /tmp/tuic_failed ]]; then
    cat > "/etc/systemd/system/tuic-server.service" << SVC
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
    log_info "سرویس TUIC ساخته شد"
  fi

  # ── Hysteria2 ──────────────────────────────────────────────
  if [[ -f /usr/local/bin/hysteria && ! -f /tmp/hy2_failed ]]; then
    cat > "/etc/systemd/system/hysteria2.service" << SVC
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
    log_info "سرویس Hysteria2 ساخته شد"
  fi

  systemctl daemon-reload

  # شروع پنل
  systemctl enable masterpanel > /dev/null 2>&1
  systemctl start masterpanel
  sleep 4

  if systemctl is-active --quiet masterpanel; then
    log_info "MasterPanel با موفقیت شروع شد ✓"
  else
    log_error "پنل شروع نشد! لاگ:"
    journalctl -u masterpanel -n 20 --no-pager
    log_warn "برای رفع مشکل: journalctl -u masterpanel -f"
  fi
}

setup_ssl_renewal(){
  log_step "تنظیم تجدید خودکار SSL..."
  CRON_CMD="0 3 * * * certbot renew --quiet --pre-hook 'systemctl stop masterpanel' --post-hook 'systemctl start masterpanel; systemctl restart xray; systemctl restart tuic-server 2>/dev/null; systemctl restart hysteria2 2>/dev/null'"
  (crontab -l 2>/dev/null | grep -v certbot; echo "$CRON_CMD") | crontab -
  log_info "تجدید خودکار SSL تنظیم شد"
}

print_summary(){
  SERVER_IP=$(curl -4 -s --max-time 5 https://api4.ipify.org 2>/dev/null \
    || curl -4 -s --max-time 5 https://ipv4.icanhazip.com 2>/dev/null \
    || hostname -I | awk '{for(i=1;i<=NF;i++) if($i !~ /:/) {print $i; exit}}')
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
  echo -e "  ${YELLOW}⚠ از IP سرور باز کنید، نه دامنه!${NC}"
  echo -e "  ${GREEN}→ http://$SERVER_IP:$PANEL_PORT${NC}"
  echo ""
  echo -e "  ${WHITE}مراحل بعدی:${NC}"
  echo -e "  ۱. از پنل وارد شوید"
  echo -e "  ۲. در بخش «کاربران»، کاربر اضافه کنید"
  echo -e "  ۳. لینک سابسکریپشن کاربر را کپی کنید"
  echo ""
  echo -e "  ${YELLOW}دستورات مدیریت:${NC}"
  echo -e "  bash $PANEL_DIR/mp.sh status"
  echo -e "  bash $PANEL_DIR/mp.sh users"
  echo -e "  bash $PANEL_DIR/mp.sh logs panel"
  echo -e "  bash $PANEL_DIR/mp.sh restart-all"
  echo ""
}

# ══ اجرای اصلی ═══════════════════════════════════════════════
print_banner
check_root
check_os
get_user_input
install_dependencies
setup_panel
install_python_venv_and_flask
install_xray
install_tuic
install_hysteria2
obtain_ssl
copy_panel_files
setup_firewall
create_services
setup_ssl_renewal
print_summary
