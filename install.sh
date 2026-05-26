#!/bin/bash
# ══════════════════════════════════════════════════════════════════
#  Johnny Castaway RTSP – Install Script für Debian/Ubuntu LXC
#  https://github.com/DEIN-USERNAME/johnny-castaway-rtsp
#
#  Aufruf:
#    bash <(curl -fsSL https://raw.githubusercontent.com/DEIN-USERNAME/johnny-castaway-rtsp/main/install.sh)
# ══════════════════════════════════════════════════════════════════
set -e

# ── Farben ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✓]${NC} $*"; }
info()    { echo -e "${CYAN}[…]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
err()     { echo -e "${RED}[✗]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ── Konfiguration ─────────────────────────────────────────────────
INSTALL_DIR="/opt/johnny-castaway"
SCREENSAVER_DIR="${INSTALL_DIR}/screensaver"
SCR_FILE="${SCREENSAVER_DIR}/johnny.scr"
MEDIAMTX_VERSION="v1.9.1"
MEDIAMTX_DIR="/opt/mediamtx"
DISPLAY_NUM=":99"
WIDTH=640
HEIGHT=480
FPS=10
BITRATE="300k"
RTSP_PORT=8554
HLS_PORT=8888

# ── Root-Check ────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || err "Bitte als root ausführen (sudo bash install.sh)"

# ── OS-Check ─────────────────────────────────────────────────────
if ! grep -qiE "debian|ubuntu" /etc/os-release 2>/dev/null; then
    err "Nur Debian/Ubuntu wird unterstützt."
fi

section "System-Pakete installieren"
info "Paketlisten aktualisieren..."
apt-get update -qq

info "32-Bit-Architektur aktivieren (für Wine)..."
dpkg --add-architecture i386
apt-get update -qq

info "Pakete installieren (Wine, Xvfb, FFmpeg)..."
apt-get install -y --no-install-recommends \
    wine \
    wine32 \
    xvfb \
    ffmpeg \
    wget \
    curl \
    procps \
    ca-certificates \
    2>/dev/null
log "Pakete installiert."

section "MediaMTX installieren"
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  MTX_ARCH="amd64" ;;
    aarch64) MTX_ARCH="arm64" ;;
    armv7*)  MTX_ARCH="armv7" ;;
    *) err "Unbekannte Architektur: $ARCH" ;;
esac

MTX_URL="https://github.com/bluenviron/mediamtx/releases/download/${MEDIAMTX_VERSION}/mediamtx_${MEDIAMTX_VERSION}_linux_${MTX_ARCH}.tar.gz"

info "Lade MediaMTX ${MEDIAMTX_VERSION} (${MTX_ARCH})..."
mkdir -p "${MEDIAMTX_DIR}"
wget -q --show-progress -O /tmp/mediamtx.tar.gz "${MTX_URL}"
tar -xzf /tmp/mediamtx.tar.gz -C "${MEDIAMTX_DIR}"
rm /tmp/mediamtx.tar.gz
chmod +x "${MEDIAMTX_DIR}/mediamtx"
log "MediaMTX installiert → ${MEDIAMTX_DIR}/mediamtx"

section "Verzeichnisse & Konfiguration anlegen"
mkdir -p "${SCREENSAVER_DIR}"
mkdir -p "/root/.wine"

# MediaMTX Konfiguration
cat > "${MEDIAMTX_DIR}/mediamtx.yml" <<EOF
logLevel: warn
rtsp:
  protocols: [tcp]
rtspAddress: :${RTSP_PORT}
hls:
  address: :${HLS_PORT}
api:
  address: :9997
EOF
log "MediaMTX Konfiguration → ${MEDIAMTX_DIR}/mediamtx.yml"

# Start-Script für Johnny Castaway
cat > "${INSTALL_DIR}/start.sh" <<SCRIPT
#!/bin/bash
set -e

SCR_FILE="${SCR_FILE}"
DISPLAY="${DISPLAY_NUM}"
export DISPLAY
export WINEPREFIX="/root/.wine"
export WINEDLLOVERRIDES="mscoree,mshtml="

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "\${GREEN}[johnny]\${NC} \$*"; }
warn() { echo -e "\${YELLOW}[johnny]\${NC} \$*"; }
err()  { echo -e "\${RED}[johnny]\${NC} \$*"; }

# Prüfe .scr Datei
if [ ! -f "\${SCR_FILE}" ]; then
    err "──────────────────────────────────────────────────"
    err " FEHLER: Screensaver-Datei nicht gefunden!"
    err ""
    err " Bitte kopiere deine johnny.scr hierhin:"
    err "   ${SCREENSAVER_DIR}/johnny.scr"
    err ""
    err " Dann Service neu starten:"
    err "   systemctl restart johnny-castaway"
    err "──────────────────────────────────────────────────"
    exit 1
fi
log "Screensaver gefunden: \${SCR_FILE}"

# Xvfb starten
log "Starte Xvfb (${WIDTH}x${HEIGHT}) auf Display ${DISPLAY_NUM}"
Xvfb ${DISPLAY_NUM} -screen 0 ${WIDTH}x${HEIGHT}x16 -nolisten tcp &
XVFB_PID=\$!
sleep 2

# Wine-Prefix initialisieren (nur beim ersten Start)
if [ ! -d "\${WINEPREFIX}/drive_c" ]; then
    log "Initialisiere Wine (einmalig, ~30s)..."
    wineboot --init 2>/dev/null
    sleep 8
fi

# Johnny Castaway starten
log "Starte Johnny Castaway..."
wine "\${SCR_FILE}" /s &
WINE_PID=\$!
sleep 4

# Cleanup bei Shutdown
cleanup() {
    warn "Shutdown..."
    kill \$WINE_PID \$XVFB_PID 2>/dev/null || true
}
trap cleanup SIGTERM SIGINT

# FFmpeg → RTSP
log "Stream läuft → rtsp://\$(hostname -I | awk '{print \$1}'):${RTSP_PORT}/johnny"
log "HLS:           http://\$(hostname -I | awk '{print \$1}'):${HLS_PORT}/johnny"

ffmpeg -loglevel warning \
    -f x11grab \
    -r ${FPS} \
    -s ${WIDTH}x${HEIGHT} \
    -i ${DISPLAY_NUM}.0 \
    -vcodec libx264 \
    -preset ultrafast \
    -tune animation \
    -b:v ${BITRATE} \
    -maxrate ${BITRATE} \
    -bufsize 600k \
    -pix_fmt yuv420p \
    -g $(( FPS * 2 )) \
    -f rtsp \
    -rtsp_transport tcp \
    "rtsp://127.0.0.1:${RTSP_PORT}/johnny"

wait \$WINE_PID \$XVFB_PID 2>/dev/null
SCRIPT

chmod +x "${INSTALL_DIR}/start.sh"
log "Start-Script → ${INSTALL_DIR}/start.sh"

section "systemd Services einrichten"

# MediaMTX Service
cat > /etc/systemd/system/mediamtx.service <<EOF
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

# Johnny Castaway Service
cat > /etc/systemd/system/johnny-castaway.service <<EOF
[Unit]
Description=Johnny Castaway RTSP Stream
After=network.target mediamtx.service
Requires=mediamtx.service

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/start.sh
Restart=always
RestartSec=10
# Warte auf MediaMTX beim Start
ExecStartPre=/bin/sleep 3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mediamtx
systemctl enable johnny-castaway
systemctl start mediamtx
log "Services aktiviert & MediaMTX gestartet."

# ── Abschlussmeldung ──────────────────────────────────────────────
HOST_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Installation abgeschlossen!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${YELLOW}Nächster Schritt – johnny.scr kopieren:${NC}"
echo -e "  ${CYAN}cp /pfad/zu/johnny.scr ${SCREENSAVER_DIR}/${NC}"
echo ""
echo -e "  Dann Stream starten:"
echo -e "  ${CYAN}systemctl start johnny-castaway${NC}"
echo ""
echo -e "  Stream-URLs:"
echo -e "  ${GREEN}RTSP:${NC}  rtsp://${HOST_IP}:${RTSP_PORT}/johnny"
echo -e "  ${GREEN}HLS: ${NC}  http://${HOST_IP}:${HLS_PORT}/johnny"
echo ""
echo -e "  Nützliche Befehle:"
echo -e "  ${CYAN}systemctl status johnny-castaway${NC}   Status"
echo -e "  ${CYAN}journalctl -u johnny-castaway -f${NC}   Logs"
echo -e "  ${CYAN}systemctl restart johnny-castaway${NC}  Neustart"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
