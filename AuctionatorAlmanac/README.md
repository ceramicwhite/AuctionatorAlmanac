# Auctionator Almanac

A companion to [Auctionator](../Auctionator) for WoW Forever. Auctionator only shows its data at the
Auction House; Almanac opens a window **anywhere in the world** where you can search every item
Auctionator has priced, see its price history, and see what you did with it and where you keep it.

## Install

Almanac needs Auctionator in the same AddOns folder. The easiest way on any system: download
`AuctionatorAlmanac-<version>.zip` from the [latest release](https://github.com/ceramicwhite/AuctionatorAlmanac/releases/latest)
and unzip it into `Interface/AddOns`. (To build the same zip yourself, run `scripts/package.sh`; it lands in `dist/`.)

```sh
scripts/deploy.sh            # symlink into the Forever beta AddOns folder (edits show after /reload)
scripts/deploy.sh --copy     # or copy the files instead
scripts/deploy.sh --help
```

Or copy the `AuctionatorAlmanac` folder into `.../_classic_beta_/Interface/AddOns/` yourself.

**Windows:** unzip `AuctionatorAlmanac-<version>.zip` into the same
`Interface\AddOns` folder that already holds `Auctionator`. You should end up with
`AddOns\AuctionatorAlmanac\AuctionatorAlmanac.toc`, not a doubled `AuctionatorAlmanac\AuctionatorAlmanac\` folder.

## Using it

Open it with `/almanac`, the minimap button, or a key binding (Options > Key Bindings > AddOns).

The **Overview | Top 500 | Search** switch in the middle of the title bar picks the page. The window opens on **Overview** (`/almanac search <text>` opens on Search). **Top 500** is the 500 items that matter most on the WoW Forever auction house (the same list as the Almanac website's), priced from your own scans: sort it by any column, high to low or low to high, search it, or show one kind at a time. On any page, picking an item opens its detail panel on the right; **Close** takes it away again, and each page remembers the item that was open on it.

Every item row, on every page and in every full list, has a **star** left of its icon: click it to watch the item (the star fills in, and the item goes on the Watchlist), click again to stop.

- **Search** by name or item ID. Matches update as you type. Filter by quality, "owned only", and how recently the price was seen.
- **Recent searches and autofill.** Almanac remembers what you search for (press Enter, open a result, or pick from the **v** menu in the search box) and merges it with the recent searches made in Auctionator. The menu shows the newest twelve, and typing completes from the list, and from your Auctionator shopping list terms, as Auctionator's search box does: keep typing to ignore the highlighted completion, Backspace removes it, Enter accepts it, Escape drops it.
- **Categories** on the left mirror the Auction House list; empty categories are hidden.
- **On AH** is how many were listed in the latest scan and **At lowest** how many of those were at the lowest price (see "What it tracks" for where that comes from; a dimmed On AH is Auctionator's count for the day instead). Narrow lists drop Seen, Own and Change before these.
- **Click a column header** to sort. Shift-click or right-click an item to link it in chat.
- **Select an item** for its detail panel: lowest price now, average, 7-day change, range, how many are listed and how many at the lowest price, and vendor price, then three tabs:
  - **Price History** - gold line is the daily lowest price, shaded bars the day's low to high, grey bars the quantity. Hover for exact numbers; your sales, purchases and postings appear as markers. Ranges: 7d, 21d, 90d, All.
  - **My Activity** - what you posted, sold, bought, and had expire or cancel, with totals and net.
  - **Where I Own It** - every character and location (bags, bank, mail, equipped, active auctions, warband and guild bank), when each was last seen, and the stack's value at the lowest price.
- **The Overview page** is seven short tables across the whole window, Watchlist first. **Click any heading** (it says "View all") to open that table on its own, with a search box, filters and every row; "< Overview" takes you back. An item opened from a table shows beside it, so the table stays put. Columns appear as there is room for them (On AH and At lowest from 460 pixels, the rest from 600), in the short tables and the full lists alike.
  - **Biggest movers (7 days)** and **Below their average** have a **Confidence** column (see below).
  - **New finds** - items Auctionator saw for the first time on the last scan, rarest first. Built to spot new rare items turning up on the Auction House.
  - **Watchlist** - items you watch (a row's star, or the **Watch** button on any item), with how they have moved since you added them.
  - **Recent activity** - your sales and purchases; the full list also has postings, expiries and cancellations, and a search.
  - **Your inventory** and your Auctionator **Shopping lists** with current prices.
  - Every column header is a button: click to sort, click again to reverse.
- **Drag the divider** beside an open detail panel to resize it, or **hide the list beside it** with the **<** button on the divider to give the panel the whole width. Searching or picking a category brings the item list back; closing the item brings either list back.
- **Resize** by dragging the grip in the bottom-right corner. Everything re-lays-out; the size is remembered.

Item tooltips can also get a line with the lowest price and who owns the item (off by default; turn on in Options).

**Auto-scan:** when the Auction House opens, Almanac asks Auctionator to run the scan the Full Scan button would, so you do
not have to click it. It only asks when Auctionator says a scan is due (its auto-scan interval, 15 minutes by default, and the
server's own limit on full scans both still apply), it goes through Auctionator's own scan so you see its normal progress, and it
never changes Auctionator's settings. On by default; switch it off in Options. `/almanac debug` shows whether it found
Auctionator's scan frame.

**Website export:** when you log out or `/reload`, Almanac writes a compact copy of Auctionator's prices (plus who, where and when) into its own saved file, as `ALMANAC_DB.export`, so the one file `WTF\Account\<ACCOUNT>\SavedVariables\AuctionatorAlmanac.lua` can be uploaded to an Almanac website. Nothing is sent by the game. If Auctionator's data is not loaded at that moment the previous copy is kept. On by default; the checkbox in Options turns it off and removes the copy. `/almanac export` shows what the next save will contain.

**Link** puts the item's link into chat. If no chat box is open it opens one with the link in it.
**Watch** (or a row's star) adds the item to your Watchlist (it says so in chat) and keeps its price history beyond Auctionator's 21 days; watched items wear a filled star in every list.

## How Confidence works

A "big mover" is only interesting if the move is real. Almanac compares an item's lowest price now with the average of its daily lowest prices over the week before, then scores 0-100 how far that move can be trusted. Each factor is between 0 and 1 and any one serious problem drags the whole score down:

| Factor | Looks at | Example of a low score |
|---|---|---|
| Depth | listings up now and typically (the smaller of the two) | a single listing sets the price |
| Signal | the move against the item's own day-to-day wobble | +30% on an item that swings 30% daily |
| History | days of data to compare with | only two days |
| Freshness | whether it was seen in the newest scan | last priced four days ago |
| Material | the move in actual coins | 20 copper on a cheap item |
| Sanity | how extreme the jump is | x10 overnight is usually one odd listing |

70+ is high (green), 40-69 medium, below that low. Hover a row for the reasons. Lists are ranked by size of move times confidence, so a clear +30% in a deep market outranks +900% on one listing; the full list can be filtered to 40+, 60+ or 80+.

**New finds** has its own confidence: if most of an item's category is "new" at once (for example the first full scan after only scanning one category), it was probably just never scanned before, and the score says so.

## What it tracks, and what it cannot

Auctionator saves only the lowest price per item per day. Almanac reads that, so it cannot show
individual auctions. Auctionator does not record sales or purchases, so Almanac tracks them itself:

| Thing | How it is detected | Notes |
|---|---|---|
| Sales | "Auction successful" invoice mails, read when you open the mailbox | Needs the mailbox; each mail is counted once. |
| Purchases | Commodity purchases and single-item buyouts at the Auction House, confirmed by the "Auction won" invoice | A buyout is shown as unconfirmed until its invoice is read. |
| Expired / cancelled | Returned-item mails | |
| Postings | Auctionator's own posting history, imported | Auctionator keeps ~10 per item. |
| Inventory | Snapshots when bags/bank/mail/auctions change | A character's bank and mail are as of its last visit; the tab says how old each snapshot is. |
| Long price history | Daily copies of Auctionator's data for items you own, trade or watch, kept up to a year | Auctionator itself only keeps 21 days. |
| New finds | The first scan day Almanac saw each item, remembered even after Auctionator forgets it | Needs scans on two different days before it can say anything is new. |
| At lowest | Every scan hands each auction's price and size to `Auctionator.Database:ProcessScan`, which then saves each item with `SetPrice`. Almanac listens to both and, for each item saved from that scan, keeps how many were listed at the lowest price and in all, per realm | Auctionator itself saves only a total. Any other save of an item's price (a posting, a one-item search) makes its count unknown ("—") until the next scan. Before an item's first scan with Almanac 1.5, **On AH** is Auctionator's count for the day (the most it saw listed that day) and is shown dimmed. `/almanac debug` says whether Almanac is listening. |

Sales and purchases from before Almanac was installed cannot be recovered.

## If something is missing

Run `/almanac debug`. It lists every game feature Almanac relies on and says `ok` or `MISSING`, plus what
Auctionator exposed and how much Almanac has stored. The Forever client's API set is still moving; a
`MISSING` line tells you exactly which feature to look at. Everything degrades quietly rather than erroring.

## Commands

```
/almanac                      open or close the window
/almanac search <text>        open it with a search
/almanac options              open the options
/almanac refresh              re-read Auctionator's saved prices
/almanac export               what the next save will contain for the website
/almanac debug                feature and data report
/almanac reset <ledger|inventory|history|items|discovery|searches> confirm
/almanac reset window         put the window back in the middle
```

The erase buttons in Options each open a confirmation window that says what will be lost.

The export block is documented in the website project's design (`format = 1`: `realm`, `faction`, `character`, `today`, and `market[key] = "last|day,low,high,qty;..."`). Saved data lives in `ALMANAC_DB`. Auctionator's data is only ever read, never written.

## Development

Pure logic and the UI both run headless under a plain Lua with a fake widget environment:

```sh
lua tests/run.lua            # everything
lua tests/run.lua ledger     # just files matching "ledger"
```

The in-game textures (`Media/*.tga`, the minimap icon and the AddOns-list logo) are generated from the
SVGs in `branding/` by `scripts/build-media.sh`; edit the SVG and rerun it. The game cannot load SVG/PNG
reliably, so they are uncompressed 32-bit TGAs, and the tests check that they are valid.

The UI tests lay frames out with a small anchor resolver, so resizing is asserted with real rectangles.
What they cannot show is how the real Forever client behaves, which is what `/almanac debug` is for.
