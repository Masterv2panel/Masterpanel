<div align="center">

# 🛡️ MasterPanel

**پنل مدیریت حرفه‌ای پروتکل‌های Xray — رابط کاربری فارسی**

[![Version](https://img.shields.io/badge/version-4.7.0-blue?style=for-the-badge)](https://github.com/Masterv2panel/Masterpanel/releases)
[![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-orange?style=for-the-badge)](https://github.com/Masterv2panel/Masterpanel)
[![Python](https://img.shields.io/badge/python-3.8+-yellow?style=for-the-badge)](https://python.org)

</div>

---

## 🌟 معرفی

MasterPanel یک پنل مدیریت VPN متن‌باز است که روی Xray-core ساخته شده و برای کاربران فارسی‌زبان طراحی شده. با یک دستور نصب می‌شود، SSL واقعی می‌گیرد، و بدون نیاز به دانش فنی قابل استفاده است.

---

## ✨ قابلیت‌های کامل

### مدیریت کاربران
- ساخت کاربر با UUID و پسورد اختصاصی
- محدودیت ترافیک (GB) با اعمال خودکار
- تاریخ انقضا با اعمال خودکار
- فعال/غیرفعال کردن فوری کاربر
- ریست ترافیک مصرفی
- تمدید اشتراک
- لینک سابسکریپشن اختصاصی برای هر کاربر
- پیوند حساب تلگرام به کاربر VPN

### ساخت کانفیگ
- ساخت خودکار همه پروتکل‌ها با یک کلیک
- ساخت کانفیگ اختصاصی به ازای هر کاربر
- ساخت پروتکل خاص برای کاربر (بدون پاک کردن بقیه)
- QR Code برای هر کانفیگ
- کپی لینک منفرد یا همه لینک‌ها
- لینک سابسکریپشن Base64 (سازگار با v2rayNG، Nekobox، Hiddify، Streisand)
- دانلود فایل txt همه لینک‌ها

### مانیتورینگ
- نمودار CPU، RAM، دیسک، شبکه (real-time)
- آمار ترافیک کل و per-user از Xray API
- وضعیت سرویس‌های Panel و Xray
- لاگ‌های Xray (آخرین ۵۰ خط)
- نمایش uptime سرور

### تست اتصال
- تست باز بودن پورت
- تست لیتنسی (ms)
- بررسی TLS handshake و Cipher Suite
- تست همزمان همه کانفیگ‌ها

### SSL و امنیت
- دریافت خودکار گواهی Let's Encrypt هنگام نصب
- پشتیبانی از subdomain جداگانه برای پنل (بدون هشدار مرورگر)
- تمدید خودکار SSL (crontab روزانه)
- fallback به self-signed اگر Let's Encrypt ناموفق باشد
- Session cookie امن (HttpOnly + Secure + SameSite)

### ربات تلگرام
- مدیریت کامل از تلگرام (ادمین)
- دریافت کانفیگ و مشاهده مصرف (کاربر)
- نوتیف خودکار انقضا (۳ روز مانده، روز آخر)
- نوتیف مصرف ترافیک (۸۰٪ و ۹۵٪)
- اطلاع‌رسانی غیرفعال شدن کاربر به ادمین
- لینک سابسکریپشن مستقیم از ربات

### آپدیت و مدیریت
- آپدیت یک‌کلیکی از داخل پنل
- CLI کامل (`mp.sh`) برای مدیریت از سرور
- فیلتر تبلیغات (geosite:category-ads-all)
- فیلتر یوتوب (geosite:youtube)
- Bypass خودکار سایت‌های ایرانی
- مسدودسازی IP های خصوصی

---

## 📦 پروتکل‌های پشتیبانی‌شده

| پروتکل | Transport | TLS | پورت سرور | نوع اتصال |
|--------|-----------|-----|-----------|-----------|
| VLESS | WebSocket | TLS | 443 | Cloudflare CDN + IP مستقیم |
| VLESS | gRPC | TLS | 2053 | Cloudflare CDN |
| VLESS | HTTPUpgrade | TLS | 2083 | Cloudflare CDN |
| VLESS | TCP | TLS | 2087 | IP مستقیم |
| VLESS | TCP | بدون TLS | 10086 | IP مستقیم |
| VLESS | TCP | REALITY | 4431-4434 | IP مستقیم (4 dest) |
| VMess | WebSocket | TLS | 2096 | Cloudflare CDN + IP مستقیم |
| VMess | gRPC | TLS | 8443 | Cloudflare CDN |
| VMess | HTTPUpgrade | TLS | 2095 | Cloudflare CDN |
| VMess | WebSocket | بدون TLS | 10087 | IP مستقیم |
| Trojan | WebSocket | TLS | 2052 | Cloudflare CDN + IP مستقیم |
| Trojan | gRPC | TLS | 2082 | Cloudflare CDN |
| Trojan | TCP | TLS | 2086 | IP مستقیم |
| Trojan | TCP | REALITY | 4451-4454 | IP مستقیم (4 dest) |
| Shadowsocks | TCP | — | 8388 | IP — chacha20-ietf-poly1305 |
| Shadowsocks | TCP | — | 8389 | IP — aes-256-gcm |
| Shadowsocks | TCP | — | 8390 | IP — 2022-blake3-aes-256-gcm |
| Shadowsocks | TCP | — | 8392 | IP — 2022-blake3-aes-128-gcm |
| ShadowTLS | TCP | TLS | 8401-8404 | IP — wrapper روی SS |

### REALITY Destinations
| پورت | Destination | SNI | Fingerprint |
|------|-------------|-----|-------------|
| 4431/4451 | www.google.com:443 | www.google.com | chrome |
| 4432/4452 | www.apple.com:443 | www.apple.com | safari |
| 4433/4453 | discord.com:443 | discord.com | firefox |
| 4434/4454 | cdn.jsdelivr.net:443 | cdn.jsdelivr.net | chrome |

---

## ⚡ نصب

### نصب سریع (توصیه‌شده)
```bash
bash <(curl -Ls https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main/install.sh)
```

### نصب از فایل ZIP
```bash
# دانلود و اکسترکت ZIP
unzip masterpanel_v4.7.0.zip
cd masterpanel_v4.7.0
bash install.sh
```

### پیش‌نیازها
- **سیستم‌عامل:** Ubuntu 20.04+ یا Debian 11+
- **دسترسی:** root
- **پورت 80:** باید آزاد باشد (برای Let's Encrypt)
- **دامنه VPN:** مثل `vpn.example.com` — در Cloudflare می‌تواند Proxied باشد
- **دامنه پنل:** مثل `panel.example.com` — باید **DNS only (ابر خاکستری)** در Cloudflare باشد و مستقیم به IP سرور اشاره کند

> **چرا دو دامنه؟** دامنه VPN برای کانفیگ‌های پروکسی استفاده می‌شود (می‌تواند پشت CF باشد). دامنه پنل برای دسترسی به صفحه مدیریت است — چون CF پورت 9090 را پروکسی نمی‌کند، باید DNS only باشد تا Let's Encrypt گواهی واقعی بدهد.

### مراحل نصب
نصب‌کننده از شما می‌پرسد:

```
Domain (for VPN configs): vpn.example.com
Panel domain [blank = same]: panel.example.com
Admin username (min 4 chars): admin
Admin password (min 8 chars): ••••••••
```

بعد از تأیید، به ترتیب انجام می‌دهد:
1. نصب وابستگی‌ها (curl، wget، certbot، ufw، python3)
2. دانلود و نصب آخرین نسخه Xray-core
3. دانلود geoip.dat و geosite.dat ایرانی (Chocolate4U)
4. دریافت SSL برای دامنه VPN
5. دریافت SSL برای دامنه پنل
6. ساخت محیط Python و نصب Flask
7. تنظیم فایروال (UFW)
8. راه‌اندازی Nginx برای سابسکریپشن HTTPS (پورت 8081)
9. ساخت سرویس‌های systemd
10. شروع پنل

### بعد از نصب
```
Panel URL: https://panel.example.com:9090
Username : admin
```

---

## 🔧 راهنمای استفاده

### ۱. ورود
```
https://panel.example.com:9090
```
یا اگه SSL پنل نگرفته:
```
https://YOUR_IP:9090
```
هشدار مرورگر را قبول کنید (self-signed cert).

### ۲. ساخت کانفیگ عمومی
**داشبورد** → **ساخت کانفیگ** → **ساخت همه پروتکل‌ها**

این کانفیگ‌ها برای اشتراک‌گذاری عمومی مناسبند.

### ۳. ساخت کاربر اختصاصی
1. **کاربران** → **+ کاربر جدید**
2. نام کاربر، محدودیت GB (0 = نامحدود)، روز انقضا (0 = بدون انقضا)
3. روی کاربر کلیک کنید → **✨ ساخت کانفیگ** → **همه**
4. لینک سابسکریپشن را به کاربر بدهید

### ۴. ربات تلگرام
1. **تنظیمات** → **ربات تلگرام**
2. Bot Token را وارد کنید (از @BotFather)
3. Telegram ID ادمین را وارد کنید
4. **ذخیره** → ربات خودکار شروع می‌کند

برای اتصال کاربر به ربات:
1. روی کاربر در پنل → **🔗 کد اتصال**
2. کد را به کاربر بدهید
3. کاربر در ربات می‌نویسد: `/link CODE`

### ۵. پیکربندی Cloudflare
برای CDN کار کند:
- DNS record دامنه VPN: **Proxied (ابر نارنجی)**
- SSL/TLS mode در CF: **Full** (نه Full Strict)
- در کلاینت: آدرس = دامنه، SNI = دامنه، TLS = روشن

---

## 🤖 ربات تلگرام — راهنمای کامل

### دستورات
| دستور | توضیح |
|-------|-------|
| `/start` | شروع — منوی ادمین یا کاربر |
| `/menu` | بازگشت به منوی اصلی |
| `/link CODE` | اتصال حساب تلگرام به کاربر VPN |

### قابلیت‌های ادمین
- **👥 کاربران** — لیست همه کاربران با وضعیت، مصرف، تعداد کانفیگ
- **➕ کاربر جدید** — ساخت کاربر مرحله‌به‌مرحله از تلگرام
- **📊 آمار سرور** — ترافیک کل آپلود/دانلود
- **⚙️ وضعیت** — وضعیت سرویس‌های Panel و Xray
- **🔄 ری‌استارت Xray** — ریستارت بدون نیاز به SSH
- روی هر کاربر: مشاهده جزئیات، ساخت کانفیگ، فعال/غیرفعال، کد اتصال، لینک سابسکریپشن، حذف

### قابلیت‌های کاربر عادی
- **📱 کانفیگ‌های من** — دریافت همه لینک‌ها
- **📊 مصرف من** — حجم مصرفی، حد مجاز، تاریخ انقضا
- **🔗 لینک سابسکریپشن** — لینک آماده برای import در کلاینت

### نوتیف‌های خودکار (هر ۶ ساعت)
| رویداد | گیرنده |
|--------|--------|
| ۳ روز به انقضا | کاربر |
| روز آخر انقضا | کاربر |
| مصرف ۸۰٪ حجم | کاربر |
| مصرف ۹۵٪ حجم | کاربر |
| غیرفعال شدن کاربر | ادمین |

---

## 🛠️ مدیریت از سرور (mp.sh)

```bash
# وضعیت کامل (سرویس‌ها، SSL، کانفیگ‌ها)
bash /opt/masterpanel/mp.sh status

# ری‌استارت پنل
bash /opt/masterpanel/mp.sh restart

# ری‌استارت Xray
bash /opt/masterpanel/mp.sh restart-xray

# ری‌استارت همه
bash /opt/masterpanel/mp.sh restart-all

# لاگ‌ها (Ctrl+C برای خروج)
bash /opt/masterpanel/mp.sh logs panel
bash /opt/masterpanel/mp.sh logs xray
bash /opt/masterpanel/mp.sh logs access

# تمدید SSL
bash /opt/masterpanel/mp.sh renew-ssl

# آپدیت از GitHub
bash /opt/masterpanel/mp.sh update

# تغییر رمز ادمین
bash /opt/masterpanel/mp.sh update-pass

# نمایش همه کانفیگ‌های ساخته‌شده
bash /opt/masterpanel/mp.sh configs

# نمایش همه لینک‌ها
bash /opt/masterpanel/mp.sh links

# حذف کامل پنل
bash /opt/masterpanel/mp.sh uninstall
```

---

## 📂 ساختار فایل‌ها

```
/opt/masterpanel/
├── masterpanel.py        # سرور اصلی Flask
├── bot.py                # ربات تلگرام
├── mp.sh                 # ابزار CLI مدیریت
├── panel.conf            # تنظیمات (دامنه، یوزر، رمز، مسیر SSL)
├── bot.conf              # تنظیمات ربات (token، admin IDs)
├── version.txt           # نسخه فعلی
├── notif_sent.json       # tracking نوتیف‌های ارسال‌شده
├── .secret_key           # کلید session (پایدار بین ری‌استارت‌ها)
├── panel_cert.pem        # گواهی self-signed (fallback)
├── panel_key.pem         # کلید self-signed (fallback)
├── venv/                 # محیط مجازی Python
├── templates/
│   └── index.html        # رابط کاربری فارسی
├── configs/
│   ├── users.json        # اطلاعات کاربران و کانفیگ‌هایشان
│   ├── all_configs.json  # کانفیگ‌های عمومی
│   ├── all_links.txt     # همه لینک‌ها به صورت متن
│   ├── subscription.txt  # لینک‌های خام برای سابسکریپشن
│   └── subscription_b64.txt  # سابسکریپشن base64
└── logs/
    ├── panel.log         # لاگ پنل
    ├── bot.log           # لاگ ربات
    ├── xray-access.log   # لاگ دسترسی Xray
    └── xray-error.log    # لاگ خطاهای Xray

/usr/local/etc/xray/
└── config.json           # کانفیگ Xray (تولید خودکار)

/usr/local/bin/
├── xray                  # Xray-core binary
├── geoip.dat             # پایگاه IP (ایرانی — Chocolate4U)
└── geosite.dat           # پایگاه دامنه (ایرانی — Chocolate4U)

/etc/systemd/system/
├── masterpanel.service   # سرویس پنل
└── masterbot.service     # سرویس ربات تلگرام
```

---

## 🔐 پیکربندی Cloudflare

### برای استفاده از CDN
1. رکورد A بسازید: `vpn.example.com` → IP سرور → **Proxied (🟠)**
2. SSL/TLS Mode را روی **Full** بگذارید (نه Full Strict)
3. در کلاینت VPN: آدرس = `vpn.example.com`، SNI = `vpn.example.com`

### برای پنل (ضروری)
1. رکورد A بسازید: `panel.example.com` → IP سرور → **DNS only (⬜)**
2. این دامنه باید مستقیم به IP سرور برسد تا Let's Encrypt گواهی بدهد

### IP های Clean Cloudflare (داخل کانفیگ‌ها)
پنل به صورت خودکار کانفیگ‌هایی با IP های Clean CF می‌سازد:
```
104.16.x.x — 104.22.x.x
172.64.x.x — 172.66.x.x
162.159.x.x
188.114.96.x — 188.114.97.x
```

---

## ⚠️ رفع خطاهای رایج

### ❌ پنل باز نمی‌شود

```bash
# بررسی وضعیت سرویس
systemctl status masterpanel

# مشاهده لاگ خطا
journalctl -u masterpanel -n 50 --no-pager

# ری‌استارت دستی
systemctl restart masterpanel
sleep 3
systemctl is-active masterpanel
```

**دلایل احتمالی:**
- پورت 9090 توسط فایروال بسته است → `ufw allow 9090/tcp`
- فایل `panel.conf` خراب شده → بررسی کنید مقادیر درست هستند
- مشکل SSL → مشکل را از لاگ بخوانید

---

### ❌ Xray کار نمی‌کند

```bash
# وضعیت
systemctl status xray
journalctl -u xray -n 30 --no-pager

# تست کانفیگ
/usr/local/bin/xray run -test -c /usr/local/etc/xray/config.json

# ری‌استارت
systemctl restart xray
```

**دلایل احتمالی:**
- کانفیگ هنوز ساخته نشده → از پنل «ساخت همه پروتکل‌ها» را بزنید
- geosite.dat مشکل دارد → با دستور زیر جایگزین کنید:
```bash
wget -q "https://github.com/Chocolate4U/Iran-v2ray-rules/releases/latest/download/geosite.dat" \
  -O /usr/local/bin/geosite.dat
cp /usr/local/bin/geosite.dat /usr/local/share/xray/geosite.dat
systemctl restart xray
```

---

### ❌ پنل بعد از «ساخت پروتکل» کرش می‌کند

این مشکل در نسخه‌های قدیمی‌تر با TUIC و Hysteria2 وجود داشت. نسخه 4.7.0 این مشکل را برطرف کرده است. اگر هنوز دارید:

```bash
# آپدیت به آخرین نسخه
bash /opt/masterpanel/mp.sh update

# یا آپدیت دستی
wget -q https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main/masterpanel.py \
  -O /opt/masterpanel/masterpanel.py
systemctl restart masterpanel
```

---

### ❌ SSL نگرفت / هشدار مرورگر

```bash
# بررسی DNS (باید IP سرور را برگرداند)
dig +short panel.example.com
curl -4 https://api4.ipify.org

# پورت 80 آزاد است؟
fuser 80/tcp || echo "Port 80 is free"

# گرفتن SSL دستی
bash /opt/masterpanel/mp.sh renew-ssl
```

**نکات مهم:**
- دامنه پنل باید **DNS only** (ابر خاکستری) در Cloudflare باشد
- Let's Encrypt به پورت 80 روی IP سرور نیاز دارد
- اگه SSL نگرفت، پنل از گواهی self-signed استفاده می‌کند — در مرورگر «ادامه» را بزنید

---

### ❌ ربات تلگرام کار نمی‌کند

```bash
# بررسی وضعیت
systemctl status masterbot
journalctl -u masterbot -n 30 --no-pager

# ری‌استارت
systemctl restart masterbot
```

**بررسی کنید:**
- Token در پنل → تنظیمات → ربات تلگرام درست وارد شده باشد
- Telegram ID ادمین اشتباه نباشد (از @userinfobot بگیرید)
- سرور به api.telegram.org دسترسی داشته باشد: `curl -s https://api.telegram.org`

---

### ❌ کانفیگ‌ها وصل نمی‌شوند

```bash
# تست پورت از سرور
nc -zv 127.0.0.1 443

# بررسی فایروال
ufw status

# باز کردن پورت‌های لازم
ufw allow 443/tcp
ufw allow 2052/tcp
ufw allow 2053/tcp
# ... (بقیه پورت‌ها)
```

**پورت‌های لازم:**

| پورت | پروتکل | کاربرد |
|------|--------|--------|
| 443 | TCP/UDP | VLESS WS |
| 2052-2053 | TCP | Trojan WS / VLESS gRPC |
| 2082-2083 | TCP | Trojan gRPC / VLESS HU |
| 2086-2087 | TCP | Trojan TCP / VLESS TCP |
| 2095-2096 | TCP | VMess HU / VMess WS |
| 8443 | TCP | VMess gRPC |
| 4431-4434 | TCP | VLESS REALITY |
| 4451-4454 | TCP | Trojan REALITY |
| 8388-8392 | TCP | Shadowsocks |
| 8401-8404 | TCP | ShadowTLS |
| 10086-10087 | TCP | VLESS/VMess no-TLS |
| 8081 | TCP | سابسکریپشن HTTPS |
| 9090 | TCP | پنل مدیریت |

---

### ❌ سابسکریپشن کار نمی‌کند

```bash
# بررسی Nginx
systemctl status nginx
nginx -t

# ری‌استارت Nginx
systemctl restart nginx

# تست URL سابسکریپشن
curl -k https://vpn.example.com:8081/sub/TOKEN
```

**نکته:** اگه SSL برای دامنه VPN نگرفته، Nginx راه‌اندازی نمی‌شود. در این حالت از لینک جایگزین استفاده کنید:
```
https://panel.example.com:9090/sub/TOKEN
```

---

### ❌ تلگرام «دسترسی نمی‌دهد» به ربات

```bash
# بررسی bot.conf
cat /opt/masterpanel/bot.conf

# دستی set کردن ADMIN_IDS
echo "BOT_TOKEN=your_token" > /opt/masterpanel/bot.conf
echo "ADMIN_IDS=123456789" >> /opt/masterpanel/bot.conf
systemctl restart masterbot
```

---

## 🗑️ حذف

### حذف فقط پنل (نگه داشتن Xray)
```bash
bash /opt/masterpanel/mp.sh uninstall
```

### حذف کامل (همه چیز)
```bash
bash /opt/masterpanel/mp.sh uninstall

# حذف Xray
rm -f /usr/local/bin/xray
rm -f /etc/systemd/system/xray.service
systemctl daemon-reload

# حذف SSL
certbot delete --cert-name vpn.example.com
certbot delete --cert-name panel.example.com

# حذف Nginx
apt-get remove --purge nginx -y
rm -f /etc/nginx/sites-enabled/masterpanel-sub

# حذف crontab
crontab -l | grep -v "certbot\|api/enforce" | crontab -
```

---

## 🔄 آپدیت

### از داخل پنل (توصیه‌شده)
داشبورد → دکمه **⬆ آپدیت** → منتظر بمان → رفرش

### از سرور
```bash
bash /opt/masterpanel/mp.sh update
```

### دستی
```bash
wget -q https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main/masterpanel.py \
  -O /opt/masterpanel/masterpanel.py
wget -q https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main/index.html \
  -O /opt/masterpanel/templates/index.html
wget -q https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main/bot.py \
  -O /opt/masterpanel/bot.py
wget -q https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main/mp.sh \
  -O /opt/masterpanel/mp.sh && chmod +x /opt/masterpanel/mp.sh
systemctl restart masterpanel masterbot
```

---

## 🏗️ معماری فنی

```
┌─────────────────────────────────────────────────┐
│                  MasterPanel                     │
│                                                  │
│  Flask (HTTPS:9090) ──── masterpanel.py         │
│         │                                        │
│         ├── /api/generate → Xray config.json    │
│         ├── /api/users    → users.json           │
│         ├── /api/stats    → Xray gRPC API        │
│         └── /sub/<token>  → subscription b64     │
│                                                  │
│  Bot (bot.py) ──── Telegram API                  │
│         │                                        │
│         └── X-Internal → Panel API              │
│                                                  │
│  Nginx (HTTPS:8081) ──── /sub/ → Panel          │
└─────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────┐
│   Xray-core     │
│                 │
│  inbounds:      │
│  ├── VLESS WS   │──▶ Cloudflare ──▶ Client
│  ├── VMess gRPC │──▶ Direct IP  ──▶ Client
│  ├── Trojan TCP │──▶ Direct IP  ──▶ Client
│  ├── SS         │──▶ Direct IP  ──▶ Client
│  └── REALITY    │──▶ Direct IP  ──▶ Client
│                 │
│  routing:       │
│  ├── ads → DROP │
│  ├── youtube→DROP│
│  ├── IR → DIRECT│
│  └── * → PROXY  │
└─────────────────┘
```

### Stack
- **Backend:** Python 3 + Flask
- **Proxy Engine:** Xray-core (XTLS)
- **SSL:** Let's Encrypt (certbot)
- **Reverse Proxy:** Nginx (فقط برای سابسکریپشن)
- **Database:** SQLite-style JSON flat files
- **Frontend:** HTML/CSS/JS خالص (بدون framework)
- **Bot:** python-requests + Telegram Bot API (long polling)
- **Init:** systemd
- **Firewall:** UFW

---

## 📄 لایسنس

MIT License — آزاد برای استفاده شخصی و تجاری

---

<div align="center">

[گزارش مشکل](https://github.com/Masterv2panel/Masterpanel/issues) · [درخواست ویژگی](https://github.com/Masterv2panel/Masterpanel/issues)

</div>
