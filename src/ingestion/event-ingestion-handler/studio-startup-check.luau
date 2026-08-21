-- Runs once per Studio playtest to catch the two most common "why aren't my
-- events showing up" setups: HTTP requests disabled, the ROSA_API_KEY secret
-- missing from Studio's own settings, and Rosa never required from a LocalScript.
local Constants = require(script.Parent.Parent.Parent.models.constants)
local Logger    = require(script.Parent.Parent.Parent.utils.logger)

local CLIENT_CHECKIN_TIMEOUT_SECONDS = 5

local HANDSHAKE_TAG = "___RosaStudioHandshake___"

local function runServerChecks(self, httpService)
	if Constants.DEV_MODE then
		Logger.warn(`Rosa is pointed at a local dev API ({Constants.EVENTS_API_ROUTE}) because DEV_MODE is enabled in models/constants.luau. Events will NOT reach the production dashboard while this is on.`)
	end

	if httpService.HttpEnabled == false then
		Logger.warn("HTTP Requests are disabled for this place. Rosa cannot send events. Enable them via Game Settings > Security > Allow HTTP Requests.")
	end

	if self.logStudioEvents then
		local ok, secretOrErr = pcall(function()
			return httpService:GetSecret(Constants.SECRETS_KEY_LOOKUP)
		end)
		if not ok or not secretOrErr then
			Logger.warn("ROSA_API_KEY secret not found for Studio. logStudioEvents = true requires its own copy of the secret under Studio's settings (Game Settings > Security > Secrets), separate from the published game's secret. Details: " .. tostring(secretOrErr))
		end
	end

	task.delay(CLIENT_CHECKIN_TIMEOUT_SECONDS, function()
		if not self.studioClientCheckedIn then
			Logger.warn("No client check-in received. Make sure Rosa is required from a LocalScript as well as a ServerScript, or client-side events (ButtonPress, platform detection, etc.) won't be tracked.")
		end
	end)
end

local function registerClientCheckin(self)
	self.studioClientCheckedIn = true
end

local function runClientCheck(self)
	self.clientEventStream:FireServer({ tag = HANDSHAKE_TAG })
end

return {
	HANDSHAKE_TAG          = HANDSHAKE_TAG,
	runServerChecks        = runServerChecks,
	registerClientCheckin  = registerClientCheckin,
	runClientCheck         = runClientCheck,
}
