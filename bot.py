#!/usr/bin/env python3
# ============================================================
#   MasterPanel Telegram Bot
#   Full management: users, configs, stats, restart
#   Access: admin (full) + regular users (own configs)
# ============================================================
import json
import logging
import subprocess
import time
from pathlib import Path
from datetime import datetime, timedelta

try:
    import requests
except ImportError:
    subprocess.run(["pip", "install", "requests", "--break-system-packages"], capture_output=True)
    import requests

# ── Paths (shared with panel) ─────────────────────────────────
PANEL_DIR   = Path("/opt/masterpanel")
CONF_FILE   = PANEL_DIR / "panel.conf"
CONFIGS_DIR = PANEL_DIR / "configs"
USERS_FILE  = CONFIGS_DIR / "users.json"
BOT_CONF    = PANEL_DIR / "bot.conf"

logging.basicConfig(level=logging.INFO,
    format="%(asctime)s [bot] %(message)s",
    handlers=[logging.FileHandler(PANEL_DIR / "logs" / "bot.log"),
              logging.StreamHandler()])
log = logging.getLogger("bot")


# ── Config loaders ────────────────────────────────────────────
def load_conf():
    cfg = {}
    if CONF_FILE.exists():
        for line in CONF_FILE.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip()
    return cfg


def load_bot_conf():
    cfg = {}
    if BOT_CONF.exists():
        for line in BOT_CONF.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip()
    return cfg


def load_users():
    if USERS_FILE.exists():
        try:
            return json.loads(USERS_FILE.read_text())
        except Exception:
            pass
    return {}


def save_users(u):
    USERS_FILE.write_text(json.dumps(u, indent=2, ensure_ascii=False))


PANEL = load_conf()
BOTCFG = load_bot_conf()
TOKEN = BOTCFG.get("BOT_TOKEN", "")
ADMIN_IDS = [int(x) for x in BOTCFG.get("ADMIN_IDS", "").split(",") if x.strip().isdigit()]
# Panel now serves HTTPS (self-signed when no domain cert); talk to it over
# loopback and skip cert verification. Carry X-Internal so login_required lets us in.
PANEL_PORT_N = PANEL.get("PANEL_PORT", "9090")
PANEL_URL = f"https://127.0.0.1:{PANEL_PORT_N}"
INTERNAL_HEADERS = {"X-Internal": "1"}
API = f"https://api.telegram.org/bot{TOKEN}"

try:
    import urllib3
    urllib3.disable_warnings()
except Exception:
    pass


# ── Helpers ───────────────────────────────────────────────────
def new_uuid():
    import uuid
    return str(uuid.uuid4())


def new_password(n=20):
    import secrets, string
    alpha = string.ascii_letters + string.digits
    return "".join(secrets.choice(alpha) for _ in range(n))


def is_admin(uid):
    return uid in ADMIN_IDS


def fmt_bytes(b):
    b = float(b or 0)
    for u in ["B", "KB", "MB", "GB", "TB"]:
        if b < 1024:
            return f"{b:.1f} {u}"
        b /= 1024
    return f"{b:.2f} PB"


# ── Telegram API ──────────────────────────────────────────────
def tg(method, **params):
    try:
        r = requests.post(f"{API}/{method}", json=params, timeout=20)
        return r.json()
    except Exception as e:
        log.error(f"tg {method}: {e}")
        return {}


def send(chat_id, text, keyboard=None, parse="HTML"):
    params = {"chat_id": chat_id, "text": text, "parse_mode": parse,
              "disable_web_page_preview": True}
    if keyboard:
        params["reply_markup"] = {"inline_keyboard": keyboard}
    return tg("sendMessage", **params)


def edit(chat_id, msg_id, text, keyboard=None, parse="HTML"):
    params = {"chat_id": chat_id, "message_id": msg_id, "text": text,
              "parse_mode": parse, "disable_web_page_preview": True}
    if keyboard:
        params["reply_markup"] = {"inline_keyboard": keyboard}
    return tg("editMessageText", **params)


def answer_cb(cb_id, text=""):
    tg("answerCallbackQuery", callback_query_id=cb_id, text=text)


# ── Keyboards ─────────────────────────────────────────────────
def admin_menu():
    return [
        [{"text": "👥 کاربران", "callback_data": "users"},
         {"text": "➕ کاربر جدید", "callback_data": "newuser"}],
        [{"text": "📊 آمار سرور", "callback_data": "stats"},
         {"text": "⚙️ وضعیت", "callback_data": "status"}],
        [{"text": "🔄 ری‌استارت Xray", "callback_data": "restart_xray"},
         {"text": "✨ ساخت کانفیگ‌ها", "callback_data": "genall"}],
    ]


def user_menu():
    return [
        [{"text": "📱 کانفیگ‌های من", "callback_data": "myconfigs"}],
        [{"text": "📊 مصرف من", "callback_data": "myusage"}],
    ]


def back_btn(to="menu"):
    return [[{"text": "« بازگشت", "callback_data": to}]]


# ── Server actions ────────────────────────────────────────────
def get_status():
    def active(svc):
        r = subprocess.run(["systemctl", "is-active", svc],
                           capture_output=True, text=True)
        return r.stdout.strip() == "active"
    return {
        "panel": active("masterpanel"),
        "xray": active("xray"),
        "tuic": active("tuic-server"),
        "hy2": active("hysteria2"),
    }


def restart_xray():
    subprocess.run(["systemctl", "restart", "xray"], capture_output=True, timeout=20)
    time.sleep(2)
    return get_status()["xray"]


def get_traffic_stats():
    """Query Xray API for traffic."""
    xray_bin = PANEL.get("XRAY_BIN", "/usr/local/bin/xray")
    try:
        r = subprocess.run([xray_bin, "api", "statsquery", "--server=127.0.0.1:10085"],
                           capture_output=True, text=True, timeout=8)
        data = json.loads(r.stdout)
        total_up = total_down = 0
        for item in data.get("stat", []):
            name = item.get("name", "")
            val = int(item.get("value", 0))
            if "uplink" in name:
                total_up += val
            elif "downlink" in name:
                total_down += val
        return total_up, total_down
    except Exception:
        return 0, 0


# ── Command handlers ──────────────────────────────────────────
def handle_start(chat_id, uid, name):
    if is_admin(uid):
        send(chat_id,
             f"👋 سلام <b>{name}</b>\n\n🛡 <b>پنل مدیریت MasterPanel</b>\n"
             f"شما دسترسی <b>ادمین</b> دارید.\n\nیک گزینه را انتخاب کنید:",
             admin_menu())
    else:
        # Regular user — find them by telegram_id
        users = load_users()
        linked = next((u for u in users.values() if u.get("telegram_id") == uid), None)
        if linked:
            send(chat_id,
                 f"👋 سلام <b>{linked['name']}</b>\n\nبه پنل کاربری خوش آمدید:",
                 user_menu())
        else:
            send(chat_id,
                 f"👋 سلام <b>{name}</b>\n\n"
                 f"حساب شما هنوز به یک کاربر VPN متصل نشده.\n"
                 f"کد اتصال خود را از ادمین بگیرید و ارسال کنید:\n\n"
                 f"<code>/link CODE</code>")


def handle_users_list(chat_id, msg_id=None):
    users = load_users()
    if not users:
        txt = "👥 <b>کاربران</b>\n\nهیچ کاربری وجود ندارد."
        kb = [[{"text": "➕ کاربر جدید", "callback_data": "newuser"}]] + back_btn()
    else:
        txt = f"👥 <b>کاربران</b> ({len(users)})\n\n"
        kb = []
        for u in list(users.values())[:20]:
            used = fmt_bytes(u.get("used_bytes", 0))
            limit = f"{u['limit_gb']}GB" if u.get("limit_gb", 0) > 0 else "∞"
            status = "🟢" if u.get("enabled", True) else "🔴"
            cfg_n = len(u.get("configs", []))
            txt += f"{status} <b>{u['name']}</b> — {used}/{limit} — {cfg_n} کانفیگ\n"
            kb.append([{"text": f"⚙️ {u['name']}", "callback_data": f"user_{u['id']}"}])
        kb += back_btn()
    if msg_id:
        edit(chat_id, msg_id, txt, kb)
    else:
        send(chat_id, txt, kb)


def handle_user_detail(chat_id, msg_id, user_id):
    users = load_users()
    u = users.get(user_id)
    if not u:
        edit(chat_id, msg_id, "کاربر یافت نشد.", back_btn("users"))
        return
    used = fmt_bytes(u.get("used_bytes", 0))
    limit = f"{u['limit_gb']}GB" if u.get("limit_gb", 0) > 0 else "نامحدود"
    status = "فعال 🟢" if u.get("enabled", True) else "غیرفعال 🔴"
    expire = u.get("expire_at") or "بدون انقضا"
    cfg_n = len(u.get("configs", []))
    txt = (f"👤 <b>{u['name']}</b>\n\n"
           f"وضعیت: {status}\n"
           f"مصرف: {used} / {limit}\n"
           f"انقضا: {expire}\n"
           f"کانفیگ‌ها: {cfg_n}\n"
           f"ساخته شده: {u.get('created_at','—')}\n"
           f"UUID: <code>{u['uuid']}</code>")
    toggle = "🔴 غیرفعال کن" if u.get("enabled", True) else "🟢 فعال کن"
    kb = [
        [{"text": "📱 کانفیگ‌ها", "callback_data": f"ucfg_{user_id}"},
         {"text": "✨ ساخت کانفیگ", "callback_data": f"ugen_{user_id}"}],
        [{"text": toggle, "callback_data": f"utog_{user_id}"},
         {"text": "🔗 کد اتصال", "callback_data": f"ulink_{user_id}"}],
        [{"text": "🗑 حذف کاربر", "callback_data": f"udel_{user_id}"}],
    ] + back_btn("users")
    edit(chat_id, msg_id, txt, kb)


def handle_user_configs(chat_id, msg_id, user_id):
    users = load_users()
    u = users.get(user_id)
    if not u or not u.get("configs"):
        edit(chat_id, msg_id, "کانفیگی وجود ندارد. اول «ساخت کانفیگ» را بزنید.",
             back_btn(f"user_{user_id}"))
        return
    # Send configs as subscription text
    links = [c.get("link", "") for c in u["configs"] if c.get("link")]
    txt = f"📱 <b>کانفیگ‌های {u['name']}</b> ({len(links)})\n\n"
    txt += "برای کپی، روی هرکدام بزنید:\n\n"
    edit(chat_id, msg_id, txt, back_btn(f"user_{user_id}"))
    # Send links in chunks (each as copyable code)
    chunk = ""
    for link in links:
        if len(chunk) + len(link) > 3500:
            send(chat_id, f"<code>{chunk}</code>")
            chunk = ""
        chunk += link + "\n\n"
    if chunk:
        send(chat_id, f"<code>{chunk}</code>")


def handle_user_generate(chat_id, msg_id, user_id):
    edit(chat_id, msg_id, "⏳ در حال ساخت کانفیگ‌ها...", None)
    try:
        r = requests.post(f"{PANEL_URL}/api/users/{user_id}/generate",
                          headers=INTERNAL_HEADERS, json={"proto": "all"},
                          verify=False, timeout=90)
        d = r.json() if r.status_code == 200 else {}
        if d.get("ok"):
            edit(chat_id, msg_id, f"✅ {d['count']} کانفیگ ساخته شد!",
                 [[{"text": "📱 مشاهده کانفیگ‌ها", "callback_data": f"ucfg_{user_id}"}]] + back_btn(f"user_{user_id}"))
        else:
            edit(chat_id, msg_id,
                 f"⚠️ ساخت ناموفق: {d.get('error','نامشخص')}",
                 back_btn(f"user_{user_id}"))
    except Exception as e:
        edit(chat_id, msg_id, f"❌ خطا: {e}", back_btn(f"user_{user_id}"))


def handle_user_toggle(chat_id, msg_id, user_id):
    users = load_users()
    u = users.get(user_id)
    if u:
        u["enabled"] = not u.get("enabled", True)
        save_users(users)
    handle_user_detail(chat_id, msg_id, user_id)


def handle_user_link(chat_id, msg_id, user_id):
    """Generate a one-time link code for the user to connect their telegram."""
    users = load_users()
    u = users.get(user_id)
    if not u:
        return
    code = new_password(8)
    u["link_code"] = code
    save_users(users)
    txt = (f"🔗 <b>کد اتصال {u['name']}</b>\n\n"
           f"این کد را به کاربر بدهید تا در ربات ارسال کند:\n\n"
           f"<code>/link {code}</code>")
    edit(chat_id, msg_id, txt, back_btn(f"user_{user_id}"))


def handle_user_delete(chat_id, msg_id, user_id):
    users = load_users()
    if user_id in users:
        name = users[user_id]["name"]
        del users[user_id]
        save_users(users)
        edit(chat_id, msg_id, f"🗑 کاربر <b>{name}</b> حذف شد.", back_btn("users"))
    else:
        edit(chat_id, msg_id, "کاربر یافت نشد.", back_btn("users"))


def handle_stats(chat_id, msg_id):
    up, down = get_traffic_stats()
    users = load_users()
    total_users = len(users)
    active_users = sum(1 for u in users.values() if u.get("enabled", True))
    txt = (f"📊 <b>آمار سرور</b>\n\n"
           f"⬆️ آپلود کل: {fmt_bytes(up)}\n"
           f"⬇️ دانلود کل: {fmt_bytes(down)}\n"
           f"📦 مجموع: {fmt_bytes(up + down)}\n\n"
           f"👥 کاربران: {active_users}/{total_users} فعال")
    edit(chat_id, msg_id, txt, back_btn())


def handle_server_status(chat_id, msg_id):
    s = get_status()
    def icon(x): return "🟢 فعال" if x else "🔴 خاموش"
    txt = (f"⚙️ <b>وضعیت سرویس‌ها</b>\n\n"
           f"پنل: {icon(s['panel'])}\n"
           f"Xray: {icon(s['xray'])}\n"
           f"TUIC: {icon(s['tuic'])}\n"
           f"Hysteria2: {icon(s['hy2'])}\n\n"
           f"🌐 IP: <code>{PANEL.get('DOMAIN','—')}</code>")
    edit(chat_id, msg_id, txt, back_btn())


def handle_restart_xray(chat_id, msg_id):
    edit(chat_id, msg_id, "⏳ در حال ری‌استارت Xray...", None)
    ok = restart_xray()
    edit(chat_id, msg_id,
         "✅ Xray ری‌استارت شد" if ok else "❌ Xray استارت نشد — لاگ را بررسی کنید",
         back_btn())


def handle_link_command(chat_id, uid, code):
    users = load_users()
    u = next((u for u in users.values() if u.get("link_code") == code), None)
    if u:
        u["telegram_id"] = uid
        u.pop("link_code", None)
        save_users(users)
        send(chat_id, f"✅ حساب شما به کاربر <b>{u['name']}</b> متصل شد!", user_menu())
    else:
        send(chat_id, "❌ کد نامعتبر است.")


def handle_my_configs(chat_id, uid, msg_id):
    users = load_users()
    u = next((u for u in users.values() if u.get("telegram_id") == uid), None)
    if not u or not u.get("configs"):
        edit(chat_id, msg_id, "کانفیگی برای شما وجود ندارد. با ادمین تماس بگیرید.",
             back_btn())
        return
    links = [c.get("link", "") for c in u["configs"] if c.get("link")]
    edit(chat_id, msg_id, f"📱 <b>{len(links)} کانفیگ شما</b>\n\nدر پیام‌های بعدی:", back_btn())
    chunk = ""
    for link in links:
        if len(chunk) + len(link) > 3500:
            send(chat_id, f"<code>{chunk}</code>")
            chunk = ""
        chunk += link + "\n\n"
    if chunk:
        send(chat_id, f"<code>{chunk}</code>")


def handle_my_usage(chat_id, uid, msg_id):
    users = load_users()
    u = next((u for u in users.values() if u.get("telegram_id") == uid), None)
    if not u:
        edit(chat_id, msg_id, "حساب متصل نیست.", back_btn())
        return
    used = fmt_bytes(u.get("used_bytes", 0))
    limit = f"{u['limit_gb']}GB" if u.get("limit_gb", 0) > 0 else "نامحدود"
    expire = u.get("expire_at") or "بدون انقضا"
    txt = (f"📊 <b>مصرف شما</b>\n\n"
           f"کاربر: {u['name']}\n"
           f"مصرف: {used} / {limit}\n"
           f"انقضا: {expire}")
    edit(chat_id, msg_id, txt, back_btn())


# ── New user flow (admin) ─────────────────────────────────────
PENDING = {}  # chat_id -> state


def handle_newuser_start(chat_id, msg_id):
    PENDING[chat_id] = {"step": "name"}
    edit(chat_id, msg_id, "➕ <b>کاربر جدید</b>\n\nنام کاربر را ارسال کنید:", None)


def handle_newuser_input(chat_id, uid, text):
    st = PENDING.get(chat_id)
    if not st:
        return False
    if st["step"] == "name":
        st["name"] = text.strip()
        st["step"] = "limit"
        send(chat_id, f"نام: <b>{text}</b>\n\nحجم مصرف به GB (0 = نامحدود):")
    elif st["step"] == "limit":
        try:
            st["limit_gb"] = float(text)
        except ValueError:
            st["limit_gb"] = 0
        st["step"] = "days"
        send(chat_id, "تعداد روز انقضا (0 = بدون انقضا):")
    elif st["step"] == "days":
        try:
            days = int(text)
        except ValueError:
            days = 0
        # Create user
        users = load_users()
        uid_new = new_uuid()
        expire = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d") if days > 0 else ""
        users[uid_new] = {
            "id": uid_new, "name": st["name"], "uuid": new_uuid(),
            "password": new_password(20), "limit_gb": st["limit_gb"],
            "expire_at": expire, "created_at": datetime.now().strftime("%Y-%m-%d %H:%M"),
            "enabled": True, "used_bytes": 0, "configs": []
        }
        save_users(users)
        del PENDING[chat_id]
        send(chat_id,
             f"✅ کاربر <b>{st['name']}</b> ساخته شد!\n\n"
             f"حالا از پنل یا دکمه زیر کانفیگ بسازید.",
             [[{"text": "⚙️ مدیریت کاربر", "callback_data": f"user_{uid_new}"}]] + back_btn())
    return True


# ── Update loop ───────────────────────────────────────────────
def handle_callback(cb):
    data = cb["data"]
    chat_id = cb["message"]["chat"]["id"]
    msg_id = cb["message"]["message_id"]
    uid = cb["from"]["id"]
    cb_id = cb["id"]
    answer_cb(cb_id)

    # User-level callbacks (no admin needed)
    if data == "myconfigs":
        handle_my_configs(chat_id, uid, msg_id); return
    if data == "myusage":
        handle_my_usage(chat_id, uid, msg_id); return
    if data == "menu":
        if is_admin(uid):
            edit(chat_id, msg_id, "🛡 منوی اصلی:", admin_menu())
        else:
            edit(chat_id, msg_id, "منوی کاربری:", user_menu())
        return

    # Admin-only below
    if not is_admin(uid):
        answer_cb(cb_id, "دسترسی ندارید")
        return

    if data == "users":
        handle_users_list(chat_id, msg_id)
    elif data == "newuser":
        handle_newuser_start(chat_id, msg_id)
    elif data == "stats":
        handle_stats(chat_id, msg_id)
    elif data == "status":
        handle_server_status(chat_id, msg_id)
    elif data == "restart_xray":
        handle_restart_xray(chat_id, msg_id)
    elif data == "genall":
        edit(chat_id, msg_id,
             "✨ برای ساخت همه کانفیگ‌ها از پنل وب دکمه «ساخت همه پروتکل‌ها» را بزنید.\n"
             "(این عملیات نیاز به لاگین پنل دارد)", back_btn())
    elif data.startswith("user_"):
        handle_user_detail(chat_id, msg_id, data[5:])
    elif data.startswith("ucfg_"):
        handle_user_configs(chat_id, msg_id, data[5:])
    elif data.startswith("ugen_"):
        handle_user_generate(chat_id, msg_id, data[5:])
    elif data.startswith("utog_"):
        handle_user_toggle(chat_id, msg_id, data[5:])
    elif data.startswith("ulink_"):
        handle_user_link(chat_id, msg_id, data[6:])
    elif data.startswith("udel_"):
        handle_user_delete(chat_id, msg_id, data[5:])


def handle_message(msg):
    chat_id = msg["chat"]["id"]
    uid = msg["from"]["id"]
    name = msg["from"].get("first_name", "کاربر")
    text = msg.get("text", "")

    if text.startswith("/start"):
        PENDING.pop(chat_id, None)
        handle_start(chat_id, uid, name)
    elif text.startswith("/link "):
        handle_link_command(chat_id, uid, text.split(" ", 1)[1].strip())
    elif chat_id in PENDING and is_admin(uid):
        handle_newuser_input(chat_id, uid, text)
    elif text.startswith("/menu"):
        handle_start(chat_id, uid, name)


def main():
    if not TOKEN:
        log.error("BOT_TOKEN not set in bot.conf — exiting")
        return
    log.info(f"Bot started. Admins: {ADMIN_IDS}")
    offset = 0
    while True:
        try:
            r = requests.get(f"{API}/getUpdates",
                           params={"offset": offset, "timeout": 30}, timeout=40)
            updates = r.json().get("result", [])
            for up in updates:
                offset = up["update_id"] + 1
                if "callback_query" in up:
                    handle_callback(up["callback_query"])
                elif "message" in up:
                    handle_message(up["message"])
        except requests.exceptions.Timeout:
            continue
        except Exception as e:
            log.error(f"loop: {e}")
            time.sleep(3)


if __name__ == "__main__":
    main()
