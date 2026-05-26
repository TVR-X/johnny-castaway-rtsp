#!/bin/bash
set -e

# ── Konfiguration (via docker-compose Environment überschreibbar) ──────────
SCR_FILE="${SCR_FILE:-/screensaver/johnny.scr}"
RTSP_URL="${RTSP_URL:-rtsp://mediamtx:8554/johnny}"
WIDTH="${WIDTH:-640}"
HEIGHT="${HEIGHT:-480}"
FPS="${FPS:-10}"
BITRATE="${BITRATE:-300k}"
MEDIAMTX_HOST="${MEDIAMTX_HOST:-mediamtx}"
MEDIAMTX_PORT="${MEDIAMTX_PORT:-8554}"

# ── Farben für Logs ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[johnny]${NC} $*"; }
warn() { echo -e "${YELLOW}[johnny]${NC} $*"; }
err()  { echo -e "${RED}[johnny]${NC} $*"; }

# ── Prüfe ob .scr vorhanden ───────────────────────────────────────────────
if [ ! -f "${SCR_FILE}" ]; then
    err "────────────────────────────────────────────────────────"
    err "  FEHLER: Screensaver-Datei nicht gefunden!"
    err ""
    err "  Erwartet unter: ${SCR_FILE}"
    err ""
    err "  Lösung:"
    err "  1. Erstelle den Ordner:  mkdir -p screensaver"
    err "  2. Kopiere deine Datei:  cp /pfad/zu/johnny.scr screensaver/"
    err "  3. Starte neu:           docker compose up -d"
    err "────────────────────────────────────────────────────────"
    exit 1
fi

log "Screensaver gefunden: ${SCR_FILE}"

# ── Warte auf MediaMTX ────────────────────────────────────────────────────
log "Warte auf MediaMTX (${MEDIAMTX_HOST}:${MEDIAMTX_PORT})..."
RETRIES=0
until wget -q --timeout=2 -O /dev/null \
    "http://${MEDIAMTX_HOST}:9997/v3/config/get" 2>/dev/null; do
    RETRIES=$((RETRIES+1))
    if [ $RETRIES -ge 30 ]; then
        err "MediaMTX nicht erreichbar nach 30 Versuchen. Abbruch."
        exit 1
    fi
    warn "  Noch nicht bereit, warte... (${RETRIES}/30)"
    sleep 2
done
log "MediaMTX ist bereit."

# ── Xvfb starten ─────────────────────────────────────────────────────────
log "Starte Xvfb (${WIDTH}x${HEIGHT}x16) auf Display :99"
Xvfb :99 -screen 0 "${WIDTH}x${HEIGHT}x16" -nolisten tcp &
XVFB_PID=$!
sleep 2

# ── Wine initialisieren (nur beim ersten Start) ───────────────────────────
if [ ! -d "${WINEPREFIX}/drive_c" ]; then
    log "Initialisiere Wine-Prefix (einmalig, dauert ~30s)..."
    wineboot --init 2>/dev/null
    sleep 5
fi

# ── Johnny Castaway starten ───────────────────────────────────────────────
log "Starte Johnny Castaway via Wine..."
wine "${SCR_FILE}" /s &
WINE_PID=$!
sleep 4

# ── Cleanup bei Signalen ──────────────────────────────────────────────────
cleanup() {
    warn "Shutdown-Signal empfangen, beende Prozesse..."
    kill $WINE_PID $XVFB_PID 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# ── FFmpeg RTSP-Stream ────────────────────────────────────────────────────
log "Starte FFmpeg → ${RTSP_URL}"
log "Einstellungen: ${WIDTH}x${HEIGHT} @ ${FPS}fps, Bitrate: ${BITRATE}"

ffmpeg -loglevel warning \
    -f x11grab \
    -r "${FPS}" \
    -s "${WIDTH}x${HEIGHT}" \
    -i :99.0 \
    -vcodec libx264 \
    -preset ultrafast \
    -tune animation \
    -b:v "${BITRATE}" \
    -maxrate "${BITRATE}" \
    -bufsize "$(( ${BITRATE%k} * 2 ))k" \
    -pix_fmt yuv420p \
    -g $(( FPS * 2 )) \
    -f rtsp \
    -rtsp_transport tcp \
    "${RTSP_URL}"

# Falls FFmpeg unerwartet endet
wait $WINE_PID $XVFB_PID 2>/dev/null
