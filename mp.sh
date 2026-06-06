#!/bin/bash
# ============================================================
#   MasterPanel - Management CLI v2.0
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BLUE='\033[0;34m'; WHITE='\033[1;37m'; NC='\033[0m'

PANEL_DIR="/opt/masterpanel"
CONF_FILE="$PANEL_DIR/panel.conf"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CFG="/usr/local/etc/xray/config.json"
TUIC_BIN="/usr/local/bin/tuic-server"
HY2_BIN="/usr/local/bin/hysteria"

load_conf() {
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE" 2>/dev/null || true
}

print_banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║     MasterPanel Manager CLI v2.0          ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

svc_status() {
    local name=$1
    if systemctl is-active --quiet "$name" 2>/dev/null; then
        echo -e "${GREEN}Running ✓${NC}"
    else
        echo -e "${RED}Stopped ✗${NC}"
    fi
}

cmd_status() {
    load_conf
    echo -e "${WHITE}── Services ────────────────────────────${NC}"
    echo -ne "  MasterPanel : "; svc_status masterpanel
    echo -ne "  Xray        : "; svc_status xray
    echo -ne "  TUIC v5     : "
    if [[ -f "$TUIC_BIN" ]]; then svc_status tuic-server; else echo -e "${YELLOW}Not installed${NC}"; fi
    echo -ne "  Hysteria2   : "
    if [[ -f "$HY2_BIN" ]]; then svc_status hysteria2; else echo -e "${YELLOW}Not installed${NC}"; fi

    echo -e "${WHITE}── Versions ────────────────────────────${NC}"
    echo -e "  Xray      : $($XRAY_BIN version 2>/dev/null | head -1 || echo 'N/A')"
    echo -e "  TUIC      : $($TUIC_BIN --version 2>/dev/null | head -1 || echo 'N/A')"
    echo -e "  Hysteria2 : $($HY2_BIN version 2>/dev/null | head -1 || echo 'N/A')"

    echo -e "${WHITE}── SSL ─────────────────────────────────${NC}"
    if [[ -n "$DOMAIN" ]]; then
        CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        if [[ -f "$CERT" ]]; then
            EXPIRY=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null | cut -d= -f2)
            echo -e "  Domain  : $DOMAIN"
            echo -e "  Expires : ${GREEN}$EXPIRY${NC}"
        else
            echo -e "  SSL Cert : ${RED}Not found${NC}"
        fi
    fi

    echo -e "${WHITE}── Configs ─────────────────────────────${NC}"
    CFG_FILE="$PANEL_DIR/configs/all_configs.json"
    if [[ -f "$CFG_FILE" ]]; then
        TOTAL=$(python3 -c "import json; d=json.load(open('$CFG_FILE')); print(len(d))" 2>/dev/null || echo "0")
        VLESS=$(python3 -c "import json; d=json.load(open('$CFG_FILE')); print(sum(1 for c in d if c['protocol']=='vless'))" 2>/dev/null || echo "0")
        VMESS=$(python3 -c "import json; d=json.load(open('$CFG_FILE')); print(sum(1 for c in d if c['protocol']=='vmess'))" 2>/dev/null || echo "0")
        TROJAN=$(python3 -c "import json; d=json.load(open('$CFG_FILE')); print(sum(1 for c in d if c['protocol']=='trojan'))" 2>/dev/null || echo "0")
        SS=$(python3 -c "import json; d=json.load(open('$CFG_FILE')); print(sum(1 for c in d if c['protocol']=='shadowsocks'))" 2>/dev/null || echo "0")
        TUIC=$(python3 -c "import json; d=json.load(open('$CFG_FILE')); print(sum(1 for c in d if c['protocol']=='tuic'))" 2>/dev/null || echo "0")
        HY2=$(python3 -c "import json; d=json.load(open('$CFG_FILE')); print(sum(1 for c in d if c['protocol']=='hysteria2'))" 2>/dev/null || echo "0")
        echo -e "  Total     : ${CYAN}$TOTAL${NC}"
        echo -e "  VLESS     : $VLESS  |  VMess: $VMESS  |  Trojan: $TROJAN"
        echo -e "  SS        : $SS  |  TUIC: $TUIC  |  Hysteria2: $HY2"
    else
        echo -e "  ${YELLOW}No configs generated yet${NC}"
    fi

    echo -e "${WHITE}── Network ─────────────────────────────${NC}"
    IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    echo -e "  Server IP : $IP"
    echo -e "  Panel URL : ${CYAN}https://$IP:${PANEL_PORT:-9090}${NC}"
    echo ""
}

cmd_restart() {
    echo -e "${BLUE}[*]${NC} Restarting MasterPanel..."
    systemctl restart masterpanel
    sleep 1
    systemctl is-active --quiet masterpanel \
        && echo -e "${GREEN}[✓]${NC} MasterPanel restarted" \
        || echo -e "${RED}[✗]${NC} Failed — check: journalctl -u masterpanel -n 20"
}

cmd_restart_xray() {
    echo -e "${BLUE}[*]${NC} Restarting Xray..."
    if systemctl is-enabled --quiet xray 2>/dev/null; then
        systemctl restart xray
    else
        pkill -f "xray run" 2>/dev/null || true
        sleep 1
        nohup $XRAY_BIN run -c $XRAY_CFG \
            > $PANEL_DIR/logs/xray-access.log \
            2> $PANEL_DIR/logs/xray-error.log &
    fi
    sleep 1
    pgrep -f "xray run" > /dev/null \
        && echo -e "${GREEN}[✓]${NC} Xray restarted" \
        || echo -e "${RED}[✗]${NC} Xray failed"
}

cmd_restart_tuic() {
    echo -e "${BLUE}[*]${NC} Restarting TUIC..."
    systemctl restart tuic-server 2>/dev/null \
        && echo -e "${GREEN}[✓]${NC} TUIC restarted" \
        || echo -e "${RED}[✗]${NC} TUIC failed or not installed"
}

cmd_restart_hy2() {
    echo -e "${BLUE}[*]${NC} Restarting Hysteria2..."
    systemctl restart hysteria2 2>/dev/null \
        && echo -e "${GREEN}[✓]${NC} Hysteria2 restarted" \
        || echo -e "${RED}[✗]${NC} Hysteria2 failed or not installed"
}

cmd_restart_all() {
    cmd_restart_xray
    cmd_restart_tuic
    cmd_restart_hy2
    cmd_restart
}

cmd_logs() {
    case "${1:-panel}" in
        panel)    tail -f "$PANEL_DIR/logs/panel.log" ;;
        xray)     tail -f "$PANEL_DIR/logs/xray-error.log" ;;
        access)   tail -f "$PANEL_DIR/logs/xray-access.log" ;;
        tuic)     tail -f "$PANEL_DIR/logs/tuic.log" ;;
        hy2|hysteria2) tail -f "$PANEL_DIR/logs/hysteria2.log" ;;
        *) echo "Usage: mp.sh logs [panel|xray|access|tuic|hy2]" ;;
    esac
}

cmd_show_configs() {
    CFG_FILE="$PANEL_DIR/configs/all_configs.json"
    if [[ ! -f "$CFG_FILE" ]]; then
        echo -e "${YELLOW}No configs generated yet.${NC}"
        return
    fi
    python3 - << 'EOF'
import json
with open("/opt/masterpanel/configs/all_configs.json") as f:
    configs = json.load(f)

W='\033[1;37m'; C='\033[0;36m'; Y='\033[1;33m'
G='\033[0;32m'; M='\033[0;35m'; R='\033[0;31m'; NC='\033[0m'

COLORS = {'vless':C,'vmess':M,'trojan':Y,'shadowsocks':G,'tuic':'\033[0;34m','hysteria2':R,'wireguard':W}
TLS_C  = {'tls':G,'reality':M,'none':'\033[0;90m','shadowtls':Y}

print(f"\n{W}{'#':<3} {'Name':<38} {'Proto':<13} {'TLS':<10} {'Port':<7} {'Type'}{NC}")
print("─" * 85)
for i,c in enumerate(configs,1):
    proto = c.get('protocol','')
    tls   = c.get('tls','none')
    ctype = '☁️ CDN' if c.get('connection_type')=='domain' else '🖥 IP'
    pc = COLORS.get(proto, NC)
    tc = TLS_C.get(tls, NC)
    print(f"  {i:<3} {c['name']:<38} {pc}{proto.upper():<13}{NC} {tc}{tls:<10}{NC} {c.get('port',''):<7} {ctype}")

print(f"\n  Total: {len(configs)} configs\n")
EOF
}

cmd_show_links() {
    f="$PANEL_DIR/configs/all_links.txt"
    if [[ -f "$f" ]]; then cat "$f"; else echo -e "${YELLOW}No links yet.${NC}"; fi
}

cmd_renew_ssl() {
    load_conf
    echo -e "${BLUE}[*]${NC} Renewing SSL for $DOMAIN..."
    systemctl stop masterpanel 2>/dev/null || true
    certbot renew --force-renewal -d "$DOMAIN" 2>&1 | tail -5
    systemctl start masterpanel
    systemctl restart tuic-server 2>/dev/null || true
    systemctl restart hysteria2 2>/dev/null || true
    echo -e "${GREEN}[✓]${NC} Done"
}

cmd_update_pass() {
    load_conf
    echo -e "${WHITE}Current user: ${CYAN}$PANEL_USER${NC}"
    echo -ne "New password (min 8 chars): "
    read -s NEW_PASS; echo ""
    if [[ ${#NEW_PASS} -lt 8 ]]; then echo -e "${RED}Too short${NC}"; return; fi
    sed -i "s/^PANEL_PASS=.*/PANEL_PASS=$NEW_PASS/" "$CONF_FILE"
    systemctl restart masterpanel
    echo -e "${GREEN}[✓]${NC} Password updated"
}

cmd_install_tuic() {
    echo -e "${BLUE}[*]${NC} Installing/updating TUIC v5..."
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && TA="aarch64-unknown-linux-gnu" || TA="x86_64-unknown-linux-gnu"
    VER=$(curl -s https://api.github.com/repos/EAimTY/tuic/releases/latest | jq -r '.tag_name' 2>/dev/null || echo "tuic-server-1.0.0")
    wget -q "https://github.com/EAimTY/tuic/releases/download/${VER}/tuic-server-${TA}" -O /usr/local/bin/tuic-server
    chmod +x /usr/local/bin/tuic-server
    echo -e "${GREEN}[✓]${NC} TUIC installed"
}

cmd_install_hy2() {
    echo -e "${BLUE}[*]${NC} Installing/updating Hysteria2..."
    bash <(curl -fsSL https://get.hy2.sh/) 2>&1 | tail -3
    echo -e "${GREEN}[✓]${NC} Hysteria2 installed"
}

cmd_update() {
    echo -e "${BLUE}[*]${NC} Updating MasterPanel from GitHub..."
    GRAW="https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main"
    wget -q "$GRAW/masterpanel.py" -O /opt/masterpanel/masterpanel.py         && echo -e "${GREEN}[✓]${NC} masterpanel.py" || echo -e "${RED}[✗]${NC} masterpanel.py"
    wget -q "$GRAW/index.html" -O /opt/masterpanel/templates/index.html         && echo -e "${GREEN}[✓]${NC} index.html" || echo -e "${RED}[✗]${NC} index.html"
    wget -q "$GRAW/mp.sh" -O /opt/masterpanel/mp.sh && chmod +x /opt/masterpanel/mp.sh         && echo -e "${GREEN}[✓]${NC} mp.sh" || echo -e "${RED}[✗]${NC} mp.sh"
    systemctl restart masterpanel && sleep 1
    systemctl is-active --quiet masterpanel         && echo -e "${GREEN}[✓]${NC} Panel restarted"         || echo -e "${RED}[✗]${NC} Restart failed — check: journalctl -u masterpanel -n 20"
}

cmd_uninstall() {
    echo -e "${RED}[WARNING]${NC} This will remove MasterPanel completely."
    echo -ne "Are you sure? (yes/no): "
    read CONFIRM
    [[ "$CONFIRM" != "yes" ]] && echo "Cancelled." && return
    systemctl stop masterpanel tuic-server hysteria2 2>/dev/null || true
    systemctl disable masterpanel tuic-server hysteria2 2>/dev/null || true
    rm -f /etc/systemd/system/masterpanel.service
    rm -f /etc/systemd/system/tuic-server.service
    rm -f /etc/systemd/system/hysteria2.service
    rm -rf /opt/masterpanel
    systemctl daemon-reload
    echo -e "${GREEN}[✓]${NC} MasterPanel removed."
    echo -e "${YELLOW}[NOTE]${NC} Xray, TUIC, Hysteria2 binaries and SSL certs kept."
}

cmd_help() {
    print_banner
    echo -e "  ${WHITE}Usage:${NC} bash mp.sh [command]"
    echo ""
    echo -e "  ${CYAN}status${NC}            Show all services, configs, SSL"
    echo -e "  ${CYAN}restart${NC}           Restart MasterPanel panel"
    echo -e "  ${CYAN}restart-xray${NC}      Restart Xray"
    echo -e "  ${CYAN}restart-tuic${NC}      Restart TUIC v5"
    echo -e "  ${CYAN}restart-hy2${NC}       Restart Hysteria2"
    echo -e "  ${CYAN}restart-all${NC}       Restart all services"
    echo -e "  ${CYAN}logs [service]${NC}    Tail logs: panel|xray|access|tuic|hy2"
    echo -e "  ${CYAN}configs${NC}           List all generated configs"
    echo -e "  ${CYAN}links${NC}             Show all share links"
    echo -e "  ${CYAN}renew-ssl${NC}         Force renew SSL certificate"
    echo -e "  ${CYAN}update-pass${NC}       Change panel password"
    echo -e "  ${CYAN}install-tuic${NC}      Install/update TUIC v5"
    echo -e "  ${CYAN}install-hy2${NC}       Install/update Hysteria2"
    echo -e "  ${CYAN}uninstall${NC}         Remove MasterPanel"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────
print_banner
case "${1:-help}" in
    status)       cmd_status ;;
    restart)      cmd_restart ;;
    restart-xray) cmd_restart_xray ;;
    restart-tuic) cmd_restart_tuic ;;
    restart-hy2)  cmd_restart_hy2 ;;
    restart-all)  cmd_restart_all ;;
    logs)         cmd_logs "$2" ;;
    configs)      cmd_show_configs ;;
    links)        cmd_show_links ;;
    renew-ssl)    cmd_renew_ssl ;;
    update-pass)  cmd_update_pass ;;
    install-tuic) cmd_install_tuic ;;
    install-hy2)  cmd_install_hy2 ;;
    update)       cmd_update ;;
    uninstall)    cmd_uninstall ;;
    help|*)       cmd_help ;;
esac
