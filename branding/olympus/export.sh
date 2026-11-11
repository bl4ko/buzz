#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"

rgba() { rsvg-convert -w "$2" -h "$2" "$here/$1" | magick png:- -strip "PNG32:$3"; }
icon() { if [ "$1" -lt 64 ]; then echo g3-small.svg; else echo g3.svg; fi; }
opaque() { rsvg-convert -w "$2" -h "$2" "$here/$1" | magick png:- -strip -alpha off "PNG24:$3"; }

for file in "$root"/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png; do
  name="${file##*/Icon-App-}"
  points="${name%%x*}"
  scale="${name##*@}"
  px="$(echo "$points * ${scale%x.png}" | bc | cut -d. -f1)"
  opaque "$(icon "$px")" "$px" "$file"
done
opaque g3-watch.svg 1024 "$root/mobile/ios/Bl4uzzWatch/Assets.xcassets/AppIcon.appiconset/Icon.png"

launch="$root/mobile/ios/Runner/Assets.xcassets/LaunchImage.imageset"
for scale in 1 2 3; do
  suffix="@${scale}x"
  sed 's/viewBox="92 31 840 840"/viewBox="-13 -74 1050 1050"/' "$here/g3-mark.svg" |
    rsvg-convert -w $((210 * scale)) -h $((210 * scale)) |
    magick png:- -strip "PNG32:$launch/LaunchImage${suffix/@1x/}.png"
done

icons="$root/desktop/src-tauri/icons"
opaque g3.svg 1024 "$icons/buzz-source.png"
"$root/scripts/macos-icon.sh"
rgba g3-small.svg 32 "$icons/32x32.png"
rgba g3.svg 64 "$icons/64x64.png"
rgba g3.svg 128 "$icons/128x128.png"
rgba g3.svg 256 "$icons/128x128@2x.png"
rgba g3.svg 512 "$icons/icon.png"
rgba g3.svg 112 "$root/desktop/public/app-icon@2x.png"
rgba g3.svg 168 "$root/desktop/public/app-icon@3x.png"
