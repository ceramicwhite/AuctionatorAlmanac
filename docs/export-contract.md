# The saved file: what the addon writes and the website reads

The addon and the Almanac website are two repositories with one thing in common: the player's saved file. This page is the contract between them. **The addon writes it, so the addon repository owns this page.** The website's half (what it accepts, what it does when it does not) is `docs/addon-contract.md` in the website repository (checked out beside this one as `../AuctionatorAlmanacWeb`).

If you are a session working on either repository and you are about to change anything described here, read "Changing it" first.

## What travels

A player uploads one file, as it is, from `WTF\Account\<account>\SavedVariables\AuctionatorAlmanac.lua`. It holds one global, `ALMANAC_DB`, written by the game in its usual saved-variables shape. The website never runs the Lua: it reads the file with its own table parser, so only plain data counts (strings, numbers, booleans, tables).

| Key in `ALMANAC_DB` | What it is | Written by | Used by the website for |
|---|---|---|---|
| `export` | The prices block, below | `AuctionatorAlmanac/Core/Export.lua` (at logout and `/reload`) | The market: price history per item |
| `items` | Item facts the game told us, one positional row per item: name, quality, icon, class, subclass, inventory type, vendor price, minimum level, item level | `Data/Items.lua` | Names, types and levels on item pages and lists |
| `ledger.entries` | Sales, purchases, postings, expiries and cancellations | `Tracker/Ledger.lua` | The uploader's own sales and activity |
| `chars`, `guilds`, `warband` | Where the player's items are, by place, with the time each place was last seen | `Tracker/Inventory.lua` | Inventory and "where do I keep it" |
| `history.items`, `history.watched` | Almanac's own long-term daily copies of prices, and the watch list | `Tracker/History.lua` | Fills days the export no longer has; the watchlist |
| `discovery.first`, `discovery.floor` | The day each item was first seen, and the earliest day that can be trusted | `Data/Discovery.lua` | "New finds" |

Everything else in `ALMANAC_DB` (settings, search history, UI state) is the addon's own business. It may change freely. The website ignores keys it does not know.

## The prices block, `ALMANAC_DB.export`

```lua
ALMANAC_DB.export = {
  format = 1,                    -- integer; see "Versions"
  generatedAt = <unix seconds>,
  addon = "1.4.0",               -- informational
  realm = "...",
  faction = "Horde" | "Alliance" | nil,
  character = "Name-Realm",
  house = nil,                   -- reserved: "faction" | "neutral"
  today = <Auctionator day>,
  market = { ["19019"] = "last|day,low,high,qty;day,low,high,qty", ["g:123:200"] = "..." },
}
```

- **Price list**: one string per item, `last|day,low,high,qty;...`, days ascending. Prices are whole copper. `qty` may be empty. A day is Auctionator's day number, which counts days from 2020-01-01. One string and not nested tables is deliberate: the file is far smaller and loads fast in the game.
- **Keys** are Auctionator's: `"123"` (plain item), `"g:123:200"` (gear at item level 200), `"gr:123:suffix"` (legacy suffix gear). Any other key is rejected by the site.
- **Bounds the site enforces**: item id 1 to 99,999,999; price up to 100,000,000,000 copper; quantity up to 10,000,000; day 0 to 7305; `low <= high`; days ascending. A row outside them is dropped and counted, and never stored.
- **Market naming**: WoW: Forever has no realms to pick from, so the website groups uploads by `realm` (the ruleset, such as "PvP") and `faction`.
- A file from before addon 1.3.0 has no `export`. The website still takes the rest of it (sales, inventory, watch list) and stores no prices.

The code is the final word on field shapes. The addon side is `AuctionatorAlmanac/Core/Export.lua` and the modules in the table. The website side is `src/lib/export/` (`normalize.ts`, `pack.ts`, `types.ts`) in the website repository.

## Versions

- `format` is an integer and the website **refuses any value it does not know**, with the message "This file has export format N, which this site does not understand yet." So bumping `format` makes every upload from the new addon fail until the website has been deployed with support for it. Do not bump it for a change that only adds.
- **Adding** a key or a section is not a format change: the website ignores what it does not know, and an old addon simply does not write it. Add to the addon first, release it, then teach the website to read it.
- **Never** rename, remove or change the meaning of a key the website reads without a format bump. Players keep old addon versions for months, so the website reads every addon version still in the wild. Old files keep arriving.
- Do not rely on `addon` for logic. It is recorded, and the website's README states the oldest addon whose files carry prices (1.3.0).

## Changing it

1. **Additive change** (a new field or section): change the addon, add or extend the test in `tests/test_export.lua` (or the module's own test), and regenerate the website's fixtures (below). Then the website can read the new field in its own repository, in its own session, with its own tests. Neither side waits for the other to merge.
2. **Breaking change** (`format` goes up, or a key the website reads changes meaning): the website goes first. Deploy a website that accepts both the old and the new format, confirm it is live, and only then release the addon that writes the new one. Drop the old format on the website only when nobody still uploads it. Say so in the website's contract page when you do.
3. **Tell the other repository's session.** Either send it a message (sessions on one machine can message each other by name) or open an issue labelled `cross-repo` in the repository that has to react. A message is gone when the session ends; an issue is not.
4. **Update this page and the website's `docs/addon-contract.md`** in the same piece of work.

## Regenerating the website's fixtures

The website's tests read saved files that the addon's own test harness writes, so the two cannot quietly drift apart. From this repository's root:

```sh
lua scripts/make-fixture.lua ../AuctionatorAlmanacWeb/tests/fixtures
```

It boots the real addon with a generated market, records sales, purchases, inventory and a watch list through the addon's own modules, lets it write its export block, and writes `AuctionatorAlmanac.lua` and `AuctionatorAlmanac.small.lua` (with `.meta.json` files holding the counts). The output is seeded and reproducible. Then run the website's tests (`npx vitest run tests/export tests/ingest tests/upload`). A failure there means the change was not additive.
