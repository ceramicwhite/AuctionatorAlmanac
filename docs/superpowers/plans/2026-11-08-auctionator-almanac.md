# Auctionator Almanac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A companion addon for WoW Forever that opens a WoW-themed window anywhere in the world to search and browse Auctionator's saved price data, with price graphs, the owner's own sale/purchase history and cross-character inventory.

**Architecture:** Pure-Lua logic modules (adapter, stats, items, search, categories, ledger, inventory, history) take their WoW environment from `A.env` so they run under plain `lua` with fixtures. Thin event glue and a widget-based UI sit on top. UI is anchor-driven and virtualized so the window resizes from its bottom-right corner.

**Tech Stack:** Lua 5.1 semantics (WoW), no libraries. System `lua`/`luac` (5.4) for tests and syntax checks, so the code avoids `goto`, `//`, bit operators and anything 5.1 lacks.

**Spec:** `docs/superpowers/specs/2026-11-08-auctionator-almanac-design.md`

## Global Constraints

- Addon folder `AuctionatorAlmanac/`, TOC `## Interface: 16001, 120100, 120105`, `## Dependencies: Auctionator`, `## SavedVariables: ALMANAC_DB`, slash `/almanac`.
- Forever uses the 12.1.5 API set: use `C_Item.*`, `C_AddOns.*`, `C_Container.*`; feature-detect everything else and never assume an API exists. `RegisterEvent` is always wrapped in `pcall`.
- Never write into Auctionator's tables. All access to Auctionator saved data goes through `Data/Adapter.lua`.
- No global leaks beyond `ALMANAC_DB`, `SLASH_ALMANAC1`, `BINDING_*` strings and the one Bindings function `AuctionatorAlmanac_Toggle`.
- Saved variables carry `version`; migrations never wipe tracked history.
- Stale or missing data is always labeled, never shown as zero.
- All files start `local ADDON, A = ...`. Tests load files with `loadfile(path)(ADDON, A)`.
- Window minimum size 760x460, saved size/position, resize grip bottom-right.

## Review Focus

- Auctionator not ready, price DB empty (`no_price_database` on) or realm table missing → window shows a clear empty state, no Lua error.
- Item names not cached yet → rows show `Item 12345` placeholder and update when loaded; search by numeric ID still works.
- Mail invoices missing/nil, the same mail scanned repeatedly, or two identical sales in one day → no duplicates, no lost sales.
- `ALMANAC_DB` missing, from an older version, or hand-corrupted → repaired in place without discarding the ledger.
- Pet keys (`p:`), gear keys (`g:id:ilvl`, `gr:`), unparseable keys → grouped or skipped, never crash the index.
- Window at minimum and at huge sizes; zero results; one result; 15,000 results.

---

### Task 1: Scaffold, saved variables, event bus, test harness

**Files:**
- Create: `AuctionatorAlmanac/AuctionatorAlmanac.toc`, `AuctionatorAlmanac/Core/Init.lua`, `tests/run.lua`, `tests/harness.lua`, `tests/test_init.lua`

**Interfaces:**
- Produces: `A.env` (defaults to `_G`), `A.Bus.On(name, fn)`, `A.Bus.Fire(name, ...)`, `A.DB_VERSION = 1`, `A.NewDB() -> table`, `A.InitDB(saved: table|nil) -> table` (repairs/migrates, never drops `ledger`), `A.db`, `A.Settings` accessors `A.Get(key)`, `A.Set(key, value)`, `A.Print(msg)`, `A.RegisterEvent(event, fn) -> boolean`.
- Harness: `harness.new() -> A`, `harness.load(A, paths)`, `T.eq(a, b, msg)`, `T.truthy`, `T.run()`.

- [ ] Write `tests/test_init.lua`: `InitDB(nil)` returns defaults with `version == 1`, empty `ledger.entries`, `settings.tooltips == true`; `InitDB({version=0, ledger={entries={{id=1}}}})` keeps the entry; `InitDB("garbage")` returns defaults; Bus delivers args to every listener and survives an erroring listener.
- [ ] Run `lua tests/run.lua` → FAIL (module missing).
- [ ] Implement `Core/Init.lua` per the interface; `Bus.Fire` uses `pcall` per listener.
- [ ] Run → PASS. Commit.

### Task 2: Formatting

**Files:** Create `Core/Format.lua`, `tests/test_format.lua`.

**Interfaces:** `A.Format.Money(copper, opts) -> string` (`opts.plain`, `opts.short`; nil → `"—"`; 0 → `0c`), `Ago(seconds) -> "2h 14m"`, `Freshness(seconds) -> "fresh"|"ok"|"stale"|"old"` (< 6h, < 24h, < 72h, else), `Percent(ratio) -> "+8%"`, `Date(t)`, `Count(n)` (thousand separators), `QualityColor(q) -> r,g,b,hex`, `ColorName(name, q)`.

- [ ] Tests: `Money(11240, {plain=true}) == "1g 12s 40c"`, `Money(5, {plain=true}) == "5c"`, `Money(1234567, {plain=true, short=true}) == "123g 45s"`, `Money(nil) == "—"`, `Ago(8040) == "2h 14m"`, `Ago(45) == "45s"`, `Freshness(3600) == "fresh"`, `Percent(0.083) == "+8%"`, `Percent(-0.031) == "-3%"`, `Count(14203) == "14,203"`, quality 1 is white `ffffff`, 2 is green `1eff00`, 3 is blue `0070dd`, 4 is purple `a335ee`, unknown quality falls back to white.
- [ ] Implement, run, commit.

### Task 3: Auctionator adapter

**Files:** Create `Data/Adapter.lua`, `tests/fixtures.lua`, `tests/test_adapter.lua`.

**Interfaces:**
- `Adapter.IsReady() -> boolean` (true when `Auctionator.State.Loaded` and `Auctionator.Database.db` is a table)
- `Adapter.RealmData() -> table|nil` (prefers `Auctionator.Database.db`, falls back to `AUCTIONATOR_PRICE_DATABASE[State.CurrentRealm]`)
- `Adapter.ParseKey(key) -> itemID:number|nil, variant:string|nil` (`"123"`→123; `"g:123:200"`→123,"g:200"; `"gr:123:of Bear"`→123,"gr:of Bear"; `"p:9"`→nil; garbage→nil)
- `Adapter.BuildIndex() -> {items = {[id] = {keys = {...}, base = "123"|nil}}, count = n}`
- `Adapter.GetSeries(key) -> {key, last, days = {{day, low, high, qty}...ascending}}|nil`
- `Adapter.DayToTime(day) -> epoch`, `Adapter.TimeToDay(t) -> number`, `Adapter.Today()`
- `Adapter.LastScan() -> {time, kind = "full"|"browse"|"data"|nil, browse, full}`
- `Adapter.PostingHistory(itemID) -> {{time, price, quantity, bidPrice}...}`
- `Adapter.ShoppingLists() -> {{name, items = {string}}...}`
- `Adapter.HistoryDays() -> number` (config `price_history_days`, default 21)

- [ ] Fixtures: a realm table with plain, `g:`, `gr:`, `p:`, garbage keys; entries with and without `l`/`a`; string day keys.
- [ ] Tests: ParseKey cases above; `GetSeries` returns ascending numeric days, `low = l[day] or h[day]`, `qty = nil` when `a` missing; index groups variants under the base ID and skips pet/garbage keys; `LastScan` takes the max of browse/replicate/getall timestamps and falls back to kind `"data"`; `IsReady` false when Auctionator absent, and `RealmData` nil → index empty not error; ShoppingLists tolerates nil.
- [ ] Implement, run, commit.

### Task 4: Statistics

**Files:** Create `Data/Stats.lua`, `tests/test_stats.lua`.

**Interfaces:**
- `Stats.Summarize(series, todayDay) -> {last, low, high, avg, nDays, qty, lastDay, ageDays, change1d, change7d}|nil`
  - `last` = series.last or the latest day's low; `avg` = mean of daily lows; `change1d` = last day low vs previous recorded day low; `change7d` = `last` vs the mean of daily lows of recorded days in the 7 days before the latest day (nil if < 2 such days).
- `Stats.Merge(ext, live) -> series` (union by day, live wins; `last` from live)
- `Stats.Movers(list, {minQty=5, minPrice=500, limit=10}) -> up[], down[]`, `Stats.BelowAverage(list, {threshold=0.8, minDays=5, minQty=3, limit=10}) -> list[]` where `list` = `{{id, s = summary}}`
- `Stats.InventoryValue(counts, priceOf, vendorOf) -> {value, priced, unpriced = {ids}, vendorValue}`

- [ ] Tests with exact numbers: lows `{100,110,90}` → avg 100; change1d `90/110-1`; one-day series gives nil changes and `nDays == 1`; empty series → nil; `Merge` prefers live on overlap; Movers ignores low-qty/low-price items; `InventoryValue` counts unpriced items separately and sums vendor value for them.
- [ ] Implement, run, commit.

### Task 5: Item cache

**Files:** Create `Data/Items.lua`, `tests/test_items.lua`.

**Interfaces:**
- `Items.Init(db)`, `Items.Get(id) -> {id, name, lname, quality, icon, class, sub, invType, sell, minLevel, ilvl}|nil`, `Items.Name(id) -> string` (`"Item <id>"` placeholder), `Items.Ensure(id) -> info` (stores instant info via `C_Item.GetItemInfoInstant`, queues name load), `Items.EnsureAll(ids, onProgress)` (chunked), `Items.Progress() -> have, total`, `Items.OnLoaded(id)` (event handler), `Items.NameIndex() -> {[id] = lname}`, `Items.EquipToInventoryType(equipLoc) -> number|nil`.
- Persistent layout `db.items[id] = {name, quality, icon, class, sub, invType, sell, minLevel, ilvl}` (array form).

- [ ] Tests with fake `C_Item`: instant info stored immediately with `name == nil`; after `OnLoaded` the name, quality, sell price and `lname` appear; `Name()` placeholder before; queue is throttled (at most 20 `RequestLoadItemDataByID` per tick) and not re-queued while pending; items already named are never re-requested; `EquipToInventoryType("INVTYPE_HEAD") == 1`, `"INVTYPE_CLOAK" == 16`, nil/unknown → nil.
- [ ] Implement with `A.env.C_Timer.After` for the throttle; run; commit.

### Task 6: Search and categories

**Files:** Create `Data/Search.lua`, `Data/Categories.lua`, `tests/test_search.lua`.

**Interfaces:**
- `Search.Tokenize(text) -> {string}` (lowercased, split on spaces, quotes keep phrase)
- `Search.Run(ids, params, ctx) -> ids[]`; `params = {text, category (node), quality, ownedOnly, minPrice, maxPrice, recent (days)}`; `ctx = {info(id), summary(id), owned(id), nameIndex}`. Numeric text matches that item ID.
- `Search.Sort(ids, key, ascending, ctx)` keys: `"name"|"price"|"change"|"owned"|"age"`; nil values always sort last; stable by name.
- `Categories.Build(env) -> {{name, filters = {{classID, subClassID, inventoryType}}, children}}` (uses `env.AuctionCategories` if present, else generated from `C_Item.GetItemClassInfo`/`GetItemSubClassInfo` in classic AH order), `Categories.Matches(node, info) -> boolean`.

- [ ] Tests: multi-token AND; case-insensitive; phrase; ID match; category + text combine; ownedOnly/price/quality filters; unnamed items match only by ID or category; nil-last sorting; category match by class, class+sub, inventoryType; generated tree order Weapon, Armor, Container, Consumable, Trade Goods, Projectile, Quiver, Recipe, Gem, Miscellaneous, Quest.
- [ ] Implement, run, commit.

### Task 7: Ledger (sales, purchases, postings)

**Files:** Create `Tracker/Ledger.lua`, `tests/test_ledger.lua`.

**Interfaces:**
- Entry: `{id, kind = "sold"|"bought"|"posted"|"expired"|"cancelled", itemID, qty, total, unit, fee, deposit, time, char, realm, party, source = "mail"|"ah"|"auctionator", confirmed}`
- `Ledger.Init(db)`, `Ledger.Add(entry) -> entry|nil` (nil on duplicate), `Ledger.ForItem(itemID) -> entries newest-first`, `Ledger.Recent(n)`, `Ledger.Summary(entries) -> {sold = {n, qty, gross, fees, avg}, bought = {n, qty, spent, avg}, net}`, `Ledger.Prune(keepDays, now)`
- `Ledger.ClassifySubject(subject) -> kind|nil, itemName|nil` (uses `AUCTION_SOLD_MAIL_SUBJECT`, `AUCTION_WON_MAIL_SUBJECT`, `AUCTION_EXPIRED_MAIL_SUBJECT`, `AUCTION_REMOVED_MAIL_SUBJECT` from `A.env` or the English defaults)
- `Ledger.FromMail(m) -> entry|nil`, `m = {subject, invoice = {type, itemName, party, bid, buyout, deposit, consignment, count}|nil, attachments = {{itemID, count}}, daysLeft, now, char, realm, resolveName(name)->itemID}`
- `Ledger.ImportPosting(adapter, char, realm) -> added`

- [ ] Tests: subject classification for sold/won/expired/cancelled/outbid(nil)/garbage; a `seller` invoice produces `kind="sold"`, `total = buyout` (or bid when buyout is 0), `fee = consignment`, `time = now - (30 - daysLeft) * 86400`; the same mail scanned twice 40s apart (daysLeft decayed accordingly) is deduped; two real identical sales 2 hours apart are both kept; `buyer` invoice with an attachment gives itemID and count from the attachment; `seller_temp_invoice` yields nil; expired/cancelled use the attachment; an AH-observed purchase is confirmed (not duplicated) by a later matching `buyer` invoice; `ImportPosting` is idempotent; `Prune` drops only old entries; `Summary` totals match.
- [ ] Implement, run, commit.

### Task 8: Inventory snapshots

**Files:** Create `Tracker/Inventory.lua`, `tests/test_inventory.lua`.

**Interfaces:**
- `Inventory.Init(db)`, `Inventory.CharKey(name, realm) -> "Name-Realm"`, `Inventory.EnsureChar(info) -> charRecord` (`info = {name, realm, class, faction}`), `Inventory.SetLocation(charKey, loc, counts, now)` with `loc` in `bags|bank|mail|equipped|auctions|reagents`, `Inventory.SetGuildTab(guildKey, guildName, tab, counts, now)`, `Inventory.SetWarband(counts, now)`
- `Inventory.Owned(itemID) -> {total, rows = {{charKey, name, realm, loc, count, stamp, guild}}}` sorted by character then location
- `Inventory.Totals() -> {[itemID] = n}` (memoized, invalidated on any Set*)
- `Inventory.ClassifyBag(bagID, ctx) -> "bags"|"bank"|"warband"|nil`
- Collectors (take `env`): `ScanBags`, `ScanBank`, `ScanEquipped`, `ScanMail`, `ScanOwnedAuctions`, `ScanGuildBank(tab)`, each `-> counts{[itemID]=n}|nil`

- [ ] Tests: counts sum across stacks; `Owned` rows for two characters and several locations; totals memoization invalidates; bag classification with a retail-like `Enum.BagIndex` (backpack 0–4, reagent 5, character bank tabs, account bank tabs) and with a classic-like layout (bank −1, 5–11); collectors against a fake `C_Container`; missing APIs return nil not error.
- [ ] Implement, run, commit.

### Task 9: Extended history

**Files:** Create `Tracker/History.lua`, `tests/test_history.lua`.

**Interfaces:** `History.Init(db)`, `History.TrackedIDs(ctx) -> set` (ledger items, owned items, watchlist, last 200 viewed), `History.Snapshot(adapter, tracked, today, keepDays) -> n`, `History.Series(itemID) -> series|nil` (same shape as `Adapter.GetSeries`), `History.MarkViewed(itemID)`, `History.Watch(itemID, bool)`, `History.IsWatched(itemID)`.

- [ ] Tests: snapshot copies days and is idempotent; days older than `keepDays` are pruned; untracked items are not stored; viewed list capped at 200 and oldest evicted; `Series` merges correctly with `Stats.Merge`.
- [ ] Implement, run, commit.

### Task 10: Tracker event glue

**Files:** Create `Tracker/Events.lua`, `tests/test_events.lua`.

**Interfaces:** `A.Tracker.Start()` registers (each via `A.RegisterEvent`, failures ignored): `BAG_UPDATE_DELAYED`, `PLAYER_EQUIPMENT_CHANGED`, `BANKFRAME_OPENED/CLOSED`, `MAIL_SHOW`, `MAIL_INBOX_UPDATE`, `MAIL_CLOSED`, `AUCTION_HOUSE_SHOW/CLOSED`, `OWNED_AUCTIONS_UPDATED`, `COMMODITY_PURCHASE_SUCCEEDED/FAILED`, `GUILDBANKBAGSLOTS_CHANGED`, `PLAYER_LOGOUT`. Hooks via `hooksecurefunc` guarded by `pcall`: `C_AuctionHouse.StartCommoditiesPurchase`, `C_AuctionHouse.PlaceBid`. `Tracker.ScanMailbox()`, `Tracker.OnCommodityStart/Succeeded/Failed`, `Tracker.RefreshBags()` (debounced 0.5s). Fires `LEDGER_UPDATED` and `INVENTORY_UPDATED` on the Bus.

- [ ] Tests with a fake env: opening the mailbox with a sold invoice adds exactly one `sold` entry and a second `MAIL_INBOX_UPDATE` adds none; a commodity start + success records one `bought` (`source="ah"`), failure records none; bank open records `bank` only when `BANKFRAME_OPENED` fired; missing `C_Mail` APIs cause no error.
- [ ] Implement, run, commit.

### Task 11: UI foundation and window

**Files:** Create `UI/Theme.lua`, `UI/Widgets.lua`, `UI/VirtualList.lua`, `UI/Table.lua`, `UI/Window.lua`, `tests/ui_stub.lua`, `tests/test_ui_smoke.lua`.

**Interfaces:**
- `UI.Theme` colors and fonts; `UI.Widgets.Button(parent, text, onClick)`, `.Checkbox(parent, text, get, set)`, `.EditBox(parent, placeholder, onChange)`, `.Tabs(parent, defs, onSelect) -> {Select(i)}`, `.Scrollbar(parent) -> obj`, `.Panel(parent, name) -> frame` (dark fill with gold border)
- `UI.VirtualList.New(parent, {rowHeight, createRow(parent) -> row, update(row, item, index, selected)}) -> list` with `list:SetData(array)`, `list:SetSelected(index)`, `list:ScrollTo(index)`, `list:Refresh()`, auto-grows row pool on `OnSizeChanged`
- `UI.Table.New(parent, {columns = {{key, title, width|flex, align, render(row, item)}}, sortable, onSort, onSelect, rowHeight}) -> table` with `:SetData`, `:SetSort(key, asc)`, `:Layout()`
- `UI.Window.Get() -> frame` (creates once), `.Toggle()`, `.Show()`, with `frame.left`, `frame.center`, `frame.detail`, `frame.status` regions; resize grip, `SetResizeBounds` (fallback `SetMinResize`), saved geometry, Esc to close via `UISpecialFrames`.
- `tests/ui_stub.lua`: a permissive proxy `CreateFrame`/`UIParent`/fonts so every UI file loads and the windows open without errors.

- [ ] Smoke test: with the stub env, load UI files, `Window.Show()`, fire `OnSizeChanged` at 760x460 and 1800x1200, `VirtualList:SetData` with 0, 1 and 15,000 items, and `Table:SetSort`; assert no Lua error and row pool ≤ visible rows + 2.
- [ ] Implement widgets then window; run; commit.

### Task 12: Browse UI (status, search, categories, results)

**Files:** Create `UI/Status.lua`, `UI/CategoryPanel.lua`, `UI/Results.lua`, `Core/Controller.lua`; extend `tests/test_ui_smoke.lua`.

**Interfaces:**
- `Controller` owns state `{text, category, filters, sortKey, asc, selected}`; `Controller.Refresh()` runs `Search.Run` + `Sort` over the Adapter index and feeds `Results`; `Controller.Select(itemID)`; `Controller.Data()` returns memoized `summaries` (computed in chunks of 500, firing `DATA_UPDATED`); listens to the Bus.
- `UI.Status.Update()` shows scan age (colored), kind, priced count, realm, history days, name-cache progress.
- `UI.CategoryPanel` shows the tree with expand/collapse; selecting sets `Controller.category`.
- `UI.Results`: columns Item (icon + colored name), Lowest, Change, Own, Seen; header sort; right-click and shift-click link to chat; tooltip on hover (`GameTooltip:SetItemByID`).

- [ ] Smoke test additions: empty state when `Adapter.IsReady()` is false; typing in the search box with 3 fixture items filters; clicking a category narrows; sort toggle reverses.
- [ ] Implement; run; commit.

### Task 13: Detail panel and graph

**Files:** Create `UI/Graph.lua`, `UI/Detail.lua`, `UI/TabHistory.lua`, `UI/TabActivity.lua`, `UI/TabOwned.lua`.

**Interfaces:** `UI.Graph.New(parent) -> g` with `g:SetSeries(series, {range = 7|21|0, markers = {{time, kind}}})`, pooled `Line`/`Texture` objects, redraw on `OnSizeChanged`, crosshair and tooltip on hover. `UI.Detail.Show(itemID)` builds header (icon, name, link, star), stats row and the three tabs. History tab: graph, range buttons, daily table, gear-variant selector. Activity tab: summary line plus ledger table. Owned tab: character/location table with snapshot dates, total and value.

- [ ] Smoke test: selecting an item with 0, 1, 21 and 365 days of data renders without error; an item with no data shows the "no data" label; the Owned tab for an unknown item shows "None tracked".
- [ ] Implement; run; commit.

### Task 14: Home view

**Files:** Create `UI/Home.lua`.

**Interfaces:** `UI.Home.Show()` renders scan freshness, Biggest movers, Below average, Inventory value (+ top items), Recent activity, Shopping lists (query text resolved via `Items.NameIndex`, exact then substring). Clicking any row selects the item.

- [ ] Smoke test: Home renders with an empty db and with the fixture db; shopping-list entry `"Thorium Bar";;;;` resolves to the fixture item.
- [ ] Implement; run; commit.

### Task 15: Settings, minimap button, tooltip, slash, bindings, debug

**Files:** Create `UI/Settings.lua`, `UI/Minimap.lua`, `Core/Tooltip.lua`, `Core/Slash.lua`, `Core/Debug.lua`, `AuctionatorAlmanac/Bindings.xml`, `Core/Main.lua` (startup orchestration).

**Interfaces:**
- Settings: minimap on/off, tooltip lines on/off, history range default, ledger keep-days, extended-history keep-days, reset buttons with confirmation; also registered with the game's Settings via `pcall`.
- `Slash`: `/almanac` toggles; `/almanac debug`, `/almanac reset ledger|inventory|history|items`, `/almanac settings`, `/almanac help`.
- `Debug.Report() -> lines[]`: for each used API `name: ok|missing`, Auctionator readiness, item and day counts.
- Tooltip: `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ...)` inside `pcall`, skips secret values (`issecretvalue`), adds ownership and lowest-price lines.
- `Main`: on `ADDON_LOADED` initializes the db and modules; on `PLAYER_LOGIN` waits (retry every 0.5s up to 20s) for `Adapter.IsReady()`, then builds the index, starts item loading, ledger posting import, history snapshot, tracker start.

- [ ] Tests: `Debug.Report` runs with the fake env and lists every API; slash parsing; tooltip callback no-ops safely with secret/nil data; `Main` retry gives up after the limit without error.
- [ ] Implement; run; commit.

### Task 16: Deploy script, docs, final verification

**Files:** Create `scripts/deploy.sh`, `AuctionatorAlmanac/README.md`.

- [ ] `scripts/deploy.sh [target]` symlinks (or with `--copy` copies) `AuctionatorAlmanac` into `target`, default `/Applications/World of Warcraft/_classic_beta_/Interface/AddOns`; refuses to overwrite a real directory without `--force`.
- [ ] Run: all tests, `luac -p` on every `.lua`, a global-leak scan (`luac -l` for `SETTABUP _ENV` / `SETGLOBAL`) against the allowed list, TOC file-existence check (every listed file exists, every `.lua` is listed).
- [ ] Commit.
