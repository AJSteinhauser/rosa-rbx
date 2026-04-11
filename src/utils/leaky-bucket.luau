-- Token bucket rate limiter.
-- Tracks a "level" that fills as events are added and drains over time.
-- If adding a new event would exceed capacity, the event is rejected.

local LeakyBucket = {}
LeakyBucket.__index = LeakyBucket

function LeakyBucket.new(capacity: number, leakRatePerSec: number)
	local self = setmetatable({}, LeakyBucket)
	self.capacity = capacity
	self.leakRatePerSec = leakRatePerSec
	self.level = 0
	self.lastTime = os.clock()
	return self
end

function LeakyBucket:leak(now: number)
	local elapsed = math.max(0, now - self.lastTime)
	local leaked = elapsed * self.leakRatePerSec
	self.level = math.max(0, self.level - leaked)
	self.lastTime = now
end

-- Returns true if the event is allowed, false if rate limited.
-- cost defaults to 1, now defaults to os.clock()
function LeakyBucket:allow(cost: number?, now: number?): boolean
	cost = cost or 1
	now = now or os.clock()
	assert(cost > 0, "Cost must be positive")

	self:leak(now)

	if self.level + cost > self.capacity then
		return false
	end

	self.level += cost
	return true
end

function LeakyBucket:getLevel(now: number?): number
	self:leak(now or os.clock())
	return self.level
end

return LeakyBucket
