# 🛡️ Master Panel — پنل مدیریت X-UI سنایی

<div align="center">

![Version](https://img.shields.io/badge/version-3.0.0-cyan?style=for-the-badge)
![Shell](https://img.shields.io/badge/shell-bash-green?style=for-the-badge&logo=gnubash)
![License](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)
![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%20%7C%2022.04%20%7C%2024.04-orange?style=for-the-badge&logo=ubuntu)
![X-UI](https://img.shields.io/badge/X--UI-Sanaei%20Fork-purple?style=for-the-badge)

**پنل مدیریت حرفه‌ای و تعاملی برای X-UI (نسخه سنایی) — کاملاً به فارسی**

[نصب سریع](#-نصب-سریع) · [ویژگی‌ها](#-ویژگیها) · [راهنما](#-راهنمای-استفاده) · [داشبورد وب](#-داشبورد-وب)

</div>

---

## 📋 معرفی

**Master Panel** یک اسکریپت Bash پیشرفته و یک داشبورد وب فارسی است که مدیریت کامل سرور X-UI (نسخه سنایی/3x-ui) را از طریق یک رابط تعاملی زیبا فراهم می‌کند.

- 🖥️ **TUI فارسی** — منوی رنگی تعاملی در ترمینال (ANSI)
- 🌐 **Web Dashboard** — داشبورد HTML فارسی، RTL، تم تاریک صنعتی
- 🔒 **SSL بدون دامنه** — گواهی Let's Encrypt از طریق sslip.io روی IP خالی
- ☁️ **Cloudflare هوشمند** — پشتیبانی از CDN، IP تمیز، DNS API
- 🤖 **ربات تلگرام** — بکاپ خودکار، هشدار ترافیک، گزارش روزانه

---

## ✨ ویژگی‌ها

### 🔧 پروتکل‌ها و Transport
| پروتکل | Transport | Security |
|--------|-----------|----------|
| VLESS | TCP, WS, gRPC, XHTTP, H2, QUIC | None, TLS, Reality, XTLS |
| VMess | TCP, WS, gRPC, XHTTP | None, TLS |
| Trojan | TCP, WS, gRPC | TLS, Reality |
| ShadowSocks | TCP, WS | — |
| Hysteria2 | UDP | TLS |

### 👥 مدیریت کاربران
- ایجاد، ویرایش، حذف کاربر (CRUD کامل)
- تنظیم حجم ترافیک (GB) و تاریخ انقضا
- ریست ترافیک، فعال/غیرفعال
- آمار مصرف و هشدار ۹۰٪ ترافیک

### ☁️ Cloudflare
- کانفیگ مستقیم (Direct IP) برای Reality / Hysteria2
- کانفیگ CDN با دامنه Cloudflare-proxied
- کانفیگ IP تمیز با تزریق Clean IP در آدرس target
- تست خودکار دسترسی‌پذیری IP های تمیز
- DNS API برای مدیریت رکوردها

### 🔒 SSL
- نصب Let's Encrypt **بدون دامنه** از طریق `sslip.io`
- تبدیل `1.2.3.4` → `1.2.3.4.sslip.io` → گواهی معتبر
- پشتیبانی از احراز Standalone، Webroot، DNS-CF
- تمدید خودکار با acme.sh

### 🤖 تلگرام
- ارسال بکاپ روزانه/هفتگی دیتابیس
- هشدار کاربران نزدیک به اتمام ترافیک
- هشدار کاربران منقضی‌شده
- گزارش ترافیک کامل

### 💾 بکاپ
- بکاپ دستی و خودکار (Cron)
- نگهداری آخرین ۷ بکاپ
- بازیابی از فایل

---

## 🚀 نصب سریع

### روش یک‌خطی (توصیه‌شده)
```bash
bash <(curl -Ls https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main/install-xui-panel.sh)
```

### روش دستی
```bash
# ۱. دانلود فایل‌ها
git clone https://github.com/Masterv2panel/Masterpanel.git
cd Masterpanel

# ۲. مجوز اجرا
chmod +x xui-panel.sh xui-panel-part2.sh install-xui-panel.sh

# ۳. نصب
sudo bash install-xui-panel.sh

# ۴. اجرا
sudo xui-panel
```

### پیش‌نیازها
```bash
# نصب خودکار هنگام اولین اجرا — یا دستی:
sudo apt-get install -y curl jq sqlite3 openssl uuid-runtime qrencode cron bc socat unzip wget
```

---

## 📁 ساختار فایل‌ها

```
Masterpanel/
├── xui-panel.sh            # هسته اصلی — TUI، DB، منو، مدیریت کاربران
├── xui-panel-part2.sh      # ماژول‌ها — کانفیگ، CF، ساب، تلگرام، SSL
├── install-xui-panel.sh    # نصب‌کننده سریع
├── xui-dashboard.html      # داشبورد وب فارسی (تک‌فایل HTML)
└── README.md
```

---

## 🖥️ داشبورد وب

فایل `xui-dashboard.html` یک داشبورد کامل است که:
- مستقیم در مرورگر باز می‌شود (بدون نیاز به سرور)
- با **X-UI API** ارتباط برقرار می‌کند
- داده‌های نمونه برای نمایش در حالت Demo دارد

```bash
# قرار دادن روی سرور
cp xui-dashboard.html /var/www/html/

# یا دسترسی مستقیم
firefox xui-dashboard.html
```

**اتصال به X-UI:** تنظیمات → آدرس سرور → `http://YOUR-IP:54321`

---

## 📖 راهنمای استفاده

```
sudo xui-panel

 ┌─────────────────────────────┐
 │  1) مدیریت کاربران          │
 │  2) مدیریت اینباندها         │
 │  3) تولید کانفیگ             │
 │  4) Cloudflare               │
 │  5) ساب‌اسکریپشن            │
 │  6) ربات تلگرام              │
 │  7) بکاپ                     │
 │  8) SSL                      │
 │  9) مدیریت سرویس            │
 │ 10) تنظیمات                  │
 └─────────────────────────────┘
```

---

## ⚙️ پیکربندی

تنظیمات در `/etc/xui-panel/config.env` ذخیره می‌شوند:

```env
PANEL_CF_DOMAIN="vpn.example.com"
PANEL_TG_TOKEN="your_bot_token"
PANEL_TG_CHAT_ID="your_chat_id"
PANEL_PUBLIC_IP="1.2.3.4"
PANEL_SUB_PORT="8080"
PANEL_SSL_DOMAIN="1.2.3.4.sslip.io"
```

---

## 🔐 امنیت

- فایل تنظیمات با `chmod 600` محافظت می‌شود
- توکن تلگرام هرگز در لاگ ذخیره نمی‌شود
- بکاپ‌ها در `/var/backups/xui-panel/` با دسترسی root ذخیره می‌شوند

---

## 📊 سازگاری

| سیستم‌عامل | وضعیت |
|------------|--------|
| Ubuntu 20.04 LTS | ✅ کامل |
| Ubuntu 22.04 LTS | ✅ کامل |
| Ubuntu 24.04 LTS | ✅ کامل |
| Debian 11/12 | ⚠️ آزمایشی |

---

## 🤝 مشارکت

Pull Request ها歡迎 هستند. برای تغییرات بزرگ ابتدا یک Issue باز کنید.

---

## 📄 لایسنس

MIT License — آزاد برای استفاده شخصی و تجاری

---

<div align="center">

ساخته‌شده با ❤️ برای جامعه فارسی‌زبان

**[⭐ Star بده](https://github.com/Masterv2panel/Masterpanel)** اگر مفید بود!

</div>
