#!/usr/bin/env bash
# Builds dist/AuctionatorAlmanac-<version>.zip: one top-level AuctionatorAlmanac/ folder,
# ready to unzip into World of Warcraft\<flavor>\Interface\AddOns on any OS.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
toc="$root/AuctionatorAlmanac/AuctionatorAlmanac.toc"
version="$(sed -n 's/^## Version: *//p' "$toc" | tr -d '\r')"
out="$root/dist/AuctionatorAlmanac-$version.zip"

# Every file the TOC loads must exist, or the addon would load half-built.
missing=0
while IFS= read -r f; do
  p="${f//\\//}"   # the TOC uses WoW-style backslashes
  [ -f "$root/AuctionatorAlmanac/$p" ] || { echo "TOC lists a missing file: $f" >&2; missing=1; }
done < <(grep -v '^#' "$toc" | grep -v '^[[:space:]]*$' | tr -d '\r')
[ "$missing" = 0 ] || exit 1

mkdir -p "$root/dist"
rm -f "$out"
(cd "$root" && zip -rqX "$out" AuctionatorAlmanac -x '*.DS_Store' -x '*luac.out')
echo "$out"
unzip -l "$out" | tail -1
