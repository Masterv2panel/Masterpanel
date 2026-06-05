#!/usr/bin/env python3
"""
MasterPanel - Xray Multi-User Management Panel
Backend Server v3.0  (Advanced Edition)

Upgraded from v2.0:
  • SQLite-backed multi-user management (users.db)
  • Dynamic per-user Xray client generation (conflict-free port map)
  • Subscription endpoint  /sub/<uuid>  (Base64, with remaining-traffic profile)
  • XHTTP protocol + Cloudflare Clean-IP injection for CDN configs
  • Background traffic monitor via Xray Stats API  (auto disable on limit/expiry)
  • Telegram bot  (DB backups + limit/expiry notifications)
  • One-click GitHub auto-update (keeps users.db intact)

Protocols: VLESS (WS / XHTTP / gRPC / TCP / REALITY-Vision), VMess (WS / XHTTP / TCP),
           Trojan (WS / TCP), Shadowsocks-2022, TUIC v5, Hysteria2, WireGuard (note)
"""

import os, json, uuid, subprocess, socket, ssl, time, base64, secrets, string
import sqlite3, threading, shutil
import urllib.parse, urllib.request
from urllib.parse import quote
from functools import wraps
from datetime import datetime, date, timedelta
from pathlib import Path
from flask import Flask, render_template, request, jsonify, session, redirect, url_for, Response

app = Flask(__name__)

# ══════════════════════════════════════════════════════════════════
#  Configuration  (panel.conf — written by install.sh)
# ══════════════════════════════════════════════════════════════════
PANEL_DIR = Path("/opt/masterpanel")
CONF_FILE = PANEL_DIR / "panel.conf"
DB_FILE   = PANEL_DIR / "users.db"
LOGS_DIR  = PANEL_DIR / "logs"
CONFIGS_DIR = PANEL_DIR / "configs"


def load_conf():
    conf = {}
    if CONF_FILE.exists():
        for line in CONF_FILE.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip()
    return conf


CFG          = load_conf()
DOMAIN       = CFG.get("DOMAIN", "example.com")
PANEL_USER   = CFG.get("PANEL_USER", "admin")
PANEL_PASS   = CFG.get("PANEL_PASS", "admin123")
PANEL_PORT   = int(CFG.get("PANEL_PORT", 9090))
CERT_PATH    = CFG.get("CERT_PATH", "")
KEY_PATH     = CFG.get("KEY_PATH", "")
XRAY_CFG_DIR = Path(CFG.get("XRAY_CONFIG_DIR", "/usr/local/etc/xray"))
XRAY_BIN     = CFG.get("XRAY_BIN", "/usr/local/bin/xray")
TUIC_BIN     = CFG.get("TUIC_BIN", "/usr/local/bin/tuic-server")
HY2_BIN      = CFG.get("HY2_BIN", "/usr/local/bin/hysteria")

for d in (PANEL_DIR, CONFIGS_DIR, LOGS_DIR):
    try:
        d.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
try:
    XRAY_CFG_DIR.mkdir(parents=True, exist_ok=True)
except Exception:
    pass

# ── Constants ─────────────────────────────────────────────────────
GB             = 1024 ** 3
XRAY_API_PORT  = 10085                       # loopback Xray gRPC API
SS_METHOD      = "2022-blake3-aes-256-gcm"
HY2_PORT       = 443                         # UDP
TUIC_PORT      = 2053                        # UDP
WG_PORT        = 51820                       # note only
REALITY_DEST   = "www.microsoft.com:443"
REALITY_SNI    = "www.microsoft.com"

_apply_lock = threading.Lock()


def log(msg):
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)


# ══════════════════════════════════════════════════════════════════
#  Database layer
# ══════════════════════════════════════════════════════════════════
def get_conn():
    conn = sqlite3.connect(str(DB_FILE), timeout=15)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_conn()
    c = conn.cursor()
    c.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id                 INTEGER PRIMARY KEY AUTOINCREMENT,
            username           TEXT UNIQUE NOT NULL,
            uuid               TEXT UNIQUE NOT NULL,
            password           TEXT NOT NULL,
            ss_psk             TEXT NOT NULL,
            status             TEXT NOT NULL DEFAULT 'active',
            traffic_limit_gb   REAL NOT NULL DEFAULT 0,
            used_traffic_bytes INTEGER NOT NULL DEFAULT 0,
            expire_date        TEXT,
            note               TEXT,
            created_at         TEXT
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS settings (
            key   TEXT PRIMARY KEY,
            value TEXT
        )
    """)
    conn.commit()
    # Seed default settings (only if missing)
    defaults = {
        "clean_ip":           "",
        "telegram_bot_token": "",
        "telegram_admin_chat": "",
        "github_repo":        "Masterv2panel/Masterpanel",
        "github_branch":      "main",
        "monitor_interval":   "60",
        "backup_hour":        "6",
        "sub_url_base":       "",
    }
    for k, v in defaults.items():
        c.execute("INSERT OR IGNORE INTO settings(key, value) VALUES (?, ?)", (k, v))
    conn.commit()
    conn.close()


# ── Settings helpers ──────────────────────────────────────────────
def get_setting(key, default=""):
    try:
        conn = get_conn()
        row = conn.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
        conn.close()
        if row is not None and row["value"] is not None:
            return row["value"]
    except Exception as e:
        log(f"get_setting error: {e}")
    return default


def set_setting(key, value):
    try:
        conn = get_conn()
        conn.execute(
            "INSERT INTO settings(key, value) VALUES (?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            (key, str(value)))
        conn.commit()
        conn.close()
    except Exception as e:
        log(f"set_setting error: {e}")


# ── User helpers ──────────────────────────────────────────────────
def get_all_users():
    try:
        conn = get_conn()
        rows = conn.execute("SELECT * FROM users ORDER BY id ASC").fetchall()
        conn.close()
        return [dict(r) for r in rows]
    except Exception as e:
        log(f"get_all_users error: {e}")
        return []


def get_user(uid):
    conn = get_conn()
    row = conn.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
    conn.close()
    return dict(row) if row else None


def get_user_by_uuid(token):
    conn = get_conn()
    row = conn.execute("SELECT * FROM users WHERE uuid=?", (token,)).fetchone()
    conn.close()
    return dict(row) if row else None


def get_user_by_name(name):
    conn = get_conn()
    row = conn.execute("SELECT * FROM users WHERE username=?", (name,)).fetchone()
    conn.close()
    return dict(row) if row else None


def create_user(username, traffic_limit_gb=0, expire_date=None, note="",
                user_uuid=None, password=None, ss_psk=None, status="active"):
    user_uuid = user_uuid or new_uuid()
    password  = password  or new_password(20)
    ss_psk    = ss_psk    or new_ss_psk()
    conn = get_conn()
    conn.execute(
        "INSERT INTO users (username, uuid, password, ss_psk, status, "
        "traffic_limit_gb, used_traffic_bytes, expire_date, note, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?)",
        (username, user_uuid, password, ss_psk, status,
         float(traffic_limit_gb or 0), expire_date, note, now_iso()))
    conn.commit()
    uid = conn.execute("SELECT id FROM users WHERE username=?", (username,)).fetchone()["id"]
    conn.close()
    return uid


def update_user(uid, **fields):
    if not fields:
        return
    cols = ", ".join(f"{k}=?" for k in fields)
    vals = list(fields.values()) + [uid]
    conn = get_conn()
    conn.execute(f"UPDATE users SET {cols} WHERE id=?", vals)
    conn.commit()
    conn.close()


def delete_user(uid):
    conn = get_conn()
    conn.execute("DELETE FROM users WHERE id=?", (uid,))
    conn.commit()
    conn.close()


# ══════════════════════════════════════════════════════════════════
#  Date / format helpers
# ══════════════════════════════════════════════════════════════════
def now_iso():
    return datetime.now().strftime("%Y-%m-%d %H:%M")


def remaining_days(expire_date):
    """None = unlimited. int = days remaining (negative if past)."""
    if not expire_date:
        return None
    try:
        d = datetime.strptime(expire_date[:10], "%Y-%m-%d").date()
        return (d - date.today()).days
    except Exception:
        return None


def is_expired(expire_date):
    rd = remaining_days(expire_date)
    return rd is not None and rd < 0


def expire_unix(expire_date):
    """Unix timestamp at end of expiry day (0 = unlimited)."""
    if not expire_date:
        return 0
    try:
        d = datetime.strptime(expire_date[:10], "%Y-%m-%d")
        d = d.replace(hour=23, minute=59, second=59)
        return int(d.timestamp())
    except Exception:
        return 0


def parse_expire(data):
    """Accept either expire_date 'YYYY-MM-DD' or expire_days int (0 = unlimited)."""
    if data.get("expire_date"):
        return str(data["expire_date"])[:10]
    days = data.get("expire_days")
    if days in (None, "", "0", 0):
        return None
    try:
        days = int(days)
        if days <= 0:
            return None
        return (date.today() + timedelta(days=days)).strftime("%Y-%m-%d")
    except Exception:
        return None


def human_bytes(n):
    try:
        n = float(n)
    except Exception:
        return "0 B"
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(n) < 1024.0 or unit == "TB":
            return f"{n:.2f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1024.0
    return f"{n:.2f} TB"


# ══════════════════════════════════════════════════════════════════
#  Crypto / credential helpers
# ══════════════════════════════════════════════════════════════════
def new_uuid():
    return str(uuid.uuid4())


def new_password(length=20):
    chars = string.ascii_letters + string.digits
    return "".join(secrets.choice(chars) for _ in range(length))


def new_ss_psk():
    """32-byte base64 PSK for 2022-blake3-aes-256-gcm."""
    return base64.b64encode(secrets.token_bytes(32)).decode()


def gen_reality_keys():
    """Generate one x25519 keypair via the xray binary."""
    try:
        r = subprocess.run([XRAY_BIN, "x25519"], capture_output=True, text=True, timeout=5)
        priv = pub = ""
        for line in r.stdout.strip().splitlines():
            low = line.lower()
            if "private" in low:
                priv = line.split(":")[-1].strip()
            elif "public" in low:
                pub = line.split(":")[-1].strip()
        return priv, pub
    except Exception as e:
        log(f"gen_reality_keys error: {e}")
        return "", ""


def ensure_server_secrets():
    """Lazily create + persist shared server secrets. Returns a dict."""
    priv = get_setting("reality_priv")
    pub  = get_setting("reality_pub")
    if not priv or not pub:
        priv, pub = gen_reality_keys()
        if priv:
            set_setting("reality_priv", priv)
        if pub:
            set_setting("reality_pub", pub)

    sid = get_setting("reality_sid")
    if not sid:
        sid = secrets.token_hex(4)
        set_setting("reality_sid", sid)

    ss_server = get_setting("ss_server_psk")
    if not ss_server:
        ss_server = new_ss_psk()
        set_setting("ss_server_psk", ss_server)

    return {
        "reality_priv": priv,
        "reality_pub":  pub,
        "reality_sid":  sid,
        "ss_server_psk": ss_server,
    }


# ── Server IP (forces IPv4) ───────────────────────────────────────
_server_ip_cache = {"ip": None}


def get_server_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and not ip.startswith("127.") and ":" not in ip:
            return ip
    except Exception:
        pass
    for api in ("https://api4.ipify.org", "https://ipv4.icanhazip.com", "https://v4.ident.me"):
        try:
            req = urllib.request.Request(api, headers={"User-Agent": "curl/7.0"})
            with urllib.request.urlopen(req, timeout=4) as r:
                ip = r.read().decode().strip()
                if ip and ":" not in ip and not ip.startswith("127."):
                    return ip
        except Exception:
            continue
    try:
        for r in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = r[4][0]
            if not ip.startswith("127."):
                return ip
    except Exception:
        pass
    return "0.0.0.0"


def server_ip():
    if not _server_ip_cache["ip"]:
        _server_ip_cache["ip"] = get_server_ip()
    return _server_ip_cache["ip"]


def get_uptime():
    try:
        with open("/proc/uptime") as f:
            secs = float(f.read().split()[0])
        h = int(secs // 3600)
        m = int((secs % 3600) // 60)
        return f"{h}h {m}m"
    except Exception:
        return "N/A"


# ══════════════════════════════════════════════════════════════════
#  Port map / config templates
#  Each template defines ONE inbound shared by all users.
#  conn:  cdn  -> behind Cloudflare (address = clean_ip or DOMAIN, TLS, CF port)
#         direct -> straight to server IP
#  net:   ws | xhttp | grpc | tcp
#  sec:   tls | reality | none
# ══════════════════════════════════════════════════════════════════
TEMPLATES = [
    # ── CDN (Cloudflare) — TLS only, CF-supported HTTPS ports ──────
    {"key": "vl-ws",   "label": "VLESS-WS-CDN",     "proto": "vless",  "net": "ws",    "sec": "tls", "port": 443,  "conn": "cdn", "path": "/vl-ws"},
    {"key": "vl-xh",   "label": "VLESS-XHTTP-CDN",  "proto": "vless",  "net": "xhttp", "sec": "tls", "port": 8443, "conn": "cdn", "path": "/vl-xh"},
    {"key": "vl-grpc", "label": "VLESS-gRPC-CDN",   "proto": "vless",  "net": "grpc",  "sec": "tls", "port": 2053, "conn": "cdn", "service": "vl-grpc"},
    {"key": "vm-ws",   "label": "VMESS-WS-CDN",     "proto": "vmess",  "net": "ws",    "sec": "tls", "port": 2083, "conn": "cdn", "path": "/vm-ws"},
    {"key": "vm-xh",   "label": "VMESS-XHTTP-CDN",  "proto": "vmess",  "net": "xhttp", "sec": "tls", "port": 2087, "conn": "cdn", "path": "/vm-xh"},
    {"key": "tr-ws",   "label": "TROJAN-WS-CDN",    "proto": "trojan", "net": "ws",    "sec": "tls", "port": 2096, "conn": "cdn", "path": "/tr-ws"},

    # ── Direct IP — TCP inbounds on dedicated ports (9443-9449) ────
    {"key": "vl-reality", "label": "VLESS-REALITY-Vision", "proto": "vless",  "net": "tcp",   "sec": "reality", "port": 9443, "conn": "direct", "flow": "xtls-rprx-vision", "sni": REALITY_SNI, "dest": REALITY_DEST},
    {"key": "vl-xh-d",    "label": "VLESS-XHTTP-IP",       "proto": "vless",  "net": "xhttp", "sec": "tls",     "port": 9444, "conn": "direct", "path": "/vl-xh"},
    {"key": "vl-ws-d",    "label": "VLESS-WS-IP",          "proto": "vless",  "net": "ws",    "sec": "tls",     "port": 9445, "conn": "direct", "path": "/vl-ws"},
    {"key": "vm-ws-d",    "label": "VMESS-WS-IP",          "proto": "vmess",  "net": "ws",    "sec": "tls",     "port": 9446, "conn": "direct", "path": "/vm-ws"},
    {"key": "tr-tcp-d",   "label": "TROJAN-TCP-IP",        "proto": "trojan", "net": "tcp",   "sec": "tls",     "port": 9447, "conn": "direct"},
    {"key": "vl-tcp-d",   "label": "VLESS-TCP-IP",         "proto": "vless",  "net": "tcp",   "sec": "tls",     "port": 9448, "conn": "direct"},
    {"key": "vm-tcp-d",   "label": "VMESS-TCP-IP",         "proto": "vmess",  "net": "tcp",   "sec": "tls",     "port": 9449, "conn": "direct"},

    # ── Shadowsocks 2022 (tcp+udp) — two ports for failover ────────
    {"key": "ss-1", "label": "Shadowsocks-2022", "proto": "ss", "net": "tcp", "sec": "none", "port": 8388, "conn": "direct"},
    {"key": "ss-2", "label": "Shadowsocks-2022", "proto": "ss", "net": "tcp", "sec": "none", "port": 8389, "conn": "direct"},
]

XRAY_TEMPLATES = [t for t in TEMPLATES]   # everything above runs inside Xray


# ══════════════════════════════════════════════════════════════════
#  Share-link builders
# ══════════════════════════════════════════════════════════════════
def stream_params(tpl, address, sni, host, sec):
    """Build the query string shared by VLESS/Trojan share links."""
    net = tpl["net"]
    params = {"type": net, "security": sec}
    if sec in ("tls", "reality"):
        params["sni"] = sni
        params["fp"] = "chrome"
    if sec == "reality":
        secd = ensure_server_secrets()
        params["pbk"] = secd["reality_pub"]
        params["sid"] = secd["reality_sid"]
    if net == "ws":
        params["path"] = tpl.get("path", "/")
        params["host"] = host
    elif net == "xhttp":
        params["path"] = tpl.get("path", "/")
        params["host"] = host
        params["mode"] = "auto"
    elif net == "grpc":
        params["serviceName"] = tpl.get("service", "grpc")
        params["mode"] = "gun"
    # tcp: nothing extra
    parts = []
    for k, v in params.items():
        parts.append(f"{k}={quote(str(v), safe='')}")
    return "&".join(parts)


def vless_link(tpl, u, address, sni, host, name):
    q = stream_params(tpl, address, sni, host, tpl["sec"])
    if tpl.get("flow"):
        q += f"&flow={tpl['flow']}"
    return f"vless://{u['uuid']}@{address}:{tpl['port']}?{q}#{quote(name)}"


def trojan_link(tpl, u, address, sni, host, name):
    q = stream_params(tpl, address, sni, host, tpl["sec"])
    return f"trojan://{quote(u['password'], safe='')}@{address}:{tpl['port']}?{q}#{quote(name)}"


def vmess_link(tpl, u, address, sni, host, name):
    net = tpl["net"]
    data = {
        "v": "2", "ps": name, "add": address, "port": str(tpl["port"]),
        "id": u["uuid"], "aid": "0", "scy": "auto",
        "net": net, "type": "none", "host": host,
        "path": tpl.get("path", "/"),
        "tls": "tls" if tpl["sec"] == "tls" else "",
        "sni": sni, "fp": "chrome",
    }
    if net == "grpc":
        data["net"] = "grpc"
        data["path"] = tpl.get("service", "grpc")
        data["type"] = "gun"
    elif net == "xhttp":
        data["net"] = "xhttp"
    elif net == "tcp":
        data["net"] = "tcp"
    return "vmess://" + base64.b64encode(json.dumps(data).encode()).decode()


def ss_link(tpl, u, address, sec, name):
    """SS-2022 multi-user URI: ss://b64(method:serverPSK:userPSK)@addr:port#name"""
    userinfo = base64.b64encode(
        f"{SS_METHOD}:{sec['ss_server_psk']}:{u['ss_psk']}".encode()).decode()
    return f"ss://{userinfo}@{address}:{tpl['port']}#{quote(name)}"


def tuic_link(u, address, name):
    return (f"tuic://{u['uuid']}:{quote(u['password'], safe='')}@{address}:{TUIC_PORT}"
            f"?sni={quote(DOMAIN)}&congestion_control=bbr&alpn=h3&udp_relay_mode=native#{quote(name)}")


def hy2_link(u, address, name):
    return (f"hysteria2://{quote(u['username'], safe='')}:{quote(u['password'], safe='')}"
            f"@{address}:{HY2_PORT}?sni={quote(DOMAIN)}#{quote(name)}")


# ══════════════════════════════════════════════════════════════════
#  Build all share links for ONE user
# ══════════════════════════════════════════════════════════════════
def build_user_configs(u):
    sec = ensure_server_secrets()
    clean = get_setting("clean_ip", "").strip()
    ip = server_ip()
    configs = []

    for tpl in TEMPLATES:
        proto, conn = tpl["proto"], tpl["conn"]
        if conn == "cdn":
            address = clean if clean else DOMAIN
            host    = DOMAIN
            sni     = DOMAIN
        else:  # direct
            address = ip
            host    = DOMAIN
            sni     = tpl.get("sni", DOMAIN)
        name = f"{u['username']}-{tpl['label']}"

        if proto == "vless":
            link = vless_link(tpl, u, address, sni, host, name)
        elif proto == "vmess":
            link = vmess_link(tpl, u, address, sni, host, name)
        elif proto == "trojan":
            link = trojan_link(tpl, u, address, sni, host, name)
        elif proto == "ss":
            link = ss_link(tpl, u, address, sec, name)
        else:
            continue

        configs.append({
            "name": name, "protocol": proto, "network": tpl["net"],
            "tls": tpl["sec"], "port": tpl["port"], "conn": conn,
            "address": address, "link": link, "note": "",
        })

    # ── UDP daemons (separate processes) ──────────────────────────
    if Path(HY2_BIN).exists():
        nm = f"{u['username']}-HYSTERIA2"
        configs.append({
            "name": nm, "protocol": "hysteria2", "network": "udp", "tls": "tls",
            "port": HY2_PORT, "conn": "direct", "address": ip,
            "link": hy2_link(u, ip, nm), "note": "UDP",
        })
    if Path(TUIC_BIN).exists():
        nm = f"{u['username']}-TUIC"
        configs.append({
            "name": nm, "protocol": "tuic", "network": "udp", "tls": "tls",
            "port": TUIC_PORT, "conn": "direct", "address": ip,
            "link": tuic_link(u, ip, nm), "note": "UDP",
        })

    # WireGuard placeholder (manual setup — note only)
    configs.append({
        "name": f"{u['username']}-WireGuard", "protocol": "wireguard",
        "network": "udp", "tls": "none", "port": WG_PORT, "conn": "direct",
        "address": ip, "link": "",
        "note": "WireGuard نیازمند پیکربندی دستی است (پشتیبانی از لینک اشتراکی ندارد)",
    })
    return configs


def build_info_node(u):
    """A leading VLESS node whose NAME shows remaining traffic / days."""
    rd = remaining_days(u["expire_date"])
    if rd is None:
        days_txt = "نامحدود"
    elif rd < 0:
        days_txt = "منقضی شده"
    else:
        days_txt = f"{rd} روز"

    if u["traffic_limit_gb"] and u["traffic_limit_gb"] > 0:
        remain = max(0, u["traffic_limit_gb"] * GB - u["used_traffic_bytes"])
        traf_txt = human_bytes(remain)
    else:
        traf_txt = "نامحدود"

    name = f"♻️ {traf_txt} | ⏳ {days_txt}"
    clean = get_setting("clean_ip", "").strip()
    address = clean if clean else DOMAIN
    tpl = {"net": "ws", "sec": "tls", "port": 443, "path": "/vl-ws"}
    q = stream_params(tpl, address, DOMAIN, DOMAIN, "tls")
    return f"vless://{u['uuid']}@{address}:443?{q}#{quote(name)}"


# ══════════════════════════════════════════════════════════════════
#  Xray inbound builders
# ══════════════════════════════════════════════════════════════════
def clients_for(tpl, users, sec):
    proto = tpl["proto"]
    clients = []
    for u in users:
        if proto in ("vless",):
            cl = {"id": u["uuid"], "email": u["username"], "level": 0}
            if tpl.get("flow"):
                cl["flow"] = tpl["flow"]
            clients.append(cl)
        elif proto == "vmess":
            clients.append({"id": u["uuid"], "email": u["username"], "level": 0})
        elif proto == "trojan":
            clients.append({"password": u["password"], "email": u["username"], "level": 0})
        elif proto == "ss":
            clients.append({"password": u["ss_psk"], "email": u["username"]})
    return clients


def tls_settings():
    return {
        "serverName": DOMAIN,
        "alpn": ["h2", "http/1.1"],
        "certificates": [{"certificateFile": CERT_PATH, "keyFile": KEY_PATH}],
    }


def reality_settings(tpl, sec):
    return {
        "show": False,
        "dest": tpl.get("dest", REALITY_DEST),
        "xver": 0,
        "serverNames": [tpl.get("sni", REALITY_SNI)],
        "privateKey": sec["reality_priv"],
        "shortIds": [sec["reality_sid"]],
    }


def stream_settings(tpl, sec):
    net = tpl["net"]
    st = {"network": net, "security": tpl["sec"]}
    if tpl["sec"] == "tls":
        st["tlsSettings"] = tls_settings()
    elif tpl["sec"] == "reality":
        st["realitySettings"] = reality_settings(tpl, sec)
    if net == "ws":
        st["wsSettings"] = {"path": tpl.get("path", "/"), "headers": {"Host": DOMAIN}}
    elif net == "xhttp":
        st["xhttpSettings"] = {"path": tpl.get("path", "/"), "host": DOMAIN, "mode": "auto"}
    elif net == "grpc":
        st["grpcSettings"] = {"serviceName": tpl.get("service", "grpc")}
    return st


def build_inbound(tpl, users, sec):
    proto = tpl["proto"]
    clients = clients_for(tpl, users, sec)
    inbound = {
        "tag": f"in-{tpl['key']}",
        "listen": "0.0.0.0",
        "port": tpl["port"],
    }
    if proto == "ss":
        inbound["protocol"] = "shadowsocks"
        inbound["settings"] = {
            "method": SS_METHOD,
            "password": sec["ss_server_psk"],
            "clients": clients,
            "network": "tcp,udp",
        }
        inbound["streamSettings"] = {"network": "tcp"}
    elif proto == "vless":
        inbound["protocol"] = "vless"
        inbound["settings"] = {"clients": clients, "decryption": "none"}
        inbound["streamSettings"] = stream_settings(tpl, sec)
    elif proto == "vmess":
        inbound["protocol"] = "vmess"
        inbound["settings"] = {"clients": clients}
        inbound["streamSettings"] = stream_settings(tpl, sec)
    elif proto == "trojan":
        inbound["protocol"] = "trojan"
        inbound["settings"] = {"clients": clients}
        inbound["streamSettings"] = stream_settings(tpl, sec)
    return inbound


def write_xray_config(users, sec):
    inbounds = []
    for t in XRAY_TEMPLATES:
        # A REALITY inbound with an empty privateKey would crash all of Xray,
        # so skip it gracefully if key generation failed.
        if t["sec"] == "reality" and not sec.get("reality_priv"):
            log("Skipping REALITY inbound (no private key available).")
            continue
        inbounds.append(build_inbound(t, users, sec))
    # API inbound (loopback) for live stats
    inbounds.append({
        "tag": "api",
        "listen": "127.0.0.1",
        "port": XRAY_API_PORT,
        "protocol": "dokodemo-door",
        "settings": {"address": "127.0.0.1"},
    })
    conf = {
        "log": {
            "loglevel": "warning",
            "access": str(LOGS_DIR / "xray-access.log"),
            "error":  str(LOGS_DIR / "xray-error.log"),
        },
        "stats": {},
        "api": {"tag": "api", "services": ["HandlerService", "StatsService"]},
        "policy": {
            "levels": {"0": {"statsUserUplink": True, "statsUserDownlink": True}},
            "system": {"statsInboundUplink": True, "statsInboundDownlink": True},
        },
        "inbounds": inbounds,
        "outbounds": [
            {"tag": "direct",  "protocol": "freedom"},
            {"tag": "blocked", "protocol": "blackhole"},
        ],
        "routing": {
            "rules": [
                {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
                {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"},
                {"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "blocked"},
            ]
        },
    }
    path = XRAY_CFG_DIR / "config.json"
    path.write_text(json.dumps(conf, indent=2))
    return path


def write_tuic_config(users):
    """TUIC v5 supports multiple users via a {uuid: password} map."""
    if not users:
        return
    user_map = {u["uuid"]: u["password"] for u in users}
    conf = {
        "server": f"0.0.0.0:{TUIC_PORT}",
        "users": user_map,
        "certificate": CERT_PATH,
        "private_key": KEY_PATH,
        "congestion_controller": "bbr",
        "alpn": ["h3"],
        "log_level": "warn",
    }
    (CONFIGS_DIR / "tuic_config.json").write_text(json.dumps(conf, indent=2))


def write_hy2_config(users):
    """Hysteria2 userpass auth — map of {username: password}."""
    if not users:
        return
    lines = []
    lines.append(f"listen: :{HY2_PORT}")
    lines.append("tls:")
    lines.append(f"  cert: {CERT_PATH}")
    lines.append(f"  key: {KEY_PATH}")
    lines.append("auth:")
    lines.append("  type: userpass")
    lines.append("  userpass:")
    for u in users:
        lines.append(f"    {u['username']}: {u['password']}")
    lines.append("masquerade:")
    lines.append("  type: proxy")
    lines.append("  proxy:")
    lines.append("    url: https://www.bing.com")
    lines.append("    rewriteHost: true")
    (CONFIGS_DIR / "hysteria2_config.yaml").write_text("\n".join(lines) + "\n")


# ══════════════════════════════════════════════════════════════════
#  Service control
# ══════════════════════════════════════════════════════════════════
def restart_xray():
    path = XRAY_CFG_DIR / "config.json"
    try:
        r = subprocess.run(["systemctl", "restart", "xray"], timeout=12, capture_output=True)
        if r.returncode == 0:
            return
    except Exception:
        pass
    # Fallback: kill running xray and relaunch
    try:
        subprocess.run(["pkill", "-f", "xray run"], capture_output=True)
        time.sleep(1)
        subprocess.Popen([XRAY_BIN, "run", "-c", str(path)],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except Exception as e:
        log(f"restart_xray fallback error: {e}")


def restart_service(name):
    try:
        subprocess.run(["systemctl", "restart", name], timeout=12, capture_output=True)
    except Exception as e:
        log(f"restart_service {name} error: {e}")


def stop_service(name):
    try:
        subprocess.run(["systemctl", "stop", name], timeout=12, capture_output=True)
    except Exception:
        pass


def active_users():
    """Users that should be live: status active AND not expired."""
    return [u for u in get_all_users()
            if u["status"] == "active" and not is_expired(u["expire_date"])]


def apply_configs():
    """Rebuild every server config from the DB and reload services."""
    sec = ensure_server_secrets()
    users = active_users()

    write_xray_config(users, sec)
    restart_xray()

    if Path(HY2_BIN).exists():
        if users:
            write_hy2_config(users)
            restart_service("hysteria2")
        else:
            stop_service("hysteria2")

    if Path(TUIC_BIN).exists():
        if users:
            write_tuic_config(users)
            restart_service("tuic-server")
        else:
            stop_service("tuic-server")

    log(f"apply_configs: {len(users)} active user(s) synced.")


def apply_configs_async():
    def _run():
        with _apply_lock:
            try:
                apply_configs()
            except Exception as e:
                log(f"apply_configs error: {e}")
    threading.Thread(target=_run, daemon=True).start()


# ══════════════════════════════════════════════════════════════════
#  Xray Stats API  →  traffic monitor
# ══════════════════════════════════════════════════════════════════
def query_xray_stats():
    """Return {username: delta_bytes_since_last_poll}. Uses -reset (delta mode)."""
    deltas = {}
    try:
        r = subprocess.run(
            [XRAY_BIN, "api", "statsquery", f"--server=127.0.0.1:{XRAY_API_PORT}", "-reset"],
            capture_output=True, text=True, timeout=10)
        if r.returncode != 0 or not r.stdout.strip():
            return deltas
        data = json.loads(r.stdout)
        for stat in data.get("stat", []) or []:
            name = stat.get("name", "")
            value = int(stat.get("value", 0) or 0)
            # pattern: user>>>EMAIL>>>traffic>>>uplink|downlink
            if name.startswith("user>>>"):
                parts = name.split(">>>")
                if len(parts) >= 2:
                    email = parts[1]
                    deltas[email] = deltas.get(email, 0) + value
    except Exception as e:
        log(f"query_xray_stats error: {e}")
    return deltas


def run_monitor():
    """Update usage, auto-disable on limit/expiry, reload if anything changed."""
    deltas = query_xray_stats()
    changed = False
    for u in get_all_users():
        delta = int(deltas.get(u["username"], 0))
        new_used = u["used_traffic_bytes"] + delta
        new_status = u["status"]

        if u["status"] == "active":
            limit = u["traffic_limit_gb"] or 0
            if limit > 0 and new_used >= limit * GB:
                new_status = "limited"
                changed = True
                tg_send(f"⛔️ کاربر <b>{u['username']}</b> به سقف ترافیک رسید و غیرفعال شد.\n"
                        f"مصرف: {human_bytes(new_used)} / {limit} گیگابایت")
            elif is_expired(u["expire_date"]):
                new_status = "expired"
                changed = True
                tg_send(f"⏳ اشتراک کاربر <b>{u['username']}</b> منقضی شد و غیرفعال گردید.")

        if delta != 0 or new_status != u["status"]:
            update_user(u["id"], used_traffic_bytes=new_used, status=new_status)

    if changed:
        apply_configs_async()


# ══════════════════════════════════════════════════════════════════
#  Telegram bot
# ══════════════════════════════════════════════════════════════════
def tg_token():
    return get_setting("telegram_bot_token", "").strip()


def tg_chat():
    return get_setting("telegram_admin_chat", "").strip()


def tg_enabled():
    return bool(tg_token() and tg_chat())


def tg_send(text):
    if not tg_enabled():
        return False
    try:
        import requests
        url = f"https://api.telegram.org/bot{tg_token()}/sendMessage"
        requests.post(url, json={"chat_id": tg_chat(), "text": text,
                                 "parse_mode": "HTML"}, timeout=10)
        return True
    except Exception as e:
        log(f"tg_send error: {e}")
        return False


def tg_send_doc(path, caption=""):
    if not tg_enabled():
        return False
    try:
        import requests
        url = f"https://api.telegram.org/bot{tg_token()}/sendDocument"
        with open(path, "rb") as fp:
            requests.post(url, data={"chat_id": tg_chat(), "caption": caption},
                          files={"document": fp}, timeout=30)
        return True
    except Exception as e:
        log(f"tg_send_doc error: {e}")
        return False


def tg_backup():
    if not DB_FILE.exists():
        return False
    ts = datetime.now().strftime("%Y-%m-%d_%H-%M")
    tmp = CONFIGS_DIR / f"users_backup_{ts}.db"
    try:
        shutil.copy(str(DB_FILE), str(tmp))
        ok = tg_send_doc(str(tmp), caption=f"📦 پشتیبان دیتابیس MasterPanel\n🕒 {ts}")
        try:
            tmp.unlink()
        except Exception:
            pass
        return ok
    except Exception as e:
        log(f"tg_backup error: {e}")
        return False


# ══════════════════════════════════════════════════════════════════
#  Connectivity tests
# ══════════════════════════════════════════════════════════════════
def test_port(host, port):
    try:
        with socket.create_connection((host, int(port)), timeout=5):
            return {"ok": True}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def test_tls_handshake(host, port=443):
    try:
        ctx = ssl.create_default_context()
        with socket.create_connection((host, int(port)), timeout=5) as sock:
            with ctx.wrap_socket(sock, server_hostname=host) as ss:
                return {"ok": True, "tls_version": ss.version(), "cipher": ss.cipher()[0]}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def test_latency(host, port=443):
    try:
        start = time.time()
        socket.create_connection((host, int(port)), timeout=5).close()
        return {"ok": True, "ms": round((time.time() - start) * 1000)}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def xray_status():
    try:
        r = subprocess.run(["pgrep", "-f", "xray"], capture_output=True, text=True)
        running = bool(r.stdout.strip())
        version = ""
        if running:
            vr = subprocess.run([XRAY_BIN, "version"], capture_output=True, text=True, timeout=3)
            version = vr.stdout.splitlines()[0] if vr.stdout else ""
        return {"running": running, "version": version}
    except Exception:
        return {"running": False, "version": ""}


def tpl_address(tpl):
    if tpl["conn"] == "cdn":
        clean = get_setting("clean_ip", "").strip()
        return clean if clean else DOMAIN
    return server_ip()


# ══════════════════════════════════════════════════════════════════
#  User serialization for the API
# ══════════════════════════════════════════════════════════════════
def user_public(u):
    limit = u["traffic_limit_gb"] or 0
    used = u["used_traffic_bytes"] or 0
    expired = is_expired(u["expire_date"])
    percent = 0
    if limit > 0:
        percent = min(100, round(used / (limit * GB) * 100, 1))
    effective = "active" if (u["status"] == "active" and not expired) else u["status"]
    if expired and u["status"] == "active":
        effective = "expired"
    return {
        "id": u["id"], "username": u["username"], "uuid": u["uuid"],
        "status": u["status"], "effective_status": effective,
        "traffic_limit_gb": limit,
        "limit_human": (f"{limit:g} GB" if limit > 0 else "نامحدود"),
        "used_traffic_bytes": used, "used_human": human_bytes(used),
        "used_gb": round(used / GB, 2),
        "percent": percent,
        "expire_date": u["expire_date"] or "",
        "remaining_days": remaining_days(u["expire_date"]),
        "expired": expired,
        "note": u["note"] or "",
        "created_at": u["created_at"] or "",
    }


def sub_url_for(u):
    base = get_setting("sub_url_base", "").strip().rstrip("/")
    if base:
        return f"{base}/sub/{u['uuid']}"
    try:
        host = request.host
        scheme = request.scheme
        return f"{scheme}://{host}/sub/{u['uuid']}"
    except Exception:
        return f"http://{server_ip()}:{PANEL_PORT}/sub/{u['uuid']}"


def all_users_links_text():
    lines = ["# MasterPanel v3.0 — All Users Export",
             f"# Generated: {now_iso()}", ""]
    for u in get_all_users():
        lines.append(f"# ── {u['username']} ({user_public(u)['effective_status']}) ──")
        for c in build_user_configs(u):
            if c.get("link"):
                lines.append(c["link"])
        lines.append("")
    return "\n".join(lines)


# ══════════════════════════════════════════════════════════════════
#  Auth
# ══════════════════════════════════════════════════════════════════
def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("logged_in"):
            if request.path.startswith("/api/"):
                return jsonify({"ok": False, "error": "unauthorized"}), 401
            return redirect(url_for("login_page"))
        return f(*args, **kwargs)
    return decorated


def serve_html():
    html_path = PANEL_DIR / "templates" / "index.html"
    if html_path.exists():
        return html_path.read_text(encoding="utf-8"), 200, {"Content-Type": "text/html; charset=utf-8"}
    return "<h1>index.html not found</h1>", 404


# ══════════════════════════════════════════════════════════════════
#  Routes — core
# ══════════════════════════════════════════════════════════════════
@app.route("/")
def index():
    if not session.get("logged_in"):
        return redirect(url_for("login_page"))
    return serve_html()


@app.route("/login", methods=["GET", "POST"])
def login_page():
    if request.method == "POST":
        d = request.get_json(silent=True) or {}
        if d.get("username") == PANEL_USER and d.get("password") == PANEL_PASS:
            session["logged_in"] = True
            return jsonify({"ok": True})
        return jsonify({"ok": False, "error": "نام کاربری یا رمز اشتباه است"})
    return serve_html()


@app.route("/api/logout", methods=["POST"])
def logout():
    session.clear()
    return jsonify({"ok": True})


@app.route("/api/status")
@login_required
def api_status():
    users = get_all_users()
    total_used = sum(u["used_traffic_bytes"] or 0 for u in users)
    act = len([u for u in users if u["status"] == "active" and not is_expired(u["expire_date"])])
    ip = server_ip()
    return jsonify({
        "xray": xray_status(),
        "domain": DOMAIN,
        "server_ip": ip,
        "panel_url": f"http://{ip}:{PANEL_PORT}",
        "user_count": len(users),
        "active_count": act,
        "total_used_bytes": total_used,
        "total_used_human": human_bytes(total_used),
        "config_count": len(TEMPLATES) + 2,   # + hy2 + tuic per user
        "ssl_valid": Path(CERT_PATH).exists() if CERT_PATH else False,
        "uptime": get_uptime(),
        "clean_ip": get_setting("clean_ip", ""),
        "telegram_enabled": tg_enabled(),
    })


# ══════════════════════════════════════════════════════════════════
#  Routes — user management (CRUD)
# ══════════════════════════════════════════════════════════════════
@app.route("/api/users", methods=["GET"])
@login_required
def api_users_list():
    return jsonify({"ok": True, "users": [user_public(u) for u in get_all_users()]})


@app.route("/api/users", methods=["POST"])
@login_required
def api_users_create():
    d = request.get_json(silent=True) or {}
    username = (d.get("username") or "").strip()
    if not username:
        return jsonify({"ok": False, "error": "نام کاربری الزامی است"})
    if get_user_by_name(username):
        return jsonify({"ok": False, "error": "این نام کاربری قبلاً ثبت شده است"})
    try:
        expire_date = parse_expire(d)
        uid = create_user(
            username=username,
            traffic_limit_gb=d.get("traffic_limit_gb", 0),
            expire_date=expire_date,
            note=(d.get("note") or "").strip(),
            user_uuid=(d.get("uuid") or "").strip() or None,
            status="active",
        )
        apply_configs_async()
        return jsonify({"ok": True, "user": user_public(get_user(uid))})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})


@app.route("/api/users/<int:uid>", methods=["PUT"])
@login_required
def api_users_update(uid):
    u = get_user(uid)
    if not u:
        return jsonify({"ok": False, "error": "کاربر یافت نشد"})
    d = request.get_json(silent=True) or {}
    fields = {}
    if "username" in d and d["username"].strip():
        nm = d["username"].strip()
        other = get_user_by_name(nm)
        if other and other["id"] != uid:
            return jsonify({"ok": False, "error": "این نام کاربری قبلاً ثبت شده است"})
        fields["username"] = nm
    if "traffic_limit_gb" in d:
        try:
            fields["traffic_limit_gb"] = float(d["traffic_limit_gb"] or 0)
        except Exception:
            pass
    if "note" in d:
        fields["note"] = (d.get("note") or "").strip()
    if d.get("expire_date") is not None or d.get("expire_days") is not None:
        fields["expire_date"] = parse_expire(d)
    if "status" in d and d["status"] in ("active", "disabled", "limited", "expired"):
        fields["status"] = d["status"]
    try:
        update_user(uid, **fields)
        apply_configs_async()
        return jsonify({"ok": True, "user": user_public(get_user(uid))})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})


@app.route("/api/users/<int:uid>", methods=["DELETE"])
@login_required
def api_users_delete(uid):
    if not get_user(uid):
        return jsonify({"ok": False, "error": "کاربر یافت نشد"})
    delete_user(uid)
    apply_configs_async()
    return jsonify({"ok": True})


@app.route("/api/users/<int:uid>/reset", methods=["POST"])
@login_required
def api_users_reset(uid):
    u = get_user(uid)
    if not u:
        return jsonify({"ok": False, "error": "کاربر یافت نشد"})
    new_status = "active" if u["status"] == "limited" else u["status"]
    update_user(uid, used_traffic_bytes=0, status=new_status)
    apply_configs_async()
    return jsonify({"ok": True, "user": user_public(get_user(uid))})


@app.route("/api/users/<int:uid>/toggle", methods=["POST"])
@login_required
def api_users_toggle(uid):
    u = get_user(uid)
    if not u:
        return jsonify({"ok": False, "error": "کاربر یافت نشد"})
    new_status = "disabled" if u["status"] == "active" else "active"
    update_user(uid, status=new_status)
    apply_configs_async()
    return jsonify({"ok": True, "user": user_public(get_user(uid))})


@app.route("/api/users/<int:uid>/links", methods=["GET"])
@login_required
def api_users_links(uid):
    u = get_user(uid)
    if not u:
        return jsonify({"ok": False, "error": "کاربر یافت نشد"})
    configs = build_user_configs(u)
    raw = "\n".join(c["link"] for c in configs if c.get("link"))
    return jsonify({
        "ok": True,
        "configs": configs,
        "raw": raw,
        "sub_url": sub_url_for(u),
    })


# ══════════════════════════════════════════════════════════════════
#  Routes — subscription (PUBLIC, no auth)
# ══════════════════════════════════════════════════════════════════
@app.route("/sub/<token>")
def subscription(token):
    u = get_user_by_uuid(token)
    if not u:
        return Response("not found", status=404)

    links = [build_info_node(u)]
    for c in build_user_configs(u):
        if c.get("link"):
            links.append(c["link"])
    body = base64.b64encode("\n".join(links).encode()).decode()

    limit = u["traffic_limit_gb"] or 0
    total = int(limit * GB) if limit > 0 else 0
    headers = {
        "Content-Type": "text/plain; charset=utf-8",
        "Profile-Update-Interval": "12",
        "Subscription-Userinfo":
            f"upload=0; download={u['used_traffic_bytes']}; total={total}; "
            f"expire={expire_unix(u['expire_date'])}",
        "Profile-Title": "base64:" + base64.b64encode(
            f"MasterPanel - {u['username']}".encode()).decode(),
    }
    return Response(body, headers=headers)


# ══════════════════════════════════════════════════════════════════
#  Routes — settings
# ══════════════════════════════════════════════════════════════════
EDITABLE_SETTINGS = [
    "clean_ip", "telegram_bot_token", "telegram_admin_chat",
    "github_repo", "github_branch", "monitor_interval", "backup_hour",
    "sub_url_base",
]


@app.route("/api/settings", methods=["GET"])
@login_required
def api_settings_get():
    out = {}
    for k in EDITABLE_SETTINGS:
        out[k] = get_setting(k, "")
    out["telegram_enabled"] = tg_enabled()
    return jsonify({"ok": True, "settings": out})


@app.route("/api/settings", methods=["POST"])
@login_required
def api_settings_set():
    d = request.get_json(silent=True) or {}
    changed_clean = False
    for k in EDITABLE_SETTINGS:
        if k in d:
            if k == "clean_ip" and str(d[k]).strip() != get_setting("clean_ip", ""):
                changed_clean = True
            set_setting(k, str(d[k]).strip())
    # Clean-IP changes affect generated configs only (no server rewrite needed),
    # but rebuild anyway so any host/SNI changes propagate.
    if changed_clean:
        apply_configs_async()
    return jsonify({"ok": True, "settings": {k: get_setting(k, "") for k in EDITABLE_SETTINGS}})


# ══════════════════════════════════════════════════════════════════
#  Routes — Xray / apply / test
# ══════════════════════════════════════════════════════════════════
@app.route("/api/apply", methods=["POST"])
@login_required
def api_apply():
    apply_configs_async()
    return jsonify({"ok": True, "message": "همگام‌سازی پیکربندی‌ها آغاز شد"})


@app.route("/api/xray/restart", methods=["POST"])
@login_required
def api_xray_restart():
    try:
        restart_xray()
        time.sleep(1)
        return jsonify({"ok": True, "status": xray_status()})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})


@app.route("/api/xray/logs")
@login_required
def api_xray_logs():
    f = LOGS_DIR / "xray-error.log"
    lines = f.read_text().splitlines()[-50:] if f.exists() else []
    return jsonify({"ok": True, "lines": lines})


@app.route("/api/test", methods=["POST"])
@login_required
def api_test():
    d = request.get_json(silent=True) or {}
    t = d.get("type")
    host = d.get("host", DOMAIN)
    port = d.get("port", 443)
    if t == "tls":
        return jsonify(test_tls_handshake(host, port))
    if t == "port":
        return jsonify(test_port(host, port))
    if t == "latency":
        return jsonify(test_latency(host, port))
    if t == "all":
        results = {}
        for tpl in TEMPLATES:
            addr = tpl_address(tpl)
            label = tpl["label"]
            if tpl["proto"] in ("ss",) or tpl["net"] in ("tcp", "ws", "xhttp", "grpc"):
                lat = test_latency(addr, tpl["port"])
                prt = test_port(addr, tpl["port"])
                results[f"{label}:{tpl['port']}"] = {
                    "latency": lat.get("ms") if lat["ok"] else None,
                    "port_open": prt["ok"],
                    "protocol": tpl["proto"], "network": tpl["net"],
                    "tls": tpl["sec"], "conn": tpl["conn"],
                }
        # UDP daemons can't be tested with TCP connect
        results["HYSTERIA2:443"] = {"latency": None, "port_open": None,
                                    "protocol": "hysteria2", "network": "udp",
                                    "tls": "tls", "conn": "direct", "udp": True}
        results["TUIC:2053"] = {"latency": None, "port_open": None,
                                "protocol": "tuic", "network": "udp",
                                "tls": "tls", "conn": "direct", "udp": True}
        return jsonify({"ok": True, "results": results})
    return jsonify({"ok": False, "error": "Unknown test type"})


# ══════════════════════════════════════════════════════════════════
#  Routes — Telegram
# ══════════════════════════════════════════════════════════════════
@app.route("/api/telegram/test", methods=["POST"])
@login_required
def api_tg_test():
    if not tg_enabled():
        return jsonify({"ok": False, "error": "توکن یا چت‌آیدی تنظیم نشده است"})
    ok = tg_send("✅ اتصال ربات تلگرام MasterPanel با موفقیت برقرار شد.")
    return jsonify({"ok": ok})


@app.route("/api/telegram/backup", methods=["POST"])
@login_required
def api_tg_backup():
    if not tg_enabled():
        return jsonify({"ok": False, "error": "توکن یا چت‌آیدی تنظیم نشده است"})
    ok = tg_backup()
    return jsonify({"ok": ok, "message": "پشتیبان ارسال شد" if ok else "ارسال ناموفق بود"})


@app.route("/api/backup")
@login_required
def api_backup():
    if not DB_FILE.exists():
        return jsonify({"ok": False, "error": "دیتابیس یافت نشد"})
    ts = datetime.now().strftime("%Y-%m-%d_%H-%M")
    return Response(
        DB_FILE.read_bytes(),
        mimetype="application/octet-stream",
        headers={"Content-Disposition": f"attachment; filename=users_{ts}.db"})


# ══════════════════════════════════════════════════════════════════
#  Routes — GitHub auto-update
# ══════════════════════════════════════════════════════════════════
@app.route("/api/update", methods=["POST"])
@login_required
def api_update():
    repo = get_setting("github_repo", "").strip()
    branch = get_setting("github_branch", "main").strip() or "main"
    if not repo:
        return jsonify({"ok": False, "error": "ریپازیتوری گیت‌هاب تنظیم نشده است"})

    base = f"https://raw.githubusercontent.com/{repo}/{branch}"
    targets = [
        (f"{base}/masterpanel.py", PANEL_DIR / "masterpanel.py"),
        (f"{base}/index.html",     PANEL_DIR / "templates" / "index.html"),
    ]
    updated = []
    try:
        for url, dest in targets:
            req = urllib.request.Request(url, headers={"User-Agent": "MasterPanel-Updater"})
            with urllib.request.urlopen(req, timeout=20) as r:
                data = r.read()
            if not data:
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            if dest.exists():
                shutil.copy(str(dest), str(dest) + ".bak")
            dest.write_bytes(data)
            updated.append(dest.name)
    except Exception as e:
        return jsonify({"ok": False, "error": f"خطا در دریافت فایل‌ها: {e}"})

    if not updated:
        return jsonify({"ok": False, "error": "هیچ فایلی دریافت نشد"})

    # Restart the panel shortly after responding (users.db is untouched)
    def _restart():
        time.sleep(1.2)
        try:
            subprocess.run(["systemctl", "restart", "masterpanel"], capture_output=True)
        except Exception:
            pass
    threading.Thread(target=_restart, daemon=True).start()

    return jsonify({
        "ok": True,
        "updated": updated,
        "message": "بروزرسانی انجام شد. پنل در حال راه‌اندازی مجدد است… "
                   "(دیتابیس کاربران حفظ شد). چند لحظه صبر کنید و صفحه را تازه‌سازی نمایید.",
    })


# ══════════════════════════════════════════════════════════════════
#  Legacy-compat routes (so an old v2 index.html keeps working)
# ══════════════════════════════════════════════════════════════════
@app.route("/api/configs")
@login_required
def api_configs():
    users = get_all_users()
    return jsonify(build_user_configs(users[0]) if users else [])


@app.route("/api/generate", methods=["POST"])
@login_required
def api_generate():
    apply_configs_async()
    users = get_all_users()
    cfgs = build_user_configs(users[0]) if users else []
    return jsonify({"ok": True, "count": len(cfgs), "configs": cfgs})


@app.route("/api/export/links")
@login_required
def api_export_links():
    return Response(all_users_links_text(), mimetype="text/plain",
                    headers={"Content-Disposition": "attachment; filename=all_links.txt"})


@app.route("/api/export/subscription")
@login_required
def api_export_subscription():
    raw = "\n".join(l for l in all_users_links_text().splitlines()
                    if l and not l.startswith("#"))
    return Response(raw, mimetype="text/plain",
                    headers={"Content-Disposition": "attachment; filename=subscription.txt"})


@app.route("/api/export/subscription_b64")
@login_required
def api_export_subscription_b64():
    raw = "\n".join(l for l in all_users_links_text().splitlines()
                    if l and not l.startswith("#"))
    return Response(base64.b64encode(raw.encode()).decode(), mimetype="text/plain",
                    headers={"Content-Disposition": "attachment; filename=subscription_b64.txt"})


@app.route("/api/export/summary")
@login_required
def api_export_summary():
    users = get_all_users()
    return jsonify({
        "ok": True,
        "total_users": len(users),
        "active_users": len([u for u in users if u["status"] == "active" and not is_expired(u["expire_date"])]),
        "configs_per_user": len(TEMPLATES) + 2,
    })


# ══════════════════════════════════════════════════════════════════
#  Background scheduler
# ══════════════════════════════════════════════════════════════════
def _initial_sync():
    time.sleep(2)
    with _apply_lock:
        try:
            apply_configs()
        except Exception as e:
            log(f"initial sync error: {e}")


def start_background():
    # Initial sync from DB on boot
    threading.Thread(target=_initial_sync, daemon=True).start()

    interval = max(15, int(get_setting("monitor_interval", "60") or 60))
    backup_hour = int(get_setting("backup_hour", "6") or 6)

    try:
        from apscheduler.schedulers.background import BackgroundScheduler
        sched = BackgroundScheduler(daemon=True)
        sched.add_job(run_monitor, "interval", seconds=interval, id="monitor",
                      max_instances=1, coalesce=True)
        sched.add_job(tg_backup, "cron", hour=backup_hour, minute=0, id="backup")
        sched.start()
        log(f"APScheduler started (monitor every {interval}s, backup at {backup_hour}:00).")
    except Exception as e:
        log(f"APScheduler unavailable ({e}); using thread fallback.")

        def _monitor_loop():
            while True:
                time.sleep(interval)
                try:
                    run_monitor()
                except Exception as ex:
                    log(f"monitor loop error: {ex}")

        def _backup_loop():
            last_day = None
            while True:
                time.sleep(60)
                now = datetime.now()
                if now.hour == backup_hour and now.date() != last_day:
                    last_day = now.date()
                    try:
                        tg_backup()
                    except Exception as ex:
                        log(f"backup loop error: {ex}")

        threading.Thread(target=_monitor_loop, daemon=True).start()
        threading.Thread(target=_backup_loop, daemon=True).start()


# ══════════════════════════════════════════════════════════════════
#  Bootstrap (runs on import too, so any WSGI launcher works)
# ══════════════════════════════════════════════════════════════════
init_db()
_fs = get_setting("flask_secret")
if not _fs:
    _fs = secrets.token_hex(32)
    set_setting("flask_secret", _fs)
app.secret_key = _fs

if __name__ == "__main__":
    import logging
    logging.getLogger("werkzeug").setLevel(logging.WARNING)
    log(f"[MasterPanel v3.0] Starting on port {PANEL_PORT}")
    start_background()
    app.run(host="0.0.0.0", port=PANEL_PORT, debug=False, threaded=True)
