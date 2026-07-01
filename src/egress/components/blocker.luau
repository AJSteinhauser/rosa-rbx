local DEFAULT_PROBE_INTERVAL = 30 * 60
local BACKOFF_MULTIPLIER     = 2 -- probe interval doubles on each consecutive failed probe

local Blocker = {}
Blocker.__index = Blocker

-- maxInterval caps the backoff growth. Defaults to baseInterval (no growth) so
-- existing callers that don't pass one keep the old fixed-interval behavior.
-- jitterFraction (0..1) de-syncs a fleet by shortening each wait by up to that
-- fraction; defaults to 0 (deterministic). random is injectable for tests.
function Blocker.new(label, baseInterval, getTime, maxInterval, jitterFraction, random)
	local self = setmetatable({}, Blocker)
	self._label          = label or "unknown"
	self._baseInterval   = baseInterval or DEFAULT_PROBE_INTERVAL
	self._maxInterval    = maxInterval or self._baseInterval
	self._getTime        = getTime or os.clock
	self._jitterFraction = jitterFraction or 0
	self._random         = random or math.random
	self._blocked        = false
	self._hitAt          = 0
	self._attemptCount   = 0
	self._probeInterval  = self._baseInterval
	return self
end

function Blocker:isBlocked()
	if not self._blocked then return false end
	return (self._getTime() - self._hitAt) < self._probeInterval
end

-- Called each time a probe (request made while unblocked) fails. Consecutive
-- failures grow the wait exponentially, capped at maxInterval, with jitter to
-- spread the fleet. retryAfterSeconds (from a server Retry-After header) acts as
-- a floor: we never probe sooner than the server asked, honored up to maxInterval.
function Blocker:onBlocked(retryAfterSeconds)
	if not self._blocked then
		warn(string.format("ROSA [%s]: blocked. Events discarded until resolved.", self._label))
	end
	self._attemptCount += 1

	local interval = math.min(
		self._baseInterval * (BACKOFF_MULTIPLIER ^ (self._attemptCount - 1)),
		self._maxInterval
	)
	if self._jitterFraction > 0 then
		interval = interval * (1 - self._jitterFraction * self._random())
	end
	if retryAfterSeconds and retryAfterSeconds > 0 then
		interval = math.max(interval, math.min(retryAfterSeconds, self._maxInterval))
	end

	self._probeInterval = interval
	self._blocked = true
	self._hitAt   = self._getTime()
end

function Blocker:onSuccess()
	if self._blocked then
		self._blocked = false
		warn(string.format("ROSA [%s]: resolved. Resuming event ingestion.", self._label))
	end
	self._attemptCount  = 0
	self._probeInterval = self._baseInterval
end

return Blocker
