#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
#  Johnny Castaway RTSP – Install Script
#  Getestet auf: Ubuntu 26.04 LXC (Proxmox)
#
#  Aufruf:
#    apt-get -qq -o Dpkg::Use-Pty=0 install -y curl > /dev/null && \
#    bash <(curl -fsSL https://raw.githubusercontent.com/TVR-X/johnny-castaway-rtsp/main/install.sh)
#
#  Nach Installation:
#    cp /pfad/zu/johnny.scr /opt/johnny-castaway/screensaver/
#    systemctl start johnny-castaway
# ══════════════════════════════════════════════════════════════════════
set -e

export DEBIAN_FRONTEND=noninteractive

# ── Farben ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✓]${NC} $*"; }
info()    { echo -e "${CYAN}[…]${NC} $*"; }
err()     { echo -e "${RED}[✗]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ── Konfiguration ─────────────────────────────────────────────────────
INSTALL_DIR="/opt/johnny-castaway"
SCREENSAVER_DIR="${INSTALL_DIR}/screensaver"
MEDIAMTX_VERSION="v1.9.1"
MEDIAMTX_DIR="/opt/mediamtx"
WIDTH=640
HEIGHT=480
FPS=15
BITRATE="300k"
RTSP_PORT=8554
HLS_PORT=8888
API_PORT=9997

# ── Checks ────────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || err "Bitte als root ausführen"
grep -qiE "debian|ubuntu" /etc/os-release 2>/dev/null || err "Nur Debian/Ubuntu unterstützt"

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
    pulseaudio \
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
info "Lade MediaMTX (${MTX_ARCH})..."
mkdir -p "${MEDIAMTX_DIR}"
wget -q --show-progress \
    -O /tmp/mediamtx.tar.gz \
    "https://github.com/bluenviron/mediamtx/releases/download/${MEDIAMTX_VERSION}/mediamtx_${MEDIAMTX_VERSION}_linux_${MTX_ARCH}.tar.gz"
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
section "PulseAudio"
# ══════════════════════════════════════════════════════════════════════
mkdir -p /root/.config/pulse

cat > /root/.config/pulse/default.pa << 'EOF'
load-module module-pipe-sink sink_name=virtual_out file=/tmp/audio.pipe format=u8 rate=11025 channels=1
set-default-sink virtual_out
load-module module-native-protocol-unix
EOF

cat > /root/.config/pulse/daemon.conf << 'EOF'
exit-idle-time = -1
default-fragments = 2
default-fragment-size-msec = 5
resample-method = trivial
default-sample-rate = 11025
alternate-sample-rate = 11025
EOF
log "PulseAudio konfiguriert"

# ══════════════════════════════════════════════════════════════════════
section "Verzeichnisse"
# ══════════════════════════════════════════════════════════════════════
mkdir -p "${SCREENSAVER_DIR}"
mkdir -p /root/.wine
log "Verzeichnisse angelegt"

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
FPS="${FPS:-15}"
BITRATE="${BITRATE:-300k}"

export DISPLAY=:99
export WINEPREFIX=/root/.wine
export WINEARCH=win32
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEDEBUG=err-vulkan,err-system
export XDG_RUNTIME_DIR=/tmp/pulse-runtime
export PULSE_SERVER=unix:/tmp/pulse-runtime/pulse/native

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[johnny]${NC} $*"; }
warn() { echo -e "${YELLOW}[johnny]${NC} $*"; }
err()  { echo -e "${RED}[johnny]${NC} $*"; }

# Screensaver prüfen
if [ ! -f "${SCR_FILE}" ]; then
    err "──────────────────────────────────────────────"
    err " FEHLER: Screensaver nicht gefunden!"
    err "   /opt/johnny-castaway/screensaver/johnny.scr"
    err " Dann: systemctl start johnny-castaway"
    err "──────────────────────────────────────────────"
    exit 1
fi
log "Screensaver: ${SCR_FILE}"

# Audio-Pipe vorbereiten
rm -f /tmp/audio.pipe
mkfifo /tmp/audio.pipe
log "Audio-Pipe erstellt"

# PulseAudio starten
log "Starte PulseAudio..."
pulseaudio --kill 2>/dev/null || true
sleep 1
mkdir -p "${XDG_RUNTIME_DIR}"
pulseaudio --exit-idle-time=-1 --disallow-exit &
PULSE_PID=$!

# Warten bis Sink bereit
RETRIES=0
until pactl list short sinks 2>/dev/null | grep -q "virtual_out"; do
    RETRIES=$((RETRIES+1))
    [ $RETRIES -ge 15 ] && { err "PulseAudio Timeout"; exit 1; }
    sleep 1
done
log "PulseAudio bereit"

# Wine-Prefix initialisieren (nur einmalig)
if [ ! -d "${WINEPREFIX}/drive_c" ]; then
    log "Initialisiere Wine (einmalig, ~30s)..."
    wineboot --init 2>/dev/null || true
    sleep 8
fi

# Wine auf PulseAudio-Treiber setzen
wine reg add "HKCU\Software\Wine\Drivers" \
    /v Audio /t REG_SZ /d pulse /f 2>/dev/null || true

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
    kill "${PULSE_PID}" 2>/dev/null || true
    pulseaudio --kill 2>/dev/null || true
    rm -f /tmp/audio.pipe
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
    -f u8 \
    -ar 11025 \
    -ac 1 \
    -i /tmp/audio.pipe \
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
CPUQuota=10%
Nice=10
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
