#!/usr/bin/env bash
# ==============================================================
#  Master Panel — نصب‌کننده سریع
#  https://github.com/Masterv2panel/Masterpanel
# ==============================================================
set -e

RED="\033[1;31m"; GREEN="\033[1;32m"; CYAN="\033[1;36m"
YELLOW="\033[1;33m"; DIM="\033[2m"; R="\033[0m"; B="\033[1m"

[[ $EUID -ne 0 ]] && { echo -e "${RED}[خطا] با دسترسی root اجرا کنید: sudo bash $0${R}"; exit 1; }

clear
echo -e "${CYAN}${B}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   🛡  Master Panel — X-UI سنایی v3.0.0   ║"
echo "  ║   https://github.com/Masterv2panel/Masterpanel  ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${R}"

INSTALL_DIR="/opt/xui-panel"
GITHUB_RAW="https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main"

mkdir -p "$INSTALL_DIR"

echo -e "${YELLOW}[۱/۴]${R} دانلود فایل اصلی..."
curl -sL "${GITHUB_RAW}/xui-panel.sh" -o "${INSTALL_DIR}/xui-panel.sh" \
    || { echo -e "${RED}خطا در دانلود xui-panel.sh${R}"; exit 1; }

echo -e "${YELLOW}[۲/۴]${R} دانلود ماژول‌ها..."
curl -sL "${GITHUB_RAW}/xui-panel-part2.sh" -o "${INSTALL_DIR}/xui-panel-part2.sh" \
    || { echo -e "${RED}خطا در دانلود xui-panel-part2.sh${R}"; exit 1; }

echo -e "${YELLOW}[۳/۴]${R} دانلود داشبورد وب..."
curl -sL "${GITHUB_RAW}/xui-dashboard.html" -o "${INSTALL_DIR}/xui-dashboard.html" \
    || echo -e "${DIM}داشبورد دانلود نشد (اختیاری)${R}"

echo -e "${YELLOW}[۴/۴]${R} تنظیم مجوزها..."
chmod +x "${INSTALL_DIR}/xui-panel.sh"
chmod +x "${INSTALL_DIR}/xui-panel-part2.sh"
ln -sf "${INSTALL_DIR}/xui-panel.sh" /usr/local/bin/xui-panel

echo ""
echo -e "${GREEN}${B}✓ نصب کامل شد!${R}"
echo ""
echo -e "  ${CYAN}اجرا:${R}        ${B}sudo xui-panel${R}"
echo -e "  ${CYAN}مسیر نصب:${R}    ${DIM}${INSTALL_DIR}/${R}"
echo -e "  ${CYAN}داشبورد وب:${R}  ${DIM}${INSTALL_DIR}/xui-dashboard.html${R}"
echo ""
echo -ne "  آیا همین الان پنل را اجرا کنید؟ (بله/خیر): "
read -r ans
[[ "$ans" =~ ^(بله|yes|y|Y)$ ]] && exec bash "${INSTALL_DIR}/xui-panel.sh"
