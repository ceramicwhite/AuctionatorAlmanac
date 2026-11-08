# Auctionator Almanac — Design

Working name: **Auctionator Almanac** (folder `AuctionatorAlmanac`, slash command `/almanac`). The name is the designer's call; "AHledger" is already taken on CurseForge, so avoid it.

## Intent and why

The owner plays **WoW Forever** (beta, game version 1.60.1, Interface `16001`) and uses **Auctionator** (in this repo at `Auctionator/`). Auctionator only shows its data while standing at the Auction House. Everything it learned on the last scan, such as prices, daily lows and highs, and quantities, is invisible once the owner walks away.

Almanac is a **companion addon that runs alongside Auctionator** and turns that saved data into a window the owner can open anywhere in the world. It looks and behaves like a browsing view of the Auction House, but it never needs the Auction House to be open. It also fills a gap Auctionator leaves: Auctionator records neither what the owner sold or bought, nor what they own and where. Almanac tracks those itself, so a single item page answers "what is it worth, what did I do with it, and do I have any."

Success looks like this. The owner is out farming, opens Almanac, types part of an item name, clicks a match, and sees within a second or two:
- the current lowest price;
- a price-history graph;
- every time they sold or bought it;
- how many they own on which character and in which bag, bank or mail.

They can decide to hold, vendor or sell without logging off to check.

## Goals

1. A WoW-themed window, opened by slash command, keybind and minimap button, that works anywhere in the world.
2. Search with live "potential match" results, like the Auction House search box.
3. An item-category panel that mirrors the Auction House category list.
4. A full item detail view with price history graph, stats, the owner's sale and purchase history, and ownership across all characters.
5. A home view (no search typed) with scan freshness and useful summaries.
6. Own tracking of sales, purchases and inventory, since Auctionator lacks them.
7. The window is **resizable from the bottom-right corner**, and every inner element re-lays-out correctly at any legal size.
8. Reads Auctionator's data without modifying it or changing its behavior.

## Non-goals

- Not a replacement for Auctionator. No scanning, posting, buying or cancelling. Almanac never touches the Auction House except to observe.
- No individual auction listings. Auctionator saves only the lowest price, the daily low and high of that lowest price, and the daily quantity. A "list every auction currently up" view is impossible with the data that exists.
- No switching to realms other than the current one in the first version. Auctionator stores other realms as serialized blobs. This can be added later.
- No networking, no external services, no price sharing between players.
- No bundled item database. Item names come from the game client.

## Anti-goals (a failure even if it technically works)

- Taint or breakage of the Blizzard UI, Auctionator, or other addons. Almanac must never cause an "action blocked" error and must never write into Auctionator's tables.
- Hitches. Opening the window or indexing items with ~15,000 entries must not freeze the game. Work is chunked over frames.
- Wrong numbers presented confidently. Stale or missing data must be visibly labeled (scan age, "seen N days ago", "no data"), never silently zero.
- Losing the owner's tracked history. Saved-data changes are versioned and migrated, never wiped on a schema bump.
- Looking like a debug panel. The standard is "Blizzard would have shipped this."

## Constraints and known facts

**Forever client (researched, partly unverified in-game).**
- It runs the retail-style UI on the 12.1.5 API set with the classic item pool. Several classic-era globals no longer exist. Reported missing in public porting notes (not checked in game): `GetItemInfo`, `GetItemQualityColor`, `GetItemIcon`, `GetDetailedItemLevelInfo`, `GetAddOnMetadata`, `IsAddOnLoaded`, `GetMouseFocus`, `MouseIsOver`, `NUM_ITEM_QUALITIES`, `InterfaceOptionsFrame_OpenToCategory`. Use `C_Item.*`, `C_AddOns.*`, `C_Container.*`, `GetMouseFoci()`, `Region:IsMouseOver()` and `Settings.OpenToCategory`. Where an API's existence on Forever is not certain, **feature-detect and fall back; never assume**.
- The client uses the retail-style addon restrictions of the current retail era, so code that reads tooltip or unit data must be defensive about restricted values.
- The TOC must list `## Interface: 16001`. Optionally list the other interface numbers that Auctionator's TOC lists.
- Some beta builds fail to load SavedVariables at client start. The owner reports Auctionator's data persisting for them, so this is not a blocker. Still, Almanac must treat its own saved data as possibly missing or empty and recover cleanly, without errors.

**Auctionator's saved data (verified by reading this repo).** Almanac depends on Auctionator (`## Dependencies: Auctionator`) and reads the following. Only `Auctionator.API.v1.*` is a promised-stable API, and it exposes only the last price, so Almanac reads the saved tables directly and must isolate that access in one adapter module. If Auctionator changes, only the adapter changes.
- `AUCTIONATOR_PRICE_DATABASE[realm]`, available after `PLAYER_LOGIN` once Auctionator has deserialized it. `realm` is Auctionator's connected-realm root (`Auctionator.State.CurrentRealm`). Each key is an item identifier string. Each value is `{ m = lastSeenMinPrice, l = {day→lowestLow}, h = {day→highestLow}, a = {day→highestQuantity} }`. `day` is a string number of days since `Auctionator.Constants.SCAN_DAY_0` (Jan 1, 2020, local midnight). `l` is only stored when it differs from `h`, so the daily low is `l[day] or h[day]`. `a` may be missing in old data.
- Item key forms: `"12345"` (plain item), `"g:12345:<ilvl>"` (gear at or above an item-level threshold, with a plain-key fallback), `"p:<speciesID>"` (battle pet; likely irrelevant on Forever), `"gr:..."` (legacy suffix gear). Group variants of one item under the base item ID.
- History window is limited to `price_history_days` (default **21**) by Auctionator's pruning.
- `AUCTIONATOR_SAVEDVARS` (`Auctionator.SavedState`): `TimeOfLastBrowseScan` and `TimeOfLastReplicateScan` (full scan), both epoch seconds. Use these for "last scanned".
- `AUCTIONATOR_POSTING_HISTORY[dbKey]`: list of `{price, quantity, bidPrice, time}` for auctions the owner **posted** (capped, default 10 per item). This is posting, not selling.
- `AUCTIONATOR_VENDOR_PRICE_CACHE`, `AUCTIONATOR_SHOPPING_LISTS`, `AUCTIONATOR_RECENT_SEARCHES`. The vendor cache is optional, because `C_Item.GetItemInfo` also returns the vendor sell price.
- `Auctionator.EventBus` and `Auctionator.Selling.Events.AuctionCreated` exist but are internal. Prefer Blizzard events for Almanac's own tracking.

**Item names.** The price database has IDs only. `C_Item.GetItemInfoInstant` returns icon and class/subclass immediately. The name needs a server round trip (`C_Item.RequestLoadItemDataByID` and the item-data-loaded event, or `Item:CreateFromItemID(...):ContinueOnItemLoad`). Almanac keeps a persistent item cache (name, quality, icon, class, subclass, vendor price, required level) filled in the background, so category browsing works at once and name search improves as the cache fills.

**Verification limits.** The Forever client cannot be run from the development environment. Pure-logic modules (data adapter, search, statistics, formatting, tracker logic) must be written so they run under a plain Lua 5.1-compatible interpreter with fixtures. The existing system `lua` is fine for this. UI and live-API behavior are verified by the owner in game, so the build must include an in-game self-check command (`/almanac debug`) that reports which APIs were found and what data was read.

## What the owner decided

- **Layout A, "split pane".** Left: category panel and result list. Right: full item detail. Results stay visible while clicking through items.
- **Resizable** from the bottom-right corner, with all inner elements re-laid-out correctly. If it had proven too complex, it was optional, but it is cheap in WoW and is included.
- Header strip with "last scanned at" and other overall info, "pretty".
- A search bar as the main entry, with potential matches listed like the Auction House does.
- A category panel copied from the Auction House side panel.
- Clicking an item shows: a **historical data graph**, the owner's **sale and purchase history**, and **how many they own and where** (bank, alts, etc.). Almanac tracks buys, sells and holdings itself if Auctionator doesn't.
- Be creative and make it powerful and useful. The owner delegated the extras to the designer.

## The product

### Window

- WoW-themed using Blizzard textures and templates available on Forever (a portrait-less dialog frame, gold-trimmed title bar, standard close button, standard scroll bars). Prefer Blizzard's own atlases and templates over custom art. Where one is missing on Forever, fall back to a plain dark backdrop with a gold border.
- Movable by the title bar, closes on Escape, remembers position, size and last selection. Opens via `/almanac`, a keybind, and a minimap button (no library required; a small custom button that can be hidden in settings).
- **Resizing:** a resize grip in the bottom-right corner. Minimum size is large enough that no element overlaps or clips (about 760x460 as a starting point); maximum is the screen. Layout is anchor-driven. The detail panel has a fixed-ratio width clamped to a sensible range, the results list takes the remaining width, the category panel is a fixed width, the graph and tables scale with the detail panel, and list rows are virtualized so a taller window simply shows more rows. Size is saved when the drag ends, and redraws are throttled during the drag.
- **Status strip** (always visible): last scan age with colour (green under a few hours, amber, then red as it ages), the scan type (full or browse) when known, count of priced items, current realm, history window in days, and a data-health marker if the item cache is still filling.

### Search and categories

- Search box at the top. Typing shows live matches (debounced), matching on name substrings across tokens (all tokens must match, case-insensitive), against the cached names. Items whose name is not yet cached can match by ID if the owner types a number.
- Category panel mirrors the Auction House: top-level classes with expandable subclasses. Use Blizzard's `AuctionCategories` if it can be loaded outside the Auction House (for example by loading `Blizzard_AuctionHouseUI`). Otherwise build the same tree from item class and subclass data (`C_Item.GetItemClassInfo`, `C_Item.GetItemSubClassInfo`). It is the builder's call which. Selecting a category narrows the list. Search and category combine.
- Extra filters in a compact row: quality, owned only, price range, "has recent data", and "changed recently."
- Result list columns: Item (icon, quality-coloured name), Lowest price, 24h or 7d change with arrow and colour, Own (total count), Seen (age of the last price). Sortable by clicking headers. Virtualized for ~15,000 rows.
- Right-click or shift-click on a row can insert an item link into chat, as in other addons. Hovering shows the standard item tooltip.

### Home view (nothing selected)

Shown in the detail panel when no item is selected:
- Scan freshness card.
- **Biggest movers**: largest price rises and drops over the recent window, filtered to items with enough quantity to matter.
- **Below average**: items whose lowest price is well under their recent average.
- **Inventory value**: total value of everything owned across characters at current lowest prices, with the top items by value.
- **Recent activity**: latest sales and purchases.
- **Shopping lists**: Auctionator's shopping lists with each item's current lowest price and its comparison to average (read-only).

### Item detail panel

Header: icon, quality-coloured name, class and subclass, a link-to-chat action, and a watch (star) toggle.

Stats row: lowest now, average over the history window, low and high over the window, quantity last seen, vendor price (and the margin versus vendor), data age.

Three tabs:

1. **Price History.** A graph of the daily lowest price (line), the daily low-to-high band (shaded), and quantity listed (bars). Range selector (7 days, 21 days, all available). Hover shows a crosshair with that day's low, high and quantity. The owner's posts, sales and purchases appear as markers on the graph. Below the graph is a daily table (date, low, high, quantity). Gear variants with item-level keys appear as a selector when present.
2. **My Activity.** A table of the owner's own history for this item, newest first, merged from Almanac's tracker and Auctionator's posting history: posted, sold, bought, expired, cancelled; with date, character, quantity, unit and total price, and fees where known. Summary line: total sold, average sale price, total spent, estimated profit, and sell-through where known.
3. **Where I Own It.** Per character and per location (bags, bank, mail, equipped, active auctions, and guild bank where visited): counts, with the date each snapshot was taken, plus the total and its value at the current lowest price. Data from characters that haven't logged in recently is labeled as of that date.

### Own tracking

Almanac keeps account-wide tracking data, tagged by character and realm.

- **Inventory:** snapshots of bags (on change, debounced), bank (when the bank is open), mail attachments (when the mailbox is opened or mail changes), equipped items, active auctions (when the Auction House shows them), and guild bank tabs when visited. Each character stores its own snapshot with a timestamp. A character whose snapshot is stale is shown as such.
- **Sales:** detected from the Auction House sale mails ("Auction successful") using the invoice information the mail API provides, and recorded when the mail is read or the money taken. Record item, quantity, price, fees and time. Avoid double-counting the same mail across sessions (stable de-duplication key).
- **Purchases:** observed at the Auction House purchase calls and confirmation events, confirmed by "Auction won" invoices where available. Record item, quantity, unit price and time.
- **Postings, expiries and cancellations:** postings come from the Auction House creation events and from Auctionator's posting history on first run. Expired and cancelled auctions come from the returned-item mails and cancel events.
- **Backfill:** on first run, import Auctionator's posting history as "posted" entries. Sales and purchases from before install cannot be recovered and the UI says so rather than showing an empty tab with no explanation.
- **Extended price history:** Auctionator prunes to 21 days. For items the owner cares about (owned, sold, bought, posted, watched, or recently viewed), Almanac snapshots each day's low, high and quantity into its own saved data after each scan or Auction House visit, keeping up to a year. Everything else uses Auctionator's window only. This keeps memory bounded, so cap and prune accordingly.
- **Tooltip lines** on item tooltips: ownership across characters and the lowest price with its age, toggleable in settings. Use the modern tooltip data-processor path and keep it safe under the client's addon restrictions. If it can't be done safely, ship without it and note it.

### Settings

A small panel (reached from the window and the game's addon settings list): minimap button on/off, tooltip lines on/off, history range defaults, how much tracking history to keep, data reset buttons with confirmation, and a debug report.

## Quality bar for the build

- Pure-logic modules are separate from UI and covered by runnable Lua tests with fixtures, using real-shaped Auctionator tables.
- No globals leaked beyond the addon's own namespace and its saved variables.
- Saved variables carry a schema version with migrations.
- Every feature-detected API has a fallback or a clear "unavailable" state, never a Lua error.
- Everything described above ships complete. No placeholder tabs.

## Left to the builder

- File and module structure, naming, and the choice of Blizzard templates and atlases that exist on Forever.
- Category-tree source (Blizzard's table vs generated).
- Exact thresholds (what counts as a "big mover", "below average", freshness colours).
- Graph drawing technique (lines or textures) and its pooling.
- The precise mail, bank and Auction House events and APIs, verified through the in-game probe.
- Minimap button implementation, settings panel mechanics, and the keybind definition.
- How the addon is deployed into the game's AddOns folder (a copy or symlink script is expected).
