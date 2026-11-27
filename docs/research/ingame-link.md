# In-game link between two Almanac players (research)

Status: research only, nothing built. Written 2026-11-27 from four sample addons (read, never run), Blizzard's API documentation,
and the real saved file from 2026-11-25. Everything marked **verify** has not been tested on a Forever client.

## The question

Can two friends on opposite factions share Almanac scan data and alerts **inside the game**, with no website in between: "I just
scanned the Horde AH and Elixir of Giant Growth is 6g, you sell it for 15g on the Alliance side"?

## Answer

**Yes, over Battle.net friends.** Every sample addon that crosses factions does it this way, and you two are Battle.net friends, so
you do not need Communities at all.

| Path | Crosses factions? | Verdict |
|---|---|---|
| **Battle.net game data** (`BNSendGameData` / `C_BattleNet.SendGameData`, event `BN_CHAT_MSG_ADDON`) | Yes, by design. FactionRP calls it "the BNet leg [that] exists to bridge factions". | **Use this.** |
| Hidden custom chat channel (`JoinTemporaryChannel`) | **No.** FactionRP's own constant says "Hidden channel for same-faction traffic". XFaction: "Local channel for same realm/faction communication". | Not usable across factions. |
| Addon whisper to a community member (`SendAddonMessage(..., "WHISPER", name)`) | Probably (CommunitiesForever never filters targets by faction), but no sample states it. A Blizzard forum thread suggests cross-faction communities are not simple to create on Forever (snippet only, unread). | Skip. Not needed. |
| `/say` and `/yell` coded lines (ProtoTongues) | Yes, but only to players standing next to you, and visible in chat. | Irrelevant. |

## Hard facts

From Blizzard's documentation (warcraft.wiki.gg, `BNSendGameData`):
- A message is **at most 4,078 bytes**.
- The prefix must be registered first with `C_ChatInfo.RegisterAddonMessagePrefix`.
- **Delivery is not guaranteed to be in order.**
- `BNSendGameData` was **deprecated in 12.0** in favour of `C_BattleNet.SendGameData`. The old name still works through a shim
  (CommunitiesForever uses it on Forever) but "will be removed". Call `C_BattleNet.SendGameData` when it exists, else the global. **verify** on Forever.

From the samples (how they find a valid friend, `CommunitiesForever/src/core/Friends.lua`, `FactionRP/src/Comms.lua`):
- Walk the friend list with `C_BattleNet.GetFriendNumGameAccounts(i)` and `C_BattleNet.GetFriendGameAccountInfo(i, j)`.
- Keep an account only if `isOnline`, `clientProgram == "WoW"` and `isInCurrentRegion`. CommunitiesForever also requires
  `wowProjectID == WOW_PROJECT_ID`, which is **18 on Forever** (Retail is 1).
- The game account carries `factionName`, `characterName`, `gameAccountID`: enough to confirm the friend really is on the other faction.
- Receive with `BN_CHAT_MSG_ADDON(prefix, text, channel, senderGameAccountID)`.
- Event arguments can be "secret" on the modern client. Both CommunitiesForever (`ns.Safe.values`) and XFaction (`issecretvalue`) guard every argument.

## What each sample teaches

| Addon | Client | What it does | Worth copying |
|---|---|---|---|
| **CommunitiesForever** (Vestras) | Forever (1.60.01) | Syncs a friend's characters. Battle.net game data to friends, addon whispers to community members, a hidden channel for broadcasts. | **The protocol and the layering.** Serialize, optionally deflate, chunk with a `<id>:<seq>:<total>:` header, reassemble, ask for missing parts (`!M:`), expire after 30 s, a protocol version `pv` on every message with explicit upgrade steps. A queue that sends one chunk per 0.2 s and pauses in combat. A presence model, so it never messages someone offline (a whisper to an offline player prints "No player named…" in chat). Pure-Lua `core/` kept apart from `adapters/` that touch WoW, so it is testable outside the game. |
| **FactionRP** | Retail 12.x | Shares roleplay profiles. Same-faction channel plus Battle.net friends as cross-faction relays. | A **handshake** before trusting a friend has the addon: probe, confirm on the first parseable reply, "ignore" a friend that never answers, expire the confirmation. A token-bucket send rate. |
| **XFaction** | Retail 12.x | Guild chat across realms and factions. | A full gossip mesh: de-duplicate by message key, drop anything older than 120 s, random selection of forwarders. **Far more than two friends need.** It shows what breaks at scale; you can ignore it. |
| **ProtoTongues** | Forever | Hides coded text in `/say`. | Nothing for this. |

## Proposed design: "Link" for two paired players

**Pairing.** `/almanac link Buddy#1234` on each side stores the other's BattleTag. Messages go only to that friend, never to the rest
of the friend list. Only the paired BattleTag's messages are accepted.

**Presence.** Find the buddy's game account as above, then exchange a small `HELLO` (protocol version, addon version, faction,
market name, time of last scan). Until a `HELLO` comes back, send nothing else. React to `BN_FRIEND_ACCOUNT_ONLINE/OFFLINE` and
`BN_FRIEND_INFO_CHANGED`, so "both online" is known without polling.

**Messages** (all small, plain text, no compression library needed):

| Type | Carries | Size |
|---|---|---|
| `HELLO` / `BYE` | version, faction, market, last scan time | ~80 bytes |
| `DEAL` | item (+ suffix variant), the price on the sender's AH, quantity, a margin and a confidence, scan day | 60 to 120 bytes |
| `SNAP` | the sender's price snapshot, in chunks, so the buddy can compute margins against it | see below |
| `ACK` | `msgId` of a `DEAL` | ~20 bytes |

**How much data a snapshot is** (measured on your real file: 7,332 items plus 28,600 random-suffix gear series, 866 KB for a last
price on every series):

| Only series priced at least | Series | Snapshot | Messages of ~4 KB | Time at 0.2 s apart |
|---|---|---|---|---|
| anything | 35,932 | 866 KB | 220 | 44 s |
| 1g | 18,000 | 461 KB | 117 | 23 s |
| **5g** | **4,282** | **107 KB** | **28** | **5.6 s** |
| 10g | 1,591 | 38 KB | 10 | 2.0 s |
| 50g | 219 | 4 KB | 2 | 0.4 s |

So **no compression is needed.** Send only what can make money (say 5g and up) and after the first sync send only what changed.
A full price history (3.1 MB, 807 messages, about 2.7 minutes) should stay on the website.

**The "strong, confident item" alert.**
1. Auctionator announces a finished scan with `Auctionator.FullScan.Events.ScanComplete`. Hook that, and only then.
2. Compare each item's price in the scanned house with the buddy's snapshot. This is the website's trade maths (`evaluate`,
   `tradeConfidence`, the 5% faction and 15% neutral cuts, per-suffix for random-suffix gear). **Port it to Lua** as a pure module
   and test it against the website's own fixtures, so the two cannot drift apart. Almanac's `Data/Discovery.lua` already has the
   same idea of a per-find confidence.
3. Alert only above your thresholds: a minimum profit in gold and a minimum confidence.
4. Show the best few, then "and 12 more, `/almanac trades`". Do not re-alert an item inside a cooldown unless its price moved a lot.
5. If the buddy is offline, keep the alert and deliver it when their `HELLO` arrives ("while you were away").

**Wire format.** Reuse CommunitiesForever's chunk header and add a protocol version to every message from day one. Do not rely on
delivery order (documented as unordered). Cap sizes and validate every field of anything received.

## What you do not need

Communities, hidden channels, relays, gossip, a serialization or compression library, and whispers. Two paired friends and one
transport is a much smaller thing than any of the samples.

## Verify first (one evening, ~40 lines of Lua)

An untested throwaway addon, run on both clients, answers every unknown above before any real code is written:

```lua
-- AlmLinkTest. Two clients, two Battle.net friends. /altest list | /altest send <n> <bytes>
local PREFIX = "ALMLINK"
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
local send = (C_BattleNet and C_BattleNet.SendGameData) or BNSendGameData
local function friends()
  local out = {}
  for i = 1, BNGetNumFriends() do
    for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) do
      local a = C_BattleNet.GetFriendGameAccountInfo(i, j)
      if a and a.isOnline and a.clientProgram == "WoW" then out[#out + 1] = a end
    end
  end
  return out
end
SLASH_ALTEST1 = "/altest"
SlashCmdList.ALTEST = function(msg)
  local cmd, arg = msg:match("^(%S+)%s*(.*)$")
  local list = friends()
  if cmd == "list" then
    for i, a in ipairs(list) do print(i, a.characterName, a.factionName, a.wowProjectID, a.gameAccountID, a.isInCurrentRegion) end
    print("WOW_PROJECT_ID", WOW_PROJECT_ID, "C_BattleNet.SendGameData", C_BattleNet and C_BattleNet.SendGameData ~= nil)
  elseif cmd == "send" then
    local n, bytes = arg:match("(%d+)%s+(%d+)")
    send(list[tonumber(n)].gameAccountID, PREFIX, string.rep("x", tonumber(bytes)))
    print("sent", bytes, "bytes")
  end
end
local f = CreateFrame("Frame")
f:RegisterEvent("BN_CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, _, prefix, text, _, senderID)
  if prefix == PREFIX then print("got", #text, "bytes from", senderID, GetTime()) end
end)
```

Questions it settles:
1. `/altest list`: does your buddy appear with the **opposite `factionName`**, `wowProjectID` 18 and `isInCurrentRegion`? Does
   `C_BattleNet.SendGameData` exist on Forever?
2. `/altest send 1 <bytes>` at 100, 1000, 4000, 4078 and 4079. Expect the last to fail or be cut.
3. A burst of 50 sends of 4,000 bytes: is anything lost, throttled or reordered? How long does it take?
4. Does it work with the Auction House window open, in a loading screen, in combat?
5. What happens when you send to a friend who just logged out?

## Plan

| Phase | What | Rough size |
|---|---|---|
| 0 | The test above, on two real clients | one evening |
| 1 | Pairing, presence, `HELLO`, `DEAL` alerts, the Lua port of the trade maths with parity tests | a few hundred lines plus tests |
| 2 | Snapshot sync (5g and up, then deltas), in-game trade lines in the item tooltip | similar again |
| 3 | Offline delivery, a small panel, settings | polish |

The addon already has Lua tests (`tests/run.lua`), so the pure parts (protocol, outbox, trade maths) can be built test-first, as
CommunitiesForever does.

## Risks

- `BNSendGameData` is deprecated; use `C_BattleNet.SendGameData` when present.
- "Secret" event arguments: guard every received value.
- The buddy must be online in WoW, same region and same `wowProjectID` (both on Forever). A friend on Retail will not match.
- The addon already lists Interface 16001, 120100 and 120105: Retail 12.x behaves like Forever for all of this, but test both if you
  ever want it there.
- Nothing here is a documented guarantee from Blizzard for Forever specifically: Phase 0 exists to find out.
