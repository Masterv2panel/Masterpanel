<div align="center">

# 🛡️ MasterPanel

**پنل مدیریت پروتکل‌های Xray با رابط فارسی**

[![Version](https://img.shields.io/badge/version-4.7.0-blue?style=for-the-badge)](https://github.com/Masterv2panel/Masterpanel/releases)
[![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-orange?style=for-the-badge)](https://github.com/Masterv2panel/Masterpanel)

</div>

---

## ✨ ویژگی‌ها

- **مدیریت کاربر** — ساخت کاربر با UUID اختصاصی، محدودیت ترافیک، تاریخ انقضا
- **ساخت خودکار کانفیگ** — به ازای هر کاربر: VLESS، VMess، Trojan، Shadowsocks، TUIC v5، Hysteria2
- **Cloudflare CDN** — کانفیگ‌های بهینه برای تمام پورت‌های CF (443، 2053، 2083، 2087، 2096، 8443)
- **IP مستقیم** — کانفیگ‌های بدون CDN با TLS کامل
- **REALITY** — چهار dest مختلف (Google، Apple، Discord، jsDelivr) با کلید x25519 خودکار
- **آپدیت یک‌کلیکی** — آپدیت مستقیم از GitHub بدون نیاز به دستور
- **نظارت ترافیک** — آمار آپلود/دانلود از Xray API
- **تست اتصال** — تست پورت و لیتنسی داخل پنل
- **بررسی TLS** — تست handshake و نمایش Cipher Suite
- **سشن پایدار** — بدون logout هنگام رفرش
- **رابط فارسی** — طراحی dark mode کامل

---

## 📦 پروتکل‌های پشتیبانی‌شده

| پروتکل | Transport | TLS | نوع اتصال |
|--------|-----------|-----|-----------|
| VLESS | WS | TLS | CF (6 پورت) + IP مستقیم |
| VLESS | gRPC | TLS | CF + IP |
| VLESS | HTTPUpgrade | TLS | CF + IP |
| VLESS | TCP | TLS | IP مستقیم |
| VLESS | TCP | REALITY | IP (4 dest) |
| VMess | WS | TLS | CF (4 پورت) + IP |
| VMess | gRPC | TLS | CF |
| VMess | HTTPUpgrade | TLS | CF + IP |
| Trojan | WS | TLS | CF (3 پورت) + IP |
| Trojan | gRPC | TLS | CF |
| Trojan | TCP | TLS | IP |
| Trojan | TCP | REALITY | IP |
| Shadowsocks | TCP | — | IP (chacha20 + aes256) |
| TUIC v5 | UDP | TLS | IP + CF |
| Hysteria2 | UDP | TLS | IP (plain + obfs) |

---

## ⚡ نصب سریع

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main/install.sh)
```

### پیش‌نیازها
- Ubuntu 20.04+ یا Debian 11+
- دامنه‌ای که DNS آن به IP سرور اشاره دارد (برای SSL)
- پورت 80 باز باشد (برای Let's Encrypt)
- دسترسی root

### مراحل نصب
نصب‌کننده از شما می‌پرسد:
1. **دامنه** — مثال: `vpn.example.com`
2. **نام کاربری پنل** — حداقل 4 کاراکتر
3. **رمز عبور پنل** — حداقل 8 کاراکتر

بعد از نصب، پنل روی `https://SERVER_IP:9090` در دسترس است (HTTPS مستقیم).

> ⚠️ **مهم:** پنل را با **IP مستقیم روی HTTPS** باز کنید، نه دامنه. Cloudflare پورت 9090 را پروکسی نمی‌کند. اگر گواهی واقعی صادر نشده باشد، پنل از گواهی self-signed استفاده می‌کند و باید یک‌بار هشدار مرورگر را بپذیرید.

---

## 🔧 استفاده

### ۱. ورود به پنل
```
https://YOUR_SERVER_IP:9090
```

### ۲. ساخت کاربر
- برو به **کاربران** → **+ کاربر جدید**
- نام، محدودیت ترافیک (GB)، و تاریخ انقضا را مشخص کن

### ۳. ساخت کانفیگ
- روی **⚙️ کانفیگ‌ها** کلیک کن
- پروتکل مورد نظر یا **همه پروتکل‌ها** را انتخاب کن
- کانفیگ‌های اختصاصی آن کاربر ساخته می‌شود

### ۴. دریافت لینک
- **QR Code** — برای اسکن با کلاینت موبایل
- **📋 کپی لینک** — کپی لینک منفرد
- **کپی سابسکریپشن** — Base64 برای import در v2rayN/Nekobox/Hiddify
- **دانلود لینک‌ها** — فایل txt با همه لینک‌ها

---

## 🏗️ معماری فنی

### ساختار CF vs Direct IP

```
کلاینت ──[TLS]──▶ Cloudflare ──[plain HTTP]──▶ Xray (internal port)
کلاینت ──[TLS]──▶ Xray (direct port with cert)
```

### پورت‌های Cloudflare
CF فقط این پورت‌های HTTPS را پروکسی می‌کند:
`443`, `2053`, `2083`, `2087`, `2096`, `8443`

### پورت‌های مستقیم Xray

| پروتکل | Transport | پورت |
|--------|-----------|------|
| VLESS | TCP TLS | 2053 |
| VLESS | WS TLS | 8443 |
| VLESS | HTTPUpgrade | 2087 |
| VLESS | TCP no-TLS | 10086 |
| VLESS | REALITY | 443 |
| VMess | TCP TLS | 2053 |
| VMess | WS no-TLS | 10087 |
| VMess | HTTPUpgrade | 2082 |
| Trojan | TCP TLS | 2096 |
| Trojan | WS TLS | 8443 |
| Trojan | HTTPUpgrade | 2053 |
| SS chacha20 | TCP | 8388 |
| SS aes256 | TCP | 8389 |
| TUIC v5 | UDP | 443 |
| Hysteria2 | UDP | 443, 8443, 19999 |

---

## 📂 ساختار فایل‌ها

```
/opt/masterpanel/
├── masterpanel.py          # سرور اصلی (Flask)
├── panel.conf              # تنظیمات: دامنه، یوزر، رمز
├── version.txt             # نسخه فعلی
├── .secret_key             # کلید سشن (پایدار بین ری‌استارت‌ها)
├── venv/                   # محیط Python
├── templates/
│   └── index.html          # رابط فارسی
├── configs/
│   ├── users.json          # اطلاعات کاربران و کانفیگ‌هایشان
│   ├── tuic_config.json    # کانفیگ TUIC server
│   └── hysteria2_config.yaml
└── logs/
    ├── panel.log
    ├── xray-access.log
    └── xray-error.log

/usr/local/etc/xray/
└── config.json             # کانفیگ Xray (خودکار)

/usr/local/bin/
├── xray                    # Xray core binary
├── hysteria                # Hysteria2 binary
└── tuic-server             # TUIC binary
```

---

## 🔄 آپدیت

### از داخل پنل (توصیه‌شده)
برو به داشبورد → دکمه **🔄 آپدیت** → تأیید

### دستی از سرور
```bash
bash /opt/masterpanel/mp.sh update
```

---

## 🛠️ مدیریت سرویس

```bash
# وضعیت کامل
bash /opt/masterpanel/mp.sh status

# ری‌استارت همه سرویس‌ها
bash /opt/masterpanel/mp.sh restart-all

# لاگ‌ها
bash /opt/masterpanel/mp.sh logs panel
bash /opt/masterpanel/mp.sh logs xray
bash /opt/masterpanel/mp.sh logs hy2

# تمدید SSL
bash /opt/masterpanel/mp.sh renew-ssl

# تغییر رمز
bash /opt/masterpanel/mp.sh update-pass

# حذف کامل
bash /opt/masterpanel/mp.sh uninstall
```

---

## 🔐 پیکربندی Cloudflare

برای استفاده از CDN:

1. رکورد A بسازید: `sub.domain.com` → IP سرور
2. Proxy status: 🟠 **Proxied**
3. SSL/TLS mode: **Full** (نه Strict)
4. در کلاینت: آدرس = دامنه، SNI = دامنه، TLS = روشن

---

## ⚠️ عیب‌یابی

**پنل باز نمی‌شود:**
```bash
systemctl status masterpanel
journalctl -u masterpanel -n 30
```

**Xray غیرفعال است:**
```bash
# دانلود geoip (اگر نصب نشده)
wget -O /usr/local/bin/geoip.dat \
  https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
wget -O /usr/local/bin/geosite.dat \
  https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat

systemctl restart xray
systemctl status xray
```

**SSL خطا دارد:**
```bash
# چک DNS
dig +short sub.domain.com

# تمدید
certbot renew --force-renewal -d sub.domain.com
```

---

## 📄 لایسنس

MIT License — آزاد برای استفاده شخصی و تجاری

---

<div align="center">

**ساخته‌شده با ❤️ برای جامعه فارسی‌زبان**

[گزارش مشکل](https://github.com/Masterv2panel/Masterpanel/issues) · [درخواست ویژگی](https://github.com/Masterv2panel/Masterpanel/issues)

</div>
