#!/bin/bash
# ============================================================
#   MasterPanel - Quick Installer v3.0
#   یک دستور نصب کامل
#   Usage: bash quickinstall.sh
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║      MasterPanel Quick Installer v3.0         ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

[[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR] به عنوان root اجرا کنید: sudo bash quickinstall.sh${NC}" && exit 1

TMPDIR=$(mktemp -d)
cd "$TMPDIR"
echo -e "${GREEN}[INFO]${NC} دایرکتوری موقت: $TMPDIR"

apt-get install -y -qq curl wget 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# اگر فایل‌ها در کنار این اسکریپت هستند
if [[ -f "$SCRIPT_DIR/masterpanel.py" && -f "$SCRIPT_DIR/index.html" && -f "$SCRIPT_DIR/install.sh" ]]; then
  echo -e "${GREEN}[INFO]${NC} فایل‌های محلی یافت شدند در $SCRIPT_DIR"
  for f in masterpanel.py index.html install.sh mp.sh; do
    [[ -f "$SCRIPT_DIR/$f" ]] && cp "$SCRIPT_DIR/$f" "$TMPDIR/"
  done
else
  # دانلود از GitHub
  REPO_URL="https://raw.githubusercontent.com/amirjafary4-jpg/Masterpanel/main"
  echo -e "${YELLOW}[INFO]${NC} در حال دانلود از GitHub..."
  FAILED=0
  for FILE in install.sh masterpanel.py index.html mp.sh; do
    echo -ne "  دانلود $FILE ... "
    if wget -q "$REPO_URL/$FILE" -O "$TMPDIR/$FILE" 2>/dev/null; then
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}ناموفق${NC}"; FAILED=$((FAILED+1))
    fi
  done

  if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}[ERROR]${NC} $FAILED فایل دانلود نشد"
    echo -e "${YELLOW}[راهنما]${NC} فایل‌ها را دستی آپلود کنید و اجرا کنید:"
    echo "  cd /tmp && mkdir mp && cd mp"
    echo "  # فایل‌ها را آپلود کنید"
    echo "  chmod +x install.sh && bash install.sh"
    exit 1
  fi
fi

chmod +x "$TMPDIR/install.sh"
bash "$TMPDIR/install.sh"

rm -rf "$TMPDIR"
