# Rosa API reference

## Calling an event

```lua
-- ServerScript / server-side ModuleScript:
Rosa:addServerEvent(player, { tag = "ChestOpened", quantity = 1, custom = { chestType = "Gold" } })

-- LocalScript (client-side only, last resort):
Rosa:addClientEvent({ tag = "ButtonClick", custom = { buttonId = "PlayButton" } })
```

`Rosa` is whatever the project named the module returned by requiring the Rosa package's `init`
(the file that calls `EventIngestionHandler.new({...})`). Reuse that project's existing local
name for it — don't re-require under a new alias.

## EventRequest fields

```lua
{
  tag      : string,                              -- required, PascalCase
  position : Vector3?,                             -- optional; defaults to the player's HumanoidRootPart position
  quantity : number?,                              -- optional; the event's primary numeric measure
  custom   : { [string]: string | number | boolean }?, -- optional; extra queryable fields
}
```

Fields Rosa attaches automatically — never duplicate these in `custom`: `eventId`,
`eventTimeStamp`, `sessionID`, `platform`, `position`, `version`, `teamId`, `mapName`. If the
project's config sets `customPlayerDataHook`, whatever fields it returns are also merged onto
every event automatically (event-level `custom` wins on key conflict) — check that hook before
adding a field it already provides.

### Runtime validation (`type-enforcement.luau`)

- `custom` values must be `string` or `number`. The type annotation on `EventRequest.custom`
  permits `boolean`, but the actual runtime check (`type-enforcement.luau`) only allows string or
  number and throws otherwise — treat booleans as unsupported. Use `1`/`0` or a short string.
- `custom`, once JSON-encoded, must be ≤ 500 characters total (`Constants.CUSTOM_FIELD_MAX_ENCODED_SIZE`).
  Keep it to a couple of short fields, not free text.
- `tag`, `sessionID`, `platform` must be strings; `position.x/y/z` must be numbers; these are all
  filled in automatically by `addServerEvent`/`addClientEvent` — you only ever set `tag`,
  `quantity`, and `custom` (and rarely `position`, if overriding the default).

## Client events must be whitelisted

`addClientEvent` calls go through a RemoteEvent to the server. The server only accepts tags
listed in the config's `clientEvents.whitelistedEventTags`, or explicitly allowed at runtime via
`Rosa:allowClientTag("TagName")`. Adding a new client-fired tag without also whitelisting it means
the event gets silently dropped with a `Logger.warn` — always update
`clientEvents.whitelistedEventTags` in the same change.

## Tags Rosa already tracks automatically (`defaultMetrics`)

Don't re-instrument these unless the project has disabled the corresponding flag. Check the
project's Rosa config (`defaultMetrics = {...}` block) to see what's actually enabled — all
default to `true` except `humanoidStateEvents` and `jumpEvents`, which default to `false`.

| Tag(s) | Config flag | Notes |
|---|---|---|
| `PlayerJoin`, `PlayerLeave` | `playerEvents` | `PlayerLeave.quantity` = session duration (seconds) |
| `CharacterSpawn`, `CharacterDeath` | `characterEvents` | |
| `DamageTaken` | `damageEvents` | `quantity` = damage amount, `custom.healthPct` |
| `ToolEquipped`, `ToolActivated` | `toolEvents` | `custom.toolName` |
| `PlayerIdle` | `idleDetection` | fires once idle ends; `quantity` = idle duration |
| `ProductPurchased`, `ProductDeclined` | `marketplaceEvents` | `quantity` = robux price, `custom.productId` |
| `GamePassPurchased`, `GamePassDeclined` | `marketplaceEvents` | `quantity` = robux price, `custom.gamePassId` |
| `PromptTriggered` | `proximityEvents` | any ProximityPrompt activation, `custom.action`/`object` |
| `ChatMessage` | `chatEvents` | |
| `TeamChanged` | `teamEvents` | `custom.formerTeam` |
| `HumanoidStateChange` | `humanoidStateEvents` (off by default) | Landed/Freefall/Climbing/Swimming/Seated |
| `PlayerJump` | `jumpEvents` (off by default) | noisy, low value |
| `_PathStart`, `_PathTag` | `paths` | 5% sampled position heatmap trail, not a gameplay event |
| `InputMethodChanged` (client) | — | KeyboardAndMouse/Touch/Gamepad switches |
| `SettingsOpened` (client) | — | |

Everything not in this table is fair game for instrumentation — that's what this skill is for:
kills, currency earned/spent, quests/levels completed, loot/inventory, boss/wave encounters,
matchmaking/round start-end, upgrades purchased, tutorial steps, and similar game-specific
moments the default set has no visibility into.
