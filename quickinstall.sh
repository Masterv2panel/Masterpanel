#!/bin/bash
# ============================================================
#   MasterPanel - Quick Installer v3.0
#   نصب با یک دستور
#   Usage: bash <(curl -Ls https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main/quickinstall.sh)
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

GITHUB_REPO="Masterv2panel/Masterpanel"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/main"

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║      MasterPanel Quick Installer v3.0         ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

[[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR] به عنوان root اجرا کنید: sudo bash quickinstall.sh${NC}" && exit 1

# نصب ابزارهای پایه
apt-get install -y -qq curl wget 2>/dev/null || true

TMPDIR=$(mktemp -d)
echo -e "${GREEN}[INFO]${NC} دایرکتوری موقت: $TMPDIR"
echo -e "${YELLOW}[INFO]${NC} در حال دانلود فایل‌ها از GitHub..."

FAILED=0
for FILE in install.sh masterpanel.py index.html mp.sh quickinstall.sh; do
  echo -ne "  دانلود $FILE ... "
  if wget -q "${GITHUB_RAW}/${FILE}" -O "${TMPDIR}/${FILE}" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${RED}ناموفق${NC}"
    FAILED=$((FAILED+1))
  fi
done

if [[ $FAILED -gt 0 ]]; then
  echo -e "${RED}[ERROR]${NC} $FAILED فایل دانلود نشد"
  echo -e "${YELLOW}راهنما:${NC} فایل‌ها را دستی آپلود کنید:"
  echo "  git clone https://github.com/${GITHUB_REPO}.git && cd Masterpanel"
  echo "  chmod +x install.sh && sudo bash install.sh"
  rm -rf "$TMPDIR"
  exit 1
fi

chmod +x "$TMPDIR/install.sh" "$TMPDIR/mp.sh" "$TMPDIR/quickinstall.sh"
cd "$TMPDIR"
bash install.sh

rm -rf "$TMPDIR"
