# 📺 Johnny Castaway – RTSP Stream via Docker

Streamt den klassischen Screensaver **Johnny Castaway** (1992, Sierra On-Line)
als RTSP/HLS-Stream aus einem Docker-Container. Läuft 24/7 mit minimalem
Ressourcenverbrauch (~5–10% CPU, ~120 MB RAM).

## Voraussetzungen

- Docker + Docker Compose (v2)
- `johnny.scr` (eigene Kopie erforderlich – urheberrechtlich geschützt)
- `git` auf dem Host (für den Build aus GitHub)

## Setup (3 Schritte)

```bash
# 1. Ordner anlegen
mkdir -p ~/johnny-rtsp/screensaver
cd ~/johnny-rtsp

# 2. johnny.scr hineinkopieren
cp /pfad/zu/deiner/johnny.scr screensaver/

# 3. docker-compose.yml anlegen (Inhalt unten copy-pasten)
nano docker-compose.yml
```

Dann die `docker-compose.yml` aus dem Abschnitt unten einfügen und starten:

```bash
docker compose up -d
```

Beim **ersten Start** wird das Image aus GitHub gebaut (~2–3 min).
Danach ist es gecacht – Neustarts dauern Sekunden.

## Stream-URLs

| Protokoll | URL | Verwendung |
|-----------|-----|-----------|
| RTSP | `rtsp://<HOST-IP>:8554/johnny` | VLC, ffplay, NVR |
| HLS | `http://<HOST-IP>:8888/johnny` | Browser, Kodi |

## Testen

```bash
# VLC
vlc rtsp://<HOST-IP>:8554/johnny

# ffplay
ffplay rtsp://<HOST-IP>:8554/johnny

# Logs ansehen
docker compose logs -f johnny
```

## docker-compose.yml (copy-paste)

```yaml
[... hier den Inhalt von oben einfügen ...]
```

## Umgebungsvariablen

| Variable | Standard | Beschreibung |
|----------|----------|--------------|
| `SCR_FILE` | `/screensaver/johnny.scr` | Pfad zur .scr Datei |
| `WIDTH` | `640` | Auflösung Breite |
| `HEIGHT` | `480` | Auflösung Höhe |
| `FPS` | `10` | Framerate (10 reicht völlig) |
| `BITRATE` | `300k` | Video-Bitrate |
| `RTSP_URL` | `rtsp://mediamtx:8554/johnny` | Ziel-RTSP-URL |

## Image neu bauen (nach Repo-Updates)

```bash
docker compose build --no-cache johnny
docker compose up -d
```

## Rechtlicher Hinweis

Johnny Castaway ist urheberrechtlich geschützt (Sierra On-Line / Dynamix).
Dieses Projekt enthält **keine** Kopie der Software. Du benötigst eine
eigene legitime Kopie der `johnny.scr` Datei.
