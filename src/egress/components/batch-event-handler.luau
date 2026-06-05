local HttpService  = game:GetService("HttpService")
local RunService   = game:GetService("RunService")
local Accumulator  = require(script.Parent.accumulator)
local Compressor   = require(script.Parent.compressor)
local Signature    = require(script.Parent.signature)
local ArrayUtils   = require(script.Parent.Parent.utils["array-manipulation"])
local ApiUtils     = require(script.Parent.Parent.utils["api-utils"])
local QuotaGate    = require(script.Parent["quota-gate"])
local Constants    = require(script.Parent.Parent.Parent.models.constants)

local instance = nil

local BatchHandler = {}
BatchHandler.__index = BatchHandler

function BatchHandler.new()
	assert(instance == nil, "Only one instance of BatchHandler is allowed")
	local self = setmetatable({}, BatchHandler)
	self.accumulator  = Accumulator.new()
	self.quotaGate    = QuotaGate.new()
	self._lastFlushAt = os.clock()
	instance = self

	RunService.Heartbeat:Connect(function()
		if os.clock() - self._lastFlushAt >= Constants.HEARTBEAT_FLUSH_INTERVAL then
			self._lastFlushAt = os.clock()
			if not self.quotaGate:isBlocked() then
				self:flushIfNonEmpty()
			end
		end
	end)

	game:BindToClose(function()
		self:flushIfNonEmpty()
	end)

	return self
end

function BatchHandler:flushIfNonEmpty()
	local buff = self.accumulator:flushEvents()
	if buffer.len(buff) > 2 then
		self:sendEventBuffer(buff)
	end
end

function BatchHandler:addEvent(event)
	if self.quotaGate:isBlocked() then return end
	local readyToFlush = self.accumulator:addEvent(event)
	if readyToFlush then
		self:sendEventBuffer(self.accumulator:flushEvents())
	end
end

function BatchHandler:sendEventBuffer(buff: buffer)
	local compressed = Compressor.compress(buff)
	if not compressed then
		self:splitEventsAndFlush(buff)
		return
	end

	local request = {
		Url     = Constants.EVENTS_API_ROUTE,
		Method  = "POST",
		Body    = buffer.tostring(compressed),
		Headers = Signature.generateHeader(),
	}

	task.spawn(function()
		local response, attemptCount = ApiUtils.sendRetryHandler(request)
		if not response.Success then
			if response.StatusCode == 403 then
				self.quotaGate:onQuotaExceeded()
				return
			end
			error(string.format(
				"ROSA API request failed with status %d after %d attempts\n%s\n%s",
				response.StatusCode, attemptCount, response.StatusMessage, response.Body
			))
		end
		self.quotaGate:onSuccess()
		if attemptCount > 1 then
			warn(`ROSA API request succeeded after {attemptCount} attempts`)
		end
	end)
end

function BatchHandler:splitEventsAndFlush(buff: buffer)
	local json   = buffer.readstring(buff, 0, buffer.len(buff))
	local events = HttpService:JSONDecode(json)
	local halfA, halfB = ArrayUtils.splitArrayInHalf(events)
	self:sendEventBuffer(buffer.fromstring(HttpService:JSONEncode(halfA)))
	self:sendEventBuffer(buffer.fromstring(HttpService:JSONEncode(halfB)))
end

return BatchHandler
