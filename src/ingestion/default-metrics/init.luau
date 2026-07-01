-- Default metrics that most games will want.
-- Grouped by type; each group can be disabled via config.defaultMetrics.
--
-- Server groups:
--   playerEvents         — PlayerJoin, PlayerLeave (quantity = sessionDuration)
--   characterEvents      — CharacterSpawn, CharacterDeath
--   humanoidStateEvents  — HumanoidStateChange (custom.state: Landed/Freefall/Climbing/Swimming/Seated)
--   paths                — _PathStart + _PathTag (5% sample; triggers: 25 studs, 45° turn)
--   proximityEvents      — PromptTriggered (any ProximityPrompt activation)
--   toolEvents           — ToolEquipped, ToolActivated
--   damageEvents         — DamageTaken (quantity = damage; custom.healthPct)
--   idleDetection        — PlayerIdle (quantity = idleDuration; tune with idleThresholdSeconds)
--   marketplaceEvents    — ProductPurchased, ProductDeclined, GamePassPurchased, GamePassDeclined
--   chatEvents           — ChatMessage
--   teamEvents           — TeamChanged (teamId = new team name)
--   jumpEvents           — PlayerJump (disabled by default; noisy, low value — opt in with jumpEvents = true)
--
-- Client groups (run in LocalScript context):
--   proximityPromptShown — ProximityPromptShown (custom.promptName, distanceToPrompt, inputType; position)
--   inputMethodChanged   — InputMethodChanged (custom.fromInput, custom.toInput; position)
--   settingsEvents       — SettingsOpened
--
-- All groups default to enabled unless noted. Set a group to false to disable:
--   defaultMetrics = { characterEvents = false }
-- jumpEvents is opt-in: defaultMetrics = { jumpEvents = true }

local setupPlayerEvents        = require(script["player-events"])
local setupCharacterEvents     = require(script["character-events"])
local setupHumanoidStateEvents = require(script["humanoid-state-events"])
local setupPaths               = require(script["paths"])
local setupProximityEvents     = require(script["proximity-events"])
local setupToolEvents          = require(script["tool-events"])
local setupDamageEvents        = require(script["damage-events"])
local setupIdleDetection       = require(script["idle-detection"])
local setupMarketplace         = require(script["marketplace-events"])
local setupChatEvents          = require(script["chat-events"])
local setupTeamEvents          = require(script["team-events"])
local setupJumpEvents          = require(script["jump-events"])
local setupProximityPromptShown = require(script["proximity-prompt-shown"])
local setupInputMethodChanged  = require(script["input-method-changed"])
local setupSettingsEvents      = require(script["settings-events"])

local DefaultMetrics = {}

function DefaultMetrics.setup(handler, config, userConfig, _services)
	if config.playerEvents ~= false then
		setupPlayerEvents(handler, _services)
	end
	if config.characterEvents ~= false then
		setupCharacterEvents(handler, _services)
	end
	if config.humanoidStateEvents ~= false then
		setupHumanoidStateEvents(handler, _services)
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
	if config.jumpEvents == true then
		setupJumpEvents(handler, _services)
	end

	if config.proximityPromptShown ~= false then
		handler:allowClientTag("ProximityPromptShown")
	end
	if config.inputMethodChanged ~= false then
		handler:allowClientTag("InputMethodChanged")
	end
	if config.settingsEvents ~= false then
		handler:allowClientTag("SettingsOpened")
	end
end

function DefaultMetrics.setupClient(handler, config, _services)
	if config.proximityPromptShown ~= false then
		setupProximityPromptShown(handler, _services)
	end
	if config.inputMethodChanged ~= false then
		setupInputMethodChanged(handler, _services)
	end
	if config.settingsEvents ~= false then
		setupSettingsEvents(handler, _services)
	end
end

return DefaultMetrics
