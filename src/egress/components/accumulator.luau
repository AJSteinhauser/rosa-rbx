local HttpService   = game:GetService("HttpService")
local LeakyBucket   = require(script.Parent.Parent.Parent.utils["leaky-bucket"])
local ScalingBuffer = require(script.Parent.Parent.Parent.utils["scaling-buffer"])
local Constants     = require(script.Parent.Parent.models.constants)

-- Accumulates JSON-encoded events into a single buffer, rate-limiting per session.
-- The buffer grows until it reaches BODY_OVERSHOOT_TARGET, then signals a flush.

local Accumulator = {}
Accumulator.__index = Accumulator

function Accumulator.new()
	local self = setmetatable({}, Accumulator)
	self.playerBuckets = {}
	self:initBuffer()
	return self
end

function Accumulator:initBuffer()
	self.dataBuffer = ScalingBuffer.new()
	self.dataBuffer:push_string("[")
	self.isEmpty = true
end

function Accumulator:getOrCreateBucket(sessionId: string)
	local bucket = self.playerBuckets[sessionId]
	if not bucket then
		bucket = LeakyBucket.new(Constants.ACCUMULATOR_BUCKET_SIZE, Constants.ACCUMULATOR_LEAK_PER_SECOND)
		self.playerBuckets[sessionId] = bucket
	end
	return bucket
end

-- Adds an event to the buffer. Returns true when the buffer is ready to flush.
function Accumulator:addEvent(event): boolean
	local bucket = self:getOrCreateBucket(event.sessionID)
	if not bucket:allow() then
		warn(`Player {event.sessionID} is rate limited.`)
		return false
	end
	-- Comma separates events; first event gets none so the array is valid JSON
	local encoded = HttpService:JSONEncode(event)
	if self.isEmpty then
		self.dataBuffer:push_string(encoded)
		self.isEmpty = false
	else
		self.dataBuffer:push_string("," .. encoded)
	end
	return self.dataBuffer:size() >= Constants.BODY_OVERSHOOT_TARGET
end

-- Closes the JSON array, returns the buffer, and resets for the next batch.
function Accumulator:flushEvents(): buffer
	self.dataBuffer:push_string("]")
	local result = self.dataBuffer:getBuffer()
	self:initBuffer()
	return result
end

return Accumulator
