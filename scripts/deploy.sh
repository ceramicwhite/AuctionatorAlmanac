#!/usr/bin/env bash
# Install Auctionator Almanac into a WoW AddOns folder.
#
#   scripts/deploy.sh [--copy] [--force] [ADDONS_DIR]
#
# Default ADDONS_DIR is the WoW Forever beta client. By default the addon is
# symlinked, so edits in this repo show up after /reload. --copy copies the files
# instead. An existing real folder or a link to somewhere else is only replaced
# with --force.
set -euo pipefail

mode=link
force=0
target="/Applications/World of Warcraft/_classic_beta_/Interface/AddOns"
positional=0
for arg in "$@"; do
  case "$arg" in
    --copy) mode=copy ;;
    --force) force=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) target="$arg"; positional=1 ;;
  esac
done

src="$(cd "$(dirname "$0")/.." && pwd)/AuctionatorAlmanac"
dest="$target/AuctionatorAlmanac"

[ -d "$src" ] || { echo "cannot find $src" >&2; exit 1; }
[ -d "$target" ] || { echo "AddOns folder not found: $target" >&2; exit 1; }
[ -d "$target/Auctionator" ] || echo "warning: $target/Auctionator is missing; Almanac needs Auctionator installed there" >&2

if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ] && [ "$mode" = link ]; then
  echo "already linked: $dest -> $src"
  exit 0
fi

if [ -e "$dest" ] || [ -L "$dest" ]; then
  if [ "$force" -ne 1 ]; then
    echo "$dest already exists; use --force to replace it" >&2
    exit 1
  fi
  rm -rf "$dest"
fi

if [ "$mode" = link ]; then
  ln -s "$src" "$dest"
  echo "linked $dest -> $src"
else
  cp -R "$src" "$dest"
  echo "copied $src -> $dest"
fi
