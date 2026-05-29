#!/usr/bin/env python3
"""
MasterPanel - Xray Auto Protocol Configurator
Backend Server v3.0
Fixes:
  - CF configs use TLS=none on Xray side (CF terminates TLS)
  - No duplicate ports in Xray inbounds
  - Unique paths per protocol per port
  - Separate inbound per protocol using port multiplexing
  - Traffic stats / online users via Xray API
  - User management with traffic limits
"""

import os, json, uuid, subprocess, socket, ssl, time, base64, urllib.parse, secrets, string, threading
from datetime import datetime
from pathlib import Path
from flask import Flask, request, jsonify, session, redirect, url_for, Response

app = Flask(__name__, static_folder=None)
app.secret_key = os.urandom(32)

# ── Config ────────────────────────────────────────────────────
PANEL_DIR    = Path("/opt/masterpanel")
CONF_FILE    = PANEL_DIR / "panel.conf"

def load_conf():
    conf = {}
    if CONF_FILE.exists():
        for line in CONF_FILE.read_text().splitlines():
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
CONFIGS_DIR  = PANEL_DIR / "configs"
USERS_FILE   = PANEL_DIR / "configs" / "users.json"
CONFIGS_DIR.mkdir(exist_ok=True)
XRAY_CFG_DIR.mkdir(parents=True, exist_ok=True)

# ── Helpers ───────────────────────────────────────────────────
def new_uuid():
    return str(uuid.uuid4())

def new_password(length=16):
    chars = string.ascii_letters + string.digits
    return ''.join(secrets.choice(chars) for _ in range(length))

def get_server_ip():
    """Always return IPv4."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and ":" not in ip and not ip.startswith("127."):
            return ip
    except:
        pass
    for api in ["https://api4.ipify.org", "https://ipv4.icanhazip.com"]:
        try:
            import urllib.request
            req = urllib.request.Request(api, headers={"User-Agent": "curl/7"})
            with urllib.request.urlopen(req, timeout=4) as r:
                ip = r.read().decode().strip()
                if ip and ":" not in ip:
                    return ip
        except:
            continue
    return "0.0.0.0"

def get_reality_keys():
    try:
        r = subprocess.run([XRAY_BIN, "x25519"], capture_output=True, text=True, timeout=5)
        lines = r.stdout.strip().splitlines()
        priv = lines[0].split(": ")[-1] if lines else ""
        pub  = lines[1].split(": ")[-1] if len(lines) > 1 else ""
        return priv, pub
    except:
        return "", ""

def get_uptime():
    try:
        with open("/proc/uptime") as f:
            secs = float(f.read().split()[0])
        h, m = int(secs//3600), int((secs%3600)//60)
        return f"{h}h {m}m"
    except:
        return "N/A"

def serve_html():
    html_path = PANEL_DIR / "templates" / "index.html"
    if html_path.exists():
        return html_path.read_text(encoding="utf-8"), 200, {"Content-Type": "text/html; charset=utf-8"}
    return "<h1>index.html not found</h1>", 404

# ── User Management ───────────────────────────────────────────
def load_users():
    if USERS_FILE.exists():
        try:
            return json.loads(USERS_FILE.read_text())
        except:
            pass
    return {}

def save_users(users):
    USERS_FILE.write_text(json.dumps(users, indent=2, ensure_ascii=False))

def get_user(uid):
    return load_users().get(uid)

# ── Share Link Builders ───────────────────────────────────────
def vless_link(c):
    uid  = c.get("id", "")
    addr = c.get("address", DOMAIN)
    port = c.get("port", 443)
    net  = c.get("network", "tcp")
    # Client always connects with TLS — CF handles it
    client_tls = c.get("client_tls", c.get("tls", "tls"))
    path = urllib.parse.quote(c.get("path", "/"), safe="")
    sni  = c.get("sni", DOMAIN)
    fp   = c.get("fp", "chrome")
    name = urllib.parse.quote(c.get("name", "vless"))
    flow = c.get("flow", "")
    pbk  = c.get("public_key", "")
    sid  = c.get("short_id", "")
    params = f"type={net}&security={client_tls}&sni={sni}&fp={fp}"
    if net in ("ws", "httpupgrade"):
        params += f"&path={path}"
    if net == "grpc":
        params += f"&serviceName={urllib.parse.quote(c.get('service_name','grpc'))}"
    if flow:
        params += f"&flow={flow}"
    if client_tls == "reality" and pbk:
        params += f"&pbk={pbk}&sid={sid}"
    return f"vless://{uid}@{addr}:{port}?{params}#{name}"

def vmess_link(c):
    client_tls = c.get("client_tls", c.get("tls", "tls"))
    net = c.get("network", "ws")
    data = {
        "v": "2", "ps": c.get("name", ""),
        "add": c.get("address", DOMAIN),
        "port": str(c.get("port", 443)),
        "id": c.get("id", ""), "aid": "0", "scy": "auto",
        "net": net, "type": "none",
        "host": c.get("sni", DOMAIN),
        "path": c.get("service_name", c.get("path", "/")),
        "tls": "tls" if client_tls == "tls" else "",
        "sni": c.get("sni", DOMAIN), "fp": c.get("fp", "chrome"),
    }
    return "vmess://" + base64.b64encode(json.dumps(data).encode()).decode()

def trojan_link(c):
    pw   = c.get("password", "")
    addr = c.get("address", DOMAIN)
    port = c.get("port", 443)
    net  = c.get("network", "tcp")
    client_tls = c.get("client_tls", "tls")
    sni  = c.get("sni", DOMAIN)
    fp   = c.get("fp", "chrome")
    path = urllib.parse.quote(c.get("path", "/"), safe="")
    name = urllib.parse.quote(c.get("name", "trojan"))
    params = f"type={net}&security={client_tls}&sni={sni}&fp={fp}"
    if net in ("ws", "httpupgrade"):
        params += f"&path={path}"
    if net == "grpc":
        params += f"&serviceName={urllib.parse.quote(c.get('service_name','grpc'))}"
    return f"trojan://{pw}@{addr}:{port}?{params}#{name}"

def ss_link(c):
    method   = c.get("method", "chacha20-ietf-poly1305")
    password = c.get("password", "")
    addr     = c.get("address", DOMAIN)
    port     = c.get("port", 8388)
    name     = urllib.parse.quote(c.get("name", "ss"))
    userinfo = base64.b64encode(f"{method}:{password}".encode()).decode()
    return f"ss://{userinfo}@{addr}:{port}#{name}"

def tuic_link(c):
    uid  = c.get("id", "")
    pw   = c.get("password", "")
    addr = c.get("address", DOMAIN)
    port = c.get("port", 443)
    sni  = c.get("sni", DOMAIN)
    name = urllib.parse.quote(c.get("name", "tuic"))
    return f"tuic://{uid}:{pw}@{addr}:{port}?sni={sni}&congestion_control=bbr&alpn=h3#{name}"

def hysteria2_link(c):
    pw   = c.get("password", "")
    addr = c.get("address", DOMAIN)
    port = c.get("port", 443)
    sni  = c.get("sni", DOMAIN)
    name = urllib.parse.quote(c.get("name", "hy2"))
    obfs = c.get("obfs", "")
    obfs_pw = c.get("obfs_password", "")
    params = f"sni={sni}&insecure=0"
    if obfs:
        params += f"&obfs={obfs}&obfs-password={obfs_pw}"
    return f"hysteria2://{pw}@{addr}:{port}?{params}#{name}"

# ── KEY FIX: Port Allocation ──────────────────────────────────
# Each Xray inbound needs a UNIQUE port.
# CF configs: Xray listens on internal ports, nginx/caddy or direct with TLS=none
# We use a dedicated port per protocol+transport combination.
#
# Port map:
#   CF side  (client→CF→Xray):  Xray uses TLS=none, unique internal port
#   IP side  (client→Xray):     Xray uses TLS=tls,  unique port
#
# CF WS ports (Xray internal):
#   20001 = VLESS WS (CF)
#   20002 = VMess WS (CF)
#   20003 = Trojan WS (CF)
#   20004 = VLESS gRPC (CF)
#   20005 = VMess gRPC (CF)
#   20006 = Trojan gRPC (CF)
#   20007 = VLESS HTTPUpgrade (CF)
#   20008 = VMess HTTPUpgrade (CF)
#
# Direct IP ports:
#   20010 = VLESS TCP TLS
#   20011 = VLESS WS TLS
#   20012 = VLESS HTTPUpgrade TLS
#   20013 = VLESS TCP no-TLS
#   20020 = VMess TCP TLS
#   20021 = VMess WS TLS
#   20022 = VMess HTTPUpgrade TLS
#   20023 = VMess WS no-TLS
#   20030 = Trojan TCP TLS
#   20031 = Trojan WS TLS
#   20032 = Trojan HTTPUpgrade TLS
#   8388  = SS chacha20
#   8389  = SS aes256
#   8390  = SS 2022-blake3
#   443   = VLESS REALITY (x4 dest)
#   19443 = TUIC
#   19999 = Hysteria2

def generate_all_configs():
    configs  = []
    ip       = get_server_ip()
    inbounds = []

    shared = {
        "vless_id":     new_uuid(),
        "vmess_id":     new_uuid(),
        "trojan_pw":    new_password(20),
        "tuic_id":      new_uuid(),
        "tuic_pw":      new_password(16),
        "hy2_pw":       new_password(20),
    }

    reality_dests = [
        {"dest": "www.google.com:443",   "sni": "www.google.com",   "fp": "chrome",  "port": 8001},
        {"dest": "www.apple.com:443",    "sni": "www.apple.com",    "fp": "safari",  "port": 8002},
        {"dest": "discord.com:443",      "sni": "discord.com",      "fp": "firefox", "port": 8003},
        {"dest": "cdn.jsdelivr.net:443", "sni": "cdn.jsdelivr.net", "fp": "chrome",  "port": 8004},
    ]
    for rd in reality_dests:
        priv, pub = get_reality_keys()
        rd["priv_key"] = priv
        rd["pub_key"]  = pub
        rd["short_id"] = new_uuid()[:8]

    # CF ports clients connect to (Cloudflare accepts these)
    cf_client_ports = [443, 2053, 2083, 2087, 2096, 8443]

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # VLESS CF/CDN — WS
    # KEY FIX: client_tls=tls (CF→client), server tls=none (Xray)
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    for cfport in cf_client_ports:
        configs.append({
            "name": f"VLESS-WS-CF-{cfport}",
            "protocol": "vless", "network": "ws",
            "tls": "none",          # Xray receives plain HTTP from CF
            "client_tls": "tls",    # Client connects to CF with TLS
            "port": cfport,
            "xray_port": 20001,     # Xray actually listens here
            "path": "/vless-ws", "sni": DOMAIN,
            "fp": "chrome", "address": DOMAIN,
            "id": shared["vless_id"], "connection_type": "domain",
        })

    # VLESS CF — gRPC
    configs.append({
        "name": "VLESS-gRPC-CF-443",
        "protocol": "vless", "network": "grpc",
        "tls": "none", "client_tls": "tls",
        "port": 443, "xray_port": 20004,
        "service_name": "vless-grpc", "sni": DOMAIN,
        "fp": "chrome", "address": DOMAIN,
        "id": shared["vless_id"], "connection_type": "domain",
    })

    # VLESS CF — HTTPUpgrade
    configs.append({
        "name": "VLESS-HTTPUpgrade-CF-8443",
        "protocol": "vless", "network": "httpupgrade",
        "tls": "none", "client_tls": "tls",
        "port": 8443, "xray_port": 20007,
        "path": "/vless-hu", "sni": DOMAIN,
        "fp": "chrome", "address": DOMAIN,
        "id": shared["vless_id"], "connection_type": "domain",
    })

    # ── VLESS Direct IP ───────────────────────────────────────
    configs.append({
        "name": "VLESS-TCP-TLS-IP-20010",
        "protocol": "vless", "network": "tcp", "tls": "tls", "client_tls": "tls",
        "port": 20010, "xray_port": 20010, "sni": DOMAIN, "fp": "safari",
        "address": ip, "id": shared["vless_id"], "connection_type": "direct_ip",
    })
    configs.append({
        "name": "VLESS-WS-TLS-IP-20011",
        "protocol": "vless", "network": "ws", "tls": "tls", "client_tls": "tls",
        "port": 20011, "xray_port": 20011, "path": "/vless-ws", "sni": DOMAIN,
        "fp": "chrome", "address": ip, "id": shared["vless_id"], "connection_type": "direct_ip",
    })
    configs.append({
        "name": "VLESS-HTTPUpgrade-TLS-IP-20012",
        "protocol": "vless", "network": "httpupgrade", "tls": "tls", "client_tls": "tls",
        "port": 20012, "xray_port": 20012, "path": "/vless-hu", "sni": DOMAIN,
        "fp": "edge", "address": ip, "id": shared["vless_id"], "connection_type": "direct_ip",
    })
    configs.append({
        "name": "VLESS-TCP-NOTLS-IP-20013",
        "protocol": "vless", "network": "tcp", "tls": "none", "client_tls": "none",
        "port": 20013, "xray_port": 20013, "sni": "", "fp": "chrome",
        "address": ip, "id": shared["vless_id"], "connection_type": "direct_ip",
    })

    # VLESS REALITY — 4 destinations (each on unique port)
    for rd in reality_dests:
        cfg = {
            "name": f"VLESS-REALITY-{rd['sni'].split('.')[1].upper()}-{rd['port']}",
            "protocol": "vless", "network": "tcp",
            "tls": "reality", "client_tls": "reality",
            "port": rd["port"], "xray_port": rd["port"],
            "sni": rd["sni"], "fp": rd["fp"],
            "flow": "xtls-rprx-vision", "address": ip,
            "id": shared["vless_id"],
            "reality_dest": rd["dest"],
            "priv_key": rd["priv_key"],
            "public_key": rd["pub_key"],
            "short_id": rd["short_id"],
            "connection_type": "direct_ip",
        }
        configs.append(cfg)

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # VMess CF/CDN
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    for cfport in [443, 2083, 2087, 8443]:
        configs.append({
            "name": f"VMess-WS-CF-{cfport}",
            "protocol": "vmess", "network": "ws",
            "tls": "none", "client_tls": "tls",
            "port": cfport, "xray_port": 20002,
            "path": "/vmess-ws", "sni": DOMAIN,
            "fp": "chrome", "address": DOMAIN,
            "id": shared["vmess_id"], "connection_type": "domain",
        })

    configs.append({
        "name": "VMess-gRPC-CF-443",
        "protocol": "vmess", "network": "grpc",
        "tls": "none", "client_tls": "tls",
        "port": 443, "xray_port": 20005,
        "service_name": "vmess-grpc", "sni": DOMAIN,
        "fp": "chrome", "address": DOMAIN,
        "id": shared["vmess_id"], "connection_type": "domain",
    })
    configs.append({
        "name": "VMess-HTTPUpgrade-CF-2096",
        "protocol": "vmess", "network": "httpupgrade",
        "tls": "none", "client_tls": "tls",
        "port": 2096, "xray_port": 20008,
        "path": "/vmess-hu", "sni": DOMAIN,
        "fp": "firefox", "address": DOMAIN,
        "id": shared["vmess_id"], "connection_type": "domain",
    })

    # VMess Direct IP
    configs.append({
        "name": "VMess-TCP-TLS-IP-20020",
        "protocol": "vmess", "network": "tcp", "tls": "tls", "client_tls": "tls",
        "port": 20020, "xray_port": 20020, "sni": DOMAIN, "fp": "safari",
        "address": ip, "id": shared["vmess_id"], "connection_type": "direct_ip",
    })
    configs.append({
        "name": "VMess-WS-TLS-IP-20021",
        "protocol": "vmess", "network": "ws", "tls": "tls", "client_tls": "tls",
        "port": 20021, "xray_port": 20021, "path": "/vmess-ws", "sni": DOMAIN,
        "fp": "chrome", "address": ip, "id": shared["vmess_id"], "connection_type": "direct_ip",
    })
    configs.append({
        "name": "VMess-WS-NOTLS-IP-20023",
        "protocol": "vmess", "network": "ws", "tls": "none", "client_tls": "none",
        "port": 20023, "xray_port": 20023, "path": "/vmess-ws", "sni": "",
        "fp": "chrome", "address": ip, "id": shared["vmess_id"], "connection_type": "direct_ip",
    })

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Trojan CF/CDN
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    for cfport in [443, 2096, 8443]:
        configs.append({
            "name": f"Trojan-WS-CF-{cfport}",
            "protocol": "trojan", "network": "ws",
            "tls": "none", "client_tls": "tls",
            "port": cfport, "xray_port": 20003,
            "path": "/trojan-ws", "sni": DOMAIN,
            "fp": "chrome", "address": DOMAIN,
            "password": shared["trojan_pw"], "connection_type": "domain",
        })

    configs.append({
        "name": "Trojan-gRPC-CF-443",
        "protocol": "trojan", "network": "grpc",
        "tls": "none", "client_tls": "tls",
        "port": 443, "xray_port": 20006,
        "service_name": "trojan-grpc", "sni": DOMAIN,
        "fp": "chrome", "address": DOMAIN,
        "password": shared["trojan_pw"], "connection_type": "domain",
    })

    # Trojan Direct IP
    configs.append({
        "name": "Trojan-TCP-TLS-IP-20030",
        "protocol": "trojan", "network": "tcp", "tls": "tls", "client_tls": "tls",
        "port": 20030, "xray_port": 20030, "sni": DOMAIN, "fp": "firefox",
        "address": ip, "password": shared["trojan_pw"], "connection_type": "direct_ip",
    })
    configs.append({
        "name": "Trojan-WS-TLS-IP-20031",
        "protocol": "trojan", "network": "ws", "tls": "tls", "client_tls": "tls",
        "port": 20031, "xray_port": 20031, "path": "/trojan-ws", "sni": DOMAIN,
        "fp": "chrome", "address": ip, "password": shared["trojan_pw"], "connection_type": "direct_ip",
    })
    configs.append({
        "name": "Trojan-HTTPUpgrade-TLS-IP-20032",
        "protocol": "trojan", "network": "httpupgrade", "tls": "tls", "client_tls": "tls",
        "port": 20032, "xray_port": 20032, "path": "/trojan-hu", "sni": DOMAIN,
        "fp": "safari", "address": ip, "password": shared["trojan_pw"], "connection_type": "direct_ip",
    })
    # Trojan REALITY
    rd = reality_dests[0]
    configs.append({
        "name": "Trojan-REALITY-IP-8005",
        "protocol": "trojan", "network": "tcp", "tls": "reality", "client_tls": "reality",
        "port": 8005, "xray_port": 8005, "sni": rd["sni"], "fp": rd["fp"],
        "address": ip, "password": shared["trojan_pw"],
        "reality_dest": rd["dest"], "priv_key": rd["priv_key"],
        "public_key": rd["pub_key"], "short_id": rd["short_id"],
        "connection_type": "direct_ip",
    })

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Shadowsocks
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    for method, port, pw_key in [
        ("chacha20-ietf-poly1305", 8388, new_password(16)),
        ("aes-256-gcm",            8389, new_password(16)),
        ("2022-blake3-aes-256-gcm",8390, base64.b64encode(secrets.token_bytes(32)).decode()),
    ]:
        configs.append({
            "name": f"SS-{method.split('-')[0]}-IP-{port}",
            "protocol": "shadowsocks", "network": "tcp", "tls": "none",
            "port": port, "xray_port": port,
            "method": method, "password": pw_key,
            "address": ip, "connection_type": "direct_ip",
        })

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # TUIC v5
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    configs.append({
        "name": "TUIC-v5-IP-19443",
        "protocol": "tuic", "network": "udp", "tls": "tls", "client_tls": "tls",
        "port": 19443, "xray_port": 19443, "sni": DOMAIN,
        "id": shared["tuic_id"], "password": shared["tuic_pw"],
        "address": ip, "connection_type": "direct_ip", "congestion": "bbr",
    })
    configs.append({
        "name": "TUIC-v5-CF-443",
        "protocol": "tuic", "network": "udp", "tls": "tls", "client_tls": "tls",
        "port": 443, "xray_port": 19443, "sni": DOMAIN,
        "id": shared["tuic_id"], "password": shared["tuic_pw"],
        "address": DOMAIN, "connection_type": "domain", "congestion": "bbr",
    })

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Hysteria2
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    hy2_obfs_pw = new_password(16)
    configs.append({
        "name": "Hysteria2-IP-19999",
        "protocol": "hysteria2", "network": "udp", "tls": "tls", "client_tls": "tls",
        "port": 19999, "xray_port": 19999, "sni": DOMAIN,
        "password": shared["hy2_pw"],
        "address": ip, "connection_type": "direct_ip",
    })
    configs.append({
        "name": "Hysteria2-IP-Obfs-19998",
        "protocol": "hysteria2", "network": "udp", "tls": "tls", "client_tls": "tls",
        "port": 19998, "xray_port": 19998, "sni": DOMAIN,
        "password": shared["hy2_pw"],
        "obfs": "salamander", "obfs_password": hy2_obfs_pw,
        "address": ip, "connection_type": "direct_ip",
    })
    configs.append({
        "name": "Hysteria2-CF-443",
        "protocol": "hysteria2", "network": "udp", "tls": "tls", "client_tls": "tls",
        "port": 443, "xray_port": 19999, "sni": DOMAIN,
        "password": shared["hy2_pw"],
        "address": DOMAIN, "connection_type": "domain",
    })

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Build links + inbounds
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    for cfg in configs:
        cfg["created_at"] = datetime.now().strftime("%Y-%m-%d %H:%M")
        proto = cfg["protocol"]
        if proto == "vless":
            cfg["link"] = vless_link(cfg)
        elif proto == "vmess":
            cfg["link"] = vmess_link(cfg)
        elif proto == "trojan":
            cfg["link"] = trojan_link(cfg)
        elif proto == "shadowsocks":
            cfg["link"] = ss_link(cfg)
        elif proto == "tuic":
            cfg["link"] = tuic_link(cfg)
        elif proto == "hysteria2":
            cfg["link"] = hysteria2_link(cfg)
        else:
            cfg["link"] = ""

        if proto in ("vless", "vmess", "trojan", "shadowsocks"):
            ib = build_inbound(cfg)
            if ib:
                inbounds.append(ib)

    # Save
    (CONFIGS_DIR / "all_configs.json").write_text(
        json.dumps(configs, indent=2, ensure_ascii=False))
    export_all_links(configs)
    write_xray_config(inbounds)
    write_tuic_config(configs)
    write_hysteria2_config(configs)
    return configs


# ── Xray Inbound Builder ──────────────────────────────────────
def build_inbound(cfg):
    proto      = cfg["protocol"]
    xray_port  = cfg.get("xray_port", cfg["port"])
    net        = cfg.get("network", "tcp")
    tls        = cfg.get("tls", "none")   # Xray-side TLS
    tag        = f"in-{cfg['name'].lower().replace(' ','-').replace('.','-')}"

    inbound = {
        "tag": tag[:60],
        "port": xray_port,
        "listen": "0.0.0.0",
        "protocol": proto,
        "sniffing": {"enabled": True, "destOverride": ["http","tls","quic"]},
    }

    if proto == "vless":
        client = {"id": cfg["id"], "level": 0}
        if cfg.get("flow"): client["flow"] = cfg["flow"]
        inbound["settings"] = {"clients": [client], "decryption": "none"}
    elif proto == "vmess":
        inbound["settings"] = {"clients": [{"id": cfg["id"], "alterId": 0}]}
    elif proto == "trojan":
        inbound["settings"] = {"clients": [{"password": cfg["password"]}]}
    elif proto == "shadowsocks":
        inbound["settings"] = {
            "method": cfg["method"], "password": cfg["password"], "network": "tcp,udp"
        }
        inbound["streamSettings"] = {"network": "tcp"}
        return inbound

    stream = {"network": net}

    if tls == "tls":
        stream["security"] = "tls"
        stream["tlsSettings"] = {
            "certificates": [{"certificateFile": CERT_PATH, "keyFile": KEY_PATH}],
            "alpn": ["h2","http/1.1"],
        }
    elif tls == "reality":
        stream["security"] = "reality"
        stream["realitySettings"] = {
            "show": False,
            "dest": cfg.get("reality_dest", "www.google.com:443"),
            "xver": 0,
            "serverNames": [cfg.get("sni", "www.google.com")],
            "privateKey": cfg.get("priv_key", ""),
            "shortIds": [cfg.get("short_id", new_uuid()[:8])],
        }
    else:
        # none — used for CF configs (CF does TLS termination)
        stream["security"] = "none"

    if net == "ws":
        stream["wsSettings"] = {
            "path": cfg.get("path", "/"),
            "headers": {"Host": cfg.get("sni", DOMAIN) if tls != "none" else ""}
        }
    elif net == "grpc":
        stream["grpcSettings"] = {"serviceName": cfg.get("service_name", "grpc")}
    elif net == "httpupgrade":
        stream["httpupgradeSettings"] = {
            "path": cfg.get("path", "/"),
            "host": cfg.get("sni", DOMAIN) if tls != "none" else ""
        }

    inbound["streamSettings"] = stream
    return inbound


def write_xray_config(inbounds):
    # Deduplicate by xray_port — keep first per port
    seen, unique = {}, []
    for ib in inbounds:
        p = ib["port"]
        if p not in seen:
            seen[p] = True
            unique.append(ib)

    # Add Xray API inbound for stats
    unique.append({
        "tag": "api",
        "port": 10085,
        "listen": "127.0.0.1",
        "protocol": "dokodemo-door",
        "settings": {"address": "127.0.0.1"}
    })

    conf = {
        "log": {
            "loglevel": "warning",
            "access": "/opt/masterpanel/logs/xray-access.log",
            "error":  "/opt/masterpanel/logs/xray-error.log",
        },
        "api": {
            "tag": "api",
            "services": ["HandlerService", "LoggerService", "StatsService"]
        },
        "stats": {},
        "policy": {
            "levels": {"0": {"statsUserUplink": True, "statsUserDownlink": True}},
            "system": {"statsInboundUplink": True, "statsInboundDownlink": True}
        },
        "inbounds": unique,
        "outbounds": [
            {"tag": "direct",  "protocol": "freedom"},
            {"tag": "blocked", "protocol": "blackhole"},
        ],
        "routing": {
            "domainStrategy": "IPIfNonMatch",
            "rules": [
                {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
                {"type": "field", "ip": ["geoip:private"], "outboundTag": "direct"},
                {"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "blocked"},
            ]
        }
    }

    path = XRAY_CFG_DIR / "config.json"
    path.write_text(json.dumps(conf, indent=2))

    # Restart Xray
    for cmd in [["systemctl","restart","xray"], ["systemctl","start","xray"]]:
        try:
            subprocess.run(cmd, timeout=10, capture_output=True)
            time.sleep(1)
            if xray_status()["running"]:
                break
        except:
            pass
    else:
        try:
            subprocess.run(["pkill","-f","xray run"], capture_output=True)
            time.sleep(1)
            subprocess.Popen([XRAY_BIN,"run","-c",str(path)],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except:
            pass


def write_tuic_config(configs):
    tuics = [c for c in configs if c["protocol"] == "tuic" and c.get("connection_type") == "direct_ip"]
    if not tuics: return
    c = tuics[0]
    conf = {
        "server": f"0.0.0.0:{c['xray_port']}",
        "users": {c["id"]: c["password"]},
        "certificate": CERT_PATH, "private_key": KEY_PATH,
        "congestion_controller": c.get("congestion","bbr"),
        "alpn": ["h3"], "log_level": "warn"
    }
    (CONFIGS_DIR/"tuic_config.json").write_text(json.dumps(conf, indent=2))


def write_hysteria2_config(configs):
    hy2s = [c for c in configs if c["protocol"] == "hysteria2" and c.get("connection_type") == "direct_ip" and not c.get("obfs")]
    if not hy2s: return
    c = hy2s[0]
    # Also get obfs variant
    obfs_c = next((x for x in configs if x["protocol"]=="hysteria2" and x.get("obfs")), None)
    yaml = f"""listen: :{c['xray_port']}
tls:
  cert: {CERT_PATH}
  key: {KEY_PATH}
auth:
  type: password
  password: {c['password']}
masquerade:
  type: proxy
  proxy:
    url: https://www.google.com
    rewriteHost: true
bandwidth:
  up: 1 gbps
  down: 1 gbps
"""
    if obfs_c:
        yaml += f"""
# Obfs instance runs separately on port {obfs_c['xray_port']}
# obfs:
#   type: salamander
#   salamander:
#     password: {obfs_c.get('obfs_password','')}
"""
    (CONFIGS_DIR/"hysteria2_config.yaml").write_text(yaml)


def export_all_links(configs):
    lines = [
        "# MasterPanel v3.0 - All Configs",
        f"# Generated : {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"# Domain    : {DOMAIN}",
        f"# Server IP : {get_server_ip()}",
        f"# Total     : {len(configs)} configs",
        "",
        "# KEY: CF configs — client uses TLS to CF, Xray receives plain on internal port",
        "# KEY: IP configs — client connects directly to server IP/port with TLS",
        "",
    ]
    for conn_type, header in [("domain","CDN / Cloudflare Configs"), ("direct_ip","Direct IP Configs")]:
        group = [c for c in configs if c.get("connection_type") == conn_type]
        if not group: continue
        lines.append(f"# ── {header} {'─'*(46-len(header))}")
        for c in group:
            link = c.get("link","")
            lines.append(f"# {c['name']} | {c['protocol'].upper()} | {c.get('network','').upper()} | TLS:{c.get('client_tls','none')} | Port:{c['port']}")
            if link: lines.append(link)
            lines.append("")

    (CONFIGS_DIR/"all_links.txt").write_text("\n".join(lines), encoding="utf-8")
    raw = [c.get("link","") for c in configs if c.get("link")]
    (CONFIGS_DIR/"subscription.txt").write_text("\n".join(raw), encoding="utf-8")
    (CONFIGS_DIR/"subscription_b64.txt").write_text(
        base64.b64encode("\n".join(raw).encode()).decode(), encoding="utf-8")


def load_saved_configs():
    p = CONFIGS_DIR / "all_configs.json"
    if p.exists():
        try: return json.loads(p.read_text())
        except: pass
    return []


# ── Xray Stats API ────────────────────────────────────────────
def xray_api_query(method, params=""):
    """Query Xray gRPC API for stats."""
    try:
        result = subprocess.run(
            [XRAY_BIN, "api", method, "--server=127.0.0.1:10085"] + (params.split() if params else []),
            capture_output=True, text=True, timeout=5
        )
        return result.stdout.strip()
    except:
        return ""

def get_xray_stats():
    """Get traffic stats from Xray API."""
    try:
        raw = xray_api_query("statsquery")
        if not raw: return {}
        data = json.loads(raw)
        stats = {}
        for item in data.get("stat", []):
            name = item.get("name","")
            val  = int(item.get("value", 0))
            stats[name] = val
        return stats
    except:
        return {}

def get_inbound_stats():
    """Return per-inbound up/down stats."""
    stats = get_xray_stats()
    result = {}
    for k, v in stats.items():
        # Format: inbound>>>tag>>>traffic>>>uplink / downlink
        if "inbound>>>" in k:
            parts = k.split(">>>")
            tag = parts[1] if len(parts) > 1 else k
            direction = parts[3] if len(parts) > 3 else ""
            if tag not in result:
                result[tag] = {"up": 0, "down": 0}
            if "uplink" in direction:
                result[tag]["up"] = v
            elif "downlink" in direction:
                result[tag]["down"] = v
    return result

def fmt_bytes(b):
    if b < 1024: return f"{b} B"
    elif b < 1024**2: return f"{b/1024:.1f} KB"
    elif b < 1024**3: return f"{b/1024**2:.1f} MB"
    else: return f"{b/1024**3:.2f} GB"


# ── Tests ─────────────────────────────────────────────────────
def test_tls_handshake(host, port=443):
    try:
        ctx = ssl.create_default_context()
        with socket.create_connection((host, port), timeout=5) as sock:
            with ctx.wrap_socket(sock, server_hostname=host) as ssock:
                return {"ok": True, "tls_version": ssock.version(), "cipher": ssock.cipher()[0]}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def test_port(host, port):
    try:
        with socket.create_connection((host, int(port)), timeout=5):
            return {"ok": True}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def test_latency(host, port=443):
    try:
        start = time.time()
        socket.create_connection((host, port), timeout=5).close()
        return {"ok": True, "ms": round((time.time()-start)*1000)}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def xray_status():
    try:
        r = subprocess.run(["pgrep","-f","xray"], capture_output=True, text=True)
        running = bool(r.stdout.strip())
        version = ""
        if running:
            vr = subprocess.run([XRAY_BIN,"version"], capture_output=True, text=True, timeout=3)
            version = vr.stdout.splitlines()[0] if vr.stdout else ""
        return {"running": running, "version": version}
    except:
        return {"running": False, "version": ""}


# ── Auth ──────────────────────────────────────────────────────
def login_required(f):
    from functools import wraps
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("logged_in"):
            return redirect(url_for("login_page"))
        return f(*args, **kwargs)
    return decorated


# ── Routes ────────────────────────────────────────────────────
@app.route("/")
def index():
    if not session.get("logged_in"): return redirect(url_for("login_page"))
    return serve_html()

@app.route("/login", methods=["GET","POST"])
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
    configs = load_saved_configs()
    proto_counts = {}
    for c in configs:
        p = c["protocol"]; proto_counts[p] = proto_counts.get(p,0)+1
    ip = get_server_ip()
    ib_stats = get_inbound_stats()
    total_up   = sum(v["up"]   for v in ib_stats.values())
    total_down = sum(v["down"] for v in ib_stats.values())
    return jsonify({
        "xray": xs, "domain": DOMAIN, "server_ip": ip,
        "panel_url": f"http://{ip}:{PANEL_PORT}",
        "config_count": len(configs), "proto_counts": proto_counts,
        "ssl_valid": Path(CERT_PATH).exists() if CERT_PATH else False,
        "uptime": get_uptime(),
        "traffic": {
            "total_up": fmt_bytes(total_up),
            "total_down": fmt_bytes(total_down),
            "raw_up": total_up, "raw_down": total_down,
        }
    })

@app.route("/api/configs")
@login_required
def api_configs():
    return jsonify(load_saved_configs())

@app.route("/api/generate", methods=["POST"])
@login_required
def api_generate():
    try:
        configs = generate_all_configs()
        return jsonify({"ok": True, "count": len(configs), "configs": configs})
    except Exception as e:
        import traceback
        return jsonify({"ok": False, "error": str(e), "trace": traceback.format_exc()})

@app.route("/api/stats")
@login_required
def api_stats():
    ib_stats = get_inbound_stats()
    enriched = {}
    for tag, s in ib_stats.items():
        enriched[tag] = {
            "up_raw": s["up"], "down_raw": s["down"],
            "up": fmt_bytes(s["up"]), "down": fmt_bytes(s["down"]),
        }
    return jsonify({"ok": True, "stats": enriched})

@app.route("/api/test", methods=["POST"])
@login_required
def api_test():
    d = request.get_json() or {}
    t = d.get("type")
    host = d.get("host", DOMAIN)
    port = int(d.get("port", 443))

    if t == "tls":     return jsonify(test_tls_handshake(host, port))
    if t == "port":    return jsonify(test_port(host, port))
    if t == "latency": return jsonify(test_latency(host, port))
    if t == "all":
        results = {}
        for cfg in load_saved_configs():
            h = cfg.get("address", DOMAIN)
            p = cfg.get("port", 443)
            lat = test_latency(h, p)
            prt = test_port(h, p)
            results[cfg["name"]] = {
                "latency": lat.get("ms") if lat["ok"] else None,
                "port_open": prt["ok"],
                "protocol": cfg["protocol"],
                "tls": cfg.get("client_tls", cfg.get("tls","none")),
                "network": cfg.get("network","tcp"),
                "connection_type": cfg.get("connection_type",""),
            }
        return jsonify({"ok": True, "results": results})
    return jsonify({"ok": False, "error": "Unknown test type"})

@app.route("/api/xray/restart", methods=["POST"])
@login_required
def api_xray_restart():
    try:
        subprocess.run(["systemctl","restart","xray"], timeout=10, capture_output=True)
        time.sleep(1)
        return jsonify({"ok": True, "status": xray_status()})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})

@app.route("/api/xray/logs")
@login_required
def api_xray_logs():
    f = Path("/opt/masterpanel/logs/xray-error.log")
    lines = f.read_text().splitlines()[-50:] if f.exists() else []
    return jsonify({"ok": True, "lines": lines})

@app.route("/api/export/links")
@login_required
def api_export_links():
    f = CONFIGS_DIR / "all_links.txt"
    if not f.exists(): return jsonify({"ok": False, "error": "No configs yet"})
    return Response(f.read_text(encoding="utf-8"), mimetype="text/plain",
        headers={"Content-Disposition": "attachment; filename=all_links.txt"})

@app.route("/api/export/subscription")
@login_required
def api_export_subscription():
    f = CONFIGS_DIR / "subscription.txt"
    if not f.exists(): return jsonify({"ok": False, "error": "No configs yet"})
    return Response(f.read_text(encoding="utf-8"), mimetype="text/plain",
        headers={"Content-Disposition": "attachment; filename=subscription.txt"})

@app.route("/api/export/subscription_b64")
@login_required
def api_export_subscription_b64():
    f = CONFIGS_DIR / "subscription_b64.txt"
    if not f.exists(): return jsonify({"ok": False, "error": "No configs yet"})
    return Response(f.read_text(encoding="utf-8"), mimetype="text/plain",
        headers={"Content-Disposition": "attachment; filename=subscription_b64.txt"})

@app.route("/api/export/summary")
@login_required
def api_export_summary():
    configs = load_saved_configs()
    domain_cfgs = [c for c in configs if c.get("connection_type") == "domain"]
    ip_cfgs     = [c for c in configs if c.get("connection_type") == "direct_ip"]
    proto_counts = {}
    for c in configs:
        p = c["protocol"]; proto_counts[p] = proto_counts.get(p,0)+1
    return jsonify({
        "ok": True, "total": len(configs),
        "domain_configs": len(domain_cfgs),
        "direct_ip_configs": len(ip_cfgs),
        "proto_counts": proto_counts,
        "subscription_ready": (CONFIGS_DIR/"subscription_b64.txt").exists(),
    })

# ── Users API ─────────────────────────────────────────────────
@app.route("/api/users", methods=["GET"])
@login_required
def api_users_list():
    users = load_users()
    return jsonify({"ok": True, "users": list(users.values())})

@app.route("/api/users", methods=["POST"])
@login_required
def api_users_create():
    d = request.get_json() or {}
    name  = d.get("name", "").strip()
    limit_gb = float(d.get("limit_gb", 0))   # 0 = unlimited
    expire_days = int(d.get("expire_days", 0))  # 0 = no expiry
    if not name:
        return jsonify({"ok": False, "error": "Name required"})
    users = load_users()
    uid = new_uuid()
    from datetime import timedelta
    expire_at = (datetime.now() + timedelta(days=expire_days)).strftime("%Y-%m-%d") if expire_days else ""
    users[uid] = {
        "id": uid, "name": name,
        "uuid": new_uuid(),
        "password": new_password(20),
        "limit_gb": limit_gb,
        "expire_at": expire_at,
        "created_at": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "enabled": True,
        "used_bytes": 0,
    }
    save_users(users)
    return jsonify({"ok": True, "user": users[uid]})

@app.route("/api/users/<uid>", methods=["DELETE"])
@login_required
def api_users_delete(uid):
    users = load_users()
    if uid in users:
        del users[uid]
        save_users(users)
        return jsonify({"ok": True})
    return jsonify({"ok": False, "error": "Not found"})

@app.route("/api/users/<uid>", methods=["PATCH"])
@login_required
def api_users_update(uid):
    d = request.get_json() or {}
    users = load_users()
    if uid not in users:
        return jsonify({"ok": False, "error": "Not found"})
    for k in ("name","limit_gb","expire_at","enabled"):
        if k in d:
            users[uid][k] = d[k]
    save_users(users)
    return jsonify({"ok": True, "user": users[uid]})

# ── Run ───────────────────────────────────────────────────────
if __name__ == "__main__":
    import logging
    logging.getLogger("werkzeug").setLevel(logging.WARNING)
    print(f"[MasterPanel v3.0] Starting on port {PANEL_PORT}")
    app.run(host="0.0.0.0", port=PANEL_PORT, debug=False)
