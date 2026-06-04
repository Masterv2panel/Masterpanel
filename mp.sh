#!/bin/bash
# ============================================================
#   MasterPanel - Management CLI v3.0
# ============================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; WHITE='\033[1;37m'; NC='\033[0m'

PANEL_DIR="/opt/masterpanel"
CONF_FILE="$PANEL_DIR/panel.conf"
DB_PATH="$PANEL_DIR/masterpanel.db"
XRAY_BIN="/usr/local/bin/xray"
TUIC_BIN="/usr/local/bin/tuic-server"
HY2_BIN="/usr/local/bin/hysteria"

load_conf(){ [[ -f "$CONF_FILE" ]] && source "$CONF_FILE" 2>/dev/null || true; }

print_banner(){
  echo -e "${CYAN}"
  echo "  ╔═══════════════════════════════════════════╗"
  echo "  ║     MasterPanel Manager CLI v3.0          ║"
  echo "  ╚═══════════════════════════════════════════╝"
  echo -e "${NC}"
}

svc_status(){
  systemctl is-active --quiet "$1" 2>/dev/null \
    && echo -e "${GREEN}Running ✓${NC}" \
    || echo -e "${RED}Stopped ✗${NC}"
}

cmd_status(){
  load_conf
  echo -e "${WHITE}── سرویس‌ها ──────────────────────────────────${NC}"
  echo -ne "  MasterPanel : "; svc_status masterpanel
  echo -ne "  Xray        : "; svc_status xray
  echo -ne "  TUIC v5     : "
  [[ -f "$TUIC_BIN" ]] && svc_status tuic-server || echo -e "${YELLOW}نصب نشده${NC}"
  echo -ne "  Hysteria2   : "
  [[ -f "$HY2_BIN" ]] && svc_status hysteria2 || echo -e "${YELLOW}نصب نشده${NC}"

  echo -e "${WHITE}── پایگاه داده کاربران ────────────────────────${NC}"
  if [[ -f "$DB_PATH" ]]; then
    TOTAL=$(sqlite3 "$DB_PATH"   "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
    ACTIVE=$(sqlite3 "$DB_PATH"  "SELECT COUNT(*) FROM users WHERE status='active';" 2>/dev/null || echo "0")
    EXPIRED=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status IN ('expired','quota_exceeded');" 2>/dev/null || echo "0")
    DISABLED=$(sqlite3 "$DB_PATH""SELECT COUNT(*) FROM users WHERE status='disabled';" 2>/dev/null || echo "0")
    echo -e "  کل       : ${CYAN}$TOTAL${NC}"
    echo -e "  فعال     : ${GREEN}$ACTIVE${NC}"
    echo -e "  منقضی   : ${YELLOW}$EXPIRED${NC}"
    echo -e "  غیرفعال : ${RED}$DISABLED${NC}"
  else
    echo -e "  ${YELLOW}پایگاه داده هنوز ساخته نشده${NC}"
  fi

  echo -e "${WHITE}── SSL ────────────────────────────────────────${NC}"
  if [[ -n "$DOMAIN" ]]; then
    CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    if [[ -f "$CERT" ]]; then
      EXPIRY=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null | cut -d= -f2)
      echo -e "  دامنه  : $DOMAIN"
      echo -e "  انقضا : ${GREEN}$EXPIRY${NC}"
    else
      echo -e "  ${RED}گواهی SSL یافت نشد${NC}"
    fi
  fi

  echo -e "${WHITE}── شبکه ───────────────────────────────────────${NC}"
  IP=$(curl -4 -s --max-time 5 https://api4.ipify.org 2>/dev/null \
    || hostname -I | awk '{for(i=1;i<=NF;i++) if($i !~ /:/) {print $i; exit}}')
  echo -e "  IP سرور : $IP"
  echo -e "  پنل     : ${CYAN}http://$IP:${PANEL_PORT:-9090}${NC}"
  echo ""
}

cmd_users(){
  [[ ! -f "$DB_PATH" ]] && echo -e "${YELLOW}پایگاه داده یافت نشد${NC}" && return
  echo -e "${WHITE}── لیست کاربران ──────────────────────────────${NC}"
  sqlite3 -column -header "$DB_PATH" \
    "SELECT id,
            username,
            total_quota_gb || ' GB' AS quota,
            ROUND(used_quota_bytes*1.0/1073741824, 3) || ' GB' AS used,
            status,
            COALESCE(substr(expire_date,1,10),'بدون انقضا') AS expires
     FROM users ORDER BY created_at DESC;" 2>/dev/null \
    || echo "خطا در خواندن پایگاه داده"
}

cmd_restart(){
  echo -e "${BLUE}[*]${NC} ری‌استارت MasterPanel..."
  systemctl restart masterpanel \
    && echo -e "${GREEN}[✓]${NC} پنل ری‌استارت شد" \
    || echo -e "${RED}[✗]${NC} خطا — لاگ: journalctl -u masterpanel -n 20"
}

cmd_restart_xray(){
  echo -e "${BLUE}[*]${NC} ری‌استارت Xray..."
  systemctl restart xray \
    && echo -e "${GREEN}[✓]${NC} Xray ری‌استارت شد" \
    || { echo -e "${YELLOW}[~]${NC} سرویس نیست، اجرای مستقیم..."; pkill -f "xray run" 2>/dev/null; sleep 1
         nohup $XRAY_BIN run -c /usr/local/etc/xray/config.json \
           >> "$PANEL_DIR/logs/xray-access.log" 2>> "$PANEL_DIR/logs/xray-error.log" &
         echo -e "${GREEN}[✓]${NC} Xray شروع شد"; }
}

cmd_restart_tuic(){
  echo -e "${BLUE}[*]${NC} ری‌استارت TUIC..."
  systemctl restart tuic-server 2>/dev/null \
    && echo -e "${GREEN}[✓]${NC} TUIC ری‌استارت شد" \
    || echo -e "${RED}[✗]${NC} TUIC نصب نیست یا خطا"
}

cmd_restart_hy2(){
  echo -e "${BLUE}[*]${NC} ری‌استارت Hysteria2..."
  systemctl restart hysteria2 2>/dev/null \
    && echo -e "${GREEN}[✓]${NC} Hysteria2 ری‌استارت شد" \
    || echo -e "${RED}[✗]${NC} Hysteria2 نصب نیست یا خطا"
}

cmd_restart_all(){
  cmd_restart_xray
  cmd_restart_tuic
  cmd_restart_hy2
  cmd_restart
}

cmd_logs(){
  case "${1:-panel}" in
    panel)    tail -f "$PANEL_DIR/logs/panel.log" ;;
    xray)     tail -f "$PANEL_DIR/logs/xray-error.log" ;;
    access)   tail -f "$PANEL_DIR/logs/xray-access.log" ;;
    tuic)     tail -f "$PANEL_DIR/logs/tuic.log" ;;
    hy2|hysteria2) tail -f "$PANEL_DIR/logs/hysteria2.log" ;;
    *) echo "Usage: mp.sh logs [panel|xray|access|tuic|hy2]" ;;
  esac
}

cmd_update(){
  load_conf
  echo -e "${BLUE}[*]${NC} به‌روزرسانی از GitHub..."
  REPO="https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main"
  TMPDIR=$(mktemp -d)
  FAILED=0

  for FILE in masterpanel.py index.html mp.sh install.sh quickinstall.sh; do
    echo -ne "  دانلود $FILE ... "
    if wget -q "$REPO/$FILE" -O "$TMPDIR/$FILE" 2>/dev/null; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}ناموفق${NC}"; FAILED=$((FAILED+1))
    fi
  done

  [[ -f "$TMPDIR/masterpanel.py" ]]   && cp "$TMPDIR/masterpanel.py" "$PANEL_DIR/masterpanel.py"
  [[ -f "$TMPDIR/index.html" ]]       && cp "$TMPDIR/index.html" "$PANEL_DIR/templates/index.html"
  [[ -f "$TMPDIR/mp.sh" ]]            && { cp "$TMPDIR/mp.sh" "$PANEL_DIR/mp.sh"; chmod +x "$PANEL_DIR/mp.sh"; }
  [[ -f "$TMPDIR/install.sh" ]]       && { cp "$TMPDIR/install.sh" "$PANEL_DIR/install.sh"; chmod +x "$PANEL_DIR/install.sh"; }
  [[ -f "$TMPDIR/quickinstall.sh" ]]  && { cp "$TMPDIR/quickinstall.sh" "$PANEL_DIR/quickinstall.sh"; chmod +x "$PANEL_DIR/quickinstall.sh"; }

  rm -rf "$TMPDIR"

  if [[ $FAILED -eq 0 ]]; then
    systemctl restart masterpanel
    echo -e "${GREEN}[✓]${NC} به‌روزرسانی انجام شد و پنل ری‌استارت شد"
  else
    echo -e "${YELLOW}[!]${NC} $FAILED فایل دانلود نشد — پنل ری‌استارت نشد"
  fi
}

cmd_renew_ssl(){
  load_conf
  echo -e "${BLUE}[*]${NC} تجدید SSL برای $DOMAIN..."
  systemctl stop masterpanel 2>/dev/null || true
  certbot renew --force-renewal -d "$DOMAIN" 2>&1 | tail -5
  systemctl start masterpanel
  systemctl restart xray 2>/dev/null || true
  systemctl restart tuic-server 2>/dev/null || true
  systemctl restart hysteria2 2>/dev/null || true
  echo -e "${GREEN}[✓]${NC} تجدید SSL انجام شد"
}

cmd_update_pass(){
  load_conf
  echo -e "${WHITE}کاربر فعلی: ${CYAN}$PANEL_USER${NC}"
  echo -ne "رمز جدید (حداقل ۸ کاراکتر): "; read -s NEW_PASS; echo ""
  [[ ${#NEW_PASS} -lt 8 ]] && echo -e "${RED}رمز خیلی کوتاه است${NC}" && return
  sed -i "s/^PANEL_PASS=.*/PANEL_PASS=$NEW_PASS/" "$CONF_FILE"
  systemctl restart masterpanel
  echo -e "${GREEN}[✓]${NC} رمز تغییر کرد و پنل ری‌استارت شد"
}

cmd_db_backup(){
  TS=$(date +%Y%m%d_%H%M%S)
  BACKUP="$PANEL_DIR/backups/masterpanel_${TS}.db"
  mkdir -p "$PANEL_DIR/backups"
  sqlite3 "$DB_PATH" ".backup '$BACKUP'" 2>/dev/null || cp "$DB_PATH" "$BACKUP"
  echo -e "${GREEN}[✓]${NC} پشتیبان: $BACKUP"
}

cmd_db_shell(){
  [[ ! -f "$DB_PATH" ]] && echo -e "${RED}پایگاه داده یافت نشد${NC}" && return
  echo -e "${YELLOW}ورود به SQLite shell — برای خروج .quit تایپ کنید${NC}"
  sqlite3 "$DB_PATH"
}

cmd_uninstall(){
  echo -e "${RED}[هشدار]${NC} این عمل MasterPanel را کاملاً حذف می‌کند."
  echo -ne "آیا مطمئنید؟ (yes/no): "; read CONFIRM
  [[ "$CONFIRM" != "yes" ]] && echo "لغو شد." && return
  systemctl stop masterpanel xray tuic-server hysteria2 2>/dev/null || true
  systemctl disable masterpanel xray tuic-server hysteria2 2>/dev/null || true
  rm -f /etc/systemd/system/{masterpanel,tuic-server,hysteria2,xray}.service
  rm -rf /opt/masterpanel
  systemctl daemon-reload
  echo -e "${GREEN}[✓]${NC} MasterPanel کاملاً حذف شد"
  echo -e "${YELLOW}[i]${NC} باینری‌های Xray/TUIC/HY2 و گواهی SSL نگه داشته شدند"
}

cmd_help(){
  print_banner
  echo -e "  ${WHITE}نحوه استفاده:${NC} bash mp.sh [دستور]"
  echo ""
  echo -e "  ${CYAN}status${NC}         وضعیت سرویس‌ها، کاربران و SSL"
  echo -e "  ${CYAN}users${NC}          لیست کاربران از پایگاه داده"
  echo -e "  ${CYAN}restart${NC}        ری‌استارت پنل"
  echo -e "  ${CYAN}restart-xray${NC}   ری‌استارت Xray"
  echo -e "  ${CYAN}restart-tuic${NC}   ری‌استارت TUIC v5"
  echo -e "  ${CYAN}restart-hy2${NC}    ری‌استارت Hysteria2"
  echo -e "  ${CYAN}restart-all${NC}    ری‌استارت همه سرویس‌ها"
  echo -e "  ${CYAN}update${NC}         دریافت آخرین نسخه از GitHub"
  echo -e "  ${CYAN}logs [service]${NC} لاگ‌ها: panel|xray|access|tuic|hy2"
  echo -e "  ${CYAN}renew-ssl${NC}      تجدید گواهی SSL"
  echo -e "  ${CYAN}update-pass${NC}    تغییر رمز پنل"
  echo -e "  ${CYAN}db-backup${NC}      پشتیبان‌گیری از پایگاه داده"
  echo -e "  ${CYAN}db-shell${NC}       ورود به SQLite shell"
  echo -e "  ${CYAN}uninstall${NC}      حذف کامل MasterPanel"
  echo ""
}

# ══ اجرا ══════════════════════════════════════════════════════
print_banner
case "${1:-help}" in
  status)        cmd_status ;;
  users)         cmd_users ;;
  restart)       cmd_restart ;;
  restart-xray)  cmd_restart_xray ;;
  restart-tuic)  cmd_restart_tuic ;;
  restart-hy2)   cmd_restart_hy2 ;;
  restart-all)   cmd_restart_all ;;
  update)        cmd_update ;;
  logs)          cmd_logs "$2" ;;
  renew-ssl)     cmd_renew_ssl ;;
  update-pass)   cmd_update_pass ;;
  db-backup)     cmd_db_backup ;;
  db-shell)      cmd_db_shell ;;
  uninstall)     cmd_uninstall ;;
  help|*)        cmd_help ;;
esac
