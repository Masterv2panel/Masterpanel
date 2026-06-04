# MasterPanel v3.0 - Enterprise Edition

پنل مدیریت حرفه‌ای Xray با مدیریت کاربران، رصد ترافیک و رابط فارسی

---

## ویژگی‌های نسخه ۳

- **مدیریت کاربران با SQLite** — ایجاد، ویرایش، حذف کاربران
- **معماری Multi-Client** — همه کاربران در یک اینباند مشترک (نه پورت جداگانه)
- **رصد ترافیک خودکار** — هر ۵ دقیقه از API داخلی Xray
- **اعمال محدودیت** — غیرفعال شدن خودکار پس از اتمام سهمیه یا انقضا
- **سابسکریپشن عمومی** — `/sub/<username>` با هدرهای استاندارد
- **به‌روزرسانی از GitHub** — مستقیم از پنل یا ترمینال
- **پشتیبانی از TUIC v5 و Hysteria2** — با multi-user

---

## پیش‌نیازها

- Ubuntu 20.04 / 22.04 / Debian 11+
- دامنه با DNS به IP سرور
- پورت 80 و 443 باز

---

## نصب

### روش ۱ — یک دستور

```bash
bash <(curl -Ls https://raw.githubusercontent.com/amirjafary4-jpg/Masterpanel/main/quickinstall.sh)
```

### روش ۲ — دستی

```bash
# آپلود همه فایل‌ها در یک پوشه، سپس:
chmod +x install.sh
sudo bash install.sh
```

---

## دسترسی به پنل

```
http://YOUR_SERVER_IP:9090
```

⚠️ از **IP سرور** باز کنید، نه دامنه!

---

## ساختار پورت‌ها

| پروتکل | Transport | TLS | پورت |
|--------|-----------|-----|------|
| VLESS  | REALITY   | Reality | 443 |
| VLESS  | WebSocket | TLS | 8443 |
| VLESS  | gRPC      | TLS | 2053 |
| VLESS  | HTTPUpgrade | TLS | 2087 |
| VMess  | WebSocket | TLS | 2083 |
| VMess  | gRPC      | TLS | 2096 |
| Trojan | WebSocket | TLS | 2052 |
| Trojan | TCP       | TLS | 2082 |
| Shadowsocks | TCP  | —   | 8388 |
| Shadowsocks | TCP  | —   | 8389 |
| TUIC v5 | UDP     | TLS | 19443 |
| Hysteria2 | UDP   | TLS | 19444 |

---

## مدیریت از ترمینال

```bash
# وضعیت کامل
bash /opt/masterpanel/mp.sh status

# لیست کاربران
bash /opt/masterpanel/mp.sh users

# ری‌استارت همه سرویس‌ها
bash /opt/masterpanel/mp.sh restart-all

# آپدیت از GitHub
bash /opt/masterpanel/mp.sh update

# لاگ پنل
bash /opt/masterpanel/mp.sh logs panel

# پشتیبان از پایگاه داده
bash /opt/masterpanel/mp.sh db-backup
```

---

## API سابسکریپشن

برای هر کاربر یک URL اختصاصی:

```
http://YOUR_IP:9090/sub/USERNAME
```

هدرهای استاندارد:
- `Subscription-Userinfo` — مصرف و سهمیه
- `Profile-Title` — نام کاربر

---

## ساختار فایل‌ها

```
/opt/masterpanel/
├── masterpanel.py       # سرور اصلی
├── masterpanel.db       # پایگاه داده SQLite
├── panel.conf           # تنظیمات
├── venv/                # محیط Python
├── templates/
│   └── index.html       # رابط کاربری
├── configs/
│   ├── tuic_config.json
│   └── hysteria2_config.yaml
└── logs/
    ├── panel.log
    ├── xray-access.log
    └── xray-error.log
```

---

## عیب‌یابی

```bash
# لاگ پنل
journalctl -u masterpanel -n 50

# لاگ Xray
tail -f /opt/masterpanel/logs/xray-error.log

# تست کانفیگ Xray
/usr/local/bin/xray run -test -c /usr/local/etc/xray/config.json

# وضعیت سرویس‌ها
systemctl status masterpanel xray
```

---

## به‌روزرسانی

از پنل: **تنظیمات → بررسی و نصب آپدیت از GitHub**

یا از ترمینال:
```bash
bash /opt/masterpanel/mp.sh update
```

---

## حذف کامل

```bash
bash /opt/masterpanel/mp.sh uninstall
```
