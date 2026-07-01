local DefaultHttpService    = game:GetService("HttpService")
local SessionManager        = require(script.Parent["session-manager"])
local PlayerPlatformManager = require(script.Parent["player-platform-manager"])
local Helpers               = require(script.Parent.Parent.utils.helpers)
local Types                 = require(script.Parent.types)

-- Builds a complete Event table from a lightweight EventRequest.
-- Resolves position, platform, session ID, and version automatically.
-- NOTE: buildEvent yields the calling coroutine while waiting for platform detection.

local CLOCK_ORIGIN = os.time()
local CLOCK_START  = os.clock()

local function timeMs()
	return math.floor((CLOCK_ORIGIN + (os.clock() - CLOCK_START)) * 1000)
end

local EventBuilder = {}
EventBuilder.__index = EventBuilder

-- _services (HttpService, sessionManager, platformManager, getPlaceVersion) is for
-- tests; production callers omit it and get the real Roblox-backed dependencies.
function EventBuilder.new(config, _services)
	local self = setmetatable({}, EventBuilder)
	self.config          = config
	self.httpService     = (_services and _services.HttpService)     or DefaultHttpService
	self.sessionManager  = (_services and _services.sessionManager)  or SessionManager.new()
	self.platformManager = (_services and _services.platformManager) or PlayerPlatformManager.new()
	self.getPlaceVersion = (_services and _services.getPlaceVersion) or function() return tostring(game.PlaceVersion) end
	return self
end

-- May yield while waiting for the client to report their platform.
-- Call this from inside a task.spawn'd coroutine.
function EventBuilder:buildEvent(player: Player, eventRequest: Types.EventRequest)
	local rawPos = eventRequest.position or self.config.getPosition(player)
	if not rawPos then return nil end
	local position = Helpers.vector3ToPosition(rawPos)

	local platform = self.platformManager:getPlatform(player) -- yields if not cached

	local version
	if self.config.getVersion then
		version = self.config.getVersion()
	else
		version = self.getPlaceVersion()
	end

	return {
		eventId        = self.httpService:GenerateGUID(false),
		eventTimeStamp = timeMs(),
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
