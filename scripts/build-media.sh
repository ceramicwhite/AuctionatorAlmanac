#!/usr/bin/env bash
# Regenerates the addon's textures (AuctionatorAlmanac/Media/*.tga) from the SVGs in branding/.
# The game cannot load SVG or PNG reliably, so these are uncompressed 32-bit TGAs with a
# bottom-left origin, a power-of-two size and straight (non-premultiplied) alpha.
# Needs: rsvg-convert, ImageMagick (magick), python3.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/AuctionatorAlmanac/Media"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

# tga <svg> <size> <name>
tga() {
  rsvg-convert -w "$2" -h "$2" "$1" -o "$work/$3.png"
  magick "$work/$3.png" -depth 8 "rgba:$work/$3.rgba"
  python3 -I - "$2" "$work/$3.rgba" "$out/$3.tga" <<'PY'
import struct, sys
size, source, target = int(sys.argv[1]), sys.argv[2], sys.argv[3]
data = open(source, "rb").read()
assert len(data) == size * size * 4, "unexpected pixel data"
rows = [data[i * size * 4:(i + 1) * size * 4] for i in range(size)][::-1]       # bottom row first
pixels = b"".join(bytes(v for i in range(0, len(r), 4) for v in (r[i + 2], r[i + 1], r[i], r[i + 3])) for r in rows)
# id length, no colour map, uncompressed true-colour, colour map spec, origin, size, 32 bpp, 8 alpha bits
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8)
open(target, "wb").write(header + pixels)
PY
  echo "wrote $out/$3.tga (${2}x${2})"
}

tga "$root/branding/minimap-icon.svg" 128 minimap
tga "$root/branding/almanac-logo.svg" 128 logo
