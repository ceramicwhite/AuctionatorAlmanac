# Auctionator Almanac

**Browse Auctionator's prices anywhere in the world.** Search every item Auctionator has priced, see its price history, and see what you sold, bought and own, without standing at the Auction House.

Requires the **Auctionator** addon. Made for **WoW Forever**.

## What it does

Auctionator only shows its data when you are at the Auction House. Almanac opens a window **anywhere** (in a city, on a flight path, in a dungeon) where you can browse everything from your last scan as if you were standing at the counter. It also keeps the history Auctionator does not: what you sold, what you bought, and where every item you own is kept.

Almanac never changes Auctionator's data. It only reads it.

## Features

### Search like you are at the Auction House
- Search by name or item ID. Matches appear as you type.
- The same category tree as the Auction House, with empty categories hidden.
- Filter by quality, how recently the price was seen, price range, whether the price moved, and "owned only".
- Click any column header to sort. Right-click or shift-click an item to link it in chat.

### A full page for every item
- **Price History:** a graph of the daily lowest price with the day's low-to-high band and the quantity on offer. Hover for exact numbers. Your own sales, purchases and postings appear as markers. Ranges: 7 days, 21 days, 90 days, or everything.
- Lowest price now, average, 7-day change, price range, quantity, and vendor price.
- **My Activity:** everything you posted, sold, bought, and had expire or be cancelled for that item, with totals and your net.
- **Where I Own It:** every character and location (bags, bank, mail, equipped, active auctions, guild bank and warband bank), how old each snapshot is, and what the stack is worth at the lowest price.
- **Watch** an item to follow it, and **Link** to put it in chat.

### An overview that does the looking for you
With nothing selected, the window shows seven short tables. **Click any heading to open that table on its own**, with a search box, filters, and every row. Every column header sorts.

- **Biggest movers (7 days):** items whose lowest price changed the most, with a Confidence score (below).
- **Below their average:** items priced well under their recent average, also with Confidence.
- **New finds:** items Auctionator saw for the first time on the last scan, rarest first. Handy for spotting new rare items as they reach the Auction House.
- **Watchlist:** the items you watch, and how they have moved since you added them.
- **Recent activity:** your sales and purchases with how long ago they happened, and how each price compared with the latest scan: `+10%` means you sold it 10% above the current lowest price. Green means it went your way, whether you sold high or bought low.
- **Your inventory:** what you own across your characters, most valuable first.
- **Shopping lists:** your Auctionator shopping lists with current prices.

### Confidence: telling real moves from noise
A price that jumped is only interesting if the jump is real. Almanac scores every mover from 0 to 100 on:

- **Depth:** how many listings the price rests on. One listing can set any price.
- **Signal:** the move compared with how much that item normally swings in a day.
- **History:** how many days of data it has to compare with.
- **Freshness:** whether the price was seen in the newest scan.
- **Size:** whether the move is worth real money, not a few copper.
- **Sanity:** a tenfold jump overnight is usually one odd listing, not a market.

70 and up is high, 40 to 69 is medium, below that is low. Hover a row to see why. Lists are ranked by size of move times confidence, so a clear +30% in a busy market outranks +900% on a single listing, and you can filter to 40+, 60+ or 80+.

New finds has its own confidence: if most of a whole category looks new at once, it was probably just never scanned before, and the score says so.

### It remembers what Auctionator does not
- **Sales** from your Auction House invoice mail, **purchases** from the Auction House (confirmed by the invoice), and **expired and cancelled** auctions.
- **Postings** imported from Auctionator's own posting history.
- **Inventory** for every character, recorded as you open bags, bank and mail.
- **Long-term price history** up to a year for items you own, trade or watch. Auctionator itself keeps about 21 days.

Sales and purchases from before you installed Almanac cannot be recovered.

### Comfortable to use
- Resize from the bottom-right corner. Everything inside re-lays-out, and the size and position are remembered.
- Hide the item list with the button on the divider (or drag the divider) to give the overview and item pages the whole window.
- Minimap button, key binding, and optional price and ownership lines on item tooltips (off until you turn them on in Options).
- Starts Auctionator's scan for you when the Auction House opens, so there is no Full Scan button to click. On by default; turn it off in Options.
- Every erase button in Options asks for confirmation and says exactly what will be lost.
- Built to stay smooth with a full realm's worth of prices.

## Getting started
1. Install **Auctionator** and **Auctionator Almanac**.
2. Visit the Auction House. Almanac asks Auctionator to run its scan for you, no more often than Auctionator's auto-scan interval (15 minutes by default). Prefer to click Full Scan yourself? Turn this off in Options.
3. Type `/almanac`, click the minimap button, or set a key binding (Options > Key Bindings > AddOns).

Almanac never reads the Auction House itself. It shows your last Auctionator scan, and the strip at the top tells you how old it is. The New finds list needs scans on two different days before it can tell what is new.

## Commands
- `/almanac` opens or closes the window (`/alm` works too)
- `/almanac search <text>` opens it with a search
- `/almanac options` opens the options
- `/almanac refresh` re-reads Auctionator's saved prices
- `/almanac debug` lists which game features were found
- `/almanac reset <ledger|inventory|history|items|discovery> confirm` erases stored data
- `/almanac reset window` puts the window back in the middle

## Questions

**Does this replace Auctionator?**
No. Almanac needs Auctionator and shows its data. You still scan, post and buy with Auctionator.

**A scan started when I opened the Auction House. Why?**
Almanac asked Auctionator to run its normal scan, the same one the Full Scan button runs, and only because one was due. Untick "Scan automatically when the Auction House opens" in Options to stop it. Almanac never changes Auctionator's own settings.

**I scanned on another character. Will Almanac see it?**
Yes, on the same realm or connected realms and the same game account. That character has to log out or reload first, because the game only saves addon data then.

**Why is there no history from before I installed it?**
Auctionator does not record your sales or purchases, so Almanac can only record them from the day it is installed.

**Is my data sent anywhere?**
No. Everything is stored on your computer in the addon's saved variables.

**Something looks wrong or says MISSING.**
The Forever client is still changing. Almanac checks every game feature before using it and quietly does without one that is missing. Type `/almanac debug` to see which, and include that output when you report a problem.

## Credits
Almanac reads the prices that [Auctionator](https://www.curseforge.com/wow/addons/auctionator) (by plusmouse and Borjamacare) saves. It is an independent companion addon and is not affiliated with them.
