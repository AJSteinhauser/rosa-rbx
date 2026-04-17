-- Rosa RBX Pipeline
-- Analytics event pipeline for Roblox games.
--
-- Require this module from BOTH a ServerScript and a LocalScript.
-- The module detects the runtime context automatically.
-- All requirers share the same instance (Roblox module caching).
--
-- Add your Rosa API key to Roblox secrets under the name "ROSA-API-KEY".
--
-- SERVER SCRIPT:
--   local Rosa = require(path.to.Rosa)
--   Rosa:addServerEvent(player, { tag = "PlayerKill", quantity = 1, custom = { weapon = "Sword" } })
--
-- LOCAL SCRIPT:
--   local Rosa = require(path.to.Rosa)
--   Rosa:addClientEvent({ tag = "ItemPickup", quantity = 1, custom = { item = "Potion" } })

return require(script.ingestion["event-ingestion-handler"]).new({
    -- Default metrics — fires common events automatically. Set a group to false to disable.
    defaultMetrics = {
        playerEvents    = true, -- PlayerJoin, PlayerLeave (with sessionDuration)
        characterEvents = true, -- CharacterSpawn, CharacterDeath
    },

    -- Client-side events forwarded from LocalScripts.
    clientEvents = {
        enabled              = true,
        whitelistedEventTags = { "ItemPickup", "PlayerDeath" }, -- optional, remove to allow all tags
    },

    -- Optional overrides (all have sensible defaults):
    -- getPosition = function(player) return player.Character.PrimaryPart.Position end,
    -- getVersion  = function() return "1.2.0" end,
    -- getTeamName = function(player) return player.Team and player.Team.Name end,
    -- getMapName  = function(player) return "Lobby" end,
})
