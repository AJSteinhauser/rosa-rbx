local DEFAULT_PROBE_INTERVAL = 30 * 60

local QuotaGate = {}
QuotaGate.__index = QuotaGate

function QuotaGate.new(getTime, probeInterval)
	local self = setmetatable({}, QuotaGate)
	self._getTime       = getTime or os.clock
	self._probeInterval = probeInterval or DEFAULT_PROBE_INTERVAL
	self._exceeded      = false
	self._hitAt         = 0
	return self
end

function QuotaGate:isBlocked()
	if not self._exceeded then return false end
	return (self._getTime() - self._hitAt) < self._probeInterval
end

function QuotaGate:onQuotaExceeded()
	if not self._exceeded then
		warn("ROSA: quota exceeded (403). Events will be discarded until quota is restored.")
	end
	self._exceeded = true
	self._hitAt    = self._getTime()
end

function QuotaGate:onSuccess()
	if self._exceeded then
		self._exceeded = false
		warn("ROSA: quota restored. Resuming event ingestion.")
	end
end

return QuotaGate
