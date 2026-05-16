#!/usr/bin/env bash
# Instagram Reel generator for ArtisanKANOYA
# Builds a vertical 1080x1920 / 30fps H.264 mp4 slideshow from images in assets/.
# Each image gets a slow Ken Burns zoom; clips are joined with crossfades.
#
# Usage:
#   scripts/make_reel.sh [SRC_DIR] [OUT_FILE] [SECONDS_PER_IMAGE]
# Defaults:
#   SRC_DIR=assets  OUT_FILE=assets/reel_morning.mp4  SECONDS_PER_IMAGE=2.5
#
# Add a track named assets/audio.* (mp3/m4a/aac/wav) to include background audio.

set -euo pipefail

SRC_DIR="${1:-assets}"
OUT_FILE="${2:-assets/reel_morning.mp4}"
PER="${3:-2.5}"

W=1080
H=1920
FPS=30
XF=1.2   # crossfade duration (seconds)

command -v ffmpeg >/dev/null || { echo "ERROR: ffmpeg not installed" >&2; exit 1; }

# Collect images (case-insensitive), sorted by name.
mapfile -t IMAGES < <(find "$SRC_DIR" -maxdepth 1 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
  | sort)

N=${#IMAGES[@]}
if [ "$N" -eq 0 ]; then
  echo "ERROR: no images found in '$SRC_DIR' (jpg/jpeg/png/webp)." >&2
  echo "Add your photos to '$SRC_DIR/' and re-run." >&2
  exit 1
fi
echo "Found $N image(s):"
printf '  %s\n' "${IMAGES[@]}"

FRAMES=$(awk -v p="$PER" -v f="$FPS" 'BEGIN{printf "%d", p*f}')

# Build inputs and per-image filter chains.
INPUTS=()
FILTERS=""
# Oversized working canvas leaves room for a handheld-style sway.
OW=$(( W * 8 / 5 ))   # 1.6x
OH=$(( H * 8 / 5 ))
for i in "${!IMAGES[@]}"; do
  INPUTS+=(-loop 1 -i "${IMAGES[$i]}")
  # Per-image phase so some photos sit wide (引き) while others are tight (寄り).
  P=$(awk -v i="$i" 'BEGIN{printf "%.3f", i*1.7}')
  # Scale to cover the oversized canvas, then zoompan breathes the zoom
  # between 1.0 (whole image = 引き) and 1.6 (tight = 寄り) plus a slow
  # sway, all evaluated per output frame via 'on'.
  Z="1.10+0.10*sin(2*PI*on/(18*${FPS})+${P})"
  XR="(iw-iw/zoom)/2"
  YR="(ih-ih/zoom)/2"
  FILTERS+="[${i}:v]trim=end_frame=1,scale=${OW}:${OH}:force_original_aspect_ratio=increase,crop=${OW}:${OH},setsar=1,"
  FILTERS+="zoompan=z='${Z}':d=${FRAMES}:s=${W}x${H}"
  FILTERS+=":x='${XR}+${XR}*0.45*sin(2*PI*on/(22*${FPS})+${P})'"
  FILTERS+=":y='${YR}+${YR}*0.45*sin(2*PI*on/(26*${FPS})+${P}+1.1)',"
  FILTERS+="fps=${FPS},format=yuv420p[v${i}];"
done

# Chain crossfades between consecutive clips.
if [ "$N" -eq 1 ]; then
  MAP_LABEL="[v0]"
else
  PREV="[v0]"
  ACC="$PER"
  for ((i=1;i<N;i++)); do
    OFF=$(awk -v a="$ACC" -v x="$XF" 'BEGIN{printf "%.3f", a-x}')
    OUT="[x${i}]"
    FILTERS+="${PREV}[v${i}]xfade=transition=fade:duration=${XF}:offset=${OFF}${OUT};"
    PREV="$OUT"
    ACC=$(awk -v a="$ACC" -v p="$PER" -v x="$XF" 'BEGIN{printf "%.3f", a+p-x}')
  done
  MAP_LABEL="$PREV"
fi
FILTERS="${FILTERS%;}"

# Optional background audio.
AUDIO=$(find "$SRC_DIR" -maxdepth 1 -type f \
  \( -iname 'audio.*' \) | head -n1 || true)

if [ -n "$AUDIO" ]; then
  echo "Using audio: $AUDIO"
  ffmpeg -y "${INPUTS[@]}" -i "$AUDIO" \
    -filter_complex "$FILTERS" \
    -map "$MAP_LABEL" -map "${N}:a" \
    -c:v libx264 -profile:v high -pix_fmt yuv420p -r "$FPS" \
    -c:a aac -b:a 128k -shortest -movflags +faststart "$OUT_FILE"
else
  ffmpeg -y "${INPUTS[@]}" \
    -filter_complex "$FILTERS" \
    -map "$MAP_LABEL" \
    -c:v libx264 -profile:v high -pix_fmt yuv420p -r "$FPS" \
    -movflags +faststart "$OUT_FILE"
fi

echo "Done -> $OUT_FILE"
ffprobe -v error -show_entries format=duration:stream=width,height \
  -of default=noprint_wrappers=1 "$OUT_FILE" 2>/dev/null || true
