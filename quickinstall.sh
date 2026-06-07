#!/bin/bash
# ============================================================
#   MasterPanel - Quick Installer
#   Usage: bash quickinstall.sh
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║      MasterPanel Quick Installer          ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${NC}"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] Run as root: sudo bash quickinstall.sh${NC}"
    exit 1
fi

apt-get install -y -qq curl wget 2>/dev/null || true

REPO_URL="https://raw.githubusercontent.com/Masterv2panel/Masterpanel/main"
TMPDIR=$(mktemp -d)
echo -e "${GREEN}[INFO]${NC} Working directory: $TMPDIR"

# ── اگه فایل‌ها در کنار quickinstall.sh باشن ──
# نکته: BASH_SOURCE[0] وقتی با bash <(curl) اجرا میشه درست کار نمیکنه
# پس اول چک میکنیم آیا فایل‌ها در pwd هستن
if [[ -f "$(pwd)/masterpanel.py" && -f "$(pwd)/index.html" && -f "$(pwd)/install.sh" ]]; then
    echo -e "${GREEN}[INFO]${NC} Found local files in $(pwd)"
    cp "$(pwd)/masterpanel.py" "$TMPDIR/"
    cp "$(pwd)/index.html"     "$TMPDIR/"
    cp "$(pwd)/install.sh"     "$TMPDIR/"
    cp "$(pwd)/bot.py"         "$TMPDIR/" 2>/dev/null || true
    cp "$(pwd)/mp.sh"          "$TMPDIR/" 2>/dev/null || true
else
    echo -e "${YELLOW}[INFO]${NC} Downloading from GitHub..."
    for FILE in install.sh masterpanel.py index.html bot.py mp.sh; do
        if wget -q "$REPO_URL/$FILE" -O "$TMPDIR/$FILE" 2>/dev/null; then
            echo -e "${GREEN}[OK]${NC} $FILE"
        else
            if [[ "$FILE" == "install.sh" || "$FILE" == "masterpanel.py" || "$FILE" == "index.html" ]]; then
                echo -e "${RED}[ERROR]${NC} Failed to download required file: $FILE"
                rm -rf "$TMPDIR"
                exit 1
            else
                echo -e "${YELLOW}[WARN]${NC} Optional file not found: $FILE"
            fi
        fi
    done
fi

chmod +x "$TMPDIR/install.sh"
if [[ -f "$TMPDIR/mp.sh" ]]; then chmod +x "$TMPDIR/mp.sh"; fi

cd "$TMPDIR"
bash install.sh

rm -rf "$TMPDIR"
