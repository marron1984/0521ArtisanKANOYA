#!/usr/bin/env bash
# Burns a catch copy into a Reel video.
# Intro  : main copy + subtitle (fades in/out near the start)
# Outro  : brand name + reservation CTA (fades in near the end, holds)
#
# Usage: scripts/add_caption.sh [IN_MP4] [OUT_MP4]
set -euo pipefail

IN="${1:-assets/reel_morning.mp4}"
OUT="${2:-assets/reel_morning_titled.mp4}"
BGM="${3:-assets/Concrete_Garden.mp3}"  # optional background music
# Elegant Mincho (serif) for a premium artisan feel. fontconfig family name.
FONT_MAIN="Noto Serif CJK JP"
FONT_SUB="Noto Serif CJK JP"

command -v ffmpeg >/dev/null || { echo "ERROR: ffmpeg not installed" >&2; exit 1; }
[ -f "$IN" ]   || { echo "ERROR: input not found: $IN" >&2; exit 1; }
fc-match "Noto Serif CJK JP" 2>/dev/null | grep -qi noto || \
  { echo "ERROR: 'Noto Serif CJK JP' not installed (apt-get install fonts-noto-cjk)" >&2; exit 1; }

# Total duration -> drives the outro timing.
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IN")
DUR=$(awk -v d="$DUR" 'BEGIN{printf "%.2f", d}')

# Copy text (edit here to change wording).
I1="朝を特別にする、"
I2="ひと皿を。"
ISUB="ある日のモーニング"
BRAND="L’Artisan Kanoya"
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

D () {  # font text size y alpha letterspacing
  local fnt="$1" txt="$2" sz="$3" y="$4" al="$5" ls="${6:-0}"
  echo "drawtext=font='${fnt}':text='${txt}':fontcolor=white:fontsize=${sz}:x=(w-text_w)/2:y=${y}:expansion=none:bordercolor=black@0.55:borderw=4:shadowcolor=black@0.5:shadowx=2:shadowy=2:alpha='${al}'"
}

FC=""
FC+="$(D "$FONT_MAIN" "$I1"    90  "h*0.33" "$A_IN"),"
FC+="$(D "$FONT_MAIN" "$I2"    90  "h*0.33+128" "$A_IN"),"
FC+="$(D "$FONT_SUB"  "$ISUB"  44  "h*0.33+280" "$A_IN"),"
FC+="$(D "$FONT_MAIN" "$BRAND" 80  "h*0.42" "$A_OUT"),"
FC+="$(D "$FONT_SUB"  "$CTA"   40  "h*0.42+150" "$A_OUT")"

if [ -n "$BGM" ] && [ -f "$BGM" ]; then
  # Trim BGM to the video length with a gentle fade in/out, slightly
  # lowered volume, and stop the output at the shortest stream.
  AFO=$(awk -v d="$DUR" 'BEGIN{printf "%.2f", d-2.0}')
  ffmpeg -y -i "$IN" -i "$BGM" -vf "$FC" \
    -af "volume=0.8,afade=t=in:st=0:d=1.5,afade=t=out:st=${AFO}:d=2.0" \
    -map 0:v:0 -map 1:a:0 -shortest \
    -c:v libx264 -profile:v high -pix_fmt yuv420p -r 30 \
    -c:a aac -b:a 192k \
    -movflags +faststart "$OUT"
else
  ffmpeg -y -i "$IN" -vf "$FC" \
    -c:v libx264 -profile:v high -pix_fmt yuv420p -r 30 \
    $( ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$IN" | grep -q . && echo "-c:a copy" ) \
    -movflags +faststart "$OUT"
fi

echo "Done -> $OUT"
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height \
  -show_entries format=duration -of default=noprint_wrappers=1 "$OUT"
