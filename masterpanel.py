#!/usr/bin/env python3
"""
MasterPanel v3.0 - پنل مدیریت حرفه‌ای Xray
Enterprise Edition با SQLite، مدیریت کاربران و رصد ترافیک
تمام پروتکل‌ها تست و فیکس شده‌اند
"""

import os, json, uuid, subprocess, socket, ssl, time, base64, urllib.parse
import secrets, string, sqlite3, threading, shutil, logging
from datetime import datetime, timedelta
from pathlib import Path
from functools import wraps
from flask import Flask, request, jsonify, session, redirect, url_for, Response

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("masterpanel")

app = Flask(__name__)
app.secret_key = secrets.token_hex(32)

# ── بارگذاری تنظیمات ──────────────────────────────────────────
PANEL_DIR    = Path("/opt/masterpanel")
CONF_FILE    = PANEL_DIR / "panel.conf"

def load_conf():
    conf = {}
    if CONF_FILE.exists():
        for line in CONF_FILE.read_text().splitlines():
            line = line.strip()
            if "=" in line and not line.startswith("#"):
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
CONFIGS_DIR  = PANEL_DIR / "configs"
DB_PATH      = PANEL_DIR / "masterpanel.db"

for d in [CONFIGS_DIR, XRAY_CFG_DIR, PANEL_DIR / "logs", PANEL_DIR / "templates"]:
    d.mkdir(parents=True, exist_ok=True)

# ── پورت‌های اصلی — هر پروتکل پورت منحصربه‌فرد ───────────────
CORE_PORTS = {
    "vless_reality":   443,
    "vless_ws":       8443,
    "vless_grpc":     2053,
    "vless_hu":       2087,
    "vmess_ws":       2083,
    "vmess_grpc":     2096,
    "trojan_ws":      2052,
    "trojan_tcp":     2082,
    "ss_chacha":      8388,
    "ss_aes":         8389,
    "tuic":          19443,
    "hy2":           19444,
}

_reality_cache = {}
_db_lock       = threading.Lock()

# ══════════════════════════════════════════════════════════════
#  پایگاه داده
# ══════════════════════════════════════════════════════════════

def get_db():
    conn = sqlite3.connect(str(DB_PATH), check_same_thread=False, timeout=15)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA busy_timeout=8000")
    return conn

def init_db():
    with _db_lock, get_db() as db:
        db.executescript("""
            CREATE TABLE IF NOT EXISTS users (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                username         VARCHAR(64) UNIQUE NOT NULL,
                uuid             VARCHAR(36) NOT NULL,
                password         VARCHAR(64) NOT NULL,
                total_quota_gb   REAL    DEFAULT 10.0,
                used_quota_bytes INTEGER DEFAULT 0,
                expire_date      TEXT,
                status           VARCHAR(20) DEFAULT 'active',
                note             TEXT DEFAULT '',
                created_at       TEXT DEFAULT (datetime('now'))
            );
            CREATE TABLE IF NOT EXISTS reality_keys (
                id         INTEGER PRIMARY KEY,
                priv_key   TEXT NOT NULL,
                pub_key    TEXT NOT NULL,
                short_id   TEXT NOT NULL,
                created_at TEXT DEFAULT (datetime('now'))
            );
            CREATE TABLE IF NOT EXISTS system_settings (
                key   TEXT PRIMARY KEY,
                value TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_users_status   ON users(status);
            CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
        """)
        db.execute("""
            INSERT OR IGNORE INTO system_settings (key,value) VALUES
            ('last_traffic_sync','0'),('xray_api_port','10085')
        """)
        db.commit()

# ══════════════════════════════════════════════════════════════
#  توابع کمکی
# ══════════════════════════════════════════════════════════════

def new_uuid():
    return str(uuid.uuid4())

def new_password(length=24):
    """پسورد ایمن بدون کاراکترهای خاص که پروتکل‌ها رو می‌شکنن"""
    # فقط حروف و اعداد — ایمن برای همه پروتکل‌ها (Trojan, SS, HY2, TUIC)
    chars = string.ascii_letters + string.digits
    return ''.join(secrets.choice(chars) for _ in range(length))

def new_ss_password():
    """پسورد ایمن برای Shadowsocks — باید Base64-safe باشه"""
    return secrets.token_urlsafe(18)

def get_server_ip():
    """دریافت IPv4 سرور"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(3)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and not ip.startswith("127.") and ":" not in ip:
            return ip
    except:
        pass
    import urllib.request
    for api_url in ["https://api4.ipify.org", "https://ipv4.icanhazip.com"]:
        try:
            req = urllib.request.Request(api_url, headers={"User-Agent": "curl/7.0"})
            with urllib.request.urlopen(req, timeout=5) as r:
                ip = r.read().decode().strip()
                if ip and ":" not in ip and not ip.startswith("127."):
                    return ip
        except:
            continue
    return "0.0.0.0"

def get_or_create_reality_keys():
    """Reality X25519 keys — فقط یک بار ساخته می‌شوند و در DB ذخیره می‌شوند"""
    global _reality_cache
    if _reality_cache:
        return _reality_cache
    with get_db() as db:
        row = db.execute("SELECT * FROM reality_keys ORDER BY id LIMIT 1").fetchone()
        if row:
            _reality_cache = {"priv_key": row["priv_key"],
                               "pub_key":  row["pub_key"],
                               "short_id": row["short_id"]}
            return _reality_cache
    # ساخت جدید
    priv, pub = "", ""
    try:
        r = subprocess.run([XRAY_BIN, "x25519"], capture_output=True, text=True, timeout=5)
        lines = r.stdout.strip().splitlines()
        priv = lines[0].split(": ")[-1].strip() if lines else ""
        pub  = lines[1].split(": ")[-1].strip() if len(lines) > 1 else ""
    except Exception as e:
        logger.error(f"خطا در تولید Reality keys: {e}")
    short_id = secrets.token_hex(4)
    with _db_lock, get_db() as db:
        db.execute("INSERT INTO reality_keys (priv_key,pub_key,short_id) VALUES(?,?,?)",
                   (priv, pub, short_id))
        db.commit()
    _reality_cache = {"priv_key": priv, "pub_key": pub, "short_id": short_id}
    return _reality_cache

def get_uptime():
    try:
        with open("/proc/uptime") as f:
            secs = float(f.read().split()[0])
        return f"{int(secs//3600)}h {int((secs%3600)//60)}m"
    except:
        return "N/A"

def bytes_to_human(b):
    b = max(0, int(b or 0))
    if b < 1024:        return f"{b} B"
    if b < 1024**2:     return f"{b/1024:.1f} KB"
    if b < 1024**3:     return f"{b/1024**2:.1f} MB"
    return f"{b/1024**3:.2f} GB"

def gb_to_bytes(gb):
    return int(float(gb) * 1024**3)

def get_system_stats():
    stats = {"cpu": 0, "ram_used": 0, "ram_total": 0, "disk_used": 0, "disk_total": 0}
    try:
        with open("/proc/loadavg") as f:
            load = float(f.read().split()[0])
        with open("/proc/cpuinfo") as f:
            cpus = max(f.read().count("processor\t:"), 1)
        stats["cpu"] = min(int(load / cpus * 100), 100)
        mem = {}
        with open("/proc/meminfo") as f:
            for line in f:
                p = line.split()
                if len(p) >= 2:
                    mem[p[0].rstrip(":")] = int(p[1])
        total = mem.get("MemTotal", 0)
        avail = mem.get("MemAvailable", 0)
        stats["ram_total"] = total * 1024
        stats["ram_used"]  = (total - avail) * 1024
        disk = os.statvfs("/")
        stats["disk_total"] = disk.f_blocks * disk.f_frsize
        stats["disk_used"]  = (disk.f_blocks - disk.f_bavail) * disk.f_frsize
    except Exception as e:
        logger.warning(f"آمار سیستم: {e}")
    return stats

def xray_is_running():
    try:
        r = subprocess.run(["pgrep", "-x", "xray"], capture_output=True, text=True)
        return bool(r.stdout.strip())
    except:
        return False

def xray_status():
    running = xray_is_running()
    version = ""
    if running:
        try:
            vr = subprocess.run([XRAY_BIN, "version"], capture_output=True, text=True, timeout=3)
            version = vr.stdout.splitlines()[0] if vr.stdout else ""
        except:
            pass
    return {"running": running, "version": version}

def _q(s):
    return urllib.parse.quote(str(s), safe="")

# ══════════════════════════════════════════════════════════════
#  ساخت لینک‌ها — تمام پروتکل‌ها
# ══════════════════════════════════════════════════════════════

def vless_link(user, cfg):
    uid   = user["uuid"]
    addr  = cfg["address"]
    port  = cfg["port"]
    net   = cfg.get("network", "tcp")
    tls   = cfg.get("tls", "tls")
    sni   = cfg.get("sni", DOMAIN)
    fp    = cfg.get("fp", "chrome")
    name  = _q(f"{user['username']}-{cfg['name']}")
    flow  = cfg.get("flow", "")
    pbk   = cfg.get("pub_key", "")
    sid   = cfg.get("short_id", "")
    path  = _q(cfg.get("path", "/"))

    params = f"type={net}&security={tls}"
    if tls == "tls":
        params += f"&sni={sni}&fp={fp}&alpn=h2%2Chttp%2F1.1"
    elif tls == "reality":
        params += f"&sni={sni}&fp={fp}&pbk={pbk}&sid={sid}&spx=%2F"
    else:
        params += f"&sni={sni}"

    if net == "ws":
        params += f"&path={path}&host={sni}"
    elif net == "grpc":
        svc = _q(cfg.get("service_name", "grpc"))
        params += f"&serviceName={svc}&mode=gun"
    elif net == "httpupgrade":
        params += f"&path={path}&host={sni}"

    if flow:
        params += f"&flow={flow}"

    return f"vless://{uid}@{addr}:{port}?{params}#{name}"

def vmess_link(user, cfg):
    net = cfg.get("network", "ws")
    path_or_svc = cfg.get("service_name", "grpc") if net == "grpc" else cfg.get("path", "/")
    data = {
        "v":    "2",
        "ps":   f"{user['username']}-{cfg['name']}",
        "add":  cfg["address"],
        "port": str(cfg["port"]),
        "id":   user["uuid"],
        "aid":  "0",
        "scy":  "auto",
        "net":  net,
        "type": "none",
        "host": cfg.get("sni", DOMAIN),
        "path": path_or_svc,
        "tls":  "tls" if cfg.get("tls") == "tls" else "",
        "sni":  cfg.get("sni", DOMAIN),
        "fp":   cfg.get("fp", "chrome"),
        "alpn": "h2,http/1.1",
    }
    encoded = base64.b64encode(json.dumps(data, separators=(',', ':')).encode()).decode()
    return f"vmess://{encoded}"

def trojan_link(user, cfg):
    # پسورد Trojan باید URL-safe باشه
    pw   = urllib.parse.quote(user["password"], safe="")
    net  = cfg.get("network", "tcp")
    sni  = cfg.get("sni", DOMAIN)
    path = _q(cfg.get("path", "/"))
    name = _q(f"{user['username']}-{cfg['name']}")
    fp   = cfg.get("fp", "chrome")

    params = f"security=tls&sni={sni}&fp={fp}&alpn=h2%2Chttp%2F1.1&type={net}"
    if net == "ws":
        params += f"&path={path}&host={sni}"
    elif net == "grpc":
        svc = _q(cfg.get("service_name", "grpc"))
        params += f"&serviceName={svc}&mode=gun"
    elif net == "httpupgrade":
        params += f"&path={path}&host={sni}"

    return f"trojan://{pw}@{cfg['address']}:{cfg['port']}?{params}#{name}"

def ss_link(user, cfg):
    """Shadowsocks link — هر کاربر پسورد مستقل دارد"""
    method   = cfg.get("method", "chacha20-ietf-poly1305")
    # پسورد SS از فیلد ss_password است نه password اصلی
    password = user.get("ss_password") or user["password"]
    name     = _q(f"{user['username']}-{cfg['name']}")
    userinfo = base64.b64encode(f"{method}:{password}".encode()).decode()
    return f"ss://{userinfo}@{cfg['address']}:{cfg['port']}#{name}"

def tuic_link(user, cfg):
    sni  = cfg.get("sni", DOMAIN)
    name = _q(f"{user['username']}-{cfg['name']}")
    # TUIC: uuid@host:port?password=pw&...
    pw   = urllib.parse.quote(user["password"], safe="")
    return (f"tuic://{user['uuid']}:{pw}@{cfg['address']}:{cfg['port']}"
            f"?sni={sni}&congestion_control=bbr&udp_relay_mode=native"
            f"&alpn=h3&allow_insecure=0#{name}")

def hy2_link(user, cfg):
    sni  = cfg.get("sni", DOMAIN)
    name = _q(f"{user['username']}-{cfg['name']}")
    pw   = urllib.parse.quote(user["password"], safe="")
    return (f"hysteria2://{pw}@{cfg['address']}:{cfg['port']}"
            f"?sni={sni}&fastopen=1#{name}")

# ══════════════════════════════════════════════════════════════
#  کانفیگ‌های اصلی سیستم
# ══════════════════════════════════════════════════════════════

def get_core_configs():
    ip   = get_server_ip()
    keys = get_or_create_reality_keys()
    return [
        # ── VLESS ─────────────────────────────────────────────
        {
            "id": "vless_reality", "name": "VLESS-REALITY",
            "protocol": "vless", "network": "tcp", "tls": "reality",
            "port": CORE_PORTS["vless_reality"],
            "sni": "www.google.com", "fp": "chrome",
            "flow": "xtls-rprx-vision",
            "address": ip,
            "reality_dest": "www.google.com:443",
            "priv_key": keys["priv_key"],
            "pub_key":  keys["pub_key"],
            "short_id": keys["short_id"],
        },
        {
            "id": "vless_ws", "name": "VLESS-WS-TLS",
            "protocol": "vless", "network": "ws", "tls": "tls",
            "port": CORE_PORTS["vless_ws"], "path": "/vless-ws",
            "sni": DOMAIN, "fp": "chrome", "address": DOMAIN,
        },
        {
            "id": "vless_grpc", "name": "VLESS-gRPC-TLS",
            "protocol": "vless", "network": "grpc", "tls": "tls",
            "port": CORE_PORTS["vless_grpc"], "service_name": "vless-grpc",
            "sni": DOMAIN, "fp": "chrome", "address": DOMAIN,
        },
        {
            "id": "vless_hu", "name": "VLESS-HTTPUpgrade-TLS",
            "protocol": "vless", "network": "httpupgrade", "tls": "tls",
            "port": CORE_PORTS["vless_hu"], "path": "/vless-hu",
            "sni": DOMAIN, "fp": "edge", "address": DOMAIN,
        },
        # ── VMess ─────────────────────────────────────────────
        {
            "id": "vmess_ws", "name": "VMess-WS-TLS",
            "protocol": "vmess", "network": "ws", "tls": "tls",
            "port": CORE_PORTS["vmess_ws"], "path": "/vmess-ws",
            "sni": DOMAIN, "fp": "chrome", "address": DOMAIN,
        },
        {
            "id": "vmess_grpc", "name": "VMess-gRPC-TLS",
            "protocol": "vmess", "network": "grpc", "tls": "tls",
            "port": CORE_PORTS["vmess_grpc"], "service_name": "vmess-grpc",
            "sni": DOMAIN, "fp": "firefox", "address": DOMAIN,
        },
        # ── Trojan ────────────────────────────────────────────
        {
            "id": "trojan_ws", "name": "Trojan-WS-TLS",
            "protocol": "trojan", "network": "ws", "tls": "tls",
            "port": CORE_PORTS["trojan_ws"], "path": "/trojan-ws",
            "sni": DOMAIN, "fp": "chrome", "address": DOMAIN,
        },
        {
            "id": "trojan_tcp", "name": "Trojan-TCP-TLS",
            "protocol": "trojan", "network": "tcp", "tls": "tls",
            "port": CORE_PORTS["trojan_tcp"],
            "sni": DOMAIN, "fp": "safari", "address": ip,
        },
        # ── Shadowsocks ───────────────────────────────────────
        # SS در Xray Multi-User: هر کاربر کلاینت جداگانه با پسورد خودش
        {
            "id": "ss_chacha", "name": "SS-chacha20",
            "protocol": "shadowsocks", "network": "tcp", "tls": "none",
            "port": CORE_PORTS["ss_chacha"],
            "method": "chacha20-ietf-poly1305", "address": ip,
        },
        {
            "id": "ss_aes", "name": "SS-aes256",
            "protocol": "shadowsocks", "network": "tcp", "tls": "none",
            "port": CORE_PORTS["ss_aes"],
            "method": "aes-256-gcm", "address": ip,
        },
        # ── TUIC / Hysteria2 (سرویس مستقل) ───────────────────
        {
            "id": "tuic", "name": "TUIC-v5",
            "protocol": "tuic", "network": "udp", "tls": "tls",
            "port": CORE_PORTS["tuic"], "sni": DOMAIN, "address": ip,
        },
        {
            "id": "hy2", "name": "Hysteria2",
            "protocol": "hysteria2", "network": "udp", "tls": "tls",
            "port": CORE_PORTS["hy2"], "sni": DOMAIN, "address": ip,
        },
    ]

def generate_user_links(user):
    """تولید تمام لینک‌های یک کاربر"""
    u = dict(user)
    links = []
    for cfg in get_core_configs():
        proto = cfg["protocol"]
        try:
            if proto == "vless":
                links.append(vless_link(u, cfg))
            elif proto == "vmess":
                links.append(vmess_link(u, cfg))
            elif proto == "trojan":
                links.append(trojan_link(u, cfg))
            elif proto == "shadowsocks":
                links.append(ss_link(u, cfg))
            elif proto == "tuic":
                links.append(tuic_link(u, cfg))
            elif proto == "hysteria2":
                links.append(hy2_link(u, cfg))
        except Exception as e:
            logger.warning(f"خطا در ساخت لینک {proto}/{cfg['id']}: {e}")
    return links

# ══════════════════════════════════════════════════════════════
#  ساخت کانفیگ Xray — فیکس‌شده کامل
# ══════════════════════════════════════════════════════════════

def _build_stream(cfg):
    """streamSettings صحیح برای هر پروتکل"""
    net = cfg.get("network", "tcp")
    tls = cfg.get("tls", "none")
    stream = {"network": net}

    if tls == "tls":
        stream["security"] = "tls"
        stream["tlsSettings"] = {
            "certificates": [{"certificateFile": CERT_PATH, "keyFile": KEY_PATH}],
            "alpn": ["h2", "http/1.1"],
            "minVersion": "1.2",
        }
    elif tls == "reality":
        # Reality: بدون sniffing، بدون TLS معمولی
        stream["security"] = "reality"
        stream["realitySettings"] = {
            "show":        False,
            "dest":        cfg.get("reality_dest", "www.google.com:443"),
            "xver":        0,
            "serverNames": [cfg.get("sni", "www.google.com")],
            "privateKey":  cfg.get("priv_key", ""),
            "shortIds":    [cfg.get("short_id", "")],
        }
    else:
        stream["security"] = "none"

    if net == "ws":
        stream["wsSettings"] = {
            "path": cfg.get("path", "/"),
            "headers": {"Host": cfg.get("sni", DOMAIN)},
        }
    elif net == "grpc":
        stream["grpcSettings"] = {
            "serviceName": cfg.get("service_name", "grpc"),
            "multiMode":   False,
        }
    elif net == "httpupgrade":
        stream["httpupgradeSettings"] = {
            "path": cfg.get("path", "/"),
            "host": cfg.get("sni", DOMAIN),
        }

    return stream

def build_xray_config():
    """ساخت کانفیگ کامل Xray — تمام پروتکل‌ها فیکس شده"""
    with get_db() as db:
        active_users = [dict(r) for r in db.execute(
            "SELECT * FROM users WHERE status='active'"
        ).fetchall()]

    inbounds   = []
    seen_ports = set()

    for cfg in get_core_configs():
        proto = cfg["protocol"]
        port  = cfg["port"]

        # TUIC و Hysteria2 سرویس‌های مستقل هستند، در Xray نیستند
        if proto in ("tuic", "hysteria2"):
            continue

        if port in seen_ports:
            logger.warning(f"پورت تکراری {port} برای {cfg['id']} — نادیده")
            continue
        seen_ports.add(port)

        net   = cfg.get("network", "tcp")
        is_reality = cfg.get("tls") == "reality"

        inbound = {
            "tag":      f"in-{cfg['id']}",
            "port":     port,
            "listen":   "0.0.0.0",
            "protocol": proto,
        }

        # Reality با sniffing ناسازگار است — فقط برای غیر-reality فعال می‌شود
        if not is_reality:
            inbound["sniffing"] = {
                "enabled":      True,
                "destOverride": ["http", "tls"],
                "routeOnly":    False,
            }

        if proto == "vless":
            clients = []
            for u in active_users:
                c = {"id": u["uuid"], "level": 0, "email": u["username"]}
                if cfg.get("flow") and is_reality:
                    # flow فقط برای Reality معتبر است
                    c["flow"] = cfg["flow"]
                clients.append(c)
            inbound["settings"]       = {"clients": clients, "decryption": "none"}
            inbound["streamSettings"] = _build_stream(cfg)

        elif proto == "vmess":
            clients = [{"id": u["uuid"], "alterId": 0, "level": 0, "email": u["username"]}
                       for u in active_users]
            inbound["settings"]       = {"clients": clients}
            inbound["streamSettings"] = _build_stream(cfg)

        elif proto == "trojan":
            clients = [{"password": u["password"], "level": 0, "email": u["username"]}
                       for u in active_users]
            inbound["settings"]       = {"clients": clients}
            inbound["streamSettings"] = _build_stream(cfg)

        elif proto == "shadowsocks":
            # فرمت صحیح SS Multi-User در Xray:
            # یک server_key اجباری + هر کاربر client جداگانه با پسورد خودش
            # پسورد کاربر باید alphanumeric باشد
            clients = []
            for u in active_users:
                # ss_password ذخیره‌شده یا همان password
                pw = u.get("ss_password") or u["password"]
                clients.append({
                    "password": pw,
                    "email":    u["username"],
                    "level":    0,
                })
            # server_key ثابت می‌ماند (از UUID مشتق می‌شود)
            server_key = base64.b64encode(
                bytes.fromhex(cfg["id"].replace("_","")[:32].ljust(32,"0"))
            ).decode()[:32]

            inbound["settings"] = {
                "method":   cfg.get("method", "chacha20-ietf-poly1305"),
                "password": server_key,
                "clients":  clients,
                "network":  "tcp,udp",
            }
            inbound["streamSettings"] = {"network": "tcp", "security": "none"}

        inbounds.append(inbound)

    # اگر هیچ کاربری فعال نباشد، Xray به یک placeholder نیاز دارد
    if not inbounds:
        inbounds.append({
            "tag":      "in-placeholder",
            "port":     10800,
            "listen":   "127.0.0.1",
            "protocol": "socks",
            "settings": {"auth": "noauth"},
        })

    xray_conf = {
        "log": {
            "loglevel": "warning",
            "access":   str(PANEL_DIR / "logs/xray-access.log"),
            "error":    str(PANEL_DIR / "logs/xray-error.log"),
        },
        "stats":  {},
        "api":    {"tag": "api", "services": ["StatsService"]},
        "policy": {
            "levels": {"0": {"statsUserUplink": True, "statsUserDownlink": True}},
            "system": {"statsInboundUplink": True, "statsInboundDownlink": True},
        },
        "inbounds": [
            {
                "tag":      "api-in",
                "listen":   "127.0.0.1",
                "port":     10085,
                "protocol": "dokodemo-door",
                "settings": {"address": "127.0.0.1"},
            }
        ] + inbounds,
        "outbounds": [
            {"tag": "direct",  "protocol": "freedom",  "settings": {}},
            {"tag": "blocked", "protocol": "blackhole", "settings": {}},
        ],
        "routing": {
            "domainStrategy": "IPIfNonMatch",
            "rules": [
                {"type": "field", "inboundTag": ["api-in"],          "outboundTag": "api"},
                {"type": "field", "ip":     ["geoip:private"],        "outboundTag": "direct"},
                {"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "blocked"},
            ],
        },
    }

    cfg_path = XRAY_CFG_DIR / "config.json"
    cfg_path.write_text(json.dumps(xray_conf, indent=2, ensure_ascii=False))
    logger.info(f"کانفیگ Xray → {len(inbounds)} اینباند")
    return cfg_path

def validate_xray_config():
    """تست کانفیگ Xray قبل از اعمال"""
    try:
        r = subprocess.run(
            [XRAY_BIN, "run", "-test", "-c", str(XRAY_CFG_DIR / "config.json")],
            capture_output=True, text=True, timeout=10
        )
        if r.returncode != 0:
            logger.error(f"Xray config test failed:\n{r.stderr}")
            return False, r.stderr
        return True, ""
    except Exception as e:
        return False, str(e)

def reload_xray():
    """ری‌استارت Xray با تست کانفیگ قبل از اعمال"""
    ok, err = validate_xray_config()
    if not ok:
        logger.error(f"کانفیگ معتبر نیست، ری‌استارت لغو شد: {err}")
        return False

    try:
        r = subprocess.run(["systemctl", "restart", "xray"],
                           timeout=15, capture_output=True)
        if r.returncode == 0:
            time.sleep(1)
            return True
    except:
        pass
    # fallback
    try:
        subprocess.run(["pkill", "-f", "xray run"], capture_output=True)
        time.sleep(1)
        subprocess.Popen(
            [XRAY_BIN, "run", "-c", str(XRAY_CFG_DIR / "config.json")],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return True
    except:
        return False

# ── کانفیگ TUIC v5 — فرمت صحیح ───────────────────────────────
def write_tuic_config(active_users):
    if not Path(TUIC_BIN).exists():
        return
    if not active_users:
        # اگر کاربری نیست، سرویس را متوقف کن
        subprocess.run(["systemctl", "stop", "tuic-server"], capture_output=True)
        return

    # فرمت صحیح: {"uuid": "password"}
    users_map = {}
    for u in active_users:
        users_map[u["uuid"]] = u["password"]

    conf = {
        "server":                f"0.0.0.0:{CORE_PORTS['tuic']}",
        "users":                 users_map,
        "certificate":           CERT_PATH,
        "private_key":           KEY_PATH,
        "congestion_controller": "bbr",
        "max_idle_time":         "15s",
        "authentication_timeout":"3s",
        "alpn":                  ["h3"],
        "max_udp_relay_packet_size": 1500,
        "log_level":             "warn",
    }
    conf_path = CONFIGS_DIR / "tuic_config.json"
    conf_path.write_text(json.dumps(conf, indent=2))
    try:
        subprocess.run(["systemctl", "restart", "tuic-server"],
                       capture_output=True, timeout=10)
        logger.info("TUIC ری‌استارت شد")
    except Exception as e:
        logger.warning(f"TUIC restart: {e}")

# ── کانفیگ Hysteria2 — فرمت صحیح ─────────────────────────────
def write_hysteria2_config(active_users):
    if not Path(HY2_BIN).exists():
        return
    if not active_users:
        subprocess.run(["systemctl", "stop", "hysteria2"], capture_output=True)
        return

    # فرمت YAML صحیح — پسوردها باید alphanumeric باشند (فیکس شد)
    # از json format به جای yaml استفاده می‌کنیم تا کاراکتر خاص مشکل نسازد
    userpass = {u["username"]: u["password"] for u in active_users}

    # Hysteria2 از JSON config هم پشتیبانی می‌کند
    conf = {
        "listen": f":{CORE_PORTS['hy2']}",
        "tls": {
            "cert": CERT_PATH,
            "key":  KEY_PATH,
        },
        "auth": {
            "type":     "userpass",
            "userpass": userpass,
        },
        "masquerade": {
            "type": "proxy",
            "proxy": {
                "url":         "https://www.google.com",
                "rewriteHost": True,
            },
        },
        "quic": {
            "initStreamReceiveWindow":    8388608,
            "maxStreamReceiveWindow":     8388608,
            "initConnReceiveWindow":      20971520,
            "maxConnReceiveWindow":       20971520,
            "maxIdleTimeout":             "30s",
            "maxIncomingStreams":          1024,
            "disablePathMTUDiscovery":    False,
        },
        "bandwidth": {
            "up":   "1 gbps",
            "down": "1 gbps",
        },
        "ignoreClientBandwidth": False,
        "speedTest":             False,
        "udpIdleTimeout":        "60s",
    }
    conf_path = CONFIGS_DIR / "hysteria2_config.json"
    conf_path.write_text(json.dumps(conf, indent=2, ensure_ascii=False))
    try:
        subprocess.run(["systemctl", "restart", "hysteria2"],
                       capture_output=True, timeout=10)
        logger.info("Hysteria2 ری‌استارت شد")
    except Exception as e:
        logger.warning(f"Hysteria2 restart: {e}")

def apply_all_configs():
    """اعمال کانفیگ روی همه سرویس‌ها"""
    with get_db() as db:
        active_users = [dict(r) for r in db.execute(
            "SELECT * FROM users WHERE status='active'"
        ).fetchall()]

    build_xray_config()
    ok = reload_xray()
    if not ok:
        logger.error("Xray ری‌استارت نشد — کانفیگ احتمالاً خطا دارد")

    write_tuic_config(active_users)
    write_hysteria2_config(active_users)

# ══════════════════════════════════════════════════════════════
#  رصد ترافیک
# ══════════════════════════════════════════════════════════════

class TrafficMonitor(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True, name="TrafficMonitor")
        self.interval  = 300
        self._stop     = threading.Event()
        self._api_port = 10085

    def run(self):
        time.sleep(60)
        while not self._stop.wait(self.interval):
            try:
                self._sync()
                self._enforce()
            except Exception as e:
                logger.error(f"TrafficMonitor: {e}")

    def _sync(self):
        stats = {}
        try:
            r = subprocess.run(
                [XRAY_BIN, "api", "statsquery",
                 f"--server=127.0.0.1:{self._api_port}", "-pattern", ""],
                capture_output=True, text=True, timeout=10,
            )
            if r.returncode != 0:
                return
            data = json.loads(r.stdout or "{}")
            for stat in data.get("stat", []):
                name = stat.get("name", "")
                val  = int(stat.get("value", 0) or 0)
                if "user>>>" in name:
                    parts = name.split(">>>")
                    if len(parts) >= 4:
                        username = parts[1]
                        stats[username] = stats.get(username, 0) + val
        except Exception as e:
            logger.debug(f"Xray API: {e}")
            return

        if not stats:
            return

        with _db_lock, get_db() as db:
            for username, total_bytes in stats.items():
                if total_bytes > 0:
                    db.execute(
                        "UPDATE users SET used_quota_bytes=used_quota_bytes+? WHERE username=?",
                        (total_bytes, username)
                    )
            db.execute("UPDATE system_settings SET value=? WHERE key='last_traffic_sync'",
                       (str(int(time.time())),))
            db.commit()

    def _enforce(self):
        now     = datetime.now()
        changed = False
        with _db_lock, get_db() as db:
            users = db.execute("SELECT * FROM users WHERE status='active'").fetchall()
            for u in users:
                new_status = None
                if u["expire_date"]:
                    try:
                        if now > datetime.fromisoformat(u["expire_date"]):
                            new_status = "expired"
                    except:
                        pass
                if new_status is None and float(u["total_quota_gb"]) > 0:
                    if int(u["used_quota_bytes"] or 0) >= gb_to_bytes(u["total_quota_gb"]):
                        new_status = "quota_exceeded"
                if new_status:
                    db.execute("UPDATE users SET status=? WHERE id=?", (new_status, u["id"]))
                    changed = True
                    logger.info(f"کاربر {u['username']} → {new_status}")
            if changed:
                db.commit()
        if changed:
            apply_all_configs()

# ══════════════════════════════════════════════════════════════
#  به‌روزرسانی از GitHub
# ══════════════════════════════════════════════════════════════

def github_update():
    import urllib.request
    repo     = "Masterv2panel/Masterpanel"
    base_url = f"https://raw.githubusercontent.com/{repo}/main"
    files    = ["masterpanel.py", "index.html", "mp.sh", "install.sh", "quickinstall.sh"]
    result   = {"updated": [], "failed": [], "errors": []}
    for fname in files:
        try:
            req = urllib.request.Request(
                f"{base_url}/{fname}", headers={"User-Agent": "MasterPanel-Updater/3.0"}
            )
            with urllib.request.urlopen(req, timeout=30) as r:
                content = r.read()
            dest = PANEL_DIR / "templates" / fname if fname == "index.html" else PANEL_DIR / fname
            if dest.exists():
                dest.with_suffix(dest.suffix + ".bak").write_bytes(dest.read_bytes())
            dest.write_bytes(content)
            if dest.suffix in (".sh", ".py"):
                dest.chmod(0o755)
            result["updated"].append(fname)
        except Exception as e:
            result["failed"].append(fname)
            result["errors"].append(f"{fname}: {e}")
    if "masterpanel.py" in result["updated"]:
        try:
            subprocess.Popen(["systemctl", "restart", "masterpanel"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except:
            pass
    return result

# ══════════════════════════════════════════════════════════════
#  احراز هویت
# ══════════════════════════════════════════════════════════════

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("logged_in"):
            if request.is_json or request.path.startswith("/api/"):
                return jsonify({"ok": False, "error": "احراز هویت لازم است"}), 401
            return redirect(url_for("login_page"))
        return f(*args, **kwargs)
    return decorated

def serve_html():
    p = PANEL_DIR / "templates" / "index.html"
    if p.exists():
        return p.read_text(encoding="utf-8"), 200, {"Content-Type": "text/html; charset=utf-8"}
    return "<h1>index.html یافت نشد</h1>", 404

# ══════════════════════════════════════════════════════════════
#  Routes
# ══════════════════════════════════════════════════════════════

@app.route("/")
def index():
    if not session.get("logged_in"):
        return redirect(url_for("login_page"))
    return serve_html()

@app.route("/login", methods=["GET", "POST"])
def login_page():
    if request.method == "POST":
        d = request.get_json() or {}
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
    xs = xray_status()
    with get_db() as db:
        total  = db.execute("SELECT COUNT(*) FROM users").fetchone()[0]
        active = db.execute("SELECT COUNT(*) FROM users WHERE status='active'").fetchone()[0]
        sync   = db.execute("SELECT value FROM system_settings WHERE key='last_traffic_sync'").fetchone()
    return jsonify({
        "xray":       xs,
        "domain":     DOMAIN,
        "server_ip":  get_server_ip(),
        "panel_port": PANEL_PORT,
        "ssl_valid":  Path(CERT_PATH).exists() if CERT_PATH else False,
        "uptime":     get_uptime(),
        "users":      {"total": total, "active": active},
        "last_sync":  sync["value"] if sync else "0",
        "system":     get_system_stats(),
    })

@app.route("/api/system/stats")
@login_required
def api_system_stats():
    return jsonify(get_system_stats())

# ── مدیریت کاربران ────────────────────────────────────────────

@app.route("/api/users", methods=["GET"])
@login_required
def api_users_list():
    with get_db() as db:
        rows = db.execute("""
            SELECT id, username, uuid, total_quota_gb, used_quota_bytes,
                   expire_date, status, created_at, note
            FROM users ORDER BY created_at DESC
        """).fetchall()
    now    = datetime.now()
    result = []
    for u in rows:
        u       = dict(u)
        quota_b = gb_to_bytes(u["total_quota_gb"])
        used_b  = int(u["used_quota_bytes"] or 0)
        pct     = round(used_b / quota_b * 100, 1) if quota_b > 0 else 0
        days_left = None
        if u["expire_date"]:
            try:
                days_left = (datetime.fromisoformat(u["expire_date"]) - now).days
            except:
                pass
        result.append({
            **u,
            "used_quota_human":  bytes_to_human(used_b),
            "total_quota_human": f"{float(u['total_quota_gb']):.1f} GB",
            "quota_percent":     min(pct, 100),
            "days_left":         days_left,
        })
    return jsonify(result)

@app.route("/api/users/create", methods=["POST"])
@login_required
def api_user_create():
    d        = request.get_json() or {}
    username = d.get("username", "").strip()
    quota_gb = float(d.get("quota_gb", 10))
    days     = int(d.get("days", 30))
    note     = d.get("note", "")

    if not username or len(username) < 3:
        return jsonify({"ok": False, "error": "نام کاربری باید حداقل ۳ کاراکتر باشد"})
    if not all(c.isalnum() or c in "-_." for c in username):
        return jsonify({"ok": False, "error": "فقط حروف، اعداد، - و _ مجاز است"})

    uid = new_uuid()
    pw  = new_password(24)   # alphanumeric فقط — ایمن برای همه پروتکل‌ها
    exp = (datetime.now() + timedelta(days=days)).isoformat() if days > 0 else None

    try:
        with _db_lock, get_db() as db:
            db.execute("""
                INSERT INTO users (username, uuid, password, total_quota_gb, expire_date, note)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (username, uid, pw, quota_gb, exp, note))
            db.commit()
        apply_all_configs()
        return jsonify({"ok": True, "user": {"username": username, "uuid": uid}})
    except sqlite3.IntegrityError:
        return jsonify({"ok": False, "error": "این نام کاربری قبلاً ثبت شده"})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})

@app.route("/api/users/<int:uid>", methods=["PUT"])
@login_required
def api_user_update(uid):
    d = request.get_json() or {}
    with get_db() as db:
        if not db.execute("SELECT id FROM users WHERE id=?", (uid,)).fetchone():
            return jsonify({"ok": False, "error": "کاربر یافت نشد"}), 404
    updates, params = [], []
    if "quota_gb" in d:
        updates.append("total_quota_gb=?"); params.append(float(d["quota_gb"]))
    if "days" in d:
        exp = (datetime.now() + timedelta(days=int(d["days"]))).isoformat()
        updates.append("expire_date=?");    params.append(exp)
    if d.get("reset_traffic"):
        updates.append("used_quota_bytes=0")
    if "note" in d:
        updates.append("note=?");           params.append(d["note"])
    if "status" in d and d["status"] in ("active","disabled","expired","quota_exceeded"):
        updates.append("status=?");         params.append(d["status"])
    if updates:
        params.append(uid)
        with _db_lock, get_db() as db:
            db.execute(f"UPDATE users SET {','.join(updates)} WHERE id=?", params)
            db.commit()
        apply_all_configs()
    return jsonify({"ok": True})

@app.route("/api/users/<int:uid>/toggle", methods=["POST"])
@login_required
def api_user_toggle(uid):
    with _db_lock, get_db() as db:
        row = db.execute("SELECT status FROM users WHERE id=?", (uid,)).fetchone()
        if not row:
            return jsonify({"ok": False, "error": "کاربر یافت نشد"}), 404
        new_status = "disabled" if row["status"] == "active" else "active"
        db.execute("UPDATE users SET status=? WHERE id=?", (new_status, uid))
        db.commit()
    apply_all_configs()
    return jsonify({"ok": True, "status": new_status})

@app.route("/api/users/<int:uid>", methods=["DELETE"])
@login_required
def api_user_delete(uid):
    with _db_lock, get_db() as db:
        if not db.execute("SELECT id FROM users WHERE id=?", (uid,)).fetchone():
            return jsonify({"ok": False, "error": "کاربر یافت نشد"}), 404
        db.execute("DELETE FROM users WHERE id=?", (uid,))
        db.commit()
    apply_all_configs()
    return jsonify({"ok": True})

@app.route("/api/users/<int:uid>/links", methods=["GET"])
@login_required
def api_user_links(uid):
    with get_db() as db:
        u = db.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
    if not u:
        return jsonify({"ok": False, "error": "کاربر یافت نشد"}), 404
    links   = generate_user_links(dict(u))
    sub_b64 = base64.b64encode("\n".join(links).encode()).decode()
    return jsonify({
        "ok":               True,
        "links":            links,
        "subscription_b64": sub_b64,
        "subscription_url": f"/sub/{u['username']}",
    })

# ── سابسکریپشن عمومی ─────────────────────────────────────────

@app.route("/sub/<username>")
def public_subscription(username):
    with get_db() as db:
        u = db.execute(
            "SELECT * FROM users WHERE username=? AND status='active'", (username,)
        ).fetchone()
    if not u:
        return Response("# اشتراک غیرفعال یا منقضی", status=403, mimetype="text/plain; charset=utf-8")
    if float(u["total_quota_gb"]) > 0:
        if int(u["used_quota_bytes"] or 0) >= gb_to_bytes(u["total_quota_gb"]):
            return Response("# سهمیه تمام شده", status=403, mimetype="text/plain; charset=utf-8")

    links   = generate_user_links(dict(u))
    content = base64.b64encode("\n".join(links).encode()).decode()
    expire_ts = 0
    if u["expire_date"]:
        try:
            expire_ts = int(datetime.fromisoformat(u["expire_date"]).timestamp())
        except:
            pass
    return Response(
        content,
        mimetype="text/plain; charset=utf-8",
        headers={
            "Content-Disposition":   f"inline; filename=sub-{username}.txt",
            "Profile-Title":          base64.b64encode(f"MasterPanel-{username}".encode()).decode(),
            "Subscription-Userinfo": (
                f"upload=0; download={u['used_quota_bytes'] or 0}; "
                f"total={gb_to_bytes(u['total_quota_gb'])}; expire={expire_ts}"
            ),
        },
    )

# ── Xray API ──────────────────────────────────────────────────

@app.route("/api/xray/restart", methods=["POST"])
@login_required
def api_xray_restart():
    build_xray_config()
    ok = reload_xray()
    return jsonify({"ok": ok, "message": "Xray ری‌استارت شد" if ok else "خطا در ری‌استارت"})

@app.route("/api/xray/logs")
@login_required
def api_xray_logs():
    f = PANEL_DIR / "logs" / "xray-error.log"
    lines = f.read_text(errors="replace").splitlines()[-100:] if f.exists() else []
    return jsonify({"ok": True, "lines": lines})

@app.route("/api/configs/apply", methods=["POST"])
@login_required
def api_apply_configs():
    try:
        apply_all_configs()
        ok, err = validate_xray_config()
        return jsonify({"ok": True, "xray_valid": ok, "xray_error": err})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})

@app.route("/api/core/configs")
@login_required
def api_core_configs():
    safe = [{k: v for k, v in c.items() if k != "priv_key"} for c in get_core_configs()]
    return jsonify(safe)

@app.route("/api/xray/validate")
@login_required
def api_xray_validate():
    build_xray_config()
    ok, err = validate_xray_config()
    return jsonify({"ok": ok, "error": err})

# ── تست اتصال ────────────────────────────────────────────────

@app.route("/api/test", methods=["POST"])
@login_required
def api_test():
    d    = request.get_json() or {}
    t    = d.get("type")
    host = d.get("host", DOMAIN)
    port = int(d.get("port", 443))

    if t == "tls":
        try:
            ctx = ssl.create_default_context()
            with socket.create_connection((host, port), timeout=6) as sock:
                with ctx.wrap_socket(sock, server_hostname=host) as s:
                    return jsonify({"ok": True, "tls_version": s.version(), "cipher": s.cipher()[0]})
        except Exception as e:
            return jsonify({"ok": False, "error": str(e)})

    if t == "all":
        results = {}
        for cfg in get_core_configs():
            if cfg["protocol"] in ("tuic", "hysteria2"):
                continue
            h = cfg["address"]
            p = cfg["port"]
            try:
                start = time.time()
                socket.create_connection((h, p), timeout=5).close()
                lat = round((time.time() - start) * 1000)
                results[cfg["name"]] = {"latency": lat, "port_open": True,
                                        "protocol": cfg["protocol"],
                                        "tls":      cfg.get("tls","none"),
                                        "network":  cfg.get("network","tcp")}
            except:
                results[cfg["name"]] = {"latency": None, "port_open": False,
                                        "protocol": cfg["protocol"],
                                        "tls":      cfg.get("tls","none"),
                                        "network":  cfg.get("network","tcp")}
        return jsonify({"ok": True, "results": results})

    return jsonify({"ok": False, "error": "نوع تست نامعتبر"})

# ── به‌روزرسانی ───────────────────────────────────────────────

@app.route("/api/system/update", methods=["POST"])
@login_required
def api_system_update():
    try:
        r = github_update()
        return jsonify({"ok": True, **r, "restarting": "masterpanel.py" in r["updated"]})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})

# ══════════════════════════════════════════════════════════════
#  اجرا
# ══════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print("[MasterPanel v3.0] در حال راه‌اندازی...")
    init_db()
    print("[DB] پایگاه داده آماده")

    keys = get_or_create_reality_keys()
    pub_preview = keys['pub_key'][:16] if keys['pub_key'] else "N/A"
    print(f"[Reality] pub_key: {pub_preview}...")

    try:
        apply_all_configs()
        ok, err = validate_xray_config()
        if ok:
            print("[Xray] کانفیگ اعمال و تأیید شد ✓")
        else:
            print(f"[Xray] هشدار — کانفیگ خطا دارد: {err[:120]}")
    except Exception as e:
        print(f"[Xray] خطا: {e}")

    monitor = TrafficMonitor()
    monitor.start()
    print("[Monitor] رصد ترافیک شروع شد")

    import logging as _log
    _log.getLogger("werkzeug").setLevel(_log.WARNING)
    print(f"[Ready] پنل روی پورت {PANEL_PORT} در دسترس است")
    app.run(host="0.0.0.0", port=PANEL_PORT, debug=False, threaded=True)
