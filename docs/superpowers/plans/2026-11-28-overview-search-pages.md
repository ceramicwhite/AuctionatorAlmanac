# Overview / Search pages, market depth columns, watch stars (Almanac 1.5.0)

**Goal:** Give the Watchlist and the overview the room they deserve. The title bar gets a two-button toggle,
Overview | Search. Overview is a full-width page (Watchlist first) and is what the window opens on. Search is the
category list and item table, with the detail panel appearing only when an item is picked. Item rows gain two
market columns, "On AH" (how many are listed) and "At lowest" (how many are listed at the lowest price), and every
item row gets a star left of its icon that adds the item to the Watchlist with one click.

## What the data can and cannot say

- Auctionator saves, per item and day, the lowest price, the highest "lowest price" and `a`, the most listed that
  day. It never saves how many were listed **at** the lowest price.
- Every scan (full scan, browse scan, classic search results) passes its per-auction `{price, available}` lists to
  `Auctionator.Database:ProcessScan`, which then saves each key with `Database:SetPrice(key, lowest, listed)`.
  Almanac hooks both (on `Auctionator.DatabaseMixin`, which every Database object copies, and on a Database that
  already exists). A `SetPrice` for a key of the scan in progress, matching that scan's auctions, records the lowest
  unit price, how many were listed at it, the total and the day; any other `SetPrice` (posting, one-item search)
  forgets the key's count. So a record always belongs to the save that set Auctionator's current price.
  Records are kept per realm (the saved file is account-wide). Auctionator's tables are still never written.
- The controller also requires the record's price to equal the price the loaded data shows, so counts never mix with
  a price from before the last reload.
- "On AH" uses the recorded total; without one it falls back to Auctionator's `a` for the newest day, which is the
  day's peak, so the fallback is shown dimmed.
- New counts update the overview's cached rows in place; only views sorted by the count columns are re-sorted.

## Layout

| Page | Body |
|---|---|
| Overview | overview (full width) \| detail panel only while an item is selected |
| Search | search row on top; categories \| item table \| detail panel only while an item is selected |

- The window opens on Overview every time it is shown; `/almanac search <text>` and the search row open Search.
- Each page remembers its own selected item; switching pages swaps the detail panel to that page's item.
- The divider (drag to resize, button to hide the list side) exists only while the detail panel is open.
- Detail panel's leave button becomes "Close" (it closes the pane; the list behind never left).

## Overview content

- Section order: Watchlist, Biggest movers, Below their average, New finds, Recent activity, Your inventory,
  Shopping lists.
- Columns are width-gated with one rule for compact tables and full lists (`wide` = the pane width at which a
  column appears). On the full page every column shows; a narrow pane keeps the core ones.
- On AH / At lowest on: Watchlist, movers, deals, new finds, inventory, shopping lists, and the Search table.
  Sortable everywhere (unknowns last).

## Watch star

- `W.Star` widget: own textures (`Media/star.tga`, `Media/star-empty.tga`, generated from SVGs in `branding/` by
  `scripts/build-media.sh`), so it does not depend on client art.
- Left of the icon on Search rows, overview rows and full-list rows. Click toggles watching (same chat message
  and saved start price as the Watch button). The star click never selects the row.

## Files

- New `Data/Depth.lua` (record / read / prune / install hook), `branding/star*.svg`, `Media/star*.tga`.
- `Core/Init.lua` (db.depth), `Core/Main.lua` (init, install, prune), `Core/Controller.lua` (`Depth(id)`),
  `Data/Search.lua` (sort keys), `Core/Overview.lua` (order, columns, width gating), `UI/Window.lua` (toggle,
  pages, layout), `UI/Home.lua` (own panel, stars, dynamic cells), `UI/Detail.lua` (Close, stats, `ToggleWatch(id)`),
  `UI/Results.lua` (star, columns), `UI/Widgets.lua` (`W.Star`), `Core/Slash.lua`, `Core/Debug.lua`, TOC 1.5.0,
  README.md and AuctionatorAlmanac/README.md.

## Verification

- `lua tests/run.lua` green, with new tests for: depth recording math, stale-record rejection, pruning, hook
  install on mixin and instance (no double hook), sort keys, page toggle and default page, per-page selection,
  layout at every size in both pages with and without the detail panel, star toggling from each list, width gating.
- `scripts/package.sh` builds the zip (TOC lists only files that exist).
- Independent code review, findings fixed, then push to master.
