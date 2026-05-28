#!/usr/bin/env python3
"""
MasterPanel - Xray Auto Protocol Configurator
Backend Server v1.0
"""

import os
import json
import uuid
import subprocess
import socket
import ssl
import time
import hashlib
import base64
import urllib.parse
from datetime import datetime
from pathlib import Path
from flask import Flask, render_template, request, jsonify, session, redirect, url_for

app = Flask(__name__)
app.secret_key = os.urandom(32)

# ── Load config ──────────────────────────────────────────────
PANEL_DIR = Path("/opt/masterpanel")
CONF_FILE = PANEL_DIR / "panel.conf"

def load_conf():
    conf = {}
    if CONF_FILE.exists():
        for line in CONF_FILE.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip()
    return conf

CFG = load_conf()
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

# ── Helpers ───────────────────────────────────────────────────
def new_uuid():
    return str(uuid.uuid4())

def new_password(length=16):
    import secrets, string
    chars = string.ascii_letters + string.digits
    return ''.join(secrets.choice(chars) for _ in range(length))

def get_server_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"

def vmess_link(config_data):
    data = {
        "v": "2", "ps": config_data.get("name", ""),
        "add": config_data.get("address", DOMAIN),
        "port": str(config_data.get("port", 443)),
        "id": config_data.get("id", ""),
        "aid": "0", "scy": "auto",
        "net": config_data.get("network", "ws"),
        "type": "none",
        "host": config_data.get("sni", DOMAIN),
        "path": config_data.get("path", "/"),
        "tls": config_data.get("tls", "tls"),
        "sni": config_data.get("sni", DOMAIN),
        "fp": config_data.get("fp", "chrome"),
    }
    return "vmess://" + base64.b64encode(json.dumps(data).encode()).decode()

def vless_link(config_data):
    uid  = config_data.get("id", "")
    addr = config_data.get("address", DOMAIN)
    port = config_data.get("port", 443)
    net  = config_data.get("network", "ws")
    tls  = config_data.get("tls", "tls")
    path = urllib.parse.quote(config_data.get("path", "/"), safe="")
    sni  = config_data.get("sni", DOMAIN)
    fp   = config_data.get("fp", "chrome")
    name = urllib.parse.quote(config_data.get("name", "vless"))
    flow = config_data.get("flow", "")
    params = f"type={net}&security={tls}&sni={sni}&fp={fp}&path={path}"
    if flow:
        params += f"&flow={flow}"
    return f"vless://{uid}@{addr}:{port}?{params}#{name}"

def trojan_link(config_data):
    pw   = config_data.get("password", "")
    addr = config_data.get("address", DOMAIN)
    port = config_data.get("port", 443)
    net  = config_data.get("network", "ws")
    sni  = config_data.get("sni", DOMAIN)
    fp   = config_data.get("fp", "chrome")
    path = urllib.parse.quote(config_data.get("path", "/"), safe="")
    name = urllib.parse.quote(config_data.get("name", "trojan"))
    return f"trojan://{pw}@{addr}:{port}?type={net}&security=tls&sni={sni}&fp={fp}&path={path}#{name}"

def ss_link(config_data):
    method   = config_data.get("method", "chacha20-ietf-poly1305")
    password = config_data.get("password", "")
    addr     = config_data.get("address", DOMAIN)
    port     = config_data.get("port", 8388)
    name     = urllib.parse.quote(config_data.get("name", "ss"))
    userinfo = base64.b64encode(f"{method}:{password}".encode()).decode()
    return f"ss://{userinfo}@{addr}:{port}#{name}"

# ── Protocol Generators ───────────────────────────────────────
def generate_all_configs():
    """Generate a comprehensive set of configs for all protocols."""
    configs = []
    ip = get_server_ip()

    # ── VLESS variants — Domain (CF/TLS) ────────────────────
    vless_configs = [
        {
            "name": "VLESS-WS-TLS-CF-443",
            "protocol": "vless",
            "port": 443,
            "network": "ws",
            "tls": "tls",
            "path": "/vless-ws",
            "sni": DOMAIN,
            "fp": "chrome",
            "address": DOMAIN,
            "connection_type": "domain",
        },
        {
            "name": "VLESS-WS-TLS-CF-8443",
            "protocol": "vless",
            "port": 8443,
            "network": "ws",
            "tls": "tls",
            "path": "/vless-ws",
            "sni": DOMAIN,
            "fp": "firefox",
            "address": DOMAIN,
            "connection_type": "domain",
        },
        {
            "name": "VLESS-gRPC-TLS-CF",
            "protocol": "vless",
            "port": 443,
            "network": "grpc",
            "tls": "tls",
            "service_name": "vless-grpc",
            "sni": DOMAIN,
            "fp": "chrome",
            "address": DOMAIN,
            "connection_type": "domain",
        },
        {
            "name": "VLESS-HTTPUpgrade-TLS-CF",
            "protocol": "vless",
            "port": 8443,
            "network": "httpupgrade",
            "tls": "tls",
            "path": "/upgrade",
            "sni": DOMAIN,
            "fp": "chrome",
            "address": DOMAIN,
            "connection_type": "domain",
        },
        # ── VLESS variants — Direct IP ───────────────────────
        {
            "name": "VLESS-TCP-TLS-IP",
            "protocol": "vless",
            "port": 2053,
            "network": "tcp",
            "tls": "tls",
            "sni": DOMAIN,
            "fp": "safari",
            "address": ip,
            "connection_type": "direct_ip",
        },
        {
            "name": "VLESS-WS-TLS-IP-8443",
            "protocol": "vless",
            "port": 8443,
            "network": "ws",
            "tls": "tls",
            "path": "/vless-ws",
            "sni": DOMAIN,
            "fp": "chrome",
            "address": ip,
            "connection_type": "direct_ip",
        },
        {
            "name": "VLESS-REALITY-Vision-IP",
            "protocol": "vless",
            "port": 443,
            "network": "tcp",
            "tls": "reality",
            "sni": "www.google.com",
            "fp": "chrome",
            "flow": "xtls-rprx-vision",
            "address": ip,
            "connection_type": "direct_ip",
        },
        {
            "name": "VLESS-TCP-NOTLS-IP",
            "protocol": "vless",
            "port": 10086,
            "network": "tcp",
            "tls": "none",
            "sni": "",
            "fp": "chrome",
            "address": ip,
            "connection_type": "direct_ip",
        },
    ]

    # ── VMess variants — Domain (CF/TLS) ────────────────────
    vmess_configs = [
        {
            "name": "VMess-WS-TLS-CF-443",
            "protocol": "vmess",
            "port": 443,
            "network": "ws",
            "tls": "tls",
            "path": "/vmess-ws",
            "sni": DOMAIN,
            "fp": "chrome",
            "address": DOMAIN,
            "connection_type": "domain",
        },
        {
            "name": "VMess-WS-TLS-CF-2083",
            "protocol": "vmess",
            "port": 2083,
            "network": "ws",
            "tls": "tls",
            "path": "/vmess-ws",
            "sni": DOMAIN,
            "fp": "firefox",
            "address": DOMAIN,
            "connection_type": "domain",
        },
        {
            "name": "VMess-gRPC-TLS-CF",
            "protocol": "vmess",
            "port": 443,
            "network": "grpc",
            "tls": "tls",
            "service_name": "vmess-grpc",
            "sni": DOMAIN,
            "fp": "chrome",
            "address": DOMAIN,
            "connection_type": "domain",
        },
        # ── VMess variants — Direct IP ───────────────────────
        {
            "name": "VMess-TCP-TLS-IP",
            "protocol": "vmess",
            "port": 2053,
            "network": "tcp",
            "tls": "tls",
            "sni": DOMAIN,
            "fp": "safari",
            "address": ip,
            "connection_type": "direct_ip",
        },
        {
            "name": "VMess-WS-NOTLS-IP",
            "protocol": "vmess",
            "port": 10087,
            "network": "ws",
            "tls": "none",
            "path": "/vmess-ws",
            "sni": "",
            "fp": "chrome",
            "address": ip,
            "connection_type": "direct_ip",
        },
    ]

    # ── Trojan variants — Domain ────────────────────────────
    trojan_configs = [
        {
            "name": "Trojan-WS-TLS-CF",
            "protocol": "trojan",
            "port": 443,
            "network": "ws",
            "tls": "tls",
            "path": "/trojan-ws",
            "sni": DOMAIN,
            "fp": "chrome",
            "address": DOMAIN,
            "connection_type": "domain",
        },
        {
            "name": "Trojan-gRPC-TLS-CF",
            "protocol": "trojan",
            "port": 443,
            "network": "grpc",
            "tls": "tls",
            "service_name": "trojan-grpc",
            "sni": DOMAIN,
            "fp": "chrome",
            "address": DOMAIN,
            "connection_type": "domain",
        },
        # ── Trojan variants — Direct IP ──────────────────────
        {
            "name": "Trojan-TCP-TLS-IP",
            "protocol": "trojan",
            "port": 2096,
            "network": "tcp",
            "tls": "tls",
            "sni": DOMAIN,
            "fp": "firefox",
            "address": ip,
            "connection_type": "direct_ip",
        },
        {
            "name": "Trojan-WS-TLS-IP",
            "protocol": "trojan",
            "port": 8443,
            "network": "ws",
            "tls": "tls",
            "path": "/trojan-ws",
            "sni": DOMAIN,
            "fp": "chrome",
            "address": ip,
            "connection_type": "direct_ip",
        },
    ]

    # ── Shadowsocks — Direct IP only ─────────────────────────
    ss_configs = [
        {
            "name": "SS-chacha20-IP",
            "protocol": "shadowsocks",
            "port": 8388,
            "method": "chacha20-ietf-poly1305",
            "address": ip,
            "connection_type": "direct_ip",
        },
        {
            "name": "SS-aes256-IP",
            "protocol": "shadowsocks",
            "port": 8389,
            "method": "aes-256-gcm",
            "address": ip,
            "connection_type": "direct_ip",
        },
    ]

    # ── Assign IDs/Passwords & build inbounds ───────────────
    all_raw = vless_configs + vmess_configs + trojan_configs + ss_configs
    inbounds = []

    # Shared credentials so domain+IP variants use same UUID/password
    shared_vless_id  = new_uuid()
    shared_vmess_id  = new_uuid()
    shared_trojan_pw = new_password(20)

    for cfg in all_raw:
        proto = cfg["protocol"]

        if proto == "vless":
            cfg["id"] = shared_vless_id
        elif proto == "vmess":
            cfg["id"] = shared_vmess_id
        elif proto == "trojan":
            cfg["password"] = shared_trojan_pw
        elif proto == "shadowsocks":
            cfg["password"] = new_password(16)

        cfg["created_at"] = datetime.now().strftime("%Y-%m-%d %H:%M")

        if proto == "vless":
            cfg["link"] = vless_link(cfg)
        elif proto == "vmess":
            cfg["link"] = vmess_link(cfg)
        elif proto == "trojan":
            cfg["link"] = trojan_link(cfg)
        elif proto == "shadowsocks":
            cfg["link"] = ss_link(cfg)

        configs.append(cfg)
        inbound = build_inbound(cfg)
        if inbound:
            inbounds.append(inbound)

    # ── Save JSON ────────────────────────────────────────────
    save_path = CONFIGS_DIR / "all_configs.json"
    save_path.write_text(json.dumps(configs, indent=2, ensure_ascii=False))

    # ── Export all links to subscription files ───────────────
    export_all_links(configs)

    # ── Write Xray config ────────────────────────────────────
    write_xray_config(inbounds)

    return configs


def export_all_links(configs):
    """Export all share links: annotated txt + plain txt + base64 subscription."""
    lines = []
    lines.append("# MasterPanel - All Configs Export")
    lines.append(f"# Generated : {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    lines.append(f"# Domain    : {DOMAIN}")
    lines.append(f"# Server IP : {get_server_ip()}")
    lines.append(f"# Total     : {len(configs)} configs")
    lines.append("")

    for conn_type, header in [
        ("domain",    "CDN / Domain Configs"),
        ("direct_ip", "Direct IP Configs"),
    ]:
        group = [c for c in configs if c.get("connection_type") == conn_type]
        if not group:
            continue
        lines.append(f"# ── {header} {'─'*(50-len(header))}")
        for c in group:
            link = c.get("link", "")
            if not link:
                continue
            lines.append(
                f"# {c['name']} | {c['protocol'].upper()} | "
                f"{c.get('network','tcp').upper()} | TLS:{c.get('tls','none')} | "
                f"Port:{c['port']} | Addr:{c.get('address','')}"
            )
            lines.append(link)
            lines.append("")

    # Annotated file (human-readable)
    (CONFIGS_DIR / "all_links.txt").write_text("\n".join(lines), encoding="utf-8")

    # Plain links only — one per line (direct import into clients)
    raw_links = [c.get("link", "") for c in configs if c.get("link")]
    (CONFIGS_DIR / "subscription.txt").write_text("\n".join(raw_links), encoding="utf-8")

    # Base64 subscription (v2rayN / Nekobox / Hiddify standard)
    sub_b64 = base64.b64encode("\n".join(raw_links).encode()).decode()
    (CONFIGS_DIR / "subscription_b64.txt").write_text(sub_b64, encoding="utf-8")

def build_inbound(cfg):
    proto = cfg["protocol"]
    port  = cfg["port"]
    net   = cfg.get("network", "tcp")
    tls   = cfg.get("tls", "none")

    inbound = {
        "tag": cfg["name"].lower().replace(" ", "-"),
        "port": port,
        "protocol": proto if proto != "shadowsocks" else "shadowsocks",
        "listen": "0.0.0.0",
    }

    # Settings
    if proto == "vless":
        client = {"id": cfg["id"], "level": 0}
        if cfg.get("flow"):
            client["flow"] = cfg["flow"]
        inbound["settings"] = {"clients": [client], "decryption": "none"}
    elif proto == "vmess":
        inbound["settings"] = {"clients": [{"id": cfg["id"], "level": 0}]}
    elif proto == "trojan":
        inbound["settings"] = {"clients": [{"password": cfg["password"], "level": 0}]}
    elif proto == "shadowsocks":
        inbound["settings"] = {
            "method": cfg["method"],
            "password": cfg["password"],
            "network": "tcp,udp"
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
        # Generate reality keys
        try:
            result = subprocess.run([XRAY_BIN, "x25519"], capture_output=True, text=True, timeout=5)
            lines = result.stdout.strip().splitlines()
            priv_key = lines[0].split(": ")[-1] if lines else ""
            pub_key  = lines[1].split(": ")[-1] if len(lines) > 1 else ""
        except:
            priv_key = pub_key = ""

        stream["security"] = "reality"
        stream["realitySettings"] = {
            "show": False,
            "dest": f"{cfg.get('sni','www.google.com')}:443",
            "xver": 0,
            "serverNames": [cfg.get("sni", "www.google.com")],
            "privateKey": priv_key,
            "shortIds": [new_uuid()[:8]],
        }
        cfg["public_key"] = pub_key
        cfg["short_id"]   = stream["realitySettings"]["shortIds"][0]
    else:
        stream["security"] = "none"

    # Transport
    if net == "ws":
        stream["wsSettings"] = {"path": cfg.get("path", "/"), "headers": {"Host": cfg.get("sni", DOMAIN)}}
    elif net == "grpc":
        stream["grpcSettings"] = {"serviceName": cfg.get("service_name", "grpc")}
    elif net == "httpupgrade":
        stream["httpupgradeSettings"] = {"path": cfg.get("path", "/"), "host": cfg.get("sni", DOMAIN)}

    inbound["streamSettings"] = stream
    return inbound

def write_xray_config(inbounds):
    # Deduplicate ports — keep first per port
    seen_ports = {}
    unique_inbounds = []
    for ib in inbounds:
        p = ib["port"]
        if p not in seen_ports:
            seen_ports[p] = True
            unique_inbounds.append(ib)

    xray_conf = {
        "log": {"loglevel": "warning", "access": "/opt/masterpanel/logs/xray-access.log", "error": "/opt/masterpanel/logs/xray-error.log"},
        "inbounds": unique_inbounds,
        "outbounds": [
            {"tag": "direct", "protocol": "freedom"},
            {"tag": "blocked", "protocol": "blackhole"}
        ],
        "routing": {
            "rules": [
                {"type": "field", "ip": ["geoip:private"], "outboundTag": "direct"},
                {"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "blocked"}
            ]
        }
    }

    xray_conf_path = XRAY_CFG_DIR / "config.json"
    xray_conf_path.write_text(json.dumps(xray_conf, indent=2))

    # Restart xray service if running
    try:
        subprocess.run(["systemctl", "restart", "xray"], timeout=10, capture_output=True)
    except:
        try:
            subprocess.run(["pkill", "-f", "xray"], capture_output=True)
            time.sleep(1)
            subprocess.Popen([XRAY_BIN, "run", "-c", str(xray_conf_path)],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except:
            pass

def load_saved_configs():
    save_path = CONFIGS_DIR / "all_configs.json"
    if save_path.exists():
        try:
            return json.loads(save_path.read_text())
        except:
            pass
    return []

# ── Tests ─────────────────────────────────────────────────────
def test_tls_handshake(host, port=443):
    try:
        ctx = ssl.create_default_context()
        with socket.create_connection((host, port), timeout=5) as sock:
            with ctx.wrap_socket(sock, server_hostname=host) as ssock:
                cert = ssock.getpeercert()
                return {"ok": True, "tls_version": ssock.version(), "cipher": ssock.cipher()[0]}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def test_port(host, port):
    try:
        with socket.create_connection((host, int(port)), timeout=5):
            return {"ok": True}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def test_latency(host):
    try:
        start = time.time()
        socket.create_connection((host, 443), timeout=5).close()
        ms = round((time.time() - start) * 1000)
        return {"ok": True, "ms": ms}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def xray_status():
    try:
        result = subprocess.run(["pgrep", "-f", "xray"], capture_output=True, text=True)
        running = bool(result.stdout.strip())
        version = ""
        if running:
            vr = subprocess.run([XRAY_BIN, "version"], capture_output=True, text=True, timeout=3)
            version = vr.stdout.splitlines()[0] if vr.stdout else ""
        return {"running": running, "version": version}
    except:
        return {"running": False, "version": ""}

# ── Routes ────────────────────────────────────────────────────
def login_required(f):
    from functools import wraps
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("logged_in"):
            return redirect(url_for("login_page"))
        return f(*args, **kwargs)
    return decorated

@app.route("/")
def index():
    if not session.get("logged_in"):
        return redirect(url_for("login_page"))
    return render_template("index.html")

@app.route("/login", methods=["GET", "POST"])
def login_page():
    if request.method == "POST":
        data = request.get_json() or {}
        if data.get("username") == PANEL_USER and data.get("password") == PANEL_PASS:
            session["logged_in"] = True
            return jsonify({"ok": True})
        return jsonify({"ok": False, "error": "نام کاربری یا رمز اشتباه است"})
    return render_template("index.html")

@app.route("/api/logout", methods=["POST"])
def logout():
    session.clear()
    return jsonify({"ok": True})

@app.route("/api/status")
@login_required
def api_status():
    xs = xray_status()
    configs = load_saved_configs()
    return jsonify({
        "xray": xs,
        "domain": DOMAIN,
        "server_ip": get_server_ip(),
        "config_count": len(configs),
        "ssl_valid": Path(CERT_PATH).exists() if CERT_PATH else False,
        "uptime": get_uptime(),
    })

def get_uptime():
    try:
        with open("/proc/uptime") as f:
            secs = float(f.read().split()[0])
        h = int(secs // 3600)
        m = int((secs % 3600) // 60)
        return f"{h}h {m}m"
    except:
        return "N/A"

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
    data = request.get_json() or {}
    t = data.get("type")
    host = data.get("host", DOMAIN)
    port = data.get("port", 443)

    if t == "tls":
        return jsonify(test_tls_handshake(host, port))
    elif t == "port":
        return jsonify(test_port(host, port))
    elif t == "latency":
        return jsonify(test_latency(host))
    elif t == "all":
        results = {}
        configs = load_saved_configs()
        for cfg in configs:
            name = cfg["name"]
            h = cfg.get("address", DOMAIN)
            p = cfg.get("port", 443)
            lat = test_latency(h)
            prt = test_port(h, p)
            results[name] = {
                "latency": lat.get("ms") if lat["ok"] else None,
                "port_open": prt["ok"],
                "protocol": cfg["protocol"],
                "tls": cfg.get("tls", "none"),
                "network": cfg.get("network", "tcp"),
            }
        return jsonify({"ok": True, "results": results})
    return jsonify({"ok": False, "error": "Unknown test type"})

@app.route("/api/xray/restart", methods=["POST"])
@login_required
def api_xray_restart():
    try:
        subprocess.run(["systemctl", "restart", "xray"], timeout=10, capture_output=True)
        time.sleep(1)
        return jsonify({"ok": True, "status": xray_status()})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})

@app.route("/api/xray/logs")
@login_required
def api_xray_logs():
    log_file = Path("/opt/masterpanel/logs/xray-error.log")
    if log_file.exists():
        lines = log_file.read_text().splitlines()[-50:]
        return jsonify({"ok": True, "lines": lines})
    return jsonify({"ok": True, "lines": []})

@app.route("/api/export/links")
@login_required
def api_export_links():
    f = CONFIGS_DIR / "all_links.txt"
    if not f.exists():
        return jsonify({"ok": False, "error": "No configs generated yet"})
    from flask import Response
    return Response(f.read_text(encoding="utf-8"), mimetype="text/plain",
        headers={"Content-Disposition": "attachment; filename=all_links.txt"})

@app.route("/api/export/subscription")
@login_required
def api_export_subscription():
    f = CONFIGS_DIR / "subscription.txt"
    if not f.exists():
        return jsonify({"ok": False, "error": "No configs generated yet"})
    from flask import Response
    return Response(f.read_text(encoding="utf-8"), mimetype="text/plain",
        headers={"Content-Disposition": "attachment; filename=subscription.txt"})

@app.route("/api/export/subscription_b64")
@login_required
def api_export_subscription_b64():
    f = CONFIGS_DIR / "subscription_b64.txt"
    if not f.exists():
        return jsonify({"ok": False, "error": "No configs generated yet"})
    from flask import Response
    return Response(f.read_text(encoding="utf-8"), mimetype="text/plain",
        headers={"Content-Disposition": "attachment; filename=subscription_b64.txt"})

@app.route("/api/export/summary")
@login_required
def api_export_summary():
    configs = load_saved_configs()
    domain_cfgs = [c for c in configs if c.get("connection_type") == "domain"]
    ip_cfgs     = [c for c in configs if c.get("connection_type") == "direct_ip"]
    return jsonify({
        "ok": True,
        "total": len(configs),
        "domain_configs": len(domain_cfgs),
        "direct_ip_configs": len(ip_cfgs),
        "subscription_ready": (CONFIGS_DIR / "subscription_b64.txt").exists(),
    })

# ── Run ───────────────────────────────────────────────────────
if __name__ == "__main__":
    import logging
    log = logging.getLogger("werkzeug")
    log.setLevel(logging.WARNING)
    print(f"[MasterPanel] Starting on port {PANEL_PORT}")
    app.run(host="0.0.0.0", port=PANEL_PORT, debug=False)
