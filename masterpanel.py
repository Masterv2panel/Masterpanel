#!/usr/bin/env python3
"""
MasterPanel - Xray Auto Protocol Configurator
Version: 4.0.0 (Stable Release)
GitHub: https://github.com/Masterv2panel/Masterpanel

Protocols: VLESS, VMess, Trojan, Shadowsocks, TUIC v5, Hysteria2
Features:
  - Per-user config generation with UUID/password
  - Persistent session (no logout on refresh)
  - Traffic monitoring via Xray API
  - One-click update from GitHub
  - CF-compatible configs (TLS handled by Cloudflare)
  - Direct IP configs with proper TLS
  - REALITY with multiple destinations
"""

import os, json, uuid, subprocess, socket, ssl, time, base64
import urllib.parse, urllib.request, secrets, string, hashlib
from datetime import datetime
from pathlib import Path
from flask import Flask, request, jsonify, session, redirect, url_for, Response

app = Flask(__name__, static_folder=None)

# ── Stable secret key (persisted to disk so sessions survive restarts) ────────
PANEL_DIR   = Path("/opt/masterpanel")
SECRET_FILE = PANEL_DIR / ".secret_key"
PANEL_DIR.mkdir(exist_ok=True)

if SECRET_FILE.exists():
    app.secret_key = SECRET_FILE.read_bytes()
else:
    key = secrets.token_bytes(32)
    SECRET_FILE.write_bytes(key)
    SECRET_FILE.chmod(0o600)
    app.secret_key = key

# ── Load config ───────────────────────────────────────────────
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
CONFIGS_DIR  = PANEL_DIR / "configs"
USERS_FILE   = PANEL_DIR / "configs" / "users.json"
VERSION_FILE = PANEL_DIR / "version.txt"
CONFIGS_DIR.mkdir(exist_ok=True)
XRAY_CFG_DIR.mkdir(parents=True, exist_ok=True)

CURRENT_VERSION = "4.0.0"
GITHUB_RAW = "https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main"
GITHUB_REPO = "https://github.com/Masterv2panel/Masterpanel"

# ── Helpers ───────────────────────────────────────────────────
def new_uuid():    return str(uuid.uuid4())
def new_password(n=16):
    return ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(n))

def get_server_ip():
    """Always return IPv4 — try multiple methods."""
    # UDP trick — forces IPv4
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]; s.close()
        if ip and ":" not in ip and not ip.startswith("127."): return ip
    except: pass
    # External APIs
    for api in ["https://api4.ipify.org", "https://ipv4.icanhazip.com", "https://v4.ident.me"]:
        try:
            req = urllib.request.Request(api, headers={"User-Agent": "curl/7"})
            with urllib.request.urlopen(req, timeout=4) as r:
                ip = r.read().decode().strip()
                if ip and ":" not in ip and not ip.startswith("127."): return ip
        except: continue
    return "0.0.0.0"

def get_reality_keys():
    try:
        r = subprocess.run([XRAY_BIN, "x25519"], capture_output=True, text=True, timeout=5)
        lines = r.stdout.strip().splitlines()
        return (lines[0].split(": ")[-1], lines[1].split(": ")[-1]) if len(lines) >= 2 else ("","")
    except: return ("","")

def get_uptime():
    try:
        secs = float(open("/proc/uptime").read().split()[0])
        return f"{int(secs//3600)}h {int((secs%3600)//60)}m"
    except: return "N/A"

def fmt_bytes(b):
    for u in ["B","KB","MB","GB","TB"]:
        if b < 1024: return f"{b:.1f} {u}"
        b /= 1024
    return f"{b:.2f} PB"

def serve_html():
    p = PANEL_DIR / "templates" / "index.html"
    if p.exists():
        return p.read_text(encoding="utf-8"), 200, {"Content-Type": "text/html; charset=utf-8"}
    return "<h1>index.html not found</h1>", 404

# ── User Management ───────────────────────────────────────────
def load_users():
    if USERS_FILE.exists():
        try: return json.loads(USERS_FILE.read_text())
        except: pass
    return {}

def save_users(u): USERS_FILE.write_text(json.dumps(u, indent=2, ensure_ascii=False))

# ── Share Link Builders ───────────────────────────────────────
def vless_link(c):
    uid   = c.get("id",""); addr = c.get("address", DOMAIN); port = c.get("port",443)
    net   = c.get("network","tcp"); tls = c.get("tls","tls")
    path  = urllib.parse.quote(c.get("path","/"), safe="")
    sni   = c.get("sni", DOMAIN); fp = c.get("fp","chrome")
    name  = urllib.parse.quote(c.get("name","vless")); flow = c.get("flow","")
    pbk   = c.get("public_key",""); sid = c.get("short_id","")
    p = f"type={net}&security={tls}&sni={sni}&fp={fp}"
    if net in ("ws","httpupgrade"): p += f"&path={path}"
    if net == "grpc": p += f"&serviceName={urllib.parse.quote(c.get('service_name','grpc'))}"
    if flow: p += f"&flow={flow}"
    if tls == "reality" and pbk: p += f"&pbk={pbk}&sid={sid}"
    return f"vless://{uid}@{addr}:{port}?{p}#{name}"

def vmess_link(c):
    net = c.get("network","ws"); tls = c.get("tls","tls")
    data = {
        "v":"2","ps":c.get("name",""),"add":c.get("address",DOMAIN),
        "port":str(c.get("port",443)),"id":c.get("id",""),"aid":"0","scy":"auto",
        "net":net,"type":"none","host":c.get("sni",DOMAIN),
        "path":c.get("service_name",c.get("path","/")),
        "tls":"tls" if tls=="tls" else "","sni":c.get("sni",DOMAIN),"fp":c.get("fp","chrome"),
    }
    return "vmess://" + base64.b64encode(json.dumps(data).encode()).decode()

def trojan_link(c):
    pw=c.get("password",""); addr=c.get("address",DOMAIN); port=c.get("port",443)
    net=c.get("network","tcp"); tls=c.get("tls","tls")
    sni=c.get("sni",DOMAIN); fp=c.get("fp","chrome")
    path=urllib.parse.quote(c.get("path","/"),safe="")
    name=urllib.parse.quote(c.get("name","trojan"))
    p=f"type={net}&security={tls}&sni={sni}&fp={fp}"
    if net in ("ws","httpupgrade"): p += f"&path={path}"
    if net == "grpc": p += f"&serviceName={urllib.parse.quote(c.get('service_name','grpc'))}"
    return f"trojan://{pw}@{addr}:{port}?{p}#{name}"

def ss_link(c):
    ui = base64.b64encode(f"{c.get('method','chacha20-ietf-poly1305')}:{c.get('password','')}".encode()).decode()
    return f"ss://{ui}@{c.get('address',DOMAIN)}:{c.get('port',8388)}#{urllib.parse.quote(c.get('name','ss'))}"

def tuic_link(c):
    return (f"tuic://{c.get('id','')}:{c.get('password','')}@{c.get('address',DOMAIN)}:{c.get('port',443)}"
            f"?sni={c.get('sni',DOMAIN)}&congestion_control=bbr&alpn=h3#{urllib.parse.quote(c.get('name','tuic'))}")

def hysteria2_link(c):
    pw=c.get("password",""); addr=c.get("address",DOMAIN); port=c.get("port",443)
    sni=c.get("sni",DOMAIN); name=urllib.parse.quote(c.get("name","hy2"))
    p=f"sni={sni}&insecure=0"
    if c.get("obfs"): p += f"&obfs={c['obfs']}&obfs-password={c.get('obfs_password','')}"
    return f"hysteria2://{pw}@{addr}:{port}?{p}#{name}"

# ── Config Generator (v2 logic — proven working) ─────────────
def generate_configs_for_user(u_uuid, u_pass, label=""):
    """Generate all configs for a given UUID and password."""
    configs = []; inbounds = []
    ip = get_server_ip()
    sfx = f"-{label}" if label else ""

    # Reality keys per destination
    reality_dests = [
        {"dest":"www.google.com:443",   "sni":"www.google.com",   "fp":"chrome",  "port":443},
        {"dest":"www.apple.com:443",    "sni":"www.apple.com",    "fp":"safari",  "port":443},
        {"dest":"discord.com:443",      "sni":"discord.com",      "fp":"firefox", "port":443},
        {"dest":"cdn.jsdelivr.net:443", "sni":"cdn.jsdelivr.net", "fp":"chrome",  "port":443},
    ]
    for rd in reality_dests:
        priv, pub = get_reality_keys()
        rd["priv_key"] = priv; rd["pub_key"] = pub
        rd["short_id"] = new_uuid()[:8]

    cf_ports = [443, 2053, 2083, 2087, 2096, 8443]

    # ── VLESS CF / CDN ─────────────────────────────────────────
    for port in cf_ports:
        configs.append({"name":f"VLESS-WS-TLS-CF-{port}{sfx}","protocol":"vless",
            "network":"ws","tls":"tls","port":port,"path":"/vless-ws","sni":DOMAIN,
            "fp":"chrome","address":DOMAIN,"id":u_uuid,"connection_type":"domain"})

    configs.append({"name":f"VLESS-gRPC-TLS-CF{sfx}","protocol":"vless",
        "network":"grpc","tls":"tls","port":443,"service_name":"vless-grpc","sni":DOMAIN,
        "fp":"chrome","address":DOMAIN,"id":u_uuid,"connection_type":"domain"})

    configs.append({"name":f"VLESS-HTTPUpgrade-TLS-CF{sfx}","protocol":"vless",
        "network":"httpupgrade","tls":"tls","port":8443,"path":"/vless-hu","sni":DOMAIN,
        "fp":"chrome","address":DOMAIN,"id":u_uuid,"connection_type":"domain"})

    # ── VLESS Direct IP ────────────────────────────────────────
    configs.append({"name":f"VLESS-TCP-TLS-IP{sfx}","protocol":"vless",
        "network":"tcp","tls":"tls","port":2053,"sni":DOMAIN,"fp":"safari",
        "address":ip,"id":u_uuid,"connection_type":"direct_ip"})
    configs.append({"name":f"VLESS-WS-TLS-IP{sfx}","protocol":"vless",
        "network":"ws","tls":"tls","port":8443,"path":"/vless-ws","sni":DOMAIN,
        "fp":"chrome","address":ip,"id":u_uuid,"connection_type":"direct_ip"})
    configs.append({"name":f"VLESS-HTTPUpgrade-TLS-IP{sfx}","protocol":"vless",
        "network":"httpupgrade","tls":"tls","port":2087,"path":"/vless-hu","sni":DOMAIN,
        "fp":"edge","address":ip,"id":u_uuid,"connection_type":"direct_ip"})
    configs.append({"name":f"VLESS-TCP-NOTLS-IP{sfx}","protocol":"vless",
        "network":"tcp","tls":"none","port":10086,"sni":"","fp":"chrome",
        "address":ip,"id":u_uuid,"connection_type":"direct_ip"})

    # ── VLESS REALITY ──────────────────────────────────────────
    for rd in reality_dests:
        label2 = rd["sni"].split(".")[1].upper()
        configs.append({"name":f"VLESS-REALITY-{label2}-IP{sfx}","protocol":"vless",
            "network":"tcp","tls":"reality","port":rd["port"],"sni":rd["sni"],"fp":rd["fp"],
            "flow":"xtls-rprx-vision","address":ip,"id":u_uuid,
            "reality_dest":rd["dest"],"priv_key":rd["priv_key"],
            "public_key":rd["pub_key"],"short_id":rd["short_id"],"connection_type":"direct_ip"})

    # ── VMess CF / CDN ─────────────────────────────────────────
    for port in [443,2083,2087,8443]:
        configs.append({"name":f"VMess-WS-TLS-CF-{port}{sfx}","protocol":"vmess",
            "network":"ws","tls":"tls","port":port,"path":"/vmess-ws","sni":DOMAIN,
            "fp":"chrome","address":DOMAIN,"id":u_uuid,"connection_type":"domain"})

    configs.append({"name":f"VMess-gRPC-TLS-CF{sfx}","protocol":"vmess",
        "network":"grpc","tls":"tls","port":443,"service_name":"vmess-grpc","sni":DOMAIN,
        "fp":"chrome","address":DOMAIN,"id":u_uuid,"connection_type":"domain"})
    configs.append({"name":f"VMess-HTTPUpgrade-TLS-CF{sfx}","protocol":"vmess",
        "network":"httpupgrade","tls":"tls","port":2096,"path":"/vmess-hu","sni":DOMAIN,
        "fp":"firefox","address":DOMAIN,"id":u_uuid,"connection_type":"domain"})

    # ── VMess Direct IP ────────────────────────────────────────
    configs.append({"name":f"VMess-TCP-TLS-IP{sfx}","protocol":"vmess",
        "network":"tcp","tls":"tls","port":2053,"sni":DOMAIN,"fp":"safari",
        "address":ip,"id":u_uuid,"connection_type":"direct_ip"})
    configs.append({"name":f"VMess-WS-NOTLS-IP{sfx}","protocol":"vmess",
        "network":"ws","tls":"none","port":10087,"path":"/vmess-ws","sni":"",
        "fp":"chrome","address":ip,"id":u_uuid,"connection_type":"direct_ip"})
    configs.append({"name":f"VMess-HTTPUpgrade-TLS-IP{sfx}","protocol":"vmess",
        "network":"httpupgrade","tls":"tls","port":2082,"path":"/vmess-hu","sni":DOMAIN,
        "fp":"edge","address":ip,"id":u_uuid,"connection_type":"direct_ip"})

    # ── Trojan CF / CDN ────────────────────────────────────────
    for port in [443,2096,8443]:
        configs.append({"name":f"Trojan-WS-TLS-CF-{port}{sfx}","protocol":"trojan",
            "network":"ws","tls":"tls","port":port,"path":"/trojan-ws","sni":DOMAIN,
            "fp":"chrome","address":DOMAIN,"password":u_pass,"connection_type":"domain"})

    configs.append({"name":f"Trojan-gRPC-TLS-CF{sfx}","protocol":"trojan",
        "network":"grpc","tls":"tls","port":443,"service_name":"trojan-grpc","sni":DOMAIN,
        "fp":"chrome","address":DOMAIN,"password":u_pass,"connection_type":"domain"})

    # ── Trojan Direct IP ───────────────────────────────────────
    configs.append({"name":f"Trojan-TCP-TLS-IP{sfx}","protocol":"trojan",
        "network":"tcp","tls":"tls","port":2096,"sni":DOMAIN,"fp":"firefox",
        "address":ip,"password":u_pass,"connection_type":"direct_ip"})
    configs.append({"name":f"Trojan-WS-TLS-IP{sfx}","protocol":"trojan",
        "network":"ws","tls":"tls","port":8443,"path":"/trojan-ws","sni":DOMAIN,
        "fp":"chrome","address":ip,"password":u_pass,"connection_type":"direct_ip"})
    configs.append({"name":f"Trojan-HTTPUpgrade-TLS-IP{sfx}","protocol":"trojan",
        "network":"httpupgrade","tls":"tls","port":2053,"path":"/trojan-hu","sni":DOMAIN,
        "fp":"safari","address":ip,"password":u_pass,"connection_type":"direct_ip"})

    # Trojan REALITY
    rd = reality_dests[0]
    configs.append({"name":f"Trojan-REALITY-IP{sfx}","protocol":"trojan",
        "network":"tcp","tls":"reality","port":8443,"sni":rd["sni"],"fp":rd["fp"],
        "address":ip,"password":u_pass,"reality_dest":rd["dest"],
        "priv_key":rd["priv_key"],"public_key":rd["pub_key"],"short_id":rd["short_id"],
        "connection_type":"direct_ip"})

    # ── Shadowsocks ────────────────────────────────────────────
    ss_pw2 = new_password(16)
    configs.append({"name":f"SS-chacha20-IP{sfx}","protocol":"shadowsocks",
        "network":"tcp","tls":"none","port":8388,"method":"chacha20-ietf-poly1305",
        "password":u_pass,"address":ip,"connection_type":"direct_ip"})
    configs.append({"name":f"SS-aes256-IP{sfx}","protocol":"shadowsocks",
        "network":"tcp","tls":"none","port":8389,"method":"aes-256-gcm",
        "password":ss_pw2,"address":ip,"connection_type":"direct_ip"})

    # ── TUIC v5 ────────────────────────────────────────────────
    tuic_id = new_uuid(); tuic_pw = new_password(16)
    configs.append({"name":f"TUIC-v5-IP-443{sfx}","protocol":"tuic",
        "network":"udp","tls":"tls","port":443,"sni":DOMAIN,
        "id":tuic_id,"password":tuic_pw,"address":ip,"connection_type":"direct_ip","congestion":"bbr"})
    configs.append({"name":f"TUIC-v5-CF-2096{sfx}","protocol":"tuic",
        "network":"udp","tls":"tls","port":2096,"sni":DOMAIN,
        "id":tuic_id,"password":tuic_pw,"address":DOMAIN,"connection_type":"domain","congestion":"bbr"})

    # ── Hysteria2 ──────────────────────────────────────────────
    hy2_pw = new_password(20); hy2_obfs = new_password(16)
    configs.append({"name":f"Hysteria2-IP-443{sfx}","protocol":"hysteria2",
        "network":"udp","tls":"tls","port":443,"sni":DOMAIN,
        "password":hy2_pw,"address":ip,"connection_type":"direct_ip"})
    configs.append({"name":f"Hysteria2-IP-8443{sfx}","protocol":"hysteria2",
        "network":"udp","tls":"tls","port":8443,"sni":DOMAIN,
        "password":hy2_pw,"address":ip,"connection_type":"direct_ip"})
    configs.append({"name":f"Hysteria2-IP-Obfs{sfx}","protocol":"hysteria2",
        "network":"udp","tls":"tls","port":19999,"sni":DOMAIN,
        "password":hy2_pw,"obfs":"salamander","obfs_password":hy2_obfs,
        "address":ip,"connection_type":"direct_ip"})

    # ── Build links + inbounds ─────────────────────────────────
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    for cfg in configs:
        cfg["created_at"] = ts
        proto = cfg["protocol"]
        cfg["link"] = {
            "vless": vless_link, "vmess": vmess_link,
            "trojan": trojan_link, "shadowsocks": ss_link,
            "tuic": tuic_link, "hysteria2": hysteria2_link,
        }.get(proto, lambda c: "")(cfg)

        if proto in ("vless","vmess","trojan","shadowsocks"):
            ib = build_inbound(cfg)
            if ib: inbounds.append(ib)

    return configs, inbounds


def build_inbound(cfg):
    proto = cfg["protocol"]; port = cfg["port"]
    net = cfg.get("network","tcp"); tls = cfg.get("tls","none")
    tag = f"in-{cfg['name'].lower().replace(' ','-').replace('.','-')}"[:60]

    inbound = {"tag":tag,"port":port,"listen":"0.0.0.0","protocol":proto,
               "sniffing":{"enabled":True,"destOverride":["http","tls","quic"]}}

    if proto == "vless":
        cl = {"id":cfg["id"],"level":0}
        if cfg.get("flow"): cl["flow"] = cfg["flow"]
        inbound["settings"] = {"clients":[cl],"decryption":"none"}
    elif proto == "vmess":
        inbound["settings"] = {"clients":[{"id":cfg["id"],"alterId":0}]}
    elif proto == "trojan":
        inbound["settings"] = {"clients":[{"password":cfg["password"]}]}
    elif proto == "shadowsocks":
        inbound["settings"] = {"method":cfg["method"],"password":cfg["password"],"network":"tcp,udp"}
        inbound["streamSettings"] = {"network":"tcp"}
        return inbound

    stream = {"network":net}
    if tls == "tls":
        stream["security"] = "tls"
        stream["tlsSettings"] = {
            "certificates":[{"certificateFile":CERT_PATH,"keyFile":KEY_PATH}],
            "alpn":["h2","http/1.1"]
        }
    elif tls == "reality":
        stream["security"] = "reality"
        stream["realitySettings"] = {
            "show":False,"dest":cfg.get("reality_dest","www.google.com:443"),
            "xver":0,"serverNames":[cfg.get("sni","www.google.com")],
            "privateKey":cfg.get("priv_key",""),
            "shortIds":[cfg.get("short_id",new_uuid()[:8])]
        }
    else:
        stream["security"] = "none"

    if net == "ws":
        stream["wsSettings"] = {"path":cfg.get("path","/"),"headers":{"Host":cfg.get("sni",DOMAIN)}}
    elif net == "grpc":
        stream["grpcSettings"] = {"serviceName":cfg.get("service_name","grpc")}
    elif net == "httpupgrade":
        stream["httpupgradeSettings"] = {"path":cfg.get("path","/"),"host":cfg.get("sni",DOMAIN)}

    inbound["streamSettings"] = stream
    return inbound


def write_xray_config(inbounds):
    # Merge inbounds with same port — keep TLS variant, skip duplicates
    seen = {}
    for ib in inbounds:
        p = ib["port"]
        if p not in seen:
            seen[p] = ib
        else:
            # prefer TLS over none
            existing_tls = seen[p].get("streamSettings",{}).get("security","none")
            new_tls = ib.get("streamSettings",{}).get("security","none")
            if existing_tls == "none" and new_tls != "none":
                seen[p] = ib
    unique = list(seen.values())

    # Add API inbound
    unique.append({"tag":"api","port":10085,"listen":"127.0.0.1",
                   "protocol":"dokodemo-door","settings":{"address":"127.0.0.1"}})

    conf = {
        "log":{"loglevel":"warning",
               "access":"/opt/masterpanel/logs/xray-access.log",
               "error":"/opt/masterpanel/logs/xray-error.log"},
        "api":{"tag":"api","services":["HandlerService","LoggerService","StatsService"]},
        "stats":{},
        "policy":{"levels":{"0":{"statsUserUplink":True,"statsUserDownlink":True}},
                  "system":{"statsInboundUplink":True,"statsInboundDownlink":True}},
        "inbounds":unique,
        "outbounds":[{"tag":"direct","protocol":"freedom"},{"tag":"blocked","protocol":"blackhole"}],
        "routing":{"domainStrategy":"IPIfNonMatch","rules":[
            {"type":"field","inboundTag":["api"],"outboundTag":"api"},
            {"type":"field","ip":["geoip:private"],"outboundTag":"direct"},
            {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"blocked"}
        ]}
    }

    path = XRAY_CFG_DIR / "config.json"
    path.write_text(json.dumps(conf, indent=2))

    for cmd in [["systemctl","restart","xray"],["systemctl","start","xray"]]:
        try:
            subprocess.run(cmd, timeout=10, capture_output=True)
            time.sleep(1)
            if xray_running(): break
        except: pass
    else:
        try:
            subprocess.run(["pkill","-f","xray run"], capture_output=True)
            time.sleep(1)
            subprocess.Popen([XRAY_BIN,"run","-c",str(path)],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except: pass


def write_tuic_config(configs):
    tuics = [c for c in configs if c["protocol"]=="tuic" and c.get("connection_type")=="direct_ip"]
    if not tuics: return
    c = tuics[0]
    (CONFIGS_DIR/"tuic_config.json").write_text(json.dumps({
        "server":f"0.0.0.0:{c['port']}","users":{c["id"]:c["password"]},
        "certificate":CERT_PATH,"private_key":KEY_PATH,
        "congestion_controller":c.get("congestion","bbr"),"alpn":["h3"],"log_level":"warn"
    }, indent=2))


def write_hysteria2_config(configs):
    hy2s = [c for c in configs if c["protocol"]=="hysteria2" and c.get("connection_type")=="direct_ip" and not c.get("obfs")]
    if not hy2s: return
    c = hy2s[0]
    (CONFIGS_DIR/"hysteria2_config.yaml").write_text(
        f"listen: :{c['port']}\ntls:\n  cert: {CERT_PATH}\n  key: {KEY_PATH}\n"
        f"auth:\n  type: password\n  password: {c['password']}\n"
        f"masquerade:\n  type: proxy\n  proxy:\n    url: https://www.google.com\n    rewriteHost: true\n"
        f"bandwidth:\n  up: 1 gbps\n  down: 1 gbps\n"
    )


def export_all_links(configs, label="all"):
    lines = [
        "# MasterPanel v4.0 — Config Export",
        f"# Generated : {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"# Domain    : {DOMAIN}",
        f"# Server IP : {get_server_ip()}",
        f"# Total     : {len(configs)} configs","",
    ]
    for ct, hdr in [("domain","CDN / Cloudflare"),("direct_ip","Direct IP")]:
        grp = [c for c in configs if c.get("connection_type")==ct]
        if not grp: continue
        lines.append(f"# ── {hdr} {'─'*(50-len(hdr))}")
        for c in grp:
            lines.append(f"# {c['name']} | {c['protocol'].upper()} | {c.get('network','').upper()} | Port:{c['port']}")
            if c.get("link"): lines.append(c["link"])
            lines.append("")

    (CONFIGS_DIR/f"{label}_links.txt").write_text("\n".join(lines), encoding="utf-8")
    raw = [c.get("link","") for c in configs if c.get("link")]
    (CONFIGS_DIR/f"{label}_subscription.txt").write_text("\n".join(raw), encoding="utf-8")
    (CONFIGS_DIR/f"{label}_subscription_b64.txt").write_text(
        base64.b64encode("\n".join(raw).encode()).decode(), encoding="utf-8")


# ── Xray Status & Stats ───────────────────────────────────────
def xray_running():
    try: return bool(subprocess.run(["pgrep","-f","xray"], capture_output=True, text=True).stdout.strip())
    except: return False

def xray_status():
    running = xray_running()
    version = ""
    if running:
        try:
            r = subprocess.run([XRAY_BIN,"version"], capture_output=True, text=True, timeout=3)
            version = r.stdout.splitlines()[0] if r.stdout else ""
        except: pass
    return {"running":running,"version":version}

def get_inbound_stats():
    try:
        r = subprocess.run([XRAY_BIN,"api","statsquery","--server=127.0.0.1:10085"],
                           capture_output=True, text=True, timeout=5)
        data = json.loads(r.stdout)
        stats = {}
        for item in data.get("stat",[]):
            name = item.get("name",""); val = int(item.get("value",0))
            if "inbound>>>" in name:
                parts = name.split(">>>")
                tag = parts[1] if len(parts)>1 else name
                direction = parts[3] if len(parts)>3 else ""
                if tag not in stats: stats[tag] = {"up":0,"down":0}
                if "uplink" in direction: stats[tag]["up"] = val
                elif "downlink" in direction: stats[tag]["down"] = val
        return stats
    except: return {}

# ── Auth ──────────────────────────────────────────────────────
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
@app.route("/"); 
def index():
    if not session.get("logged_in"): return redirect(url_for("login_page"))
    return serve_html()

@app.route("/login", methods=["GET","POST"])
def login_page():
    if request.method == "POST":
        d = request.get_json() or {}
        if d.get("username")==PANEL_USER and d.get("password")==PANEL_PASS:
            session["logged_in"] = True
            session.permanent = True
            return jsonify({"ok":True})
        return jsonify({"ok":False,"error":"نام کاربری یا رمز اشتباه است"})
    return serve_html()

@app.route("/api/logout", methods=["POST"])
def logout(): session.clear(); return jsonify({"ok":True})

@app.route("/api/status")
@login_required
def api_status():
    xs = xray_status()
    users = load_users()
    ib_stats = get_inbound_stats()
    total_up   = sum(v["up"]   for v in ib_stats.values())
    total_down = sum(v["down"] for v in ib_stats.values())
    ip = get_server_ip()
    return jsonify({
        "xray":xs,"domain":DOMAIN,"server_ip":ip,
        "panel_url":f"http://{ip}:{PANEL_PORT}",
        "user_count":len(users),
        "active_users":sum(1 for u in users.values() if u.get("enabled",True)),
        "ssl_valid":Path(CERT_PATH).exists() if CERT_PATH else False,
        "uptime":get_uptime(),"version":CURRENT_VERSION,
        "traffic":{"total_up":fmt_bytes(total_up),"total_down":fmt_bytes(total_down),
                   "raw_up":total_up,"raw_down":total_down}
    })

@app.route("/api/stats")
@login_required
def api_stats():
    ib = get_inbound_stats()
    return jsonify({"ok":True,"stats":{
        tag:{"up":fmt_bytes(s["up"]),"down":fmt_bytes(s["down"]),"up_raw":s["up"],"down_raw":s["down"]}
        for tag,s in ib.items()
    }})

# ── Users API ─────────────────────────────────────────────────
@app.route("/api/users", methods=["GET"])
@login_required
def api_users_list():
    users = load_users()
    return jsonify({"ok":True,"users":list(users.values())})

@app.route("/api/users", methods=["POST"])
@login_required
def api_users_create():
    d = request.get_json() or {}
    name = d.get("name","").strip()
    if not name: return jsonify({"ok":False,"error":"Name required"})
    limit_gb = float(d.get("limit_gb",0))
    expire_days = int(d.get("expire_days",0))
    users = load_users(); uid = new_uuid()
    from datetime import timedelta
    expire_at = (datetime.now()+timedelta(days=expire_days)).strftime("%Y-%m-%d") if expire_days else ""
    users[uid] = {
        "id":uid,"name":name,"uuid":new_uuid(),"password":new_password(20),
        "limit_gb":limit_gb,"expire_at":expire_at,
        "created_at":datetime.now().strftime("%Y-%m-%d %H:%M"),
        "enabled":True,"used_bytes":0,"configs":[]
    }
    save_users(users)
    return jsonify({"ok":True,"user":users[uid]})

@app.route("/api/users/<uid>", methods=["DELETE"])
@login_required
def api_users_delete(uid):
    users = load_users()
    if uid in users: del users[uid]; save_users(users); return jsonify({"ok":True})
    return jsonify({"ok":False,"error":"Not found"})

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
    users = load_users()
    if uid not in users: return jsonify({"ok":False,"error":"User not found"})
    user = users[uid]
    configs, inbounds = generate_configs_for_user(user["uuid"], user["password"], user["name"])
    users[uid]["configs"] = configs
    save_users(users)
    # Apply inbounds to Xray
    write_xray_config(inbounds)
    write_tuic_config(configs)
    write_hysteria2_config(configs)
    export_all_links(configs, f"user_{uid[:8]}")
    return jsonify({"ok":True,"count":len(configs),"configs":configs})

# ── Xray management ───────────────────────────────────────────
@app.route("/api/xray/restart", methods=["POST"])
@login_required
def api_xray_restart():
    try:
        subprocess.run(["systemctl","restart","xray"], timeout=10, capture_output=True)
        time.sleep(1); return jsonify({"ok":True,"status":xray_status()})
    except Exception as e: return jsonify({"ok":False,"error":str(e)})

@app.route("/api/xray/logs")
@login_required
def api_xray_logs():
    f = Path("/opt/masterpanel/logs/xray-error.log")
    lines = f.read_text().splitlines()[-80:] if f.exists() else []
    return jsonify({"ok":True,"lines":lines})

# ── Update from GitHub ────────────────────────────────────────
@app.route("/api/update", methods=["POST"])
@login_required
def api_update():
    results = []
    files = {
        "masterpanel.py": PANEL_DIR / "masterpanel.py",
        "index.html":     PANEL_DIR / "templates" / "index.html",
    }
    try:
        for fname, dest in files.items():
            url = f"{GITHUB_RAW}/{fname}"
            req = urllib.request.Request(url, headers={"User-Agent":"MasterPanel/4.0"})
            with urllib.request.urlopen(req, timeout=15) as r:
                content = r.read()
            dest.write_bytes(content)
            results.append(f"✅ {fname} updated")

        # Restart panel after update
        subprocess.Popen(["bash","-c","sleep 2 && systemctl restart masterpanel"])
        return jsonify({"ok":True,"results":results,"message":"پنل در حال آپدیت است... صفحه را رفرش کنید"})
    except Exception as e:
        return jsonify({"ok":False,"error":str(e),"results":results})

@app.route("/api/update/check")
@login_required
def api_update_check():
    try:
        url = f"{GITHUB_RAW}/version.txt"
        req = urllib.request.Request(url, headers={"User-Agent":"MasterPanel/4.0"})
        with urllib.request.urlopen(req, timeout=5) as r:
            latest = r.read().decode().strip()
        return jsonify({"ok":True,"current":CURRENT_VERSION,"latest":latest,
                        "update_available": latest != CURRENT_VERSION})
    except:
        return jsonify({"ok":True,"current":CURRENT_VERSION,"latest":"unknown","update_available":False})

# ── Export ────────────────────────────────────────────────────
@app.route("/api/export/<uid>/<fmt>")
@login_required
def api_export(uid, fmt):
    users = load_users()
    if uid not in users: return jsonify({"ok":False,"error":"Not found"})
    configs = users[uid].get("configs",[])
    raw = [c.get("link","") for c in configs if c.get("link")]
    if fmt == "txt":
        content = "\n".join(raw)
        fname = f"{users[uid]['name']}_subscription.txt"
    elif fmt == "b64":
        content = base64.b64encode("\n".join(raw).encode()).decode()
        fname = f"{users[uid]['name']}_subscription_b64.txt"
    else:
        lines = [f"# {c['name']}\n{c.get('link','')}" for c in configs if c.get("link")]
        content = "\n\n".join(lines)
        fname = f"{users[uid]['name']}_links.txt"
    return Response(content, mimetype="text/plain",
                    headers={"Content-Disposition":f"attachment; filename={fname}"})

# ── TLS Test ──────────────────────────────────────────────────
@app.route("/api/test", methods=["POST"])
@login_required
def api_test():
    d = request.get_json() or {}
    t = d.get("type"); host = d.get("host",DOMAIN); port = int(d.get("port",443))
    if t == "tls":
        try:
            ctx = ssl.create_default_context()
            with socket.create_connection((host,port),timeout=5) as s:
                with ctx.wrap_socket(s,server_hostname=host) as ss:
                    return jsonify({"ok":True,"tls_version":ss.version(),"cipher":ss.cipher()[0]})
        except Exception as e: return jsonify({"ok":False,"error":str(e)})
    if t == "port":
        try:
            with socket.create_connection((host,int(port)),timeout=5): return jsonify({"ok":True})
        except Exception as e: return jsonify({"ok":False,"error":str(e)})
    if t == "latency":
        try:
            start = time.time(); socket.create_connection((host,port),timeout=5).close()
            return jsonify({"ok":True,"ms":round((time.time()-start)*1000)})
        except Exception as e: return jsonify({"ok":False,"error":str(e)})
    if t == "all":
        results = {}
        for uid,user in load_users().items():
            for cfg in user.get("configs",[]):
                h = cfg.get("address",DOMAIN); p = cfg.get("port",443)
                try:
                    start = time.time(); socket.create_connection((h,p),timeout=3).close()
                    lat = round((time.time()-start)*1000); ok = True
                except: lat = None; ok = False
                results[cfg["name"]] = {"latency":lat,"port_open":ok,
                    "protocol":cfg["protocol"],"tls":cfg.get("tls","none"),
                    "network":cfg.get("network","tcp"),"connection_type":cfg.get("connection_type","")}
        return jsonify({"ok":True,"results":results})
    return jsonify({"ok":False,"error":"Unknown type"})

# ── Run ───────────────────────────────────────────────────────
if __name__ == "__main__":
    import logging
    from datetime import timedelta
    app.permanent_session_lifetime = timedelta(days=30)
    logging.getLogger("werkzeug").setLevel(logging.WARNING)
    print(f"[MasterPanel v{CURRENT_VERSION}] Starting on port {PANEL_PORT}")
    app.run(host="0.0.0.0", port=PANEL_PORT, debug=False)
