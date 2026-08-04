---
name: setup-rosa-analytics
description: Scans a Roblox/Luau codebase and instruments game-specific Rosa analytics events (kills, purchases, quest/level progress, loot, currency, boss/wave completion, etc.), matching the project's existing code style and preferring server-side calls over client-side. Use when the user asks to add analytics/telemetry, wire up Rosa events, instrument tracking for game actions, or audit event coverage in a game that uses the Rosa package.
---

# Setup Rosa Analytics

Instruments a Roblox game with Rosa (`Rosa:addServerEvent` / `Rosa:addClientEvent`) events for
game-specific actions. Read `references/rosa-api.md` first — it has the full field contract
(tag/position/quantity/custom), the list of tags Rosa already tracks automatically, and the
runtime validation rules. Don't skip it; guessing the API shape produces events that silently
fail `type-enforcement`.

## Procedure

### 1. Find Rosa and read its config

Grep the repo for `addServerEvent`, `addClientEvent`, or a require path containing `Rosa`/`rosa-rbx`
(check `wally.toml` / `Packages` too). Find the module that calls `EventIngestionHandler.new({...})`
— this is the project's Rosa config. Read it fully:

- `defaultMetrics` — which tags are auto-tracked already (see reference doc). Anything enabled
  there, don't re-instrument.
- `clientEvents.whitelistedEventTags` — any new client-fired tag must be added here, or client
  events with that tag get silently dropped.
- `customPlayerDataHook` — fields already attached to every event automatically. Never repeat
  these inside a per-event `custom` table.

If no Rosa require exists anywhere in the project, stop and tell the user — don't guess at a
require path. They can install the latest Rosa package from the
[GitHub releases page](https://github.com/ajsteinhauser/rosa-rbx/releases) or via the
[wally package](https://wally.run/package/ajsteinhauser/rosa-rbx) instead.

### 2. Check for an existing analytics/metrics system

Grep case-insensitive for things like `GameAnalytics`, `GameBeast`, `PlayFab`, `Amplitude`,
`Mixpanel`, `Segment`, `Analytics`, `Metrics`, `LogEvent`, `TrackEvent`, `:Track(`, `:SendMarker(`
(Gamebeast's marker call, e.g. `GamebeastMarkers:SendMarker("RoundEnded", { Score = 600, Map = "Office", Duration = 120 })`).
Each hit is a strong signal of "this is a meaningful game moment" someone already decided to measure.

- If found: add the matching Rosa call immediately next to each existing tracking call — same
  function, same trigger condition, adjacent line. Don't re-derive the trigger logic; reuse
  theirs.
- If nothing found: read the actual gameplay code (combat, economy/currency, progression,
  quests, loot, matchmaking/rounds, boss/wave logic) and pick natural instrumentation points
  yourself. Favor actions a game designer would actually want a chart for.

### 3. Inspect RemoteEvent/RemoteFunction handlers

Every `SomeRemote.OnServerEvent:Connect(function(player, ...) ... end)` (and `OnServerInvoke`) is
a point where a client-initiated action becomes server-authoritative — often a rich source of
"what can players actually do" in the whole codebase, and it's already server-side. Grep for
`OnServerEvent:Connect(` and `OnServerInvoke` project-wide, then read each handler — but don't
treat every remote you find as a candidate. Only instrument the ones that would genuinely help a
game analytics dashboard (economy, progression, engagement decisions); most remotes in a real
codebase are plumbing, not signal.

- Skip any remote that's Rosa's own internal transport — `RosaClientEventStream`,
  `ServerEventStream`, and the `PlatformManager` remote used for platform detection. These are
  already handled by the Rosa module itself and are never instrumentation targets.
- Skip any handler whose action already maps to a tag Rosa auto-tracks (see the `defaultMetrics`
  table in the reference doc) or that already calls `addServerEvent`/`addClientEvent` — it's
  already logged, regardless of whether that tag is currently allowed or denied in
  `clientEvents.whitelistedEventTags`. Whitelist status is irrelevant to "already handled."
- High-signal, low-frequency actions (buy item, submit trade, use ability, open shop, redeem
  code) are strong instrumentation candidates. Add the `Rosa:addServerEvent` call inside the
  handler itself, after the action is validated and applied — not before, so rejected/invalid
  requests aren't counted as the event (mirror the `ProductPurchased`/`ProductDeclined` split
  from default metrics if a rejected case is itself worth tracking).
- High-frequency, low-signal remotes (per-frame input state, camera/aim updates, movement
  replication) aren't worth tracking — skip them, don't manufacture volume.
- The remote's own name and arguments are often the tag and `custom` fields in disguise — a
  `"BuyItem"` RemoteEvent firing `(player, itemId, price)` maps almost directly to
  `{ tag = "ItemPurchased", quantity = price, custom = { itemId = itemId } }`.

This is still the server-first case (step 5): you're calling `addServerEvent` from inside the
`OnServerEvent` handler, not firing a separate `addClientEvent` from whatever fired the remote.

### 4. Match existing style

Before writing anything, grep for any Rosa calls already in the codebase (custom ones, not
defaults) — that's the strongest signal for this project's tag-naming and table-formatting
convention. Then match the surrounding file: indentation, quote style, how nearby code formats
inline tables (single line vs multi-line), and the local variable name already used for the
required Rosa module (reuse it, don't re-require under a different name).

Tag names: PascalCase, single past-tense-or-noun action — `BossDefeated`, `QuestCompleted`,
`ChestOpened`, `CurrencySpent`, `WaveCompleted`. Match whatever convention already exists in the
project's own custom tags over the examples here if they differ.

### 5. Server-first, always

Default to `Rosa:addServerEvent(player, {...})`, called from the server-authoritative code path
that actually resolves the action (the function that grants currency, confirms a purchase,
applies damage, completes a quest) — not a client-side prediction of it.

Only use `Rosa:addClientEvent({...})` when the action has no server representation at all (pure
UI/menu interaction, a client-only rendering choice). Every new client tag needs to be added to
`clientEvents.whitelistedEventTags` in the config — do this edit as part of the same change, and
mention it in your summary so the user notices.

### 6. quantity vs custom — quantity wins

`quantity` is a single indexed number and queries fast. `custom` is a JSON blob capped at 500
encoded characters and is slower to query. Rules, in order:

1. If the event has one obvious numeric measure (currency amount, damage, wave number, item
   count, elapsed seconds, kill count), put it in `quantity`. Never bury a number that belongs
   there inside `custom`.
2. Only add a `custom` field if it's something someone would actually filter/group by (item id,
   source, reason, quest id). Don't add descriptive text, don't duplicate fields Rosa already
   attaches automatically (position, version, team, map, platform, session, timestamp), and
   don't manufacture a field just to have one.
3. If an event has no useful secondary dimension, emit `{ tag = "...", quantity = ... }` with no
   `custom` at all.
4. `custom` values must be `string` or `number` only (see reference doc — booleans pass the type
   annotation but fail runtime validation). Never use a boolean; use a string/number field that
   could expand instead — e.g. instead of `{ UsedRareAmmo = true }` use `{ AmmoType = "Rare" }`.

### 7. Summarize

After editing, list every file changed, the tag/quantity/custom chosen per event with a one-line
reason, and flag any new entries added to `whitelistedEventTags`. If you're unsure whether an
action is worth tracking (low signal, high volume), ask rather than instrumenting it speculatively.
