-- Shared RNG for jitter (retry backoff, heartbeat flush, blocker probes).
--
-- Seeded per server instance so a fleet of servers booting at the same moment
-- produces INDEPENDENT jitter sequences — that de-sync is the whole point of the
-- jitter, and it only works if each instance draws from a different sequence.
--
-- Uses a dedicated Random object rather than math.randomseed(), which would mutate
-- the global RNG state that the host game may depend on.
--
-- game.JobId is a unique GUID per live server, so its bytes make the seeds distinct
-- even for servers that boot in the same millisecond. os.clock/os.time are folded in
-- as a fallback for Studio, where JobId is an empty string.

-- Folds jobId's bytes and the clock reading into a single seed in [0, 2147483647).
-- Pulled out as a pure function so the distinctness/range properties are testable
-- without depending on module-load-time globals.
local function computeSeed(jobId: string, time: number, clockMicros: number): number
	local seed = time
	for i = 1, #jobId do
		seed = (seed * 31 + string.byte(jobId, i)) % 2147483647
	end
	seed = (seed + clockMicros) % 2147483647
	return seed
end

local jobId = game.JobId or ""
local seed  = computeSeed(jobId, os.time(), math.floor(os.clock() * 1e6))
local generator = Random.new(seed)

return {
	-- Returns a float in [0, 1), matching math.random().
	next = function(): number
		return generator:NextNumber()
	end,
	computeSeed = computeSeed,
}
