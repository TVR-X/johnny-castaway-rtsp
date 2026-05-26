#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
#  Johnny Castaway RTSP – Install Script
#  Getestet auf: Ubuntu 26.04 LXC (Proxmox)
#
#  Aufruf:
#    apt install curl -y && bash <(curl -fsSL https://raw.githubusercontent.com/TVR-X/johnny-castaway-rtsp/main/install.sh)
#
#  Nach Installation:
#    cp /pfad/zu/johnny.scr /opt/johnny-castaway/screensaver/
#    systemctl start johnny-castaway
# ══════════════════════════════════════════════════════════════════════
set -e

# ── Farben ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✓]${NC} $*"; }
info()    { echo -e "${CYAN}[…]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
err()     { echo -e "${RED}[✗]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ── Konfiguration ─────────────────────────────────────────────────────
INSTALL_DIR="/opt/johnny-castaway"
SCREENSAVER_DIR="${INSTALL_DIR}/screensaver"
MEDIAMTX_VERSION="v1.9.1"
MEDIAMTX_DIR="/opt/mediamtx"
WIDTH=640
HEIGHT=480
FPS=10
BITRATE="300k"
RTSP_PORT=8554
HLS_PORT=8888
API_PORT=9997

export DEBIAN_FRONTEND=noninteractive

# ── Checks ────────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || err "Bitte als root ausführen"
grep -qiE "debian|ubuntu" /etc/os-release 2>/dev/null || err "Nur Debian/Ubuntu unterstützt"

# ── Architektur ───────────────────────────────────────────────────────
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  MTX_ARCH="amd64" ;;
    aarch64) MTX_ARCH="arm64" ;;
    armv7*)  MTX_ARCH="armv7" ;;
    *) err "Unbekannte Architektur: $ARCH" ;;
esac

# ══════════════════════════════════════════════════════════════════════
section "System-Pakete"
# ══════════════════════════════════════════════════════════════════════
info "32-Bit-Architektur aktivieren..."
dpkg --add-architecture i386
apt-get -qq -o Dpkg::Use-Pty=0 update > /dev/null

info "Pakete installieren..."
apt-get -qq -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    wine \
    wine32:i386 \
    libwine:i386 \
    xvfb \
    ffmpeg \
    wget \
    curl \
    procps \
    ca-certificates \
    libx11-6:i386 \
    libxext6:i386 \
    libxrender1:i386 \
    libxrandr2:i386 \
    libxi6:i386 \
    libxcursor1:i386 \
    libxcomposite1:i386 \
    libxinerama1:i386 > /dev/null
log "Pakete installiert"

# ══════════════════════════════════════════════════════════════════════
section "MediaMTX ${MEDIAMTX_VERSION}"
# ══════════════════════════════════════════════════════════════════════
MTX_URL="https://github.com/bluenviron/mediamtx/releases/download/${MEDIAMTX_VERSION}/mediamtx_${MEDIAMTX_VERSION}_linux_${MTX_ARCH}.tar.gz"

info "Lade MediaMTX (${MTX_ARCH})..."
mkdir -p "${MEDIAMTX_DIR}"
wget -q --show-progress -O /tmp/mediamtx.tar.gz "${MTX_URL}"
tar -xzf /tmp/mediamtx.tar.gz -C "${MEDIAMTX_DIR}"
rm /tmp/mediamtx.tar.gz
chmod +x "${MEDIAMTX_DIR}/mediamtx"
log "MediaMTX installiert"

cat > "${MEDIAMTX_DIR}/mediamtx.yml" << EOF
logLevel: warn
rtspAddress: :${RTSP_PORT}
hlsAddress: :${HLS_PORT}
api: true
apiAddress: :${API_PORT}

paths:
  johnny:
    source: publisher
  all_others:
EOF
log "MediaMTX konfiguriert"

# ══════════════════════════════════════════════════════════════════════
section "Verzeichnisse"
# ══════════════════════════════════════════════════════════════════════
mkdir -p "${SCREENSAVER_DIR}"
mkdir -p "/root/.wine"
log "Verzeichnisse angelegt: ${SCREENSAVER_DIR}"

# ══════════════════════════════════════════════════════════════════════
section "start.sh"
# ══════════════════════════════════════════════════════════════════════
cat > "${INSTALL_DIR}/start.sh" << 'SCRIPT'
#!/bin/bash
set -e

SCR_FILE="${SCR_FILE:-/opt/johnny-castaway/screensaver/johnny.scr}"
RTSP_URL="${RTSP_URL:-rtsp://127.0.0.1:8554/johnny}"
WIDTH="${WIDTH:-640}"
HEIGHT="${HEIGHT:-480}"
FPS="${FPS:-10}"
BITRATE="${BITRATE:-300k}"

export DISPLAY=:99
export WINEPREFIX=/root/.wine
export WINEARCH=win32
export WINEDLLOVERRIDES="mscoree,mshtml="

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[johnny]${NC} $*"; }
warn() { echo -e "${YELLOW}[johnny]${NC} $*"; }
err()  { echo -e "${RED}[johnny]${NC} $*"; }

# Screensaver prüfen
if [ ! -f "${SCR_FILE}" ]; then
    err "──────────────────────────────────────────────"
    err " FEHLER: Screensaver nicht gefunden!"
    err ""
    err " Bitte kopiere deine johnny.scr hierhin:"
    err "   /opt/johnny-castaway/screensaver/johnny.scr"
    err ""
    err " Dann:"
    err "   systemctl start johnny-castaway"
    err "──────────────────────────────────────────────"
    exit 1
fi
log "Screensaver: ${SCR_FILE}"

# Wine-Prefix initialisieren (nur einmalig)
if [ ! -d "${WINEPREFIX}/drive_c" ]; then
    log "Initialisiere Wine (einmalig, ~30s)..."
    wineboot --init 2>/dev/null || true
    sleep 8
fi

# Johnny Castaway starten
log "Starte Johnny Castaway..."
wine "${SCR_FILE}" /s &
WINE_PID=$!
sleep 4

# Cleanup bei Shutdown
cleanup() {
    warn "Shutdown..."
    wineserver -k 2>/dev/null || true
    kill "${WINE_PID}" 2>/dev/null || true
}
trap cleanup SIGTERM SIGINT

# FFmpeg → RTSP
HOST_IP=$(hostname -I | awk '{print $1}')
log "Stream → rtsp://${HOST_IP}:8554/johnny"
log "HLS   → http://${HOST_IP}:8888/johnny"

ffmpeg -loglevel warning \
    -f x11grab \
    -r "${FPS}" \
    -s "${WIDTH}x${HEIGHT}" \
    -i :99.0 \
    -f lavfi -i anullsrc=r=44100:cl=mono \
    -vcodec libx264 \
    -preset ultrafast \
    -tune animation \
    -b:v "${BITRATE}" \
    -maxrate "${BITRATE}" \
    -bufsize 600k \
    -pix_fmt yuv420p \
    -g $(( FPS * 2 )) \
    -acodec aac \
    -b:a 32k \
    -f rtsp \
    -rtsp_transport tcp \
    "${RTSP_URL}"
SCRIPT

chmod +x "${INSTALL_DIR}/start.sh"
log "start.sh erstellt"

# ══════════════════════════════════════════════════════════════════════
section "systemd Services"
# ══════════════════════════════════════════════════════════════════════

# Xvfb – eigener stabiler Service
cat > /etc/systemd/system/xvfb.service << EOF
[Unit]
Description=Xvfb Virtual Display :99
After=local-fs.target

[Service]
Type=simple
ExecStartPre=/bin/bash -c 'rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true'
ExecStart=/usr/bin/Xvfb :99 -screen 0 ${WIDTH}x${HEIGHT}x24 -nolisten tcp
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# MediaMTX
cat > /etc/systemd/system/mediamtx.service << EOF
[Unit]
Description=MediaMTX RTSP Server
After=network.target

[Service]
Type=simple
ExecStart=${MEDIAMTX_DIR}/mediamtx ${MEDIAMTX_DIR}/mediamtx.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Johnny Castaway
cat > /etc/systemd/system/johnny-castaway.service << EOF
[Unit]
Description=Johnny Castaway RTSP Stream
After=network.target mediamtx.service xvfb.service
Requires=mediamtx.service xvfb.service

[Service]
Type=simple
ExecStartPre=/bin/bash -c 'wineserver -k 2>/dev/null || true; sleep 1'
ExecStart=${INSTALL_DIR}/start.sh
ExecStop=/bin/bash -c 'wineserver -k 2>/dev/null || true'
KillMode=control-group
TimeoutStopSec=15
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

log "Services geschrieben"

# ══════════════════════════════════════════════════════════════════════
section "Services aktivieren & starten"
# ══════════════════════════════════════════════════════════════════════
systemctl daemon-reload
systemctl enable xvfb mediamtx johnny-castaway
systemctl start xvfb
sleep 2
systemctl start mediamtx
sleep 3
log "Xvfb und MediaMTX gestartet"

# ══════════════════════════════════════════════════════════════════════
HOST_IP=$(hostname -I | awk '{print $1}')
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Installation abgeschlossen!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${YELLOW}Nächster Schritt:${NC}"
echo -e "  ${CYAN}cp /pfad/zu/johnny.scr /opt/johnny-castaway/screensaver/${NC}"
echo -e "  ${CYAN}systemctl start johnny-castaway${NC}"
echo ""
echo -e "  Stream-URLs (sobald gestartet):"
echo -e "  ${GREEN}RTSP:${NC} rtsp://${HOST_IP}:${RTSP_PORT}/johnny"
echo -e "  ${GREEN}HLS: ${NC} http://${HOST_IP}:${HLS_PORT}/johnny"
echo ""
echo -e "  Nützliche Befehle:"
echo -e "  ${CYAN}systemctl status johnny-castaway${NC}   Status"
echo -e "  ${CYAN}journalctl -u johnny-castaway -f${NC}   Logs"
echo -e "  ${CYAN}systemctl restart johnny-castaway${NC}  Neustart"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
