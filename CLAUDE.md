# Auctionator Almanac (the addon)

A World of Warcraft addon for the WoW: Forever client: it browses Auctionator's saved prices from anywhere, remembers your sales and your searches, and writes the file the Almanac website ingests. Plain Lua, no libraries. Public repository: `ceramicwhite/AuctionatorAlmanac`, branch `master`.

## Layout

- `AuctionatorAlmanac/` is the addon (TOC, `Core/`, `Data/`, `Tracker/`, `UI/`, `Media/`). Its `README.md` is the CurseForge page.
- `Auctionator/` is a reference copy of Auctionator, for reading only. It is git-ignored. Never edit it, and never read Auctionator's saved variables for writing: the addon's adapter (`Data/Adapter.lua`) only reads them.
- `tests/` runs the real addon in a plain Lua harness with a widget stub (`ui_stub.lua`, `boot_ui.lua`). `scripts/` has `package.sh` (the release zip), `make-fixture.lua` (see below) and `build-media.sh`. `docs/` has specs, plans and research.

## Commands

- `lua tests/run.lua`: all tests. CI uses Lua 5.4. Run them before every commit.
- `scripts/package.sh`: builds `dist/AuctionatorAlmanac-<version>.zip`.
- Release: bump `## Version` in `AuctionatorAlmanac.toc` (and the `addon = "x.y.z"` comment in `Core/Export.lua`), commit, then push a tag `vX.Y.Z` that equals it. `.github/workflows/release.yml` runs the tests and publishes the GitHub release.

## How we work here

- Write the test first and watch it fail. New UI behaviour goes in the widget stub's terms, so the tests run outside the game.
- Commit messages: `feat:`, `fix:`, `docs:`, `ci:` or `chore:`, then what and why, ending with the co-author trailer the session was given. Do not commit or push unless asked.
- This repository is **public**. Nothing committed here may name the website's domain, hosting accounts, project ids, secrets, or personal paths and emails. Use relative paths such as `../AuctionatorAlmanacWeb`.
- The game cannot be run from here. A change that only a stub has checked is not verified in the client: say so.

## The website next door

The Almanac website (`../AuctionatorAlmanacWeb`, a separate private repository, Next.js and Postgres) ingests the file this addon saves. The two share exactly one thing, and it is written down in **`docs/export-contract.md`**. Read it before touching `Core/Export.lua`, the saved-variables layout (`ALMANAC_DB`), or anything the table in that page lists.

- A change that only **adds** to the file needs no website change first. A change that renames, removes or reinterprets something the website reads, or raises `format`, needs the website deployed first. See "Changing it" in the contract.
- When the saved file changes, regenerate the website's fixtures: `lua scripts/make-fixture.lua ../AuctionatorAlmanacWeb/tests/fixtures`, and run the website's tests. Do not edit the website repository's files from an addon session except those generated fixtures. Its own session owns the rest.
- Tell the website's session when its side must change: a message by session name, or an issue labelled `cross-repo` (durable).

## Several sessions at once

Two sessions on one checkout share one working tree and one git index, and they overwrite each other. So:

- A second session on the addon works in its own worktree and branch: `git worktree add ../AuctionatorHistory-<topic> -b <topic>`. It merges to `master` through git when done.
- Before committing, run `git status`. If you see staged or modified files you did not touch, they belong to another session: do not add them, do not revert them. Commit only your own paths with `git commit -m "..." -- <paths>`. Never `git add -A`, `git commit -a`, `git stash`, `git reset --hard` or `git checkout .` in a checkout another session may be using.
- Facts both repositories' sessions need belong in `docs/export-contract.md` or in an issue, not in one session's memory.
