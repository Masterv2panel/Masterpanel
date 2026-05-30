#!/bin/bash
# ============================================================
#   MasterPanel - Quick Installer
#   Downloads all files and runs install.sh
#   Usage: bash quickinstall.sh
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║      MasterPanel Quick Installer          ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${NC}"

# Check root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR] Run as root: sudo bash quickinstall.sh${NC}"
  exit 1
fi

# Temp working dir
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
echo -e "${GREEN}[INFO]${NC} Working directory: $TMPDIR"

# Install curl/wget if missing
apt-get install -y -qq curl wget 2>/dev/null || true

# ── If running from a local directory with all files present ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/masterpanel.py" && -f "$SCRIPT_DIR/index.html" && -f "$SCRIPT_DIR/install.sh" ]]; then
  echo -e "${GREEN}[INFO]${NC} Found local files in $SCRIPT_DIR"
  cp "$SCRIPT_DIR/masterpanel.py" "$TMPDIR/"
  cp "$SCRIPT_DIR/index.html" "$TMPDIR/"
  cp "$SCRIPT_DIR/install.sh" "$TMPDIR/"
else
  # ── Download from GitHub (update URL after pushing to your repo) ──
  REPO_URL="https://raw.githubusercontent.com/amirjafary4-jpg/Masterpanel/main"
  echo -e "${YELLOW}[WARN]${NC} Local files not found. Trying to download..."

  for FILE in install.sh masterpanel.py index.html; do
    echo -e "${GREEN}[INFO]${NC} Downloading $FILE..."
    if ! wget -q "$REPO_URL/$FILE" -O "$FILE"; then
      echo -e "${RED}[ERROR]${NC} Failed to download $FILE"
      echo -e "${YELLOW}[HINT]${NC} Upload the 3 files manually and run:"
      echo -e "  cd /tmp/mp && chmod +x install.sh && bash install.sh"
      exit 1
    fi
  done
fi

chmod +x "$TMPDIR/install.sh"
bash "$TMPDIR/install.sh"

# Cleanup
rm -rf "$TMPDIR"
