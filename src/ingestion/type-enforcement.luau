local HttpService = game:GetService("HttpService")
local Constants   = require(script.Parent.Parent.models.constants)
local Logger      = require(script.Parent.Parent.utils.logger)

-- Validates that a fully-built Event table has the correct shape and types.
-- Throws a descriptive error if any field is missing or has the wrong type.
-- custom values must all be string or number, and the field must be ≤ 500 chars when encoded.

local function enforce(event)
	local rawEvent = HttpService:JSONEncode(event)

	if typeof(event) ~= "table" then
		Logger.error(`Event is not a table: {rawEvent}`)
	end
	if typeof(event.tag) ~= "string" then
		Logger.error(`Event.tag is not a string: {rawEvent}`)
	end
	if typeof(event.position) ~= "table" then
		Logger.error(`Event.position is not a table: {rawEvent}`)
	end
	if typeof(event.position.x) ~= "number" then
		Logger.error(`Event.position.x is not a number: {rawEvent}`)
	end
	if typeof(event.position.y) ~= "number" then
		Logger.error(`Event.position.y is not a number: {rawEvent}`)
	end
	if typeof(event.position.z) ~= "number" then
		Logger.error(`Event.position.z is not a number: {rawEvent}`)
	end
	if typeof(event.eventTimeStamp) ~= "number" then
		Logger.error(`Event.eventTimeStamp is not a number: {rawEvent}`)
	end
	if typeof(event.sessionID) ~= "string" then
		Logger.error(`Event.sessionID is not a string: {rawEvent}`)
	end
	if typeof(event.platform) ~= "string" then
		Logger.error(`Event.platform is not a string: {rawEvent}`)
	end

	-- Optional fields
	if event.quantity ~= nil and typeof(event.quantity) ~= "number" then
		Logger.error(`Event.quantity is not a number: {rawEvent}`)
	end
	if event.teamId ~= nil and typeof(event.teamId) ~= "string" then
		Logger.error(`Event.teamId is not a string: {rawEvent}`)
	end
	if event.mapName ~= nil and typeof(event.mapName) ~= "string" then
		Logger.error(`Event.mapName is not a string: {rawEvent}`)
	end
	if event.version ~= nil and typeof(event.version) ~= "string" then
		Logger.error(`Event.version is not a string: {rawEvent}`)
	end

	if event.custom ~= nil then
		if typeof(event.custom) ~= "table" then
			Logger.error(`Event.custom is not a table: {rawEvent}`)
		end
		if #HttpService:JSONEncode(event.custom) > Constants.CUSTOM_FIELD_MAX_ENCODED_SIZE then
			Logger.error(`Event.custom is too large (max {Constants.CUSTOM_FIELD_MAX_ENCODED_SIZE} encoded chars): {rawEvent}`)
		end
		for key, value in pairs(event.custom) do
			local valueType = typeof(value)
			if valueType ~= "string" and valueType ~= "number" then
				Logger.error(`Event.custom.{key} is not a string or number: {rawEvent}`)
			end
		end
	end
end

return {
	enforce = enforce,
}
