-- Default metrics that most games will want.
-- Grouped by type; each group can be disabled via config.defaultMetrics.
--
-- Server groups:
--   playerEvents       — PlayerJoin, PlayerLeave (quantity = sessionDuration)
--   characterEvents    — CharacterSpawn, CharacterDeath
--   paths              — _PathStart + _PathTag (10% sample; triggers: 10 studs, 35° turn, 4s fallback)
--   proximityEvents    — PromptTriggered (any ProximityPrompt activation)
--   toolEvents         — ToolEquipped, ToolActivated
--   damageEvents       — DamageTaken (quantity = damage; custom.healthPct)
--   idleDetection      — PlayerIdle (quantity = idleDuration; tune with idleThresholdSeconds)
--   marketplaceEvents  — ProductPurchased, ProductDeclined, GamePassPurchased, GamePassDeclined
--   chatEvents         — ChatMessage
--   teamEvents         — TeamChanged
--   jumpEvents         — PlayerJump
--
-- Client groups (run in LocalScript context):
--   clientPerformance  — FpsSample (quantity = fps; every 30s; off by default)
--   settingsEvents     — SettingsOpened
--
-- All groups default to enabled unless noted. Set a group to false to disable:
--   defaultMetrics = { characterEvents = false }

local setupPlayerEvents    = require(script["player-events"])
local setupCharacterEvents = require(script["character-events"])
local setupPaths           = require(script["paths"])
local setupProximityEvents = require(script["proximity-events"])
local setupToolEvents      = require(script["tool-events"])
local setupDamageEvents    = require(script["damage-events"])
local setupIdleDetection   = require(script["idle-detection"])
local setupMarketplace     = require(script["marketplace-events"])
local setupChatEvents      = require(script["chat-events"])
local setupTeamEvents      = require(script["team-events"])
local setupJumpEvents      = require(script["jump-events"])
local setupClientPerf      = require(script["client-performance"])
local setupSettingsEvents  = require(script["settings-events"])

local DefaultMetrics = {}

function DefaultMetrics.setup(handler, config, userConfig, _services)
	if config.playerEvents ~= false then
		setupPlayerEvents(handler, _services)
	end
	if config.characterEvents ~= false then
		setupCharacterEvents(handler, _services)
	end
	if config.paths ~= false then
		setupPaths(handler, userConfig or {})
	end
	if config.proximityEvents ~= false then
		setupProximityEvents(handler, _services)
	end
	if config.toolEvents ~= false then
		setupToolEvents(handler, _services)
	end
	if config.damageEvents ~= false then
		setupDamageEvents(handler, _services)
	end
	if config.idleDetection ~= false then
		setupIdleDetection(handler, userConfig or {}, _services)
	end
	if config.marketplaceEvents ~= false then
		setupMarketplace(handler, _services)
	end
	if config.chatEvents ~= false then
		setupChatEvents(handler, _services)
	end
	if config.teamEvents ~= false then
		setupTeamEvents(handler, _services)
	end
	if config.jumpEvents ~= false then
		setupJumpEvents(handler, _services)
	end

	-- Register client-side default metric tags so they pass through the whitelist
	-- even when the user has whitelistedEventTags configured.
	if config.settingsEvents ~= false then
		handler:allowClientTag("SettingsOpened")
	end
	if config.clientPerformance == true then
		handler:allowClientTag("FpsSample")
	end
end

function DefaultMetrics.setupClient(handler, config, _services)
	if config.clientPerformance == true then
		setupClientPerf(handler, _services)
	end
	if config.settingsEvents ~= false then
		setupSettingsEvents(handler, _services)
	end
end

return DefaultMetrics
