#!/bin/bash
# ============================================================
#   MasterPanel - Management CLI
#   Usage: bash mp.sh [command]
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BLUE='\033[0;34m'; WHITE='\033[1;37m'; NC='\033[0m'

PANEL_DIR="/opt/masterpanel"
CONF_FILE="$PANEL_DIR/panel.conf"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CFG="/usr/local/etc/xray/config.json"

load_conf() {
  if [[ -f "$CONF_FILE" ]]; then
    source "$CONF_FILE" 2>/dev/null || true
  fi
}

print_banner() {
  echo -e "${CYAN}"
  echo "  ╔═══════════════════════════════════════╗"
  echo "  ║       MasterPanel Manager CLI         ║"
  echo "  ╚═══════════════════════════════════════╝"
  echo -e "${NC}"
}

cmd_status() {
  load_conf
  echo -e "${WHITE}── Panel ──────────────────────────────${NC}"
  if systemctl is-active --quiet masterpanel; then
    echo -e "  MasterPanel : ${GREEN}Running ✓${NC}"
  else
    echo -e "  MasterPanel : ${RED}Stopped ✗${NC}"
  fi

  echo -e "${WHITE}── Xray ───────────────────────────────${NC}"
  if pgrep -f xray > /dev/null; then
    VER=$($XRAY_BIN version 2>/dev/null | head -1)
    echo -e "  Xray        : ${GREEN}Running ✓${NC}"
    echo -e "  Version     : $VER"
  else
    echo -e "  Xray        : ${RED}Stopped ✗${NC}"
  fi

  echo -e "${WHITE}── SSL ────────────────────────────────${NC}"
  if [[ -n "$DOMAIN" ]]; then
    CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    if [[ -f "$CERT" ]]; then
      EXPIRY=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null | cut -d= -f2)
      echo -e "  Domain      : $DOMAIN"
      echo -e "  Cert Expiry : ${GREEN}$EXPIRY${NC}"
    else
      echo -e "  SSL Cert    : ${RED}Not found${NC}"
    fi
  fi

  echo -e "${WHITE}── Configs ────────────────────────────${NC}"
  CFG_FILE="$PANEL_DIR/configs/all_configs.json"
  if [[ -f "$CFG_FILE" ]]; then
    COUNT=$(python3 -c "import json; d=json.load(open('$CFG_FILE')); print(len(d))" 2>/dev/null || echo "0")
    echo -e "  Total Configs: ${CYAN}$COUNT${NC}"
  else
    echo -e "  Configs     : None generated yet"
  fi

  echo -e "${WHITE}── Network ────────────────────────────${NC}"
  IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
  echo -e "  Server IP   : $IP"
  echo -e "  Panel Port  : ${PANEL_PORT:-9090}"
  echo -e "  Panel URL   : ${CYAN}http://$IP:${PANEL_PORT:-9090}${NC}"
  echo ""
}

cmd_restart() {
  echo -e "${BLUE}[*]${NC} Restarting MasterPanel..."
  systemctl restart masterpanel
  sleep 1
  if systemctl is-active --quiet masterpanel; then
    echo -e "${GREEN}[✓]${NC} MasterPanel restarted"
  else
    echo -e "${RED}[✗]${NC} Failed. Check: journalctl -u masterpanel -n 20"
  fi
}

cmd_restart_xray() {
  echo -e "${BLUE}[*]${NC} Restarting Xray..."
  if systemctl is-enabled --quiet xray 2>/dev/null; then
    systemctl restart xray
  else
    pkill -f xray 2>/dev/null || true
    sleep 1
    nohup $XRAY_BIN run -c $XRAY_CFG > /opt/masterpanel/logs/xray-access.log 2>/opt/masterpanel/logs/xray-error.log &
  fi
  sleep 1
  if pgrep -f xray > /dev/null; then
    echo -e "${GREEN}[✓]${NC} Xray restarted"
  else
    echo -e "${RED}[✗]${NC} Xray failed to start"
  fi
}

cmd_logs() {
  local type="${1:-panel}"
  case "$type" in
    panel)  tail -f "$PANEL_DIR/logs/panel.log" ;;
    xray)   tail -f "$PANEL_DIR/logs/xray-error.log" ;;
    access) tail -f "$PANEL_DIR/logs/xray-access.log" ;;
    *)
      echo "Usage: mp.sh logs [panel|xray|access]"
      ;;
  esac
}

cmd_show_configs() {
  CFG_FILE="$PANEL_DIR/configs/all_configs.json"
  if [[ ! -f "$CFG_FILE" ]]; then
    echo -e "${YELLOW}No configs generated yet. Use the panel to generate.${NC}"
    return
  fi
  echo ""
  python3 - <<'EOF'
import json, sys

with open("/opt/masterpanel/configs/all_configs.json") as f:
    configs = json.load(f)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

print(f"{WHITE}{'#':<3} {'Name':<35} {'Proto':<14} {'TLS':<10} {'Port':<6} {'Network':<12}{NC}")
print("─" * 82)

for i, c in enumerate(configs, 1):
    proto = c.get('protocol','')
    tls   = c.get('tls','none')
    net   = c.get('network','tcp')
    port  = c.get('port','')
    name  = c.get('name','')

    color = {'vless': CYAN, 'vmess': '\033[0;35m', 'trojan': YELLOW, 'shadowsocks': GREEN}.get(proto, NC)
    tcolor = GREEN if tls == 'tls' else ('\033[0;35m' if tls == 'reality' else '\033[0;90m')

    print(f"  {i:<3} {name:<35} {color}{proto.upper():<14}{NC} {tcolor}{tls:<10}{NC} {port:<6} {net:<12}")

print("")
print(f"  Total: {len(configs)} configs")
EOF
}

cmd_show_links() {
  CFG_FILE="$PANEL_DIR/configs/all_configs.json"
  if [[ ! -f "$CFG_FILE" ]]; then
    echo -e "${YELLOW}No configs yet.${NC}"
    return
  fi
  python3 - <<'EOF'
import json
with open("/opt/masterpanel/configs/all_configs.json") as f:
    configs = json.load(f)

CYAN='\033[0;36m'; NC='\033[0m'; WHITE='\033[1;37m'
for c in configs:
    link = c.get('link','')
    if link:
        print(f"{WHITE}{c['name']}{NC}")
        print(f"  {CYAN}{link}{NC}")
        print()
EOF
}

cmd_renew_ssl() {
  load_conf
  echo -e "${BLUE}[*]${NC} Renewing SSL for $DOMAIN..."
  systemctl stop masterpanel 2>/dev/null || true
  certbot renew --force-renewal -d "$DOMAIN" 2>&1 | tail -10
  systemctl start masterpanel
  echo -e "${GREEN}[✓]${NC} Done"
}

cmd_update_pass() {
  load_conf
  echo -e "${WHITE}Current user: ${CYAN}$PANEL_USER${NC}"
  read -s -p "New password (min 8 chars): " NEW_PASS
  echo ""
  if [[ ${#NEW_PASS} -lt 8 ]]; then
    echo -e "${RED}Password too short${NC}"; return
  fi
  sed -i "s/^PANEL_PASS=.*/PANEL_PASS=$NEW_PASS/" "$CONF_FILE"
  systemctl restart masterpanel
  echo -e "${GREEN}[✓]${NC} Password updated"
}

cmd_uninstall() {
  echo -e "${RED}[WARNING]${NC} This will remove MasterPanel completely."
  read -p "Are you sure? (yes/no): " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then echo "Cancelled."; return; fi

  systemctl stop masterpanel 2>/dev/null || true
  systemctl disable masterpanel 2>/dev/null || true
  rm -f /etc/systemd/system/masterpanel.service
  rm -rf /opt/masterpanel
  systemctl daemon-reload
  echo -e "${GREEN}[✓]${NC} MasterPanel removed."
  echo -e "${YELLOW}[NOTE]${NC} Xray and SSL certs were kept. Remove manually if needed."
}

cmd_help() {
  print_banner
  echo -e "  ${WHITE}Usage:${NC} bash mp.sh [command]"
  echo ""
  echo -e "  ${CYAN}status${NC}          Show panel, Xray, SSL, and config status"
  echo -e "  ${CYAN}restart${NC}         Restart MasterPanel service"
  echo -e "  ${CYAN}restart-xray${NC}    Restart Xray core"
  echo -e "  ${CYAN}logs${NC}            Tail panel logs"
  echo -e "  ${CYAN}logs xray${NC}       Tail Xray error logs"
  echo -e "  ${CYAN}logs access${NC}     Tail Xray access logs"
  echo -e "  ${CYAN}configs${NC}         List all generated configs"
  echo -e "  ${CYAN}links${NC}           Show all share links"
  echo -e "  ${CYAN}renew-ssl${NC}       Force renew SSL certificate"
  echo -e "  ${CYAN}update-pass${NC}     Change panel password"
  echo -e "  ${CYAN}uninstall${NC}       Remove MasterPanel"
  echo -e "  ${CYAN}help${NC}            Show this help"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────
print_banner
CMD="${1:-help}"

case "$CMD" in
  status)       cmd_status ;;
  restart)      cmd_restart ;;
  restart-xray) cmd_restart_xray ;;
  logs)         cmd_logs "$2" ;;
  configs)      cmd_show_configs ;;
  links)        cmd_show_links ;;
  renew-ssl)    cmd_renew_ssl ;;
  update-pass)  cmd_update_pass ;;
  uninstall)    cmd_uninstall ;;
  help|*)       cmd_help ;;
esac
