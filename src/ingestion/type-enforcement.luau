local HttpService = game:GetService("HttpService")

-- Validates that a fully-built Event table has the correct shape and types.
-- Throws a descriptive error if any field is missing or has the wrong type.
-- custom values must all be string or number, and the field must be ≤ 500 chars when encoded.

local function enforce(event)
	local rawEvent = HttpService:JSONEncode(event)

	if typeof(event) ~= "table" then
		error(`Event is not a table: {rawEvent}`)
	end
	if typeof(event.tag) ~= "string" then
		error(`Event.tag is not a string: {rawEvent}`)
	end
	if typeof(event.position) ~= "table" then
		error(`Event.position is not a table: {rawEvent}`)
	end
	if typeof(event.position.x) ~= "number" then
		error(`Event.position.x is not a number: {rawEvent}`)
	end
	if typeof(event.position.y) ~= "number" then
		error(`Event.position.y is not a number: {rawEvent}`)
	end
	if typeof(event.position.z) ~= "number" then
		error(`Event.position.z is not a number: {rawEvent}`)
	end
	if typeof(event.eventTimeStamp) ~= "number" then
		error(`Event.eventTimeStamp is not a number: {rawEvent}`)
	end
	if typeof(event.sessionID) ~= "string" then
		error(`Event.sessionID is not a string: {rawEvent}`)
	end
	if typeof(event.platform) ~= "string" then
		error(`Event.platform is not a string: {rawEvent}`)
	end

	-- Optional fields
	if event.quantity ~= nil and typeof(event.quantity) ~= "number" then
		error(`Event.quantity is not a number: {rawEvent}`)
	end
	if event.teamId ~= nil and typeof(event.teamId) ~= "string" then
		error(`Event.teamId is not a string: {rawEvent}`)
	end
	if event.mapName ~= nil and typeof(event.mapName) ~= "string" then
		error(`Event.mapName is not a string: {rawEvent}`)
	end
	if event.version ~= nil and typeof(event.version) ~= "string" then
		error(`Event.version is not a string: {rawEvent}`)
	end

	if event.custom ~= nil then
		if typeof(event.custom) ~= "table" then
			error(`Event.custom is not a table: {rawEvent}`)
		end
		if #HttpService:JSONEncode(event.custom) > 500 then
			error(`Event.custom is too large (max 500 encoded chars): {rawEvent}`)
		end
		for key, value in pairs(event.custom) do
			local valueType = typeof(value)
			if valueType ~= "string" and valueType ~= "number" then
				error(`Event.custom.{key} is not a string or number: {rawEvent}`)
			end
		end
	end
end

return {
	enforce = enforce,
}
