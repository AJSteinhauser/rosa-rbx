local HttpService  = game:GetService("HttpService")
local RunService   = game:GetService("RunService")
local Accumulator  = require(script.Parent.accumulator)
local Compressor   = require(script.Parent.compressor)
local Signature    = require(script.Parent.signature)
local ArrayUtils   = require(script.Parent.Parent.utils["array-manipulation"])
local ApiUtils     = require(script.Parent.Parent.utils["api-utils"])
local Blocker      = require(script.Parent["blocker"])
local Constants    = require(script.Parent.Parent.Parent.models.constants)
local Rng          = require(script.Parent.Parent.Parent.utils.rng)
local Logger       = require(script.Parent.Parent.Parent.utils.logger)

local instance = nil

local BatchHandler = {}
BatchHandler.__index = BatchHandler

function BatchHandler.getInstance()
	return instance
end

-- Parses a Retry-After header into seconds. Only the delta-seconds form is
-- supported; the HTTP-date form falls back to nil (exponential backoff takes over).
local function parseRetryAfter(response): number?
	local headers = response.Headers
	if not headers then return nil end
	local raw = headers["retry-after"] or headers["Retry-After"]
	if not raw then return nil end
	local seconds = tonumber(raw)
	if seconds and seconds > 0 then return seconds end
	return nil
end

-- Heartbeat flush interval with jitter, so fleets that boot together (e.g. after a
-- game update) don't align their flushes into synchronized traffic spikes.
local function jitteredFlushInterval(): number
	local base = Constants.HEARTBEAT_FLUSH_INTERVAL
	return base * (1 - Constants.HEARTBEAT_FLUSH_JITTER * Rng.next())
end

function BatchHandler.new()
	assert(instance == nil, "Only one instance of BatchHandler is allowed")
	local self = setmetatable({}, BatchHandler)
	self.accumulator      = Accumulator.new()
	self.quotaBlocker     = Blocker.new("quota", Constants.QUOTA_BLOCKER_INTERVAL, nil, Constants.QUOTA_BLOCKER_MAX_INTERVAL, Constants.BLOCKER_JITTER, Rng.next)
	self.authBlocker      = Blocker.new("auth",  Constants.AUTH_BLOCKER_INTERVAL,  nil, Constants.AUTH_BLOCKER_MAX_INTERVAL,  Constants.BLOCKER_JITTER, Rng.next)
	self.rateLimitBlocker = Blocker.new("rate-limit", Constants.RATE_LIMIT_BLOCKER_INTERVAL, nil, Constants.RATE_LIMIT_BLOCKER_MAX_INTERVAL, Constants.BLOCKER_JITTER, Rng.next)
	self.serverBlocker    = Blocker.new("server", Constants.SERVER_BLOCKER_INTERVAL, nil, Constants.SERVER_BLOCKER_MAX_INTERVAL, Constants.BLOCKER_JITTER, Rng.next)
	-- Random initial phase spreads the very first flush of a boot-aligned fleet
	-- uniformly across the interval instead of firing them all at once.
	self._lastFlushAt   = os.clock()
	self._flushInterval = Constants.HEARTBEAT_FLUSH_INTERVAL * Rng.next()
	instance = self

	RunService.Heartbeat:Connect(function()
		if os.clock() - self._lastFlushAt >= self._flushInterval then
			self._lastFlushAt   = os.clock()
			self._flushInterval = jitteredFlushInterval()
			if not self:isSendingBlocked() then
				self:flushIfNonEmpty()
			end
		end
	end)

	game:BindToClose(function()
		-- Must block until the request actually completes: task.spawn would let this
		-- callback return immediately, and Roblox tears the server down right after,
		-- killing the in-flight request before it lands.
		self:flushIfNonEmpty(true)
	end)

	return self
end

-- True when any blocker is active (quota, auth, rate-limit, or server-unhealthy).
function BatchHandler:isSendingBlocked(): boolean
	return self.quotaBlocker:isBlocked()
		or self.authBlocker:isBlocked()
		or self.rateLimitBlocker:isBlocked()
		or self.serverBlocker:isBlocked()
end

function BatchHandler:flushIfNonEmpty(sync: boolean?)
	local buff = self.accumulator:flushEvents()
	if buffer.len(buff) > 2 then
		self:sendEventBuffer(buff, sync)
	elseif sync then
		Logger.info("BindToClose flush: nothing queued, nothing to send.")
	end
end

function BatchHandler:addEvent(event)
	if self:isSendingBlocked() then return end
	local readyToFlush = self.accumulator:addEvent(event)
	if readyToFlush then
		self:sendEventBuffer(self.accumulator:flushEvents())
	end
end

-- sync (used only by the game:BindToClose shutdown flush) sends inline instead of via
-- task.spawn, so the caller actually waits for the request to land before returning.
function BatchHandler:sendEventBuffer(buff: buffer, sync: boolean?)
	local compressed = Compressor.compress(buff)
	if not compressed then
		self:splitEventsAndFlush(buff, sync)
		return
	end

	local eventCount = #HttpService:JSONDecode(buffer.tostring(buff))
	Logger.info(string.format("Flushing %d events (%d bytes) to Rosa", eventCount, buffer.len(compressed)))

	local request = {
		Url     = Constants.EVENTS_API_ROUTE,
		Method  = "POST",
		Body    = buffer.tostring(compressed),
		Headers = Signature.generateHeader(),
	}

	local function send()
		local response, attemptCount = ApiUtils.sendRetryHandler(request)
		if not response.Success then
			local code = response.StatusCode
			if code == 403 then
				self.quotaBlocker:onBlocked()
			elseif code == 401 then
				self.authBlocker:onBlocked()
			elseif code == 429 then
				self.rateLimitBlocker:onBlocked(parseRetryAfter(response))
			elseif code >= 500 then
				self.serverBlocker:onBlocked(parseRetryAfter(response))
			else
				Logger.warn(string.format(
					"API request failed with status %d after %d attempts\n%s\n%s",
					code, attemptCount, response.StatusMessage, response.Body
				))
			end
			return
		end
		-- A successful send means the instance is healthy again; clear every blocker.
		self.quotaBlocker:onSuccess()
		self.authBlocker:onSuccess()
		self.rateLimitBlocker:onSuccess()
		self.serverBlocker:onSuccess()
		if attemptCount > 1 then
			Logger.warn(`API request succeeded after {attemptCount} attempts`)
		end
	end

	if sync then
		send()
	else
		task.spawn(send)
	end
end

function BatchHandler:splitEventsAndFlush(buff: buffer, sync: boolean?)
	local json   = buffer.readstring(buff, 0, buffer.len(buff))
	local events = HttpService:JSONDecode(json)
	local halfA, halfB = ArrayUtils.splitArrayInHalf(events)
	self:sendEventBuffer(buffer.fromstring(HttpService:JSONEncode(halfA)), sync)
	self:sendEventBuffer(buffer.fromstring(HttpService:JSONEncode(halfB)), sync)
end

return BatchHandler
