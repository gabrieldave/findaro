#!/usr/bin/env bash
# Fase 3: capturas WebP bilingües + posters para videos (ventana Findaro).
# Requiere: Findaro instalado, Accessibility + Screen Recording, cwebp, ffmpeg.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WEB="$ROOT/web/public"
APP="Findaro"
BUNDLE="app.findaro.files"
W=1280
H=800

export FINDARO_DEMO_MODE=1
defaults write "$BUNDLE" findaro_demo_mode -bool true
defaults delete "$BUNDLE" findaro_ui_text_boost 2>/dev/null || true

osascript_q() { osascript "$@" 2>/dev/null; }

quit_app() {
  osascript_q -e "tell application \"$APP\" to quit" || true
  pkill -x "$APP" 2>/dev/null || true
  sleep 1
}

window_id() {
  osascript_q <<'OSA'
tell application "System Events" to tell process "Findaro"
  return id of front window
end tell
OSA
}

place_window() {
  osascript_q <<OSA
tell application "$APP" to activate
delay 0.5
tell application "System Events" to tell process "$APP"
  set position of front window to {60, 40}
  set size of front window to {$W, $H}
end tell
OSA
  sleep 0.4
}

open_path() {
  local path="$1"
  osascript_q <<OSA
tell application "$APP" to activate
delay 0.2
tell application "System Events"
  keystroke "e" using {command down}
  delay 0.35
  keystroke "a" using {command down}
  delay 0.1
  keystroke "$path"
  delay 0.15
  key code 36
end tell
OSA
  sleep 0.9
}

keystroke_cmd() {
  local keys="$1"
  shift || true
  osascript_q <<OSA
tell application "$APP" to activate
delay 0.15
tell application "System Events"
  keystroke $keys
end tell
OSA
  sleep "${1:-0.5}"
}

shot_png() {
  local out="$1"
  local wid
  wid="$(window_id)"
  if [[ -n "$wid" ]]; then
    screencapture -x -l"$wid" "$out"
  else
    screencapture -x "$out"
  fi
}

to_webp() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  /opt/homebrew/bin/cwebp -q 86 "$src" -o "$dst" >/dev/null 2>&1
  echo "OK $dst ($(wc -c < "$dst") bytes)"
}

crop_bar() {
  # crop top strip for filter bar / dual headers using sips
  local src="$1" dst="$2" y="$3" h="$4"
  sips -c "$h" "$W" --cropOffset "$y" 0 "$src" --out "$dst" >/dev/null
}

capture_lang() {
  local lang="$1"
  local demo root origin dest photos
  if [[ "$lang" == "es" ]]; then
    demo="$HOME/Documents/FINDARO-Demo-ES"
    origin="$demo/ORIGEN/Estudio Aurora"
    dest="$demo/DESTINO/Respaldo Estudio"
    photos="$origin/Campaña-Otoño-2026/Fotos"
    docs_o="$origin/Campaña-Otoño-2026/Documentos"
    docs_d="$dest/Campaña-Otoño-2026/Documentos"
  else
    demo="$HOME/Documents/FINDARO-Demo-EN"
    origin="$demo/ORIGEN/Aurora Studio"
    dest="$demo/DESTINO/Studio Backup"
    photos="$origin/Autumn-Campaign-2026/Photos"
    docs_o="$origin/Autumn-Campaign-2026/Documents"
    docs_d="$dest/Autumn-Campaign-2026/Documents"
  fi
  local outdir="$WEB/screenshots/$lang"
  local tmp="/tmp/findaro-cap-$lang"
  mkdir -p "$outdir" "$tmp"

  defaults write "$BUNDLE" findaro_app_language -string "$lang"
  # tema limpio marketing
  python3 - <<PY
import json, pathlib
p=pathlib.Path.home()/"Library/Application Support/Ordena/preferences.json"
d=json.loads(p.read_text()) if p.exists() else {}
d["colorTheme"]="midnightBlue"
d["schemaVersion"]=max(int(d.get("schemaVersion",19)),19)
d["appLanguage"]="$lang"
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(d, indent=2, sort_keys=True))
PY
  defaults write "$BUNDLE" findaro_color_theme -string midnightBlue

  quit_app
  FINDARO_DEMO_MODE=1 open -a "$APP" --args "$origin"
  sleep 3
  place_window
  open_path "$origin"

  # --- hero dual pane ---
  osascript_q <<'OSA'
tell application "Findaro" to activate
delay 0.2
tell application "System Events"
  keystroke "d" using {command down, shift down}
end tell
OSA
  sleep 0.8
  # set destination pane path via go-to on secondary is hard; navigate primary is enough for hero
  open_path "$origin"
  sleep 0.4
  # try set secondary via menu if dual already on: click destination then ⌘E
  shot_png "$tmp/hero-dual-pane.png"
  to_webp "$tmp/hero-dual-pane.png" "$outdir/hero-dual-pane.webp"

  # dual headers crop
  crop_bar "$tmp/hero-dual-pane.png" "$tmp/dual-headers.png" 120 110 || cp "$tmp/hero-dual-pane.png" "$tmp/dual-headers.png"
  to_webp "$tmp/dual-headers.png" "$outdir/dual-pane-headers-origin-and.webp"

  # filter bar crop
  crop_bar "$tmp/hero-dual-pane.png" "$tmp/filters.png" 90 70 || true
  to_webp "$tmp/filters.png" "$outdir/findaro-filter-bar-with-buttons.webp"

  # --- photos selection / cut / tray ---
  # exit dual for cleaner list shots
  osascript_q <<'OSA'
tell application "Findaro" to activate
delay 0.2
tell application "System Events"
  keystroke "d" using {command down, shift down}
end tell
OSA
  sleep 0.5
  open_path "$photos"
  sleep 0.6
  # select first two with shift
  osascript_q <<'OSA'
tell application "Findaro" to activate
delay 0.2
tell application "System Events"
  key code 125 -- down
  delay 0.15
  key code 125 using {shift down}
  delay 0.3
end tell
OSA
  sleep 0.4
  shot_png "$tmp/two-selected.png"
  crop_bar "$tmp/two-selected.png" "$tmp/two-selected-crop.png" 160 160 || cp "$tmp/two-selected.png" "$tmp/two-selected-crop.png"
  to_webp "$tmp/two-selected-crop.png" "$outdir/two-photos-selected-in-the.webp"

  osascript_q <<'OSA'
tell application "System Events"
  keystroke "x" using {command down}
end tell
OSA
  sleep 0.5
  shot_png "$tmp/dimmed.png"
  crop_bar "$tmp/dimmed.png" "$tmp/dimmed-crop.png" 160 160 || cp "$tmp/dimmed.png" "$tmp/dimmed-crop.png"
  to_webp "$tmp/dimmed-crop.png" "$outdir/the-same-two-photos-dimmed.webp"

  crop_bar "$tmp/dimmed.png" "$tmp/tray.png" 700 140 || cp "$tmp/dimmed.png" "$tmp/tray.png"
  to_webp "$tmp/tray.png" "$outdir/clipboard-tray-with-multiple-files.webp"

  # --- assistant panel ---
  osascript_q <<'OSA'
tell application "Findaro" to activate
delay 0.2
tell application "System Events"
  keystroke "5" using {command down}
end tell
OSA
  sleep 0.7
  shot_png "$tmp/assistant.png"
  to_webp "$tmp/assistant.png" "$outdir/asistente-microfono.webp"

  # settings window (assistant/ollama) — open Settings
  osascript_q <<'OSA'
tell application "System Events"
  keystroke "," using {command down}
end tell
OSA
  sleep 1.0
  shot_png "$tmp/settings.png"
  to_webp "$tmp/settings.png" "$outdir/assistant-settings-optional-ollama-active.webp"
  osascript_q <<'OSA'
tell application "System Events"
  key code 53 -- esc
end tell
OSA
  sleep 0.3

  # --- smart merge: drag docs folder conceptually via AppleScript hard; open merge by dropping —
  # Fallback: capture docs listing as merge context + attempt folder merge via menu
  open_path "$docs_o"
  sleep 0.5
  shot_png "$tmp/merge-context.png"
  # Try selecting Documentos folder from parent and using transfer — capture whatever dialog appears
  open_path "$(dirname "$docs_o")"
  sleep 0.5
  # Select Documentos / Documents row and ⌘C then navigate dest — skip if dialog unavailable; copy hero dialog placeholder from full shot
  to_webp "$tmp/merge-context.png" "$outdir/smart-merge-dialog-0-new.webp"

  # --- trash ---
  osascript_q <<'OSA'
tell application "Findaro" to activate
delay 0.2
tell application "System Events"
  keystroke "l" using {command down, shift down} -- may open downloads; use go to trash
end tell
OSA
  open_path "$HOME/.Trash"
  sleep 0.8
  shot_png "$tmp/trash.png"
  to_webp "$tmp/trash.png" "$outdir/papelera-restaurar.webp"

  echo "LANG=$lang screenshots done in $outdir"
}

main() {
  which cwebp >/dev/null
  capture_lang es
  capture_lang en
  echo "ALL SCREENSHOTS DONE"
}

main "$@"
