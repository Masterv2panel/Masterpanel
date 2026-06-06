#!/bin/bash
# ============================================================
#   MasterPanel Fix Script
#   1. HTTPS روی پورت 9090
#   2. بات تلگرام - رفع مشکل دکمه‌ها
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step()  { echo -e "${BLUE}[→]${NC} $1"; }

PANEL_DIR="/opt/masterpanel"
CONF_FILE="$PANEL_DIR/panel.conf"

# ── Load config ──────────────────────────────────────────────
load_conf() {
    DOMAIN=$(grep "^DOMAIN=" "$CONF_FILE" | cut -d= -f2)
    PANEL_PORT=$(grep "^PANEL_PORT=" "$CONF_FILE" | cut -d= -f2)
    CERT_PATH=$(grep "^CERT_PATH=" "$CONF_FILE" | cut -d= -f2)
    KEY_PATH=$(grep "^KEY_PATH=" "$CONF_FILE" | cut -d= -f2)
}

load_conf
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   MasterPanel Fix - HTTPS + Bot        ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "دامنه   : ${YELLOW}$DOMAIN${NC}"
echo -e "پورت    : ${YELLOW}$PANEL_PORT${NC}"
echo -e "سرتیفیکت: ${YELLOW}$CERT_PATH${NC}"
echo ""

# ── Step 1: Check cert ───────────────────────────────────────
log_step "بررسی SSL سرتیفیکت..."
if [[ ! -f "$CERT_PATH" ]]; then
    log_error "سرتیفیکت پیدا نشد: $CERT_PATH"
    log_warn "در حال گرفتن سرتیفیکت جدید..."
    systemctl stop masterpanel 2>/dev/null
    fuser -k 80/tcp 2>/dev/null || true
    sleep 1
    certbot certonly --standalone --non-interactive --agree-tos \
        --register-unsafely-without-email -d "$DOMAIN" 2>&1 | tail -3
    if [[ ! -f "$CERT_PATH" ]]; then
        log_error "گرفتن سرتیفیکت ناموفق بود. DNS را چک کنید."
        exit 1
    fi
fi
log_info "سرتیفیکت OK"

# ── Step 2: Patch masterpanel.py - Add HTTPS ─────────────────
log_step "اضافه کردن HTTPS به پنل..."

# Backup
cp "$PANEL_DIR/masterpanel.py" "$PANEL_DIR/masterpanel.py.bak.$(date +%s)"

# Patch the app.run line to use SSL
python3 << 'PYEOF'
import re

path = "/opt/masterpanel/masterpanel.py"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

# Replace the run section at the bottom
old_run = '''# ── Run ───────────────────────────────────────────────────────
if __name__ == "__main__":
    import logging
    from datetime import timedelta
    app.permanent_session_lifetime = timedelta(days=30)
    logging.getLogger("werkzeug").setLevel(logging.WARNING)
    print(f"[MasterPanel v{CURRENT_VERSION}] Starting on port {PANEL_PORT}")
    app.run(host="0.0.0.0", port=PANEL_PORT, debug=False)'''

new_run = '''# ── Run ───────────────────────────────────────────────────────
if __name__ == "__main__":
    import logging
    from datetime import timedelta
    app.permanent_session_lifetime = timedelta(days=30)
    logging.getLogger("werkzeug").setLevel(logging.WARNING)
    print(f"[MasterPanel v{CURRENT_VERSION}] Starting on port {PANEL_PORT}")

    # Use HTTPS if cert and key exist
    ssl_ctx = None
    if CERT_PATH and KEY_PATH:
        from pathlib import Path as _P
        if _P(CERT_PATH).exists() and _P(KEY_PATH).exists():
            import ssl as _ssl
            ssl_ctx = _ssl.SSLContext(_ssl.PROTOCOL_TLS_SERVER)
            ssl_ctx.load_cert_chain(CERT_PATH, KEY_PATH)
            print(f"[MasterPanel] HTTPS enabled with cert: {CERT_PATH}")
        else:
            print(f"[MasterPanel] WARNING: cert not found, running HTTP")

    app.run(host="0.0.0.0", port=PANEL_PORT, debug=False,
            ssl_context=ssl_ctx if ssl_ctx else None)'''

if old_run in content:
    content = content.replace(old_run, new_run)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("✅ HTTPS patch applied")
else:
    # Try partial match on just the app.run line
    content = re.sub(
        r'app\.run\(host="0\.0\.0\.0", port=PANEL_PORT, debug=False\)',
        '''app.run(host="0.0.0.0", port=PANEL_PORT, debug=False,
            ssl_context=(__import__("ssl").SSLContext(__import__("ssl").PROTOCOL_TLS_SERVER) if (
                CERT_PATH and KEY_PATH and
                __import__("pathlib").Path(CERT_PATH).exists() and
                __import__("pathlib").Path(KEY_PATH).exists() and
                __import__("ssl").SSLContext(__import__("ssl").PROTOCOL_TLS_SERVER).load_cert_chain(CERT_PATH, KEY_PATH) or True
            ) else None) if False else None)''',
        content
    )
    # Simpler approach - inject before app.run
    content2 = open(path).read()
    if 'ssl_context=ssl_ctx' not in content2:
        # Direct injection method
        inject = '''
    # SSL context for HTTPS
    _ssl_ctx = None
    try:
        from pathlib import Path as _P2
        if CERT_PATH and KEY_PATH and _P2(CERT_PATH).exists() and _P2(KEY_PATH).exists():
            import ssl as _ssl2
            _ssl_ctx = _ssl2.SSLContext(_ssl2.PROTOCOL_TLS_SERVER)
            _ssl_ctx.load_cert_chain(CERT_PATH, KEY_PATH)
            print(f"[MasterPanel] HTTPS enabled!")
    except Exception as _e:
        print(f"[MasterPanel] SSL setup failed: {_e}")
'''
        content2 = content2.replace(
            'app.run(host="0.0.0.0", port=PANEL_PORT, debug=False)',
            inject + '    app.run(host="0.0.0.0", port=PANEL_PORT, debug=False, ssl_context=_ssl_ctx)'
        )
        with open(path, "w") as f:
            f.write(content2)
        print("✅ HTTPS patch applied (method 2)")
    else:
        print("✅ HTTPS already patched")
PYEOF

log_info "پنل patch شد"

# ── Step 3: Patch bot.py - Fix PANEL_URL for HTTPS ───────────
log_step "اصلاح بات تلگرام برای HTTPS..."

python3 << 'PYEOF'
path = "/opt/masterpanel/bot.py"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

# Fix PANEL_URL to use https
old_url = 'PANEL_URL = f"http://127.0.0.1:{PANEL.get(\'PANEL_PORT\', \'9090\')}"'
new_url = 'PANEL_URL = f"https://127.0.0.1:{PANEL.get(\'PANEL_PORT\', \'9090\')}"'

if old_url in content:
    content = content.replace(old_url, new_url)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("✅ Bot PANEL_URL updated to HTTPS")
elif 'https://127.0.0.1' in content:
    print("✅ Bot already using HTTPS")
else:
    print("⚠️  Could not find PANEL_URL line - check manually")
PYEOF

# ── Step 4: Fix bot - add verify=False for self-signed ───────
log_step "اصلاح SSL verification در بات..."

python3 << 'PYEOF'
path = "/opt/masterpanel/bot.py"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

# Add verify=False to all requests calls to panel
import re

# Fix the generate request
old_gen = 'r = requests.post(f"{PANEL_URL}/api/users/{user_id}/generate",\n                         cookies={"session": "bot"}, timeout=60)'
new_gen = 'r = requests.post(f"{PANEL_URL}/api/users/{user_id}/generate",\n                         cookies={"session": "bot"}, timeout=60, verify=False)'

if old_gen in content:
    content = content.replace(old_gen, new_gen)
    print("✅ Fixed generate request")

# Suppress SSL warnings
if 'urllib3.disable_warnings' not in content:
    insert_after = 'import requests\nexcept ImportError:'
    # Add at top after requests import
    content = content.replace(
        'try:\n    import requests\nexcept ImportError:\n    subprocess.run(["pip", "install", "requests", "--break-system-packages"], capture_output=True)\n    import requests',
        'try:\n    import requests\nexcept ImportError:\n    subprocess.run(["pip", "install", "requests", "--break-system-packages"], capture_output=True)\n    import requests\n\ntry:\n    import urllib3\n    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)\nexcept Exception:\n    pass'
    )
    print("✅ SSL warnings suppressed")

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF

# ── Step 5: Add internal bot API endpoint to panel ───────────
log_step "اضافه کردن API داخلی بدون auth برای بات..."

python3 << 'PYEOF'
path = "/opt/masterpanel/masterpanel.py"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

# Check if already patched
if "X-Bot-Internal" in content:
    print("✅ Internal bot API already exists")
    exit()

# Add internal token check helper and bypass for bot
internal_api = '''
# ── Internal Bot API (no session needed, token-based) ─────────
def is_internal_bot(req):
    """Check if request comes from local bot with internal token."""
    internal_token = Path("/opt/masterpanel/.bot_token").read_text().strip() if Path("/opt/masterpanel/.bot_token").exists() else ""
    return (req.remote_addr in ("127.0.0.1", "::1") and
            req.headers.get("X-Bot-Internal") == internal_token and
            internal_token != "")

@app.route("/api/internal/users/<uid>/generate", methods=["POST"])
def api_internal_user_generate(uid):
    """Internal endpoint for bot - no session required."""
    if not is_internal_bot(request):
        return jsonify({"ok": False, "error": "Unauthorized"}), 403
    return api_user_generate(uid)

@app.route("/api/internal/users", methods=["GET"])
def api_internal_users_list():
    """Internal endpoint for bot - no session required."""
    if not is_internal_bot(request):
        return jsonify({"ok": False, "error": "Unauthorized"}), 403
    return api_users_list()

'''

# Insert before the Run section
marker = "# ── Run ───────────────────────────────────────────────────────"
if marker in content:
    content = content.replace(marker, internal_api + marker)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("✅ Internal bot API added")
else:
    print("⚠️  Could not find insertion point")
PYEOF

# ── Step 6: Generate internal bot token ──────────────────────
log_step "ساخت توکن داخلی بات..."
BOT_TOKEN_FILE="$PANEL_DIR/.bot_token"
if [[ ! -f "$BOT_TOKEN_FILE" ]]; then
    python3 -c "import secrets; print(secrets.token_hex(32))" > "$BOT_TOKEN_FILE"
    chmod 600 "$BOT_TOKEN_FILE"
fi
BOT_INTERNAL_TOKEN=$(cat "$BOT_TOKEN_FILE")
log_info "توکن داخلی: ${BOT_INTERNAL_TOKEN:0:8}..."

# ── Step 7: Update bot.py to use internal API ────────────────
log_step "آپدیت بات برای استفاده از API داخلی..."

python3 << PYEOF
import re

path = "/opt/masterpanel/bot.py"
token = open("/opt/masterpanel/.bot_token").read().strip()

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

# Update PANEL_URL line and add BOT_INTERNAL_TOKEN
old_panel_url = 'PANEL_URL = f"https://127.0.0.1:{PANEL.get(\'PANEL_PORT\', \'9090\')}"'
new_panel_url = '''PANEL_URL = f"https://127.0.0.1:{PANEL.get('PANEL_PORT', '9090')}"
BOT_INTERNAL_TOKEN = open("/opt/masterpanel/.bot_token").read().strip() if __import__("pathlib").Path("/opt/masterpanel/.bot_token").exists() else ""
BOT_HEADERS = {"X-Bot-Internal": BOT_INTERNAL_TOKEN}'''

if 'BOT_INTERNAL_TOKEN' not in content:
    if old_panel_url in content:
        content = content.replace(old_panel_url, new_panel_url)
    elif 'PANEL_URL = f"http://127.0.0.1' in content:
        content = content.replace(
            'PANEL_URL = f"http://127.0.0.1:{PANEL.get(\'PANEL_PORT\', \'9090\')}"',
            new_panel_url.replace('https', 'https')
        )

# Fix handle_user_generate to use internal endpoint
old_gen_func = '''def handle_user_generate(chat_id, msg_id, user_id):
    edit(chat_id, msg_id, "⏳ در حال ساخت کانفیگ‌ها...", None)
    try:
        # Call panel API via session-less internal call by invoking the generator directly
        r = requests.post(f"{PANEL_URL}/api/users/{user_id}/generate",
                         cookies={"session": "bot"}, timeout=60, verify=False)
        # The panel requires login; instead call the local generation
        # Fallback: trigger via panel is auth-protected, so we generate inline
        d = r.json() if r.status_code == 200 else {}
        if d.get("ok"):
            edit(chat_id, msg_id, f"✅ {d['count']} کانفیگ ساخته شد!",
                 [[{"text": "📱 مشاهده کانفیگ‌ها", "callback_data": f"ucfg_{user_id}"}]] + back_btn(f"user_{user_id}"))
        else:
            edit(chat_id, msg_id,
                 "⚠️ ساخت از طریق بات نیاز به لاگین پنل دارد.\\n"
                 "لطفاً از خود پنل وب کانفیگ بسازید.",
                 back_btn(f"user_{user_id}"))
    except Exception as e:
        edit(chat_id, msg_id, f"❌ خطا: {e}", back_btn(f"user_{user_id}"))'''

new_gen_func = '''def handle_user_generate(chat_id, msg_id, user_id):
    edit(chat_id, msg_id, "⏳ در حال ساخت کانفیگ‌ها...", None)
    try:
        r = requests.post(
            f"{PANEL_URL}/api/internal/users/{user_id}/generate",
            headers=BOT_HEADERS, timeout=60, verify=False
        )
        d = r.json() if r.status_code == 200 else {}
        if d.get("ok"):
            cnt = d.get("count", len(d.get("configs", [])))
            edit(chat_id, msg_id, f"✅ {cnt} کانفیگ ساخته شد!",
                 [[{"text": "📱 مشاهده کانفیگ‌ها", "callback_data": f"ucfg_{user_id}"}]] + back_btn(f"user_{user_id}"))
        else:
            err = d.get("error", "خطای نامشخص")
            edit(chat_id, msg_id, f"❌ {err}", back_btn(f"user_{user_id}"))
    except Exception as e:
        edit(chat_id, msg_id, f"❌ خطا: {e}", back_btn(f"user_{user_id}"))'''

if old_gen_func in content:
    content = content.replace(old_gen_func, new_gen_func)
    print("✅ handle_user_generate fixed")
elif '/api/internal/users/' in content:
    print("✅ already using internal API")
else:
    # Partial fix - just replace the URL
    content = re.sub(
        r'requests\.post\(f"\{PANEL_URL\}/api/users/\{user_id\}/generate"',
        'requests.post(f"{PANEL_URL}/api/internal/users/{user_id}/generate", headers=BOT_HEADERS',
        content
    )
    print("✅ URL updated (partial fix)")

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF

# ── Step 8: Update Nginx to also proxy panel on 443 ──────────
log_step "اضافه کردن پروکسی پنل در Nginx (پورت 443)..."

CERT="$CERT_PATH"
KEY="$KEY_PATH"

# Check if nginx is installed
if command -v nginx &>/dev/null; then
    cat > /etc/nginx/sites-available/masterpanel-panel << NGINX
server {
    listen 8443 ssl;
    server_name ${DOMAIN};

    ssl_certificate     ${CERT};
    ssl_certificate_key ${KEY};
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass https://127.0.0.1:9090;
        proxy_ssl_verify off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 300;
    }
}
NGINX

    # Only enable if not already
    if [[ ! -f /etc/nginx/sites-enabled/masterpanel-panel ]]; then
        ln -sf /etc/nginx/sites-available/masterpanel-panel /etc/nginx/sites-enabled/masterpanel-panel
    fi

    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        ufw allow 8443/tcp > /dev/null 2>&1 || true
        log_info "Nginx proxy روی پورت 8443 فعال شد"
    else
        log_warn "Nginx config خطا داشت، skip شد"
        rm -f /etc/nginx/sites-enabled/masterpanel-panel
    fi
else
    log_warn "Nginx نصب نیست، skip"
fi

# ── Step 9: Restart services ──────────────────────────────────
log_step "ری‌استارت سرویس‌ها..."
systemctl restart masterpanel
sleep 2

# Restart bot if running
if systemctl is-active --quiet masterpanel-bot 2>/dev/null; then
    systemctl restart masterpanel-bot
    log_info "Bot ری‌استارت شد"
fi

# ── Step 10: Verify ───────────────────────────────────────────
log_step "تست اتصال..."
sleep 2

if curl -sk https://127.0.0.1:9090 -o /dev/null -w "%{http_code}" | grep -qE "200|302"; then
    log_info "پنل HTTPS روی پورت 9090 OK ✅"
else
    CODE=$(curl -sk https://127.0.0.1:9090 -o /dev/null -w "%{http_code}" 2>/dev/null)
    log_warn "پنل کد $CODE برگرداند (ممکنه نیاز به چند ثانیه بیشتر داشته باشه)"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}           تمام شد!                     ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "📌 آدرس پنل (جدید):"
echo -e "   ${CYAN}https://95.182.86.214:9090${NC}"
echo -e "   ${CYAN}https://${DOMAIN}:9090${NC}"
echo ""
echo -e "📌 آدرس پنل از طریق Nginx:"
echo -e "   ${CYAN}https://${DOMAIN}:8443${NC}"
echo ""
echo -e "⚠️  توجه: اگر مرورگر خطای سرتیفیکت داد، گزینه"
echo -e "   'Advanced > Proceed' رو بزنید (برای IP مستقیم طبیعیه)"
echo ""
