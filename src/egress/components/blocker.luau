local DEFAULT_PROBE_INTERVAL = 30 * 60

local Blocker = {}
Blocker.__index = Blocker

function Blocker.new(label, probeInterval, getTime)
	local self = setmetatable({}, Blocker)
	self._label         = label or "unknown"
	self._probeInterval = probeInterval or DEFAULT_PROBE_INTERVAL
	self._getTime       = getTime or os.clock
	self._blocked       = false
	self._hitAt         = 0
	return self
end

function Blocker:isBlocked()
	if not self._blocked then return false end
	return (self._getTime() - self._hitAt) < self._probeInterval
end

function Blocker:onBlocked()
	if not self._blocked then
		warn(string.format("ROSA [%s]: blocked. Events discarded until resolved.", self._label))
	end
	self._blocked = true
	self._hitAt   = self._getTime()
end

function Blocker:onSuccess()
	if self._blocked then
		self._blocked = false
		warn(string.format("ROSA [%s]: resolved. Resuming event ingestion.", self._label))
	end
end

return Blocker
