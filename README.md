# MasterPanel - Xray Auto Protocol Configurator

پنل مدیریت خودکار پروتکل‌های Xray با رابط فارسی

---

## ویژگی‌ها

- ساخت خودکار تمام پروتکل‌ها (VLESS, VMess, Trojan, Shadowsocks)
- پشتیبانی از REALITY, WS, gRPC, TCP, HTTPUpgrade
- رابط کاربری فارسی
- تست اتصال و لیتنسی داخل پنل
- بررسی TLS/SSL
- QR Code برای هر کانفیگ
- کپی لینک اشتراک‌گذاری
- نصب و راه‌اندازی کاملاً خودکار

---

## پیش‌نیازها

- سرور Ubuntu 20.04 / 22.04 / Debian 11+
- دامنه با DNS روی Cloudflare یا هر DNS دیگری
- DNS رکورد دامنه به IP سرور اشاره کند
- پورت 80 و 443 باز باشد (برای SSL)

---

## نصب

### روش ۱ - نصب سریع (یک دستور)

```bash
bash <(curl -Ls https://raw.githubusercontent.com/amirjafary4-jpg/Masterpanel/main/quickinstall.sh)
```

### روش ۲ - نصب دستی

```bash
# ۱. کلون یا دانلود فایل‌ها
mkdir /tmp/masterpanel && cd /tmp/masterpanel

# فایل‌ها را آپلود کنید:
# - install.sh
# - masterpanel.py
# - index.html

# ۲. اجرای نصب‌کننده
chmod +x install.sh
sudo bash install.sh
```

نصب‌کننده از شما می‌پرسد:
- دامنه (مثال: vpn.example.com)
- نام کاربری پنل
- رمز عبور پنل (حداقل ۸ کاراکتر)

---

## دسترسی به پنل

بعد از نصب:

```
http://YOUR_SERVER_IP:9090
```

---

## ساختار فایل‌ها

```
/opt/masterpanel/
├── masterpanel.py      # سرور اصلی پنل
├── panel.conf          # تنظیمات (دامنه، یوزر، پسورد)
├── venv/               # محیط Python
├── templates/
│   └── index.html      # رابط فارسی پنل
├── configs/
│   └── all_configs.json  # کانفیگ‌های ساخته‌شده
└── logs/
    ├── panel.log         # لاگ پنل
    ├── xray-access.log   # لاگ دسترسی Xray
    └── xray-error.log    # لاگ خطای Xray

/usr/local/etc/xray/
└── config.json         # کانفیگ اصلی Xray

/usr/local/bin/
└── xray                # باینری Xray
```

---

## مدیریت سرویس

```bash
# وضعیت پنل
systemctl status masterpanel

# ری‌استارت پنل
systemctl restart masterpanel

# لاگ پنل
tail -f /opt/masterpanel/logs/panel.log

# وضعیت Xray
systemctl status xray

# لاگ Xray
tail -f /opt/masterpanel/logs/xray-error.log
```

---

## پروتکل‌های پشتیبانی‌شده

| پروتکل | Transport | TLS | پورت |
|--------|-----------|-----|------|
| VLESS | WebSocket | TLS | 443 |
| VLESS | WebSocket | TLS | 8443 |
| VLESS | gRPC | TLS | 443 |
| VLESS | TCP | TLS | 2053 |
| VLESS | REALITY | REALITY | 443 |
| VLESS | HTTPUpgrade | TLS | 8443 |
| VMess | WebSocket | TLS | 443 |
| VMess | WebSocket | TLS | 2083 |
| VMess | gRPC | TLS | 443 |
| VMess | TCP | TLS | 2053 |
| Trojan | WebSocket | TLS | 443 |
| Trojan | TCP | TLS | 443 |
| Trojan | gRPC | TLS | 443 |
| Shadowsocks | TCP | — | 8388 |
| Shadowsocks | TCP | — | 8389 |

---

## پورت‌های Cloudflare CDN

پورت‌هایی که Cloudflare پروکسی می‌کند:

**HTTPS:** 443, 2053, 2083, 2087, 2096, 8443

**HTTP:** 80, 8080, 8880, 2052, 2082, 2086, 2095

---

## تنظیمات Cloudflare

برای استفاده از CDN کلادفلیر:

1. رکورد A بسازید: `sub.example.com` → IP سرور
2. Proxy Status: 🟠 Proxied
3. SSL/TLS Mode: **Full** (نه Strict اگه self-signed دارید)

---

## عیب‌یابی

**پنل باز نمی‌شود:**
```bash
systemctl status masterpanel
journalctl -u masterpanel -n 50
```

**SSL نگرفت:**
```bash
# مطمئن شوید پورت 80 باز است
ufw allow 80/tcp
# دامنه به IP سرور اشاره می‌کند
dig +short sub.example.com
```

**Xray اجرا نمی‌شود:**
```bash
/usr/local/bin/xray run -c /usr/local/etc/xray/config.json
```

---

## آپدیت

```bash
cd /tmp && mkdir mp_update && cd mp_update
# فایل‌های جدید را آپلود کنید
cp masterpanel.py /opt/masterpanel/
cp index.html /opt/masterpanel/templates/
systemctl restart masterpanel
```

---

## حذف

```bash
systemctl stop masterpanel
systemctl disable masterpanel
rm /etc/systemd/system/masterpanel.service
rm -rf /opt/masterpanel
systemctl daemon-reload
```
