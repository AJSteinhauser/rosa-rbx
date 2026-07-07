local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService         = game:GetService("RunService")
local Constants          = require(script.Parent.constants)
local Logger             = require(script.Parent.Parent.utils.logger)
local backoffSeconds     = require(script.Parent.backoff)
local JobId              = require(script.Parent.Parent.utils["job-id"])

local LeaderElection = {}
LeaderElection.__index = LeaderElection

-- Studio never participates in the real election: two people testing in Studio
-- at once must not fight a live production server for the MemoryStore lease
-- (or worse, win it and blackhole broadcasts for every other server). Studio
-- just assumes it's the leader locally and never touches MemoryStore.
function LeaderElection.new(_services)
	local self = setmetatable({}, LeaderElection)
	self.jobId = (_services and _services.jobId) or JobId.jobId
	self.isCurrentLeader = false
	self.wait = (_services and _services.wait) or task.wait

	local runService = (_services and _services.RunService) or RunService
	self.isStudio = runService:IsStudio()

	self.hashMap = _services and _services.hashMap
	if not self.hashMap and not self.isStudio then
		local memoryStoreService = (_services and _services.MemoryStoreService) or MemoryStoreService
		self:connectHashMap(memoryStoreService)
	end

	return self
end

-- GetHashMap can throw (e.g. Studio API access disabled, or a MemoryStore
-- outage); retrying here means a transient failure at boot doesn't
-- permanently disable leader election for the rest of the server's life.
function LeaderElection:connectHashMap(memoryStoreService)
	task.spawn(function()
		local attempt = 0
		while not self.hashMap do
			local ok, result = pcall(function()
				return memoryStoreService:GetHashMap(Constants.LEADER_HASHMAP_NAME)
			end)
			if ok then
				self.hashMap = result
			else
				Logger.warn("LeaderElection: GetHashMap failed, retrying: " .. tostring(result))
				self.wait(backoffSeconds(attempt))
				attempt += 1
			end
		end
	end)
end

function LeaderElection:tryElectOrRenew(ttlSeconds: number?): boolean
	if self.isStudio then
		self.isCurrentLeader = true
		return true
	end

	if not self.hashMap then
		self.isCurrentLeader = false
		return false
	end

	local jobId = self.jobId

	-- Returning nil from the UpdateAsync transform aborts the write, leaving a
	-- lease held by another server untouched.
	local ok, result = pcall(function()
		return self.hashMap:UpdateAsync(Constants.LEADER_KEY, function(currentJobId)
			if currentJobId == nil or currentJobId == jobId then
				return jobId
			end
			return nil
		end, ttlSeconds or Constants.LEADER_LEASE_TTL_SECONDS)
	end)

	if not ok then
		Logger.warn("LeaderElection: UpdateAsync failed: " .. tostring(result))
		self.isCurrentLeader = false
		return false
	end

	local becameLeader = (result == jobId) and not self.isCurrentLeader
	self.isCurrentLeader = (result == jobId)
	if becameLeader then
		Logger.info("LeaderElection: elected as leader")
	end
	return self.isCurrentLeader
end

function LeaderElection:isLeader(): boolean
	return self.isCurrentLeader
end

return LeaderElection
