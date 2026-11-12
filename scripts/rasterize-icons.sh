#!/usr/bin/env bash
# Renders the icon SVGs in Sonora/Assets.xcassets/Icons to @3x PNGs under Sonora/Resources/Icons,
# because xtool cannot compile asset catalogs. Needs ImageMagick with an SVG delegate.
set -euo pipefail
cd "$(dirname "$0")/.."
out=Sonora/Resources/Icons
rm -rf "$out"
for svg in Sonora/Assets.xcassets/Icons/*/*.imageset/*.svg; do
  pack=$(basename "$(dirname "$(dirname "$svg")")")
  name=$(basename "$svg" .svg)
  mkdir -p "$out/$pack"
  sed 's/currentColor/#000000/g' "$svg" | convert -background none -density 288 svg:- -resize 72x72 "$out/$pack/$name.png"
done
