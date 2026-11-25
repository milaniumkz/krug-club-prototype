#!/usr/bin/env bash
set -euo pipefail
platform_root="$(cd "$(dirname "$0")/.." && pwd)"
icon_source="$platform_root/branding/logo-circle.png"
icon_background='#02A3DA'
magick "$icon_source" -resize 1024x1024 -background "$icon_background" -alpha remove -alpha off "$platform_root/client/assets/qmetplus_icon.png"
for density_size in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${density_size%:*}"
  dimension="${density_size#*:}"
  icon_folder="$platform_root/client/android/app/src/main/res/mipmap-$density"
  mkdir -p "$icon_folder"
  magick "$icon_source" -resize "${dimension}x${dimension}" "$icon_folder/ic_launcher.png"
  cp "$icon_folder/ic_launcher.png" "$icon_folder/ic_launcher_round.png"
done
# Android's adaptive mask supplies its own outer shape; the cyan background avoids white corners.
magick "$icon_source" -resize 432x432 "$platform_root/client/android/app/src/main/res/drawable/ic_launcher_foreground.png"
cp "$platform_root/client/assets/qmetplus_icon.png" "$platform_root/client/android/app/src/main/res/drawable/ic_qmetplus.png"
python3 "$platform_root/scripts/export_app_icon_sets.py"
