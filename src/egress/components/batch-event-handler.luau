local HttpService  = game:GetService("HttpService")
local RunService   = game:GetService("RunService")
local Accumulator  = require(script.Parent.accumulator)
local Compressor   = require(script.Parent.compressor)
local Signature    = require(script.Parent.signature)
local ArrayUtils   = require(script.Parent.Parent.utils["array-manipulation"])
local ApiUtils     = require(script.Parent.Parent.utils["api-utils"])
local Constants    = require(script.Parent.Parent.Parent.models.constants)

-- Singleton: only one BatchHandler may exist per server.
local instance = nil

local BatchHandler = {}
BatchHandler.__index = BatchHandler

function BatchHandler.new()
	assert(instance == nil, "Only one instance of BatchHandler is allowed")
	local self = setmetatable({}, BatchHandler)
	self.accumulator  = Accumulator.new()
	self._lastFlushAt = os.clock()
	instance = self

	-- Periodic flush: send whatever has accumulated every 30 seconds.
	RunService.Heartbeat:Connect(function()
		if os.clock() - self._lastFlushAt >= Constants.HEARTBEAT_FLUSH_INTERVAL then
			self:flushIfNonEmpty()
		end
	end)

	-- Flush on server shutdown so in-flight events are not lost.
	game:BindToClose(function()
		self:flushIfNonEmpty()
	end)

	return self
end

function BatchHandler:flushIfNonEmpty()
	local buff = self.accumulator:flushEvents()
	if buffer.len(buff) > 2 then -- more than just "[]"
		self:sendEventBuffer(buff)
	end
end

-- Queues an event. Automatically flushes when the buffer is full.
function BatchHandler:addEvent(event)
	local readyToFlush = self.accumulator:addEvent(event)
	if readyToFlush then
		self:sendEventBuffer(self.accumulator:flushEvents())
	end
end

-- Compresses and sends the buffer. Splits recursively if compression fails.
-- The HTTP send runs in a separate task so it does not block the caller.
function BatchHandler:sendEventBuffer(buff: buffer)
  self._lastFlushAt = os.clock()
	local compressed = Compressor.compress(buff)
	if not compressed then
		self:splitEventsAndFlush(buff)
		return
	end

	local request = {
		Url    = Constants.EVENTS_API_ROUTE,
		Method = "POST",
		Body   = buffer.tostring(compressed),
		Headers = Signature.generateHeader(),
	}

	task.spawn(function()
		local response, attemptCount = ApiUtils.sendRetryHandler(request)
		if not response.Success then
			error(string.format(
				"ROSA API request failed with status %d after %d attempts\n%s\n%s",
				response.StatusCode, attemptCount, response.StatusMessage, response.Body
			))
		end
		if attemptCount > 1 then
			warn(`ROSA API request succeeded after {attemptCount} attempts`)
		end
	end)
end

-- If a batch cannot be compressed under the size limit, split it in half and
-- try each half independently. Recurses until batches are small enough.
function BatchHandler:splitEventsAndFlush(buff: buffer)
	local json   = buffer.readstring(buff, 0, buffer.len(buff))
	local events = HttpService:JSONDecode(json)
	local halfA, halfB = ArrayUtils.splitArrayInHalf(events)
	self:sendEventBuffer(buffer.fromstring(HttpService:JSONEncode(halfA)))
	self:sendEventBuffer(buffer.fromstring(HttpService:JSONEncode(halfB)))
end

return BatchHandler
