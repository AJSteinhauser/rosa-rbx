--[[
	Rosa Analytics — Configuration
	================================
	This is the main configuration file. Edit it here, then require this module
	from a ServerScript and a LocalScript — Rosa detects the context automatically.

	SETUP:
	  1. Add your API key to Roblox secrets under the name "ROSA-API-KEY"
	  2. Require this module in both a ServerScript and a LocalScript:
	         local Rosa = require(path.to.Rosa)

	LOGGING EVENTS:
	  -- From a ServerScript:
	  Rosa:addServerEvent(player, { tag = "PlayerKill", quantity = 1 })
	  Rosa:addServerEvent(player, { tag = "ChestOpened", custom = { chestType = "Gold" } })

	  -- From a LocalScript:
	  Rosa:addClientEvent({ tag = "ButtonClick", custom = { buttonId = "PlayButton" } })
]]

local Rosa = require(script.ingestion["event-ingestion-handler"]).new({

    -- ── AUTOMATIC EVENTS ──────────────────────────────────────────────────────
    -- Rosa fires these events automatically. Set any to false to disable.
    defaultMetrics = {
        playerEvents          = true,   -- PlayerJoin, PlayerLeave (includes session duration)
        characterEvents       = true,   -- CharacterSpawn, CharacterDeath
        damageEvents          = true,   -- DamageTaken (includes damage amount)
        toolEvents            = true,   -- ToolEquipped, ToolActivated
        idleDetection         = true,   -- PlayerIdle (fires after player stops moving)
        idleThresholdSeconds  = 15,     -- seconds of no movement before PlayerIdle fires
        marketplaceEvents     = true,   -- ProductPurchased/Declined, GamePassPurchased/Declined
        proximityEvents       = true,   -- PromptTriggered (ProximityPrompt activations)
        chatEvents            = true,   -- ChatMessage
        teamEvents            = true,   -- TeamChanged
        paths                 = true,   -- _PathStart, _PathTag (10% sample, used for heatmaps)
    },

    -- ── CLIENT EVENTS ─────────────────────────────────────────────────────────
    -- Allows LocalScripts to send events via Rosa:addClientEvent().
    clientEvents = {
        enabled              = true,
        -- Restrict which tags clients are allowed to send.
        -- Remove whitelistedEventTags entirely to allow all tags.
        whitelistedEventTags = { "ButtonPress" },
    },

    -- ── OPTIONAL OVERRIDES ────────────────────────────────────────────────────
    -- Rosa has sensible defaults for all of these. Only uncomment what you need.

    -- Where to record the event position. Defaults to HumanoidRootPart.
    -- getPosition = function(player) return player.Character.PrimaryPart.Position end,

    -- Your game's version string. Defaults to PlaceVersion.
    -- getVersion = function() return "1.0.0" end,

    -- The player's current team, attached to every event. Nil by default.
    -- getTeamName = function(player) return player.Team and player.Team.Name end,

    -- The current map name, attached to every event. Nil by default.
    -- getMapName = function(player) return "Lobby" end,

    -- ── CUSTOM PLAYER DATA ────────────────────────────────────────────────────
    -- Runs before every event is recorded. Return a table of extra fields you
    -- want attached to each event — player stats, progression, flags, anything.
    --
    -- Values must be strings or numbers. Total limit: 500 JSON characters.
    -- Fields set on the event itself (via `custom = { ... }`) win on conflict.
    --
    -- customPlayerDataHook = function(player)
    --     return {
    --       level = getPlayerLevel(player)
    --     }
    -- end,
})

return Rosa
