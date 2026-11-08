# Auctionator Almanac

A companion to [Auctionator](../Auctionator) for WoW Forever. Auctionator only shows its data at the
Auction House; Almanac opens a window **anywhere in the world** where you can search every item
Auctionator has priced, see its price history, and see what you did with it and where you keep it.

## Install

Almanac needs Auctionator in the same AddOns folder.

```sh
scripts/deploy.sh            # symlink into the Forever beta AddOns folder (edits show after /reload)
scripts/deploy.sh --copy     # or copy the files instead
scripts/deploy.sh --help
```

Or copy the `AuctionatorAlmanac` folder into `.../_classic_beta_/Interface/AddOns/` yourself.

**Windows:** unzip `dist/AuctionatorAlmanac-<version>.zip` (built by `scripts/package.sh`) into the same
`Interface\AddOns` folder that already holds `Auctionator`. You should end up with
`AddOns\AuctionatorAlmanac\AuctionatorAlmanac.toc`, not a doubled `AuctionatorAlmanac\AuctionatorAlmanac\` folder.

## Using it

Open it with `/almanac`, the minimap button, or a key binding (Options > Key Bindings > AddOns).

- **Search** by name or item ID. Matches update as you type. Filter by quality, "owned only", and how recently the price was seen.
- **Categories** on the left mirror the Auction House list; empty categories are hidden.
- **Click a column header** to sort. Shift-click or right-click an item to link it in chat.
- **Select an item** for its detail panel: lowest price now, average, 7-day change, range, quantity, and vendor price, then three tabs:
  - **Price History** - gold line is the daily lowest price, shaded bars the day's low to high, grey bars the quantity. Hover for exact numbers; your sales, purchases and postings appear as markers. Ranges: 7d, 21d, 90d, All.
  - **My Activity** - what you posted, sold, bought, and had expire or cancel, with totals and net.
  - **Where I Own It** - every character and location (bags, bank, mail, equipped, active auctions, warband and guild bank), when each was last seen, and the stack's value at the lowest price.
- **With nothing selected** the panel is an overview: biggest movers, items priced well under their average, your inventory's value, recent activity, and your Auctionator shopping lists with current prices.
- **Resize** by dragging the grip in the bottom-right corner. Everything re-lays-out; the size is remembered.

Item tooltips also get a line with the lowest price and who owns the item (turn off in Options).

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
/almanac debug                feature and data report
/almanac reset <ledger|inventory|history|items> confirm
/almanac reset window         put the window back in the middle
```

Saved data lives in `ALMANAC_DB`. Auctionator's data is only ever read, never written.

## Development

Pure logic and the UI both run headless under a plain Lua with a fake widget environment:

```sh
lua tests/run.lua            # everything
lua tests/run.lua ledger     # just files matching "ledger"
```

The UI tests lay frames out with a small anchor resolver, so resizing is asserted with real rectangles.
What they cannot show is how the real Forever client behaves, which is what `/almanac debug` is for.
