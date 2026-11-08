#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"

rgba() { rsvg-convert -w "$2" -h "$2" "$here/$1" | magick png:- -strip "PNG32:$3"; }
opaque() { rsvg-convert -w "$2" -h "$2" "$here/$1" | magick png:- -strip -alpha off "PNG24:$3"; }

for file in "$root"/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png; do
  name="${file##*/Icon-App-}"
  points="${name%%x*}"
  scale="${name##*@}"
  opaque g2.svg "$(echo "$points * ${scale%x.png}" | bc | cut -d. -f1)" "$file"
done
opaque g2-watch.svg 1024 "$root/mobile/ios/Bl4uzzWatch/Assets.xcassets/AppIcon.appiconset/Icon.png"

launch="$root/mobile/ios/Runner/Assets.xcassets/LaunchImage.imageset"
rgba g2-mark.svg 168 "$launch/LaunchImage.png"
rgba g2-mark.svg 336 "$launch/LaunchImage@2x.png"
rgba g2-mark.svg 504 "$launch/LaunchImage@3x.png"

icons="$root/desktop/src-tauri/icons"
opaque g2.svg 1024 "$icons/buzz-source.png"
"$root/scripts/macos-icon.sh"
rgba g2.svg 32 "$icons/32x32.png"
rgba g2.svg 64 "$icons/64x64.png"
rgba g2.svg 128 "$icons/128x128.png"
rgba g2.svg 256 "$icons/128x128@2x.png"
rgba g2.svg 512 "$icons/icon.png"
rgba g2.svg 112 "$root/desktop/public/app-icon@2x.png"
rgba g2.svg 168 "$root/desktop/public/app-icon@3x.png"
