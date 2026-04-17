-- Default metrics that most games will want.
-- Grouped by type; each group can be disabled via config.defaultMetrics.
--
-- Groups:
--   playerEvents    — PlayerJoin, PlayerLeave (with sessionDuration)
--   characterEvents — CharacterSpawn, CharacterDeath
--   paths           — PathStart + PathTag (10% sample; triggers: 10 studs, 35° turn, 4s fallback)
--
-- All groups default to enabled. Set a group to false to disable:
--   defaultMetrics = { characterEvents = false }

local setupPlayerEvents    = require(script["player-events"])
local setupCharacterEvents = require(script["character-events"])
local setupPaths           = require(script["paths"])

local DefaultMetrics = {}

function DefaultMetrics.setup(handler, config, userConfig)
	if config.playerEvents ~= false then
		setupPlayerEvents(handler)
	end
	if config.characterEvents ~= false then
		setupCharacterEvents(handler)
	end
	if config.paths ~= false then
		setupPaths(handler, userConfig or {})
	end
end

return DefaultMetrics
