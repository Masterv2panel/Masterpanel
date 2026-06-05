<div align="center">

<img src="https://img.shields.io/badge/MasterPanel-v3.0_Advanced-2563eb?style=for-the-badge&logo=shield&logoColor=white" alt="Version">
<img src="https://img.shields.io/badge/Xray_Core-Latest-22c55e?style=for-the-badge" alt="Xray">
<img src="https://img.shields.io/badge/Python-3.10+-eab308?style=for-the-badge&logo=python&logoColor=white" alt="Python">
<img src="https://img.shields.io/badge/UI-فارسی_RTL-f97316?style=for-the-badge" alt="Persian">
<img src="https://img.shields.io/badge/License-MIT-8b5cf6?style=for-the-badge" alt="License">

<br><br>

# 🛡️ MasterPanel v3.0 Advanced Edition

### پنل مدیریت پیشرفته پروتکل‌های Xray با رابط کاربری فارسی

**مدیریت چند کاربره · بدون تبلیغ · عبور خودکار سایت‌های ایرانی · ربات تلگرام · اشتراک اختصاصی**

<br>

[![نصب](https://img.shields.io/badge/نصب_سریع-bash_install.sh-22c55e?style=for-the-badge)](https://github.com/Masterv2panel/Masterpanel)
[![GitHub](https://img.shields.io/badge/GitHub-Masterv2panel/Masterpanel-181717?style=for-the-badge&logo=github)](https://github.com/Masterv2panel/Masterpanel)

</div>

---

## 📋 فهرست مطالب

- [نصب سریع](#-نصب-سریع)
- [امکانات](#-امکانات)
- [پروتکل‌های پشتیبانی شده](#-پروتکل‌های-پشتیبانی-شده)
- [پیش‌نیازها](#-پیش‌نیازها)
- [دسترسی به پنل](#-دسترسی-به-پنل)
- [مدیریت از طریق CLI](#-مدیریت-از-طریق-cli)
- [راهنمای تنظیمات](#-راهنمای-تنظیمات)
- [امکانات پرمیوم](#-امکانات-پرمیوم-ad-free--iran-bypass)
- [ساختار فایل‌ها](#-ساختار-فایل‌ها)
- [سوالات متداول](#-سوالات-متداول)

---

## 🚀 نصب سریع

### ✅ روش یک — نصب تک‌خطی از GitHub (توصیه‌شده)

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main/install.sh)
```

> این دستور نیاز به هیچ فایل اضافه‌ای ندارد. اسکریپت تمام فایل‌ها را مستقیماً از GitHub دانلود می‌کند.

---

### ✅ روش دو — کلون و نصب دستی

```bash
# دریافت پروژه از GitHub
git clone https://github.com/Masterv2panel/Masterpanel.git
cd Masterpanel

# اجرای نصب (به‌عنوان root)
sudo bash install.sh
```

---

### ✅ روش سه — دانلود ZIP و نصب

```bash
# دانلود و باز کردن آرشیو
wget https://github.com/Masterv2panel/Masterpanel/archive/refs/heads/main.zip
unzip main.zip
cd Masterpanel-main

# اجرای نصب
sudo bash install.sh
```

---

### ✅ روش چهار — دانلود فایل‌های جداگانه

```bash
# ساخت پوشه کاری
mkdir MasterPanel && cd MasterPanel

# دانلود فایل‌های اصلی
BASE="https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main"
curl -L "$BASE/install.sh"      -o install.sh
curl -L "$BASE/masterpanel.py"  -o masterpanel.py
curl -L "$BASE/index.html"      -o index.html
curl -L "$BASE/mp.sh"           -o mp.sh

# اجرای نصب
sudo bash install.sh
```

---

### 📋 جریان نصب

```
┌─────────────────────────────────────────────────────┐
│              MasterPanel Installer v3.0              │
├─────────────────────────────────────────────────────┤
│  1. دریافت اطلاعات (دامنه، نام کاربری، رمز عبور)   │
│  2. نصب وابستگی‌های سیستم                           │
│  3. نصب Xray-core (آخرین نسخه از GitHub)            │
│  4. دانلود geoip.dat + geosite.dat                  │
│  5. نصب TUIC v5                                     │
│  6. نصب Hysteria2                                   │
│  7. دریافت گواهی SSL از Let's Encrypt               │
│  8. راه‌اندازی Python venv + flask + apscheduler    │
│  9. کپی فایل‌های پنل (یا دانلود از GitHub)          │
│ 10. تزریق قوانین Ad-Block + Iran Bypass             │
│ 11. پیکربندی فایروال UFW (22 پورت)                  │
│ 12. ساخت سرویس‌های systemd                          │
│ 13. تنظیم cron بروزرسانی هفتگی geo database         │
└─────────────────────────────────────────────────────┘
```

---

## ✨ امکانات

<table>
<tr>
<td width="50%" valign="top">

### 👥 مدیریت چند کاربره
- دیتابیس SQLite مستقل (`users.db`)
- ایجاد، ویرایش و حذف کاربر از پنل
- تعیین حجم ترافیک (GB) برای هر کاربر
- تاریخ انقضا (تعداد روز / تاریخ دقیق / نامحدود)
- نمایش نوار پیشرفت ترافیک با رنگ‌بندی وضعیت
- غیرفعال‌سازی خودکار پس از انقضا / اتمام حجم

### 🔗 لینک اشتراک اختصاصی (Subscription)
- اندپوینت `/sub/<uuid>` برای هر کاربر
- خروجی Base64 سازگار با v2rayNG، Nekobox، Hiddify
- نمایش «حجم باقی‌مانده | روزهای مانده» در نام پروفایل
- هدرهای استاندارد `Subscription-Userinfo` و `Profile-Update-Interval`

### 📊 مانیتورینگ ترافیک زنده
- پرس‌وجو از Xray Stats API در پس‌زمینه (APScheduler)
- به‌روزرسانی خودکار مصرف هر کاربر
- غیرفعال‌سازی فوری پس از اتمام سهمیه
- اعلان تلگرام برای هر رویداد

</td>
<td width="50%" valign="top">

### 🚫 بلاک تبلیغات (Ad-Block)
- مسدود کردن تبلیغات یوتیوب (`geosite:youtube-ads`)
- فیلتر دسته‌بندی عمومی (`geosite:category-ads-all`)
- بلاک شبکه‌های بزرگسال (ExoClick, JuicyAds, TrafficJunky)
- به‌روزرسانی هفتگی پایگاه داده geo

### 🇮🇷 عبور سایت‌های ایرانی (Iran Bypass)
- تمام دامنه‌های `.ir` مستقیم — بدون VPN
- IP های ایرانی (`geoip:ir`) → direct
- بانک‌ها، اپ‌های ایرانی، درگاه‌های پرداخت
- کاهش چشمگیر مصرف ترافیک VPN

### 📡 ربات تلگرام
- اطلاع‌رسانی اتمام حجم و انقضای اشتراک
- بکاپ خودکار روزانه `users.db`
- ارسال بکاپ دستی با یک کلیک

### ☁️ Clean IP / XHTTP / REALITY
- تزریق آی‌پی تمیز CloudFlare در کانفیگ‌های CDN
- پروتکل XHTTP پیشرفته
- VLESS REALITY Vision با keypair اختصاصی

</td>
</tr>
</table>

---

## 🔗 پروتکل‌های پشتیبانی شده

| پروتکل | شبکه | امنیت | نوع اتصال | پورت |
|--------|-------|-------|-----------|------|
| VLESS | WebSocket | TLS | ☁️ CDN (CloudFlare) | 443 |
| VLESS | XHTTP | TLS | ☁️ CDN (CloudFlare) | 8443 |
| VLESS | gRPC | TLS | ☁️ CDN (CloudFlare) | 2053 |
| VMess | WebSocket | TLS | ☁️ CDN (CloudFlare) | 2083 |
| VMess | XHTTP | TLS | ☁️ CDN (CloudFlare) | 2087 |
| Trojan | WebSocket | TLS | ☁️ CDN (CloudFlare) | 2096 |
| **VLESS** | TCP | **REALITY Vision** | 🖥️ IP مستقیم | 9443 |
| VLESS | XHTTP | TLS | 🖥️ IP مستقیم | 9444 |
| VLESS | WebSocket | TLS | 🖥️ IP مستقیم | 9445 |
| VMess | WebSocket | TLS | 🖥️ IP مستقیم | 9446 |
| Trojan | TCP | TLS | 🖥️ IP مستقیم | 9447 |
| VLESS | TCP | TLS | 🖥️ IP مستقیم | 9448 |
| VMess | TCP | TLS | 🖥️ IP مستقیم | 9449 |
| **Shadowsocks 2022** | TCP+UDP | 2022-blake3 | 🖥️ IP مستقیم | 8388/8389 |
| **TUIC v5** | UDP | TLS (h3) | 🖥️ IP مستقیم | 2053 |
| **Hysteria2** | UDP | TLS | 🖥️ IP مستقیم | 443 |
| WireGuard | UDP | — | 🖥️ IP مستقیم | 51820 |

> 💡 هر کاربر به‌صورت خودکار تمام ۱۷ پروتکل را دریافت می‌کند.

---

## 📦 پیش‌نیازها

| مورد | نیاز |
|------|------|
| سیستم‌عامل | Ubuntu 20.04+ / Debian 11+ |
| دسترسی | Root (`sudo -i`) |
| رم | حداقل 512 MB (توصیه: 1 GB+) |
| فضای دیسک | حداقل 2 GB |
| دامنه | یک دامنه با رکورد DNS A به IP سرور |
| پورت 80 | برای Let's Encrypt certbot باز باشد |
| پورت 443 | برای VPN clients |

> ⚠️ **نکته CloudFlare Proxy:** هنگام نصب SSL، Proxy CloudFlare را روی **DNS Only** (خاکستری) بگذارید. بعد از نصب می‌توانید Proxy را فعال کنید.

---

## 🖥️ دسترسی به پنل

پس از نصب موفق، **با IP سرور** (نه دامنه) پنل را باز کنید:

```
http://YOUR_SERVER_IP:9090
```

```
نام کاربری : [چیزی که در نصب وارد کردید]
رمز عبور   : [چیزی که در نصب وارد کردید]
```

> ⚠️ **چرا IP؟** CloudFlare پورت 9090 را مسدود می‌کند. پنل مدیریت باید از طریق IP مستقیم باز شود. لینک‌های اشتراک کاربران از دامنه کار می‌کنند.

---

## ⌨️ مدیریت از طریق CLI

```bash
# مشاهده وضعیت کامل سیستم
bash /opt/masterpanel/mp.sh status

# لیست کاربران با ترافیک و وضعیت
bash /opt/masterpanel/mp.sh users

# افزودن کاربر جدید (تعاملی)
bash /opt/masterpanel/mp.sh add-user

# حذف کاربر
bash /opt/masterpanel/mp.sh del-user USERNAME

# ری‌ست ترافیک کاربر
bash /opt/masterpanel/mp.sh reset-user USERNAME

# فعال / غیرفعال کردن کاربر
bash /opt/masterpanel/mp.sh toggle-user USERNAME

# نمایش لینک اشتراک کاربر
bash /opt/masterpanel/mp.sh links USERNAME

# اعمال تغییرات پیکربندی از دیتابیس به Xray
bash /opt/masterpanel/mp.sh apply

# ری‌استارت همه سرویس‌ها
bash /opt/masterpanel/mp.sh restart-all

# مشاهده لاگ لحظه‌ای (real-time)
bash /opt/masterpanel/mp.sh logs panel
bash /opt/masterpanel/mp.sh logs xray
bash /opt/masterpanel/mp.sh logs tuic
bash /opt/masterpanel/mp.sh logs hy2

# پشتیبان‌گیری دستی
bash /opt/masterpanel/mp.sh backup

# تمدید SSL به‌صورت اجباری
bash /opt/masterpanel/mp.sh renew-ssl

# تغییر رمز ادمین
bash /opt/masterpanel/mp.sh update-pass

# راهنمای کامل دستورات
bash /opt/masterpanel/mp.sh help
```

### جدول کامل دستورات `mp.sh`

| دستور | توضیح |
|-------|-------|
| `status` | وضعیت سرویس‌ها + کاربران + SSL + IP |
| `users` | لیست جامع کاربران از دیتابیس |
| `add-user` | افزودن کاربر (تعاملی) |
| `del-user [name]` | حذف کاربر |
| `reset-user [name]` | ری‌ست ترافیک و فعال‌سازی مجدد |
| `toggle-user [name]` | فعال ↔ غیرفعال |
| `links [name]` | نمایش URL اشتراک |
| `apply` | اعمال تغییرات DB به همه سرویس‌ها |
| `restart` | ری‌استارت MasterPanel |
| `restart-xray` | ری‌استارت Xray |
| `restart-tuic` | ری‌استارت TUIC v5 |
| `restart-hy2` | ری‌استارت Hysteria2 |
| `restart-all` | ری‌استارت همه سرویس‌ها |
| `logs [panel/xray/access/tuic/hy2]` | لاگ لحظه‌ای |
| `backup` | بکاپ لوکال `users.db` |
| `renew-ssl` | تمدید اجباری گواهی SSL |
| `update-pass` | تغییر رمز عبور ادمین |
| `install-tuic` | نصب/بروزرسانی TUIC v5 |
| `install-hy2` | نصب/بروزرسانی Hysteria2 |
| `uninstall` | حذف پنل (دیتابیس حفظ می‌شود) |

---

## ⚙️ راهنمای تنظیمات

### ۱. آی‌پی تمیز CloudFlare

در پنل → **تنظیمات** → فیلد «آی‌پی تمیز»:

```
162.159.36.1        ← IP تمیز CloudFlare (Anycast)
104.21.xxx.xxx      ← IP اختصاصی CDN
cdn.yourcdn.com     ← دامنه Clean Proxy
```

این مقدار در فیلد `address` کانفیگ‌های CDN جایگزین می‌شود؛ `SNI` و `Host` دست‌نخورده می‌مانند.

### ۲. ربات تلگرام

```
1. @BotFather → /newbot → دریافت Token
2. @userinfobot → دریافت Chat ID
3. پنل → تنظیمات → ربات تلگرام → ذخیره
4. کلیک روی «تست اتصال ربات»
```

**رویدادهای خودکار:**
- 🔴 اتمام حجم ترافیک → پیام فوری به ادمین
- ⏰ انقضای اشتراک → پیام فوری به ادمین
- 📦 بکاپ روزانه `users.db` در ساعت تنظیم‌شده

### ۳. بروزرسانی از GitHub

پنل → تنظیمات:

```
Repo  : Masterv2panel/Masterpanel
Branch: main
```

سپس دکمه **«بروزرسانی MasterPanel»**. پنل فایل‌های جدید را دانلود و ری‌استارت می‌کند. `users.db` دست‌نخورده می‌ماند.

---

## 🌟 امکانات پرمیوم (Ad-Free + Iran Bypass)

### 🚫 قوانین Ad-Block (خودکار، بدون تنظیم)

```python
# تبلیغات یوتیوب
{"domain": ["geosite:youtube-ads"], "outboundTag": "blocked"}

# دسته‌بندی عمومی تبلیغات
{"domain": ["geosite:category-ads-all"], "outboundTag": "blocked"}

# شبکه‌های تبلیغاتی بزرگسال
{"domain": [
    "domain:exoclick.com", "domain:juicyads.com",
    "domain:trafficjunky.com", "domain:trafficjunky.net"
], "outboundTag": "blocked"}
```

### 🇮🇷 قوانین Iran Bypass (خودکار، بدون تنظیم)

```python
# دامنه‌های .ir و سایت‌های ایرانی
{"domain": ["geosite:ir", "regexp:^.*\\.ir$"], "outboundTag": "direct"}

# رنج‌های IP ایرانی
{"ip": ["geoip:ir"], "outboundTag": "direct"}
```

**استراتژی:** `IPIfNonMatch` — دقت بالا با کمترین سربار پردازشی

**مزایا:**
- ✅ بانک‌ها و درگاه پرداخت بدون VPN باز می‌شوند
- ✅ اپ‌های ایرانی (اسنپ، دیجیکالا، شاد) بدون مشکل کار می‌کنند
- ✅ مصرف ترافیک VPN تا ۵۰٪ کاهش می‌یابد
- ✅ سرعت سایت‌های داخلی به‌شدت بهتر می‌شود

### 🗓️ بروزرسانی خودکار Geo Database

```bash
# اجرا می‌شود: هر یکشنبه ساعت ۰۴:۰۰
# منبع: Loyalsoldier/v2ray-rules-dat
0 4 * * 0 bash /opt/masterpanel/update_geo.sh
```

---

## 📁 ساختار فایل‌های GitHub

```
Masterpanel/
├── install.sh              ← نصب‌کننده اصلی
├── masterpanel.py          ← بک‌اند Flask + SQLite + Xray API
├── index.html              ← رابط کاربری فارسی (RTL)
├── mp.sh                   ← مدیریت CLI
└── README.md               ← این فایل
```

### ساختار روی سرور پس از نصب

```
/opt/masterpanel/
├── masterpanel.py          ← اپلیکیشن اصلی
├── panel.conf              ← تنظیمات (دامنه، رمز، مسیرها)
├── users.db                ← دیتابیس کاربران SQLite ⭐
├── mp.sh                   ← مدیریت CLI
├── update_geo.sh           ← بروزرسانی geo database
├── templates/index.html    ← رابط کاربری
├── configs/                ← پیکربندی‌های TUIC و Hysteria2
├── logs/                   ← لاگ‌های همه سرویس‌ها
└── venv/                   ← محیط Python

/usr/local/etc/xray/
├── config.json             ← پیکربندی Xray (تولیدشده توسط پنل)
├── geoip.dat               ← پایگاه داده IP
└── geosite.dat             ← پایگاه داده دامنه
```

---

## ❓ سوالات متداول

**س: چطور بعد از نصب یک کاربر اضافه کنم؟**
```bash
# از CLI:
bash /opt/masterpanel/mp.sh add-user

# یا از پنل: http://SERVER_IP:9090 → مدیریت کاربران → کاربر جدید
```

**س: آیا سرور ری‌استارت شود چه می‌شود؟**  
تمام سرویس‌ها (`masterpanel`, `xray`, `tuic-server`, `hysteria2`) با `systemctl enable` تنظیم شده‌اند و به‌صورت خودکار بالا می‌آیند.

**س: آیا ترافیک Hysteria2 و TUIC هم محاسبه می‌شود؟**  
فعلاً خیر — ترافیک از Xray Stats API خوانده می‌شود. اما غیرفعال شدن کاربر در پنل این پروتکل‌ها را هم قطع می‌کند.

**س: چطور رمز ادمین را تغییر دهم؟**
```bash
bash /opt/masterpanel/mp.sh update-pass
```

**س: چطور SSL منقضی‌شده را تمدید کنم؟**
```bash
bash /opt/masterpanel/mp.sh renew-ssl
```

**س: اگر پنل کرش کرد چه کار کنم؟**
```bash
# بررسی وضعیت
bash /opt/masterpanel/mp.sh status

# مشاهده لاگ خطا
bash /opt/masterpanel/mp.sh logs panel

# یا مستقیم:
journalctl -u masterpanel -n 50

# ری‌استارت
bash /opt/masterpanel/mp.sh restart
```

**س: چطور پنل را کاملاً حذف کنم (بدون از دست دادن کاربران)?**
```bash
bash /opt/masterpanel/mp.sh uninstall
# users.db به /root/users_db_backup_DATE.db کپی می‌شود
```

---

## 🤝 مشارکت

Pull Request و Issue خوشامد است!

```bash
# Fork → Clone → Branch → Code → PR
git clone https://github.com/Masterv2panel/Masterpanel.git
git checkout -b feature/my-feature
# ... تغییرات ...
git push origin feature/my-feature
# باز کردن Pull Request از GitHub
```

---

<div align="center">

**📎 لینک‌های مفید**

[GitHub Repository](https://github.com/Masterv2panel/Masterpanel) · 
[گزارش باگ](https://github.com/Masterv2panel/Masterpanel/issues) · 
[درخواست ویژگی](https://github.com/Masterv2panel/Masterpanel/issues/new)

<br>

ساخته شده با ❤️ برای جامعه ایرانی

**MasterPanel v3.0 Advanced Edition**  
`https://github.com/Masterv2panel/Masterpanel`

</div>
