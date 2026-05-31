#!/usr/bin/env python3
"""
MasterPanel - Xray Auto Protocol Configurator
Backend Server v2.0
Protocols: VLESS, VMess, Trojan, Shadowsocks, TUIC, Hysteria2, ShadowTLS, NaiveProxy, WireGuard
"""

import os, json, uuid, subprocess, socket, ssl, time, base64, urllib.parse, secrets, string
from datetime import datetime
from pathlib import Path
from flask import Flask, request, jsonify, session, redirect, url_for, Response

app = Flask(__name__, static_folder=None)
_SF = Path("/opt/masterpanel/.secret_key")
Path("/opt/masterpanel").mkdir(exist_ok=True)
if _SF.exists():
    app.secret_key = _SF.read_bytes()
else:
    _k = secrets.token_bytes(32); _SF.write_bytes(_k); _SF.chmod(0o600)
    app.secret_key = _k

# ── Load config ───────────────────────────────────────────────
PANEL_DIR    = Path("/opt/masterpanel")
CONF_FILE    = PANEL_DIR / "panel.conf"

def load_conf():
    conf = {}
    if CONF_FILE.exists():
        for line in CONF_FILE.read_text().splitlines():
            if "=" in line:
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
CONFIGS_DIR.mkdir(exist_ok=True)
XRAY_CFG_DIR.mkdir(parents=True, exist_ok=True)
USERS_FILE   = PANEL_DIR / "configs" / "users.json"
CURRENT_VERSION = "3.5.0"
GITHUB_RAW   = "https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main"

def serve_html():
    p = PANEL_DIR / "templates" / "index.html"
    if p.exists(): return p.read_text(encoding="utf-8"), 200, {"Content-Type":"text/html; charset=utf-8"}
    return "<h1>index.html not found</h1>", 404

def load_users():
    if USERS_FILE.exists():
        try: return json.loads(USERS_FILE.read_text())
        except: pass
    return {}

def save_users(u): USERS_FILE.write_text(json.dumps(u, indent=2, ensure_ascii=False))

# ── Helpers ───────────────────────────────────────────────────
def new_uuid():
    return str(uuid.uuid4())

def new_password(length=16):
    chars = string.ascii_letters + string.digits
    return ''.join(secrets.choice(chars) for _ in range(length))

def get_server_ip():
    """Always return IPv4 address."""
    # Method 1: UDP trick (forces IPv4 route)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and not ip.startswith("127.") and ":" not in ip:
            return ip
    except:
        pass
    # Method 2: external IPv4-only API
    for api in [
        "https://api4.ipify.org",
        "https://ipv4.icanhazip.com",
        "https://v4.ident.me",
    ]:
        try:
            import urllib.request
            req = urllib.request.Request(api, headers={"User-Agent": "curl/7.0"})
            with urllib.request.urlopen(req, timeout=4) as r:
                ip = r.read().decode().strip()
                if ip and ":" not in ip and not ip.startswith("127."):
                    return ip
        except:
            continue
    # Method 3: hostname resolution (prefer A record)
    try:
        results = socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET)
        for r in results:
            ip = r[4][0]
            if not ip.startswith("127."):
                return ip
    except:
        pass
    return "0.0.0.0"

def get_reality_keys():
    try:
        result = subprocess.run([XRAY_BIN, "x25519"], capture_output=True, text=True, timeout=5)
        lines = result.stdout.strip().splitlines()
        priv = lines[0].split(": ")[-1] if lines else ""
        pub  = lines[1].split(": ")[-1] if len(lines) > 1 else ""
        return priv, pub
    except:
        return "", ""

def get_uptime():
    try:
        with open("/proc/uptime") as f:
            secs = float(f.read().split()[0])
        h = int(secs // 3600); m = int((secs % 3600) // 60)
        return f"{h}h {m}m"
    except:
        return "N/A"

# ── Share Link Builders ───────────────────────────────────────
def vless_link(c):
    uid    = c.get("id", "")
    addr   = c.get("address", DOMAIN)
    port   = c.get("port", 443)
    net    = c.get("network", "tcp")
    tls    = c.get("tls", "tls")
    path   = urllib.parse.quote(c.get("path", "/"), safe="")
    sni    = c.get("sni", DOMAIN)
    fp     = c.get("fp", "chrome")
    name   = urllib.parse.quote(c.get("name", "vless"))
    flow   = c.get("flow", "")
    pbk    = c.get("public_key", "")
    sid    = c.get("short_id", "")
    params = f"type={net}&security={tls}&sni={sni}&fp={fp}"
    if net in ("ws", "httpupgrade"):
        params += f"&path={path}"
    if net == "grpc":
        params += f"&serviceName={urllib.parse.quote(c.get('service_name','grpc'))}"
    if flow:
        params += f"&flow={flow}"
    if tls == "reality" and pbk:
        params += f"&pbk={pbk}&sid={sid}"
    return f"vless://{uid}@{addr}:{port}?{params}#{name}"

def vmess_link(c):
    data = {
        "v":"2", "ps": c.get("name",""),
        "add": c.get("address", DOMAIN),
        "port": str(c.get("port", 443)),
        "id": c.get("id",""), "aid":"0", "scy":"auto",
        "net": c.get("network","ws"), "type":"none",
        "host": c.get("sni", DOMAIN),
        "path": c.get("path","/"),
        "tls": "tls" if c.get("tls") == "tls" else "",
        "sni": c.get("sni", DOMAIN),
        "fp": c.get("fp","chrome"),
    }
    if c.get("network") == "grpc":
        data["path"] = c.get("service_name","grpc")
    return "vmess://" + base64.b64encode(json.dumps(data).encode()).decode()

def trojan_link(c):
    pw   = c.get("password","")
    addr = c.get("address", DOMAIN)
    port = c.get("port", 443)
    net  = c.get("network","tcp")
    sni  = c.get("sni", DOMAIN)
    fp   = c.get("fp","chrome")
    path = urllib.parse.quote(c.get("path","/"), safe="")
    name = urllib.parse.quote(c.get("name","trojan"))
    params = f"type={net}&security=tls&sni={sni}&fp={fp}"
    if net in ("ws","httpupgrade"):
        params += f"&path={path}"
    if net == "grpc":
        params += f"&serviceName={urllib.parse.quote(c.get('service_name','grpc'))}"
    return f"trojan://{pw}@{addr}:{port}?{params}#{name}"

def ss_link(c):
    method   = c.get("method","chacha20-ietf-poly1305")
    password = c.get("password","")
    addr     = c.get("address", DOMAIN)
    port     = c.get("port", 8388)
    name     = urllib.parse.quote(c.get("name","ss"))
    userinfo = base64.b64encode(f"{method}:{password}".encode()).decode()
    return f"ss://{userinfo}@{addr}:{port}#{name}"

def tuic_link(c):
    uid  = c.get("id","")
    pw   = c.get("password","")
    addr = c.get("address", DOMAIN)
    port = c.get("port", 443)
    sni  = c.get("sni", DOMAIN)
    name = urllib.parse.quote(c.get("name","tuic"))
    return f"tuic://{uid}:{pw}@{addr}:{port}?sni={sni}&congestion_control=bbr&alpn=h3#{name}"

def hysteria2_link(c):
    pw   = c.get("password","")
    addr = c.get("address", DOMAIN)
    port = c.get("port", 443)
    sni  = c.get("sni", DOMAIN)
    name = urllib.parse.quote(c.get("name","hy2"))
    obfs = c.get("obfs","")
    obfs_pw = c.get("obfs_password","")
    params = f"sni={sni}"
    if obfs:
        params += f"&obfs={obfs}&obfs-password={obfs_pw}"
    return f"hysteria2://{pw}@{addr}:{port}?{params}#{name}"

# ── Config Generator ──────────────────────────────────────────
def generate_all_configs():
    configs  = []
    ip       = get_server_ip()
    inbounds = []

    # ── Shared credentials ────────────────────────────────────
    shared = {
        "vless_id":     new_uuid(),
        "vmess_id":     new_uuid(),
        "trojan_pw":    new_password(20),
        "tuic_id":      new_uuid(),
        "tuic_pw":      new_password(16),
        "hy2_pw":       new_password(20),
        "ss_pw_chacha": new_password(16),
        "ss_pw_aes":    new_password(16),
        "ss_pw_stls":   new_password(16),
        "wg_pk":        new_password(32),
    }

    # Reality keys (one set per dest)
    reality_dests = [
        {"dest": "www.google.com:443",    "sni": "www.google.com",    "fp": "chrome"},
        {"dest": "www.apple.com:443",     "sni": "www.apple.com",     "fp": "safari"},
        {"dest": "discord.com:443",       "sni": "discord.com",       "fp": "firefox"},
        {"dest": "cdn.jsdelivr.net:443",  "sni": "cdn.jsdelivr.net",  "fp": "chrome"},
    ]
    for rd in reality_dests:
        priv, pub = get_reality_keys()
        rd["priv_key"] = priv
        rd["pub_key"]  = pub
        rd["short_id"] = new_uuid()[:8]

    # CF-supported HTTPS ports
    cf_ports = [443, 2053, 2083, 2087, 2096, 8443]

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # VLESS — Domain / CDN
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    for port in cf_ports:
        configs.append({
            "name": f"VLESS-WS-TLS-CF-{port}",
            "protocol": "vless", "network": "ws", "tls": "tls",
            "port": port, "path": "/vless-ws", "sni": DOMAIN,
            "fp": "chrome", "address": DOMAIN, "id": shared["vless_id"],
            "connection_type": "domain",
        })

    configs.append({
        "name": "VLESS-gRPC-TLS-CF",
        "protocol": "vless", "network": "grpc", "tls": "tls",
        "port": 443, "service_name": "vless-grpc", "sni": DOMAIN,
        "fp": "chrome", "address": DOMAIN, "id": shared["vless_id"],
        "connection_type": "domain",
    })

    configs.append({
        "name": "VLESS-HTTPUpgrade-TLS-CF",
        "protocol": "vless", "network": "httpupgrade", "tls": "tls",
        "port": 8443, "path": "/vless-hu", "sni": DOMAIN,
        "fp": "chrome", "address": DOMAIN, "id": shared["vless_id"],
        "connection_type": "domain",
    })

    # VLESS — Direct IP
    configs.append({
        "name": "VLESS-TCP-TLS-IP",
        "protocol": "vless", "network": "tcp", "tls": "tls",
        "port": 2053, "sni": DOMAIN, "fp": "safari",
        "address": ip, "id": shared["vless_id"],
        "connection_type": "direct_ip",
    })
    configs.append({
        "name": "VLESS-WS-TLS-IP",
        "protocol": "vless", "network": "ws", "tls": "tls",
        "port": 8443, "path": "/vless-ws", "sni": DOMAIN,
        "fp": "chrome", "address": ip, "id": shared["vless_id"],
        "connection_type": "direct_ip",
    })
    configs.append({
        "name": "VLESS-HTTPUpgrade-TLS-IP",
        "protocol": "vless", "network": "httpupgrade", "tls": "tls",
        "port": 2087, "path": "/vless-hu", "sni": DOMAIN,
        "fp": "edge", "address": ip, "id": shared["vless_id"],
        "connection_type": "direct_ip",
    })
    configs.append({
        "name": "VLESS-TCP-NOTLS-IP",
        "protocol": "vless", "network": "tcp", "tls": "none",
        "port": 10086, "sni": "", "fp": "chrome",
        "address": ip, "id": shared["vless_id"],
        "connection_type": "direct_ip",
    })

    # VLESS + REALITY — 4 different destinations
    for i, rd in enumerate(reality_dests):
        cfg = {
            "name": f"VLESS-REALITY-{rd['sni'].split('.')[1].upper()}-IP",
            "protocol": "vless", "network": "tcp", "tls": "reality",
            "port": 443, "sni": rd["sni"], "fp": rd["fp"],
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
    # VMess — Domain / CDN
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    for port in [443, 2083, 2087, 8443]:
        configs.append({
            "name": f"VMess-WS-TLS-CF-{port}",
            "protocol": "vmess", "network": "ws", "tls": "tls",
            "port": port, "path": "/vmess-ws", "sni": DOMAIN,
            "fp": "chrome", "address": DOMAIN, "id": shared["vmess_id"],
            "connection_type": "domain",
        })

    configs.append({
        "name": "VMess-gRPC-TLS-CF",
        "protocol": "vmess", "network": "grpc", "tls": "tls",
        "port": 443, "service_name": "vmess-grpc", "sni": DOMAIN,
        "fp": "chrome", "address": DOMAIN, "id": shared["vmess_id"],
        "connection_type": "domain",
    })
    configs.append({
        "name": "VMess-HTTPUpgrade-TLS-CF",
        "protocol": "vmess", "network": "httpupgrade", "tls": "tls",
        "port": 2096, "path": "/vmess-hu", "sni": DOMAIN,
        "fp": "firefox", "address": DOMAIN, "id": shared["vmess_id"],
        "connection_type": "domain",
    })

    # VMess — Direct IP
    configs.append({
        "name": "VMess-TCP-TLS-IP",
        "protocol": "vmess", "network": "tcp", "tls": "tls",
        "port": 2053, "sni": DOMAIN, "fp": "safari",
        "address": ip, "id": shared["vmess_id"],
        "connection_type": "direct_ip",
    })
    configs.append({
        "name": "VMess-WS-NOTLS-IP",
        "protocol": "vmess", "network": "ws", "tls": "none",
        "port": 10087, "path": "/vmess-ws", "sni": "",
        "fp": "chrome", "address": ip, "id": shared["vmess_id"],
        "connection_type": "direct_ip",
    })
    configs.append({
        "name": "VMess-HTTPUpgrade-TLS-IP",
        "protocol": "vmess", "network": "httpupgrade", "tls": "tls",
        "port": 2082, "path": "/vmess-hu", "sni": DOMAIN,
        "fp": "edge", "address": ip, "id": shared["vmess_id"],
        "connection_type": "direct_ip",
    })

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Trojan — Domain / CDN
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    for port in [443, 2096, 8443]:
        configs.append({
            "name": f"Trojan-WS-TLS-CF-{port}",
            "protocol": "trojan", "network": "ws", "tls": "tls",
            "port": port, "path": "/trojan-ws", "sni": DOMAIN,
            "fp": "chrome", "address": DOMAIN, "password": shared["trojan_pw"],
            "connection_type": "domain",
        })

    configs.append({
        "name": "Trojan-gRPC-TLS-CF",
        "protocol": "trojan", "network": "grpc", "tls": "tls",
        "port": 443, "service_name": "trojan-grpc", "sni": DOMAIN,
        "fp": "chrome", "address": DOMAIN, "password": shared["trojan_pw"],
        "connection_type": "domain",
    })

    # Trojan — Direct IP
    configs.append({
        "name": "Trojan-TCP-TLS-IP",
        "protocol": "trojan", "network": "tcp", "tls": "tls",
        "port": 2096, "sni": DOMAIN, "fp": "firefox",
        "address": ip, "password": shared["trojan_pw"],
        "connection_type": "direct_ip",
    })
    configs.append({
        "name": "Trojan-WS-TLS-IP",
        "protocol": "trojan", "network": "ws", "tls": "tls",
        "port": 8443, "path": "/trojan-ws", "sni": DOMAIN,
        "fp": "chrome", "address": ip, "password": shared["trojan_pw"],
        "connection_type": "direct_ip",
    })
    configs.append({
        "name": "Trojan-HTTPUpgrade-TLS-IP",
        "protocol": "trojan", "network": "httpupgrade", "tls": "tls",
        "port": 2053, "path": "/trojan-hu", "sni": DOMAIN,
        "fp": "safari", "address": ip, "password": shared["trojan_pw"],
        "connection_type": "direct_ip",
    })

    # Trojan + REALITY
    rd = reality_dests[0]
    configs.append({
        "name": "Trojan-REALITY-IP",
        "protocol": "trojan", "network": "tcp", "tls": "reality",
        "port": 8443, "sni": rd["sni"], "fp": rd["fp"],
        "address": ip, "password": shared["trojan_pw"],
        "reality_dest": rd["dest"],
        "priv_key": rd["priv_key"],
        "public_key": rd["pub_key"],
        "short_id": rd["short_id"],
        "connection_type": "direct_ip",
    })

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Shadowsocks — Direct IP
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    ss_variants = [
        {"name": "SS-chacha20-IP",    "method": "chacha20-ietf-poly1305", "port": 8388, "password": shared["ss_pw_chacha"]},
        {"name": "SS-aes256-IP",      "method": "aes-256-gcm",            "port": 8389, "password": shared["ss_pw_aes"]},
        {"name": "SS-2022-blake3-IP", "method": "2022-blake3-aes-256-gcm","port": 8390, "password": base64.b64encode(secrets.token_bytes(32)).decode()},
    ]
    for sv in ss_variants:
        configs.append({
            "protocol": "shadowsocks", "address": ip,
            "connection_type": "direct_ip", **sv
        })

    # ShadowTLS (SS over fake TLS)
    configs.append({
        "name": "SS-ShadowTLS-IP",
        "protocol": "shadowsocks", "network": "tcp", "tls": "shadowtls",
        "port": 8391, "method": "chacha20-ietf-poly1305",
        "password": shared["ss_pw_stls"],
        "shadowtls_password": new_password(20),
        "shadowtls_sni": "www.apple.com",
        "address": ip, "connection_type": "direct_ip",
        "note": "Requires ShadowTLS wrapper"
    })

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # TUIC v5 — Direct IP + CF ports
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    for port, addr, ctype in [(443, ip, "direct_ip"), (2096, DOMAIN, "domain")]:
        configs.append({
            "name": f"TUIC-v5-{'IP' if ctype=='direct_ip' else 'CF'}-{port}",
            "protocol": "tuic", "network": "udp", "tls": "tls",
            "port": port, "sni": DOMAIN,
            "id": shared["tuic_id"], "password": shared["tuic_pw"],
            "address": addr, "connection_type": ctype,
            "congestion": "bbr",
        })

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Hysteria2 — Direct IP + CF ports
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    configs.append({
        "name": "Hysteria2-IP-443",
        "protocol": "hysteria2", "network": "udp", "tls": "tls",
        "port": 443, "sni": DOMAIN,
        "password": shared["hy2_pw"],
        "address": ip, "connection_type": "direct_ip",
    })
    configs.append({
        "name": "Hysteria2-IP-8443",
        "protocol": "hysteria2", "network": "udp", "tls": "tls",
        "port": 8443, "sni": DOMAIN,
        "password": shared["hy2_pw"],
        "address": ip, "connection_type": "direct_ip",
    })
    configs.append({
        "name": "Hysteria2-IP-Obfs",
        "protocol": "hysteria2", "network": "udp", "tls": "tls",
        "port": 19999, "sni": DOMAIN,
        "password": shared["hy2_pw"],
        "obfs": "salamander", "obfs_password": new_password(16),
        "address": ip, "connection_type": "direct_ip",
    })

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # WireGuard — Direct IP (via Xray outbound style)
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    configs.append({
        "name": "WireGuard-IP-51820",
        "protocol": "wireguard", "network": "udp", "tls": "none",
        "port": 51820, "sni": "",
        "private_key": shared["wg_pk"],
        "address": ip, "connection_type": "direct_ip",
        "note": "Requires WireGuard client config — see panel for details",
    })

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Build links + timestamps
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

        # Build Xray inbound (skip TUIC/HY2/WG — they run as separate processes)
        if proto in ("vless", "vmess", "trojan", "shadowsocks"):
            ib = build_inbound(cfg)
            if ib:
                inbounds.append(ib)

    # Save JSON
    (CONFIGS_DIR / "all_configs.json").write_text(
        json.dumps(configs, indent=2, ensure_ascii=False))

    # Export links
    export_all_links(configs)

    # Write Xray + extra configs
    write_xray_config(inbounds)
    write_tuic_config(configs)
    write_hysteria2_config(configs)

    return configs


# ── Xray Inbound Builder ──────────────────────────────────────
def build_inbound(cfg):
    proto = cfg["protocol"]
    port  = cfg["port"]
    net   = cfg.get("network", "tcp")
    tls   = cfg.get("tls", "none")

    inbound = {
        "tag": f"in-{cfg['name'].lower().replace(' ','-')}",
        "port": port, "listen": "0.0.0.0",
        "protocol": proto,
    }

    if proto == "vless":
        client = {"id": cfg["id"], "level": 0}
        if cfg.get("flow"): client["flow"] = cfg["flow"]
        inbound["settings"] = {"clients": [client], "decryption": "none"}
    elif proto == "vmess":
        inbound["settings"] = {"clients": [{"id": cfg["id"], "level": 0}]}
    elif proto == "trojan":
        inbound["settings"] = {"clients": [{"password": cfg["password"], "level": 0}]}
    elif proto == "shadowsocks":
        inbound["settings"] = {
            "method": cfg["method"], "password": cfg["password"], "network": "tcp,udp"
        }
        inbound["streamSettings"] = {"network": "tcp"}
        return inbound

    # Stream settings
    stream = {"network": net}

    if tls == "tls":
        stream["security"] = "tls"
        stream["tlsSettings"] = {
            "certificates": [{"certificateFile": CERT_PATH, "keyFile": KEY_PATH}],
            "alpn": ["h2", "http/1.1"]
        }
    elif tls == "reality":
        stream["security"] = "reality"
        stream["realitySettings"] = {
            "show": False,
            "dest": cfg.get("reality_dest", "www.google.com:443"),
            "xver": 0,
            "serverNames": [cfg.get("sni","www.google.com")],
            "privateKey": cfg.get("priv_key",""),
            "shortIds": [cfg.get("short_id", new_uuid()[:8])],
        }
    else:
        stream["security"] = "none"

    if net == "ws":
        stream["wsSettings"] = {
            "path": cfg.get("path","/"),
            "headers": {"Host": cfg.get("sni", DOMAIN)}
        }
    elif net == "grpc":
        stream["grpcSettings"] = {"serviceName": cfg.get("service_name","grpc")}
    elif net == "httpupgrade":
        stream["httpupgradeSettings"] = {
            "path": cfg.get("path","/"), "host": cfg.get("sni", DOMAIN)
        }

    inbound["streamSettings"] = stream
    return inbound


def write_xray_config(inbounds):
    # Deduplicate by port — keep first
    seen, unique = {}, []
    for ib in inbounds:
        if ib["port"] not in seen:
            seen[ib["port"]] = True
            unique.append(ib)

    conf = {
        "log": {
            "loglevel": "warning",
            "access": "/opt/masterpanel/logs/xray-access.log",
            "error":  "/opt/masterpanel/logs/xray-error.log"
        },
        "inbounds": unique,
        "outbounds": [
            {"tag": "direct",  "protocol": "freedom"},
            {"tag": "blocked", "protocol": "blackhole"}
        ],
        "routing": {
            "rules": [
                {"type": "field", "ip":     ["geoip:private"],           "outboundTag": "direct"},
                {"type": "field", "domain": ["geosite:category-ads-all"],"outboundTag": "blocked"}
            ]
        }
    }

    path = XRAY_CFG_DIR / "config.json"
    path.write_text(json.dumps(conf, indent=2))

    try:
        subprocess.run(["systemctl","restart","xray"], timeout=10, capture_output=True)
    except:
        try:
            subprocess.run(["pkill","-f","xray"], capture_output=True)
            time.sleep(1)
            subprocess.Popen([XRAY_BIN,"run","-c",str(path)],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except:
            pass


def write_tuic_config(configs):
    """Write TUIC v5 server config file."""
    tuic_cfgs = [c for c in configs if c["protocol"] == "tuic"]
    if not tuic_cfgs:
        return
    c = tuic_cfgs[0]
    conf = {
        "server": f"0.0.0.0:{c['port']}",
        "users": {c["id"]: c["password"]},
        "certificate": CERT_PATH,
        "private_key": KEY_PATH,
        "congestion_controller": c.get("congestion","bbr"),
        "alpn": ["h3"],
        "log_level": "warn"
    }
    (CONFIGS_DIR / "tuic_config.json").write_text(json.dumps(conf, indent=2))


def write_hysteria2_config(configs):
    """Write Hysteria2 server config file."""
    hy2_cfgs = [c for c in configs if c["protocol"] == "hysteria2"]
    if not hy2_cfgs:
        return
    c = hy2_cfgs[0]
    conf = {
        "listen": f":{c['port']}",
        "tls": {"cert": CERT_PATH, "key": KEY_PATH},
        "auth": {"type": "password", "password": c["password"]},
        "masquerade": {"type": "proxy", "proxy": {"url": "https://www.google.com", "rewriteHost": True}},
        "quic": {"initStreamReceiveWindow": 8388608, "maxStreamReceiveWindow": 8388608},
        "bandwidth": {"up": "1 gbps", "down": "1 gbps"},
    }
    if hy2_cfgs[2].get("obfs"):
        conf["obfs"] = {"type": "salamander", "salamander": {"password": hy2_cfgs[2]["obfs_password"]}}
    (CONFIGS_DIR / "hysteria2_config.yaml").write_text(
        f"listen: :{c['port']}\n"
        f"tls:\n  cert: {CERT_PATH}\n  key: {KEY_PATH}\n"
        f"auth:\n  type: password\n  password: {c['password']}\n"
        f"masquerade:\n  type: proxy\n  proxy:\n    url: https://www.google.com\n    rewriteHost: true\n"
    )


def export_all_links(configs):
    lines = [
        "# MasterPanel - All Configs Export",
        f"# Generated : {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"# Domain    : {DOMAIN}",
        f"# Server IP : {get_server_ip()}",
        f"# Total     : {len(configs)} configs",
        "",
    ]
    proto_order = ["vless","vmess","trojan","shadowsocks","tuic","hysteria2","wireguard"]
    for conn_type, header in [("domain","CDN / Domain Configs"), ("direct_ip","Direct IP Configs")]:
        group = [c for c in configs if c.get("connection_type") == conn_type]
        if not group: continue
        lines.append(f"# ── {header} {'─'*(48-len(header))}")
        for proto in proto_order:
            pg = [c for c in group if c["protocol"] == proto]
            for c in pg:
                link = c.get("link","")
                lines.append(
                    f"# {c['name']} | {c['protocol'].upper()} | "
                    f"{c.get('network','tcp').upper()} | TLS:{c.get('tls','none')} | Port:{c['port']}"
                )
                if link:
                    lines.append(link)
                if c.get("note"):
                    lines.append(f"# NOTE: {c['note']}")
                lines.append("")

    (CONFIGS_DIR / "all_links.txt").write_text("\n".join(lines), encoding="utf-8")

    raw = [c.get("link","") for c in configs if c.get("link")]
    (CONFIGS_DIR / "subscription.txt").write_text("\n".join(raw), encoding="utf-8")
    (CONFIGS_DIR / "subscription_b64.txt").write_text(
        base64.b64encode("\n".join(raw).encode()).decode(), encoding="utf-8")


def load_saved_configs():
    p = CONFIGS_DIR / "all_configs.json"
    if p.exists():
        try: return json.loads(p.read_text())
        except: pass
    return []

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

# ── Auth decorator ────────────────────────────────────────────
def login_required(f):
    from functools import wraps
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("logged_in"):
            if request.path.startswith("/api/"):
                return jsonify({"ok":False,"error":"Unauthorized"}), 401
            return redirect(url_for("login_page"))
        return f(*args, **kwargs)
    return decorated

# ── Routes ────────────────────────────────────────────────────
def serve_html():
    """Serve index.html as plain file — bypass Jinja2 to avoid template conflicts."""
    html_path = PANEL_DIR / "templates" / "index.html"
    if html_path.exists():
        return html_path.read_text(encoding="utf-8"), 200, {"Content-Type": "text/html; charset=utf-8"}
    return "<h1>index.html not found</h1>", 404

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
        p = c["protocol"]
        proto_counts[p] = proto_counts.get(p,0) + 1
    ip = get_server_ip()
    return jsonify({
        "xray": xs, "domain": DOMAIN, "server_ip": ip,
        "panel_url": f"http://{ip}:{PANEL_PORT}",
        "config_count": len(configs), "proto_counts": proto_counts,
        "ssl_valid": Path(CERT_PATH).exists() if CERT_PATH else False,
        "uptime": get_uptime(),
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
        return jsonify({"ok": False, "error": str(e)})

@app.route("/api/test", methods=["POST"])
@login_required
def api_test():
    d = request.get_json() or {}
    t = d.get("type")
    host = d.get("host", DOMAIN)
    port = d.get("port", 443)

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
                "tls": cfg.get("tls","none"),
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

@app.route("/api/extra_configs")
@login_required
def api_extra_configs():
    """Return paths to TUIC/HY2 config files for display."""
    result = {}
    for name, fname in [("tuic","tuic_config.json"),("hysteria2","hysteria2_config.yaml")]:
        f = CONFIGS_DIR / fname
        result[name] = f.read_text() if f.exists() else None
    return jsonify({"ok": True, "configs": result})

# ── Users API ─────────────────────────────────────────────────
@app.route("/api/users", methods=["GET"])
@login_required
def api_users_list():
    return jsonify({"ok":True, "users":list(load_users().values())})

@app.route("/api/users", methods=["POST"])
@login_required
def api_users_create():
    d = request.get_json() or {}
    name = d.get("name","").strip()
    if not name: return jsonify({"ok":False,"error":"Name required"})
    from datetime import timedelta
    users = load_users(); uid = new_uuid()
    expire_days = int(d.get("expire_days",0))
    users[uid] = {
        "id":uid,"name":name,"uuid":new_uuid(),"password":new_password(20),
        "limit_gb":float(d.get("limit_gb",0)),
        "expire_at":(datetime.now()+timedelta(days=expire_days)).strftime("%Y-%m-%d") if expire_days else "",
        "created_at":datetime.now().strftime("%Y-%m-%d %H:%M"),
        "enabled":True,"used_bytes":0,"configs":[]
    }
    save_users(users)
    return jsonify({"ok":True,"user":users[uid]})

@app.route("/api/users/<uid>", methods=["DELETE"])
@login_required
def api_users_delete(uid):
    users = load_users()
    if uid in users: del users[uid]; save_users(users)
    return jsonify({"ok":True})

@app.route("/api/users/<uid>", methods=["PATCH"])
@login_required
def api_users_update(uid):
    d = request.get_json() or {}
    users = load_users()
    if uid not in users: return jsonify({"ok":False,"error":"Not found"})
    for k in ("name","limit_gb","expire_at","enabled"):
        if k in d: users[uid][k] = d[k]
    save_users(users)
    return jsonify({"ok":True,"user":users[uid]})

@app.route("/api/users/<uid>/generate", methods=["POST"])
@login_required
def api_user_generate(uid):
    """Call generate_all_configs with user UUID/pass — EXACT same logic as working version."""
    users = load_users()
    if uid not in users: return jsonify({"ok":False,"error":"User not found"})
    user = users[uid]

    # Save original shared credentials
    orig_configs = load_saved_configs()

    # Generate using user's own credentials via generate_all_configs logic
    # We do this by temporarily calling the same build functions
    ip = get_server_ip()
    configs = []; inbounds = []
    u_uuid = user["uuid"]
    u_pass = user["password"]
    sfx = f"-{user['name']}"
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")

    reality_dests = [
        {"dest":"www.google.com:443","sni":"www.google.com","fp":"chrome"},
        {"dest":"www.apple.com:443","sni":"www.apple.com","fp":"safari"},
        {"dest":"discord.com:443","sni":"discord.com","fp":"firefox"},
        {"dest":"cdn.jsdelivr.net:443","sni":"cdn.jsdelivr.net","fp":"chrome"},
    ]
    for rd in reality_dests:
        priv,pub = get_reality_keys()
        rd["priv_key"]=priv; rd["pub_key"]=pub; rd["short_id"]=new_uuid()[:8]

    cf_ports = [443,2053,2083,2087,2096,8443]

    def add(name,proto,**kw):
        cfg={"name":name,"protocol":proto,"created_at":ts,**kw}
        if proto=="vless":         cfg["link"]=vless_link(cfg)
        elif proto=="vmess":       cfg["link"]=vmess_link(cfg)
        elif proto=="trojan":      cfg["link"]=trojan_link(cfg)
        elif proto=="shadowsocks": cfg["link"]=ss_link(cfg)
        elif proto=="tuic":        cfg["link"]=tuic_link(cfg)
        elif proto=="hysteria2":   cfg["link"]=hysteria2_link(cfg)
        else: cfg["link"]=""
        configs.append(cfg)
        if proto in ("vless","vmess","trojan","shadowsocks"):
            ib=build_inbound(cfg)
            if ib: inbounds.append(ib)

    # VLESS CF
    for p in cf_ports:
        add(f"VLESS-WS-TLS-CF-{p}{sfx}","vless",network="ws",tls="tls",port=p,path="/vless-ws",sni=DOMAIN,fp="chrome",address=DOMAIN,id=u_uuid,connection_type="domain")
    add(f"VLESS-gRPC-CF{sfx}","vless",network="grpc",tls="tls",port=443,service_name="vless-grpc",sni=DOMAIN,fp="chrome",address=DOMAIN,id=u_uuid,connection_type="domain")
    add(f"VLESS-HTTPUpgrade-CF{sfx}","vless",network="httpupgrade",tls="tls",port=8443,path="/vless-hu",sni=DOMAIN,fp="chrome",address=DOMAIN,id=u_uuid,connection_type="domain")
    # VLESS IP
    add(f"VLESS-TCP-TLS-IP{sfx}","vless",network="tcp",tls="tls",port=2053,sni=DOMAIN,fp="safari",address=ip,id=u_uuid,connection_type="direct_ip")
    add(f"VLESS-WS-TLS-IP{sfx}","vless",network="ws",tls="tls",port=8443,path="/vless-ws",sni=DOMAIN,fp="chrome",address=ip,id=u_uuid,connection_type="direct_ip")
    add(f"VLESS-HTTPUpgrade-IP{sfx}","vless",network="httpupgrade",tls="tls",port=2087,path="/vless-hu",sni=DOMAIN,fp="edge",address=ip,id=u_uuid,connection_type="direct_ip")
    add(f"VLESS-TCP-NOTLS-IP{sfx}","vless",network="tcp",tls="none",port=10086,sni="",fp="chrome",address=ip,id=u_uuid,connection_type="direct_ip")
    # VLESS REALITY
    for rd in reality_dests:
        lbl=rd["sni"].split(".")[1].upper()
        add(f"VLESS-REALITY-{lbl}{sfx}","vless",network="tcp",tls="reality",port=443,sni=rd["sni"],fp=rd["fp"],flow="xtls-rprx-vision",address=ip,id=u_uuid,reality_dest=rd["dest"],priv_key=rd["priv_key"],public_key=rd["pub_key"],short_id=rd["short_id"],connection_type="direct_ip")
    # VMess CF
    for p in [443,2083,2087,8443]:
        add(f"VMess-WS-TLS-CF-{p}{sfx}","vmess",network="ws",tls="tls",port=p,path="/vmess-ws",sni=DOMAIN,fp="chrome",address=DOMAIN,id=u_uuid,connection_type="domain")
    add(f"VMess-gRPC-CF{sfx}","vmess",network="grpc",tls="tls",port=443,service_name="vmess-grpc",sni=DOMAIN,fp="chrome",address=DOMAIN,id=u_uuid,connection_type="domain")
    add(f"VMess-HTTPUpgrade-CF{sfx}","vmess",network="httpupgrade",tls="tls",port=2096,path="/vmess-hu",sni=DOMAIN,fp="firefox",address=DOMAIN,id=u_uuid,connection_type="domain")
    # VMess IP
    add(f"VMess-TCP-TLS-IP{sfx}","vmess",network="tcp",tls="tls",port=2053,sni=DOMAIN,fp="safari",address=ip,id=u_uuid,connection_type="direct_ip")
    add(f"VMess-WS-NOTLS-IP{sfx}","vmess",network="ws",tls="none",port=10087,path="/vmess-ws",sni="",fp="chrome",address=ip,id=u_uuid,connection_type="direct_ip")
    add(f"VMess-HTTPUpgrade-IP{sfx}","vmess",network="httpupgrade",tls="tls",port=2082,path="/vmess-hu",sni=DOMAIN,fp="edge",address=ip,id=u_uuid,connection_type="direct_ip")
    # Trojan CF
    for p in [443,2096,8443]:
        add(f"Trojan-WS-CF-{p}{sfx}","trojan",network="ws",tls="tls",port=p,path="/trojan-ws",sni=DOMAIN,fp="chrome",address=DOMAIN,password=u_pass,connection_type="domain")
    add(f"Trojan-gRPC-CF{sfx}","trojan",network="grpc",tls="tls",port=443,service_name="trojan-grpc",sni=DOMAIN,fp="chrome",address=DOMAIN,password=u_pass,connection_type="domain")
    # Trojan IP
    add(f"Trojan-TCP-TLS-IP{sfx}","trojan",network="tcp",tls="tls",port=2096,sni=DOMAIN,fp="firefox",address=ip,password=u_pass,connection_type="direct_ip")
    add(f"Trojan-WS-TLS-IP{sfx}","trojan",network="ws",tls="tls",port=8443,path="/trojan-ws",sni=DOMAIN,fp="chrome",address=ip,password=u_pass,connection_type="direct_ip")
    add(f"Trojan-HTTPUpgrade-IP{sfx}","trojan",network="httpupgrade",tls="tls",port=2053,path="/trojan-hu",sni=DOMAIN,fp="safari",address=ip,password=u_pass,connection_type="direct_ip")
    rd=reality_dests[0]
    add(f"Trojan-REALITY-IP{sfx}","trojan",network="tcp",tls="reality",port=8443,sni=rd["sni"],fp=rd["fp"],address=ip,password=u_pass,reality_dest=rd["dest"],priv_key=rd["priv_key"],public_key=rd["pub_key"],short_id=rd["short_id"],connection_type="direct_ip")
    # SS
    add(f"SS-chacha20{sfx}","shadowsocks",network="tcp",tls="none",port=8388,method="chacha20-ietf-poly1305",password=u_pass,address=ip,connection_type="direct_ip")
    add(f"SS-aes256{sfx}","shadowsocks",network="tcp",tls="none",port=8389,method="aes-256-gcm",password=new_password(16),address=ip,connection_type="direct_ip")
    # SS 2022
    import base64 as _b64, secrets as _sec
    ss2022_pw = _b64.b64encode(_sec.token_bytes(32)).decode()
    add(f"SS-2022-blake3{sfx}","shadowsocks",network="tcp",tls="none",port=8390,method="2022-blake3-aes-256-gcm",password=ss2022_pw,address=ip,connection_type="direct_ip")
    # TUIC
    tuic_id=new_uuid(); tuic_pw=new_password(16)
    add(f"TUIC-v5-IP{sfx}","tuic",network="udp",tls="tls",port=443,sni=DOMAIN,id=tuic_id,password=tuic_pw,address=ip,connection_type="direct_ip",congestion="bbr")
    # Hysteria2
    hy2_pw=new_password(20)
    add(f"Hysteria2-443{sfx}","hysteria2",network="udp",tls="tls",port=443,sni=DOMAIN,password=hy2_pw,address=ip,connection_type="direct_ip")
    add(f"Hysteria2-8443{sfx}","hysteria2",network="udp",tls="tls",port=8443,sni=DOMAIN,password=hy2_pw,address=ip,connection_type="direct_ip")

    write_xray_config(inbounds)
    users[uid]["configs"]=configs
    save_users(users)
    return jsonify({"ok":True,"count":len(configs),"configs":configs})

@app.route("/api/export/<uid>/<fmt>")
@login_required
def api_export_user(uid, fmt):
    users=load_users()
    if uid not in users: return jsonify({"ok":False})
    raw=[c.get("link","") for c in users[uid].get("configs",[]) if c.get("link")]
    import base64 as _b64
    ct=_b64.b64encode("\n".join(raw).encode()).decode() if fmt=="b64" else "\n".join(raw)
    fn=f"{users[uid]['name']}_{'sub_b64' if fmt=='b64' else 'links'}.txt"
    return Response(ct,mimetype="text/plain",headers={"Content-Disposition":f"attachment; filename={fn}"})

# ── Update API ─────────────────────────────────────────────────
@app.route("/api/update", methods=["POST"])
@login_required
def api_update():
    results=[]
    try:
        import urllib.request as ur
        for fname,dest in [("masterpanel.py",PANEL_DIR/"masterpanel.py"),("index.html",PANEL_DIR/"templates"/"index.html")]:
            req=ur.Request(f"{GITHUB_RAW}/{fname}",headers={"User-Agent":"MasterPanel/3.5"})
            with ur.urlopen(req,timeout=15) as r: dest.write_bytes(r.read())
            results.append(f"OK: {fname}")
        import subprocess as sp
        sp.Popen(["bash","-c","sleep 2 && systemctl restart masterpanel"])
        return jsonify({"ok":True,"results":results,"message":"آپدیت انجام شد — رفرش کنید"})
    except Exception as e:
        return jsonify({"ok":False,"error":str(e),"results":results})

@app.route("/api/update/check")
@login_required
def api_update_check():
    try:
        import urllib.request as ur
        req=ur.Request(f"{GITHUB_RAW}/version.txt",headers={"User-Agent":"MasterPanel/3.5"})
        with ur.urlopen(req,timeout=5) as r: latest=r.read().decode().strip()
        return jsonify({"ok":True,"current":CURRENT_VERSION,"latest":latest,"update_available":latest!=CURRENT_VERSION})
    except:
        return jsonify({"ok":True,"current":CURRENT_VERSION,"latest":"unknown","update_available":False})

# ── Run ───────────────────────────────────────────────────────
if __name__ == "__main__":
    import logging
    from datetime import timedelta
    app.permanent_session_lifetime = timedelta(days=30)
    logging.getLogger("werkzeug").setLevel(logging.WARNING)
    print(f"[MasterPanel v{CURRENT_VERSION}] Starting on port {PANEL_PORT}")
    app.run(host="0.0.0.0", port=PANEL_PORT, debug=False)

