#!/usr/bin/env bash
# Burns a catch copy into a Reel video.
# Intro  : main copy + subtitle (fades in/out near the start)
# Outro  : brand name + reservation CTA (fades in near the end, holds)
#
# Usage: scripts/add_caption.sh [IN_MP4] [OUT_MP4]
set -euo pipefail

IN="${1:-assets/reel_morning.mp4}"
OUT="${2:-assets/reel_morning_titled.mp4}"
FONT="/usr/share/fonts/truetype/fonts-japanese-gothic.ttf"

command -v ffmpeg >/dev/null || { echo "ERROR: ffmpeg not installed" >&2; exit 1; }
[ -f "$IN" ]   || { echo "ERROR: input not found: $IN" >&2; exit 1; }
[ -f "$FONT" ] || { echo "ERROR: font not found: $FONT" >&2; exit 1; }

# Total duration -> drives the outro timing.
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IN")
DUR=$(awk -v d="$DUR" 'BEGIN{printf "%.2f", d}')

# Copy text (edit here to change wording).
I1="目覚めるほどの、"
I2="ひと皿を。"
ISUB="ある日のモーニング"
BRAND="Artisan KANOYA"
CTA="ご予約はプロフィールのリンクから"

# Intro window: in@0.4 fade .5 hold to 3.2 fade out .5
IIN=0.4;  IFI=0.9;  IHO=3.2;  IOUT=3.7
# Outro window: in 0.5 before (DUR-3.6), hold to end
OIN=$(awk -v d="$DUR" 'BEGIN{printf "%.2f", d-3.8}')
OFI=$(awk -v d="$DUR" 'BEGIN{printf "%.2f", d-3.3}')
OEND=$(awk -v d="$DUR" 'BEGIN{printf "%.2f", d-0.15}')

# alpha(t_in, t_fadein_end, t_hold_end, t_out_end)
af () {
  echo "if(lt(t,$1),0,if(lt(t,$2),(t-$1)/($2-$1),if(lt(t,$3),1,if(lt(t,$4),($4-t)/($4-$3),0))))"
}
A_IN=$(af  "$IIN" "$IFI" "$IHO" "$IOUT")
A_OUT=$(af "$OIN" "$OFI" "$OEND" "$DUR")

D () {  # text size y alpha bold(0/1)
  local txt="$1" sz="$2" y="$3" al="$4"
  echo "drawtext=fontfile=${FONT}:text='${txt}':fontcolor=white:fontsize=${sz}:x=(w-text_w)/2:y=${y}:bordercolor=black@0.7:borderw=5:shadowcolor=black@0.55:shadowx=2:shadowy=3:alpha='${al}'"
}

FC=""
FC+="$(D "$I1"    92  "h*0.34" "$A_IN"),"
FC+="$(D "$I2"    92  "h*0.34+118" "$A_IN"),"
FC+="$(D "$ISUB"  46  "h*0.34+260" "$A_IN"),"
FC+="$(D "$BRAND" 86  "h*0.42" "$A_OUT"),"
FC+="$(D "$CTA"   42  "h*0.42+150" "$A_OUT")"

ffmpeg -y -i "$IN" -vf "$FC" \
  -c:v libx264 -profile:v high -pix_fmt yuv420p -r 30 \
  $( ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$IN" | grep -q . && echo "-c:a copy" ) \
  -movflags +faststart "$OUT"

echo "Done -> $OUT"
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height \
  -show_entries format=duration -of default=noprint_wrappers=1 "$OUT"
