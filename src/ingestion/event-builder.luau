local HttpService           = game:GetService("HttpService")
local SessionManager        = require(script.Parent["session-manager"])
local PlayerPlatformManager = require(script.Parent["player-platform-manager"])
local Helpers               = require(script.Parent.Parent.utils.helpers)

-- Builds a complete Event table from a lightweight EventRequest.
-- Resolves position, platform, session ID, and version automatically.
-- NOTE: buildEvent yields the calling coroutine while waiting for platform detection.

local EventBuilder = {}
EventBuilder.__index = EventBuilder

function EventBuilder.new(config)
	local self = setmetatable({}, EventBuilder)
	self.config          = config
	self.sessionManager  = SessionManager.new()
	self.platformManager = PlayerPlatformManager.new()
	return self
end

-- May yield while waiting for the client to report their platform.
-- Call this from inside a task.spawn'd coroutine.
function EventBuilder:buildEvent(player: Player, eventRequest)
	local rawPos = eventRequest.position or self.config.getPosition(player)
	if not rawPos then return nil end
	local position = Helpers.vector3ToPosition(rawPos)

	local platform = self.platformManager:getPlatform(player) -- yields if not cached

	local version
	if self.config.getVersion then
		version = self.config.getVersion()
	else
		version = tostring(game.PlaceVersion)
	end

	return {
		eventId        = HttpService:GenerateGUID(false),
		eventTimeStamp = os.time(),
		sessionID      = self.sessionManager:getSessionId(player),
		tag            = eventRequest.tag,
		platform       = typeof(platform) == "EnumItem" and platform.Name or tostring(platform),
		position       = position,
		version        = version,
		teamId         = self.config.getTeamName and self.config.getTeamName(player) or nil,
		mapName        = self.config.getMapName and self.config.getMapName(player) or nil,
		quantity       = eventRequest.quantity,
		custom         = eventRequest.custom,
	}
end

return EventBuilder
