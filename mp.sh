#!/bin/bash
# ============================================================
#   MasterPanel — Management CLI  v3.0
#   Usage: bash /opt/masterpanel/mp.sh [command]
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; WHITE='\033[1;37m'
MAGENTA='\033[0;35m'; NC='\033[0m'

PANEL_DIR="/opt/masterpanel"
CONF_FILE="$PANEL_DIR/panel.conf"
DB_FILE="$PANEL_DIR/users.db"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CFG="/usr/local/etc/xray/config.json"
TUIC_BIN="/usr/local/bin/tuic-server"
HY2_BIN="/usr/local/bin/hysteria"
VENV_PY="$PANEL_DIR/venv/bin/python3"

load_conf() {
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE" 2>/dev/null || true
}

print_banner() {
    echo -e "${CYAN}"
    echo "  ╔════════════════════════════════════════════════╗"
    echo "  ║      MasterPanel Manager CLI  v3.0             ║"
    echo "  ╚════════════════════════════════════════════════╝"
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

# ────────────────────────────────────────────────────────────
#  status — full system overview
# ────────────────────────────────────────────────────────────
cmd_status() {
    load_conf
    local IP
    IP=$(curl -4 -s https://api4.ipify.org 2>/dev/null \
         || hostname -I | awk '{print $1}')

    echo -e "${WHITE}── Services ────────────────────────────────────${NC}"
    echo -ne "  MasterPanel : "; svc_status masterpanel
    echo -ne "  Xray        : "; svc_status xray
    echo -ne "  TUIC v5     : "
    [[ -f "$TUIC_BIN" ]] && svc_status tuic-server || echo -e "${YELLOW}Not installed${NC}"
    echo -ne "  Hysteria2   : "
    [[ -f "$HY2_BIN" ]] && svc_status hysteria2 || echo -e "${YELLOW}Not installed${NC}"

    echo -e "${WHITE}── Versions ────────────────────────────────────${NC}"
    echo -e "  Xray      : $($XRAY_BIN version 2>/dev/null | head -1 || echo 'N/A')"
    echo -e "  TUIC      : $($TUIC_BIN --version 2>/dev/null | head -1 || echo 'N/A')"
    echo -e "  Hysteria2 : $($HY2_BIN version 2>/dev/null | head -1 || echo 'N/A')"

    echo -e "${WHITE}── SSL ──────────────────────────────────────────${NC}"
    if [[ -n "$DOMAIN" ]]; then
        local CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        if [[ -f "$CERT" ]]; then
            local EXP
            EXP=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null | cut -d= -f2)
            echo -e "  Domain  : ${CYAN}$DOMAIN${NC}"
            echo -e "  Expires : ${GREEN}$EXP${NC}"
        else
            echo -e "  SSL     : ${RED}Certificate not found${NC}"
        fi
    fi

    echo -e "${WHITE}── Users (DB) ──────────────────────────────────${NC}"
    if [[ -f "$DB_FILE" ]]; then
        "$VENV_PY" - 2>/dev/null << 'PYEOF'
import sqlite3
try:
    c = sqlite3.connect('/opt/masterpanel/users.db')
    rows = c.execute(
        "SELECT username, status, traffic_limit_gb, used_traffic_bytes, expire_date "
        "FROM users ORDER BY id").fetchall()
    if not rows:
        print("  No users yet.  Use: bash mp.sh add-user")
    else:
        W='\033[1;37m'; G='\033[0;32m'; R='\033[0;31m'
        Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'
        print(f"  {W}{'User':<20} {'Status':<10} {'Traffic':<24} {'Expire'}{NC}")
        print("  " + "─" * 65)
        for u, st, lim, used, exp in rows:
            gb = (used or 0) / 1073741824
            lim_s = f"{lim:g} GB" if lim else "∞"
            used_s = f"{gb:.2f} GB / {lim_s}"
            sc = G if st == 'active' else (Y if st in ('limited', 'expired') else R)
            exp_s = exp[:10] if exp else '—'
            print(f"  {C}{u:<20}{NC} {sc}{st:<10}{NC} {used_s:<24} {exp_s}")
        print(f"\n  Total: {len(rows)} user(s)")
except Exception as e:
    print(f"  Error reading DB: {e}")
PYEOF
    else
        echo -e "  ${YELLOW}Database not found${NC}"
    fi

    echo -e "${WHITE}── Network ──────────────────────────────────────${NC}"
    echo -e "  Server IP : ${CYAN}$IP${NC}"
    echo -e "  Panel URL : ${CYAN}http://$IP:${PANEL_PORT:-9090}${NC}"
    echo ""
}

# ────────────────────────────────────────────────────────────
#  users — detailed user table
# ────────────────────────────────────────────────────────────
cmd_users() {
    if [[ ! -f "$DB_FILE" ]]; then
        echo -e "${YELLOW}[WARN]${NC} Database not found."; return
    fi
    "$VENV_PY" - 2>/dev/null << 'PYEOF'
import sqlite3
try:
    c = sqlite3.connect('/opt/masterpanel/users.db')
    rows = c.execute(
        "SELECT id, username, uuid, status, traffic_limit_gb, "
        "used_traffic_bytes, expire_date, note FROM users ORDER BY id").fetchall()
    W='\033[1;37m'; G='\033[0;32m'; R='\033[0;31m'
    Y='\033[1;33m'; M='\033[0;35m'; C='\033[0;36m'; NC='\033[0m'
    print(f"\n  {W}{'#':<4} {'Username':<20} {'Status':<10} {'Traffic':<24} {'Expire':<12} {'Note'}{NC}")
    print("  " + "─" * 85)
    for i, (uid, u, uuid, st, lim, used, exp, note) in enumerate(rows, 1):
        gb = (used or 0) / 1073741824
        lim_s = f"{lim:g} GB" if lim else "∞"
        used_s = f"{gb:.2f}/{lim_s}"
        sc = G if st == 'active' else (Y if st == 'limited' else (M if st == 'expired' else R))
        exp_s = exp[:10] if exp else '—'
        note_s = (note[:15] + '…' if note and len(note) > 15 else note or '')
        print(f"  {i:<4} {C}{u:<20}{NC} {sc}{st:<10}{NC} {used_s:<24} {exp_s:<12} {note_s}")
    print(f"\n  Total: {len(rows)} user(s)\n")
except Exception as e:
    print(f"  Error: {e}")
PYEOF
}

# ────────────────────────────────────────────────────────────
#  add-user — interactive user creation
# ────────────────────────────────────────────────────────────
cmd_add_user() {
    load_conf
    echo -e "${WHITE}── Add New User ────────────────────────────────${NC}"
    echo -ne "${CYAN}Username: ${NC}"; read U_NAME
    if [[ -z "$U_NAME" ]]; then echo -e "${RED}[ERROR]${NC} Username required."; return 1; fi
    echo -ne "${CYAN}Traffic limit GB (0=unlimited): ${NC}"; read U_TRAF
    U_TRAF=${U_TRAF:-0}
    echo -ne "${CYAN}Expire in days (0=unlimited): ${NC}"; read U_DAYS
    U_DAYS=${U_DAYS:-0}
    echo -ne "${CYAN}Note (optional, Enter to skip): ${NC}"; read U_NOTE

    "$VENV_PY" - "$U_NAME" "$U_TRAF" "$U_DAYS" "$U_NOTE" 2>/dev/null << 'PYEOF'
import sys, sqlite3, uuid, secrets, string, base64
from datetime import date, timedelta, datetime

uname = sys.argv[1]
traf  = float(sys.argv[2] or 0)
days  = int(sys.argv[3] or 0)
note  = sys.argv[4] if len(sys.argv) > 4 else ''

uid   = str(uuid.uuid4())
chars = string.ascii_letters + string.digits
pw    = ''.join(secrets.choice(chars) for _ in range(20))
ss    = base64.b64encode(secrets.token_bytes(32)).decode()
exp   = (date.today() + timedelta(days=days)).strftime('%Y-%m-%d') if days > 0 else None
now   = datetime.now().strftime('%Y-%m-%d %H:%M')

try:
    c = sqlite3.connect('/opt/masterpanel/users.db')
    if c.execute("SELECT 1 FROM users WHERE username=?", (uname,)).fetchone():
        print(f"\033[0;31m[ERROR]\033[0m Username '{uname}' already exists.")
        sys.exit(1)
    c.execute(
        "INSERT INTO users (username,uuid,password,ss_psk,status,traffic_limit_gb,"
        "used_traffic_bytes,expire_date,note,created_at) VALUES (?,?,?,?,'active',?,0,?,?,?)",
        (uname, uid, pw, ss, traf, exp, note, now))
    c.commit()
    print(f"\033[0;32m[OK]\033[0m User created: {uname}")
    print(f"     UUID   : {uid}")
    print(f"     Sub    : /sub/{uid}")
    if exp:
        print(f"     Expire : {exp}")
    if traf:
        print(f"     Traffic: {traf:g} GB")
except Exception as e:
    print(f"\033[0;31m[ERROR]\033[0m {e}")
    sys.exit(1)
PYEOF

    echo -e "${YELLOW}[INFO]${NC} Applying configs…"
    cmd_apply
}

# ────────────────────────────────────────────────────────────
#  del-user
# ────────────────────────────────────────────────────────────
cmd_del_user() {
    local NAME="$1"
    if [[ -z "$NAME" ]]; then
        echo -ne "${CYAN}Username to delete: ${NC}"; read NAME
    fi
    if [[ -z "$NAME" ]]; then echo -e "${RED}[ERROR]${NC} Username required."; return 1; fi
    echo -ne "${YELLOW}Delete user '$NAME'? [y/N]: ${NC}"; read CONF3
    [[ "$CONF3" != "y" && "$CONF3" != "Y" ]] && echo "Cancelled." && return

    "$VENV_PY" - "$NAME" 2>/dev/null << 'PYEOF'
import sys, sqlite3
name = sys.argv[1]
c = sqlite3.connect('/opt/masterpanel/users.db')
row = c.execute("SELECT id FROM users WHERE username=?", (name,)).fetchone()
if not row:
    print(f"\033[0;31m[ERROR]\033[0m User '{name}' not found.")
    sys.exit(1)
c.execute("DELETE FROM users WHERE username=?", (name,))
c.commit()
print(f"\033[0;32m[OK]\033[0m User '{name}' deleted.")
PYEOF

    cmd_apply
}

# ────────────────────────────────────────────────────────────
#  reset-user — zero traffic
# ────────────────────────────────────────────────────────────
cmd_reset_user() {
    local NAME="$1"
    if [[ -z "$NAME" ]]; then
        echo -ne "${CYAN}Username to reset: ${NC}"; read NAME
    fi

    "$VENV_PY" - "$NAME" 2>/dev/null << 'PYEOF'
import sys, sqlite3
name = sys.argv[1]
c = sqlite3.connect('/opt/masterpanel/users.db')
row = c.execute("SELECT id, status FROM users WHERE username=?", (name,)).fetchone()
if not row:
    print(f"\033[0;31m[ERROR]\033[0m User '{name}' not found.")
    sys.exit(1)
new_st = 'active' if row[1] == 'limited' else row[1]
c.execute("UPDATE users SET used_traffic_bytes=0, status=? WHERE username=?", (new_st, name))
c.commit()
print(f"\033[0;32m[OK]\033[0m Traffic for '{name}' reset. Status: {new_st}")
PYEOF

    cmd_apply
}

# ────────────────────────────────────────────────────────────
#  toggle-user — active ↔ disabled
# ────────────────────────────────────────────────────────────
cmd_toggle_user() {
    local NAME="$1"
    if [[ -z "$NAME" ]]; then
        echo -ne "${CYAN}Username to toggle: ${NC}"; read NAME
    fi

    "$VENV_PY" - "$NAME" 2>/dev/null << 'PYEOF'
import sys, sqlite3
name = sys.argv[1]
c = sqlite3.connect('/opt/masterpanel/users.db')
row = c.execute("SELECT status FROM users WHERE username=?", (name,)).fetchone()
if not row:
    print(f"\033[0;31m[ERROR]\033[0m User '{name}' not found.")
    sys.exit(1)
new_st = 'disabled' if row[0] == 'active' else 'active'
c.execute("UPDATE users SET status=? WHERE username=?", (new_st, name))
c.commit()
print(f"\033[0;32m[OK]\033[0m User '{name}' status → {new_st}")
PYEOF

    cmd_apply
}

# ────────────────────────────────────────────────────────────
#  links — show subscription URL for a user
# ────────────────────────────────────────────────────────────
cmd_links() {
    load_conf
    local NAME="$1"
    if [[ -z "$NAME" ]]; then
        echo -ne "${CYAN}Username: ${NC}"; read NAME
    fi
    local IP
    IP=$(curl -4 -s https://api4.ipify.org 2>/dev/null \
         || hostname -I | awk '{print $1}')

    "$VENV_PY" - "$NAME" "$IP" "${PANEL_PORT:-9090}" 2>/dev/null << 'PYEOF'
import sys, sqlite3
name, ip, port = sys.argv[1], sys.argv[2], sys.argv[3]
c = sqlite3.connect('/opt/masterpanel/users.db')
row = c.execute("SELECT uuid, status FROM users WHERE username=?", (name,)).fetchone()
if not row:
    print(f"\033[0;31m[ERROR]\033[0m User '{name}' not found.")
    sys.exit(1)
uid, st = row
print(f"\n  \033[1;37mUser\033[0m    : \033[0;36m{name}\033[0m  [{st}]")
print(f"  \033[1;37mUUID\033[0m    : \033[0;35m{uid}\033[0m")
print(f"  \033[1;37mSub URL\033[0m : \033[0;32mhttp://{ip}:{port}/sub/{uid}\033[0m")
print()
print("  Import this URL into v2rayNG, Nekobox, or any compatible client.")
print()
PYEOF
}

# ────────────────────────────────────────────────────────────
#  apply — rebuild configs from DB via panel API
# ────────────────────────────────────────────────────────────
cmd_apply() {
    load_conf
    echo -e "${BLUE}[*]${NC} Applying configs from database..."
    if systemctl is-active --quiet masterpanel 2>/dev/null; then
        local RESULT
        RESULT=$(curl -s -c /tmp/mp_cookie.txt \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"${PANEL_USER:-admin}\",\"password\":\"${PANEL_PASS:-admin123}\"}" \
            "http://127.0.0.1:${PANEL_PORT:-9090}/login" 2>/dev/null \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print('ok' if d.get('ok') else 'fail')" 2>/dev/null)
        if [[ "$RESULT" == "ok" ]]; then
            curl -s -b /tmp/mp_cookie.txt \
                -X POST "http://127.0.0.1:${PANEL_PORT:-9090}/api/apply" > /dev/null 2>&1
            echo -e "${GREEN}[✓]${NC} Configs applied via panel API."
        else
            systemctl restart masterpanel
            echo -e "${GREEN}[✓]${NC} Panel restarted (will sync on startup)."
        fi
    else
        echo -e "${YELLOW}[WARN]${NC} Panel not running. Start with: bash mp.sh restart"
    fi
}

# ────────────────────────────────────────────────────────────
#  restart commands
# ────────────────────────────────────────────────────────────
cmd_restart() {
    echo -e "${BLUE}[*]${NC} Restarting MasterPanel..."
    systemctl restart masterpanel
    sleep 2
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
        nohup "$XRAY_BIN" run -c "$XRAY_CFG" \
            >> /opt/masterpanel/logs/xray-access.log \
            2>> /opt/masterpanel/logs/xray-error.log &
    fi
    sleep 1
    pgrep -f "xray" > /dev/null \
        && echo -e "${GREEN}[✓]${NC} Xray running" \
        || echo -e "${RED}[✗]${NC} Xray failed"
}

cmd_restart_tuic() {
    systemctl restart tuic-server 2>/dev/null \
        && echo -e "${GREEN}[✓]${NC} TUIC restarted" \
        || echo -e "${RED}[✗]${NC} TUIC not installed or failed"
}

cmd_restart_hy2() {
    systemctl restart hysteria2 2>/dev/null \
        && echo -e "${GREEN}[✓]${NC} Hysteria2 restarted" \
        || echo -e "${RED}[✗]${NC} Hysteria2 not installed or failed"
}

cmd_restart_all() {
    cmd_restart_xray
    cmd_restart_tuic
    cmd_restart_hy2
    cmd_restart
    echo -e "${GREEN}[✓]${NC} All services restarted."
}

# ────────────────────────────────────────────────────────────
#  logs
# ────────────────────────────────────────────────────────────
cmd_logs() {
    case "${1:-panel}" in
        panel)         tail -f "$PANEL_DIR/logs/panel.log" ;;
        xray)          tail -f "$PANEL_DIR/logs/xray-error.log" ;;
        access)        tail -f "$PANEL_DIR/logs/xray-access.log" ;;
        tuic)          tail -f "$PANEL_DIR/logs/tuic.log" ;;
        hy2|hysteria2) tail -f "$PANEL_DIR/logs/hysteria2.log" ;;
        *)             echo "Usage: mp.sh logs [panel|xray|access|tuic|hy2]" ;;
    esac
}

# ────────────────────────────────────────────────────────────
#  backup
# ────────────────────────────────────────────────────────────
cmd_backup() {
    if [[ ! -f "$DB_FILE" ]]; then
        echo -e "${RED}[ERROR]${NC} Database not found."; return 1
    fi
    local TS; TS=$(date +%Y-%m-%d_%H-%M)
    local OUT="$PANEL_DIR/configs/users_backup_${TS}.db"
    cp "$DB_FILE" "$OUT"
    echo -e "${GREEN}[✓]${NC} Backup saved: $OUT"
}

# ────────────────────────────────────────────────────────────
#  renew-ssl
# ────────────────────────────────────────────────────────────
cmd_renew_ssl() {
    load_conf
    echo -e "${BLUE}[*]${NC} Renewing SSL for ${DOMAIN}..."
    systemctl stop masterpanel xray 2>/dev/null || true
    certbot renew --force-renewal -d "$DOMAIN" 2>&1 | tail -5
    systemctl start masterpanel
    sleep 3
    cmd_restart_xray
    systemctl restart tuic-server 2>/dev/null || true
    systemctl restart hysteria2 2>/dev/null || true
    echo -e "${GREEN}[✓]${NC} Done"
}

# ────────────────────────────────────────────────────────────
#  update-pass
# ────────────────────────────────────────────────────────────
cmd_update_pass() {
    load_conf
    echo -e "${WHITE}Current admin: ${CYAN}${PANEL_USER}${NC}"
    echo -ne "New password (min 8 chars): "
    read -s NEW_PASS; echo ""
    if [[ ${#NEW_PASS} -lt 8 ]]; then echo -e "${RED}Too short${NC}"; return 1; fi
    sed -i "s/^PANEL_PASS=.*/PANEL_PASS=${NEW_PASS}/" "$CONF_FILE"
    systemctl restart masterpanel
    echo -e "${GREEN}[✓]${NC} Password updated and panel restarted."
}

# ────────────────────────────────────────────────────────────
#  install-tuic / install-hy2
# ────────────────────────────────────────────────────────────
cmd_install_tuic() {
    echo -e "${BLUE}[*]${NC} Installing/updating TUIC v5..."
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && TA="aarch64-unknown-linux-gnu" || TA="x86_64-unknown-linux-gnu"
    VER=$(curl -s https://api.github.com/repos/EAimTY/tuic/releases/latest \
        | jq -r '.tag_name' 2>/dev/null || echo "tuic-server-1.0.0")
    wget -q "https://github.com/EAimTY/tuic/releases/download/${VER}/tuic-server-${TA}" \
        -O /usr/local/bin/tuic-server
    chmod +x /usr/local/bin/tuic-server
    echo -e "${GREEN}[✓]${NC} TUIC installed."
}

cmd_install_hy2() {
    echo -e "${BLUE}[*]${NC} Installing/updating Hysteria2..."
    bash <(curl -fsSL https://get.hy2.sh/) 2>&1 | tail -3
    echo -e "${GREEN}[✓]${NC} Hysteria2 installed."
}

# ────────────────────────────────────────────────────────────
#  uninstall
# ────────────────────────────────────────────────────────────
cmd_uninstall() {
    echo -e "${RED}[WARNING]${NC} This will remove MasterPanel completely."
    echo -e "${YELLOW}  DB, configs, SSL certs, and binaries are KEPT.${NC}"
    echo -ne "Type ${RED}yes${NC} to confirm: "
    read CONF2
    [[ "$CONF2" != "yes" ]] && echo "Cancelled." && return
    systemctl stop masterpanel tuic-server hysteria2 xray 2>/dev/null || true
    systemctl disable masterpanel tuic-server hysteria2 xray 2>/dev/null || true
    for SVC in masterpanel tuic-server hysteria2 xray; do
        rm -f "/etc/systemd/system/${SVC}.service"
    done
    # Preserve DB before removing panel dir
    if [[ -f "$DB_FILE" ]]; then
        cp "$DB_FILE" /root/users_db_backup_$(date +%Y%m%d).db 2>/dev/null \
            && echo -e "${GREEN}[✓]${NC} DB backed up to /root/users_db_backup_$(date +%Y%m%d).db"
    fi
    rm -rf "$PANEL_DIR"
    systemctl daemon-reload
    echo -e "${GREEN}[✓]${NC} MasterPanel removed."
    echo -e "${YELLOW}[NOTE]${NC} Xray, TUIC, Hysteria2 binaries and SSL certs preserved."
}

# ────────────────────────────────────────────────────────────
#  help
# ────────────────────────────────────────────────────────────
cmd_help() {
    print_banner
    echo -e "  ${WHITE}Usage:${NC} bash mp.sh [command] [args]"
    echo ""
    echo -e "  ${CYAN}── System ──────────────────────────────────────────${NC}"
    echo -e "  ${WHITE}status${NC}              Show services, users, SSL, URLs"
    echo -e "  ${WHITE}restart${NC}             Restart MasterPanel panel"
    echo -e "  ${WHITE}restart-xray${NC}        Restart Xray"
    echo -e "  ${WHITE}restart-tuic${NC}        Restart TUIC v5"
    echo -e "  ${WHITE}restart-hy2${NC}         Restart Hysteria2"
    echo -e "  ${WHITE}restart-all${NC}         Restart all services"
    echo -e "  ${WHITE}apply${NC}               Rebuild and apply configs from DB"
    echo -e "  ${WHITE}logs [service]${NC}      Tail logs: panel|xray|access|tuic|hy2"
    echo ""
    echo -e "  ${CYAN}── User Management ──────────────────────────────────${NC}"
    echo -e "  ${WHITE}users${NC}               List all users with traffic details"
    echo -e "  ${WHITE}add-user${NC}            Add a new user (interactive)"
    echo -e "  ${WHITE}del-user [name]${NC}     Delete a user"
    echo -e "  ${WHITE}reset-user [name]${NC}   Reset traffic counter for a user"
    echo -e "  ${WHITE}toggle-user [name]${NC}  Toggle active / disabled"
    echo -e "  ${WHITE}links [name]${NC}        Show subscription URL for a user"
    echo ""
    echo -e "  ${CYAN}── Maintenance ──────────────────────────────────────${NC}"
    echo -e "  ${WHITE}backup${NC}              Save dated backup of users.db locally"
    echo -e "  ${WHITE}renew-ssl${NC}           Force renew SSL certificate"
    echo -e "  ${WHITE}update-pass${NC}         Change panel admin password"
    echo -e "  ${WHITE}install-tuic${NC}        Install / update TUIC v5"
    echo -e "  ${WHITE}install-hy2${NC}         Install / update Hysteria2"
    echo -e "  ${WHITE}uninstall${NC}           Remove MasterPanel (keeps DB & certs)"
    echo ""
}

# ══ MAIN ══════════════════════════════════════════════════════
print_banner
load_conf

case "${1:-help}" in
    status)         cmd_status ;;
    restart)        cmd_restart ;;
    restart-xray)   cmd_restart_xray ;;
    restart-tuic)   cmd_restart_tuic ;;
    restart-hy2)    cmd_restart_hy2 ;;
    restart-all)    cmd_restart_all ;;
    apply)          cmd_apply ;;
    logs)           cmd_logs "$2" ;;
    users)          cmd_users ;;
    add-user)       cmd_add_user ;;
    del-user)       cmd_del_user "$2" ;;
    reset-user)     cmd_reset_user "$2" ;;
    toggle-user)    cmd_toggle_user "$2" ;;
    links)          cmd_links "$2" ;;
    backup)         cmd_backup ;;
    renew-ssl)      cmd_renew_ssl ;;
    update-pass)    cmd_update_pass ;;
    install-tuic)   cmd_install_tuic ;;
    install-hy2)    cmd_install_hy2 ;;
    uninstall)      cmd_uninstall ;;
    help|--help|-h) cmd_help ;;
    *)              echo -e "${RED}[ERROR]${NC} Unknown command: $1"; echo ""; cmd_help ;;
esac
