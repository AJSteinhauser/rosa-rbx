local Constants = require(script.Parent.constants)
local Logger    = require(script.Parent.Parent.utils.logger)
local ApiUtils  = require(script.Parent.Parent.egress.utils["api-utils"])
local Signature = require(script.Parent.Parent.egress.components.signature)

local LeaderPoller = {}
LeaderPoller.__index = LeaderPoller

function LeaderPoller.new(leaderElection, broadcastSignal, _services)
	local self = setmetatable({}, LeaderPoller)
	self.leaderElection  = leaderElection
	self.broadcastSignal = broadcastSignal
	self.httpService      = (_services and _services.HttpService) or game:GetService("HttpService")
	self.wait              = (_services and _services.wait) or task.wait
	self.running = false
	self.pollIntervalSeconds = Constants.LEADER_POLL_INTERVAL_SECONDS
	return self
end

function LeaderPoller:start()
	if self.running then return end
	self.running = true
	task.spawn(function()
		while self.running do
			-- pcall so a bad poll() can't kill this coroutine for the rest of the server's life.
			local ok, err = pcall(function()
				self:poll()
			end)
			if not ok then
				Logger.warn("LeaderPoller: poll() errored: " .. tostring(err))
			end
			self.wait(self.pollIntervalSeconds)
		end
	end)
end

function LeaderPoller:stop()
	self.running = false
end

function LeaderPoller:poll()
	local notEntitledMode = self.pollIntervalSeconds == Constants.BROADCAST_NOT_ENTITLED_POLL_INTERVAL_SECONDS
	local leaseTtl = notEntitledMode
		and Constants.BROADCAST_NOT_ENTITLED_LEASE_TTL_SECONDS
		or Constants.LEADER_LEASE_TTL_SECONDS

	if not self.leaderElection:tryElectOrRenew(leaseTtl) then
		return
	end

	local request = {
		Url     = Constants.BROADCAST_POLL_API_ROUTE,
		Method  = "GET",
		Headers = Signature.generateHeader(self.httpService),
	}

	local response = ApiUtils.sendRetryHandler(request, nil, { HttpService = self.httpService, wait = self.wait })

	if response.StatusCode == Constants.BROADCAST_NOT_ENTITLED_STATUS then
		self.pollIntervalSeconds = Constants.BROADCAST_NOT_ENTITLED_POLL_INTERVAL_SECONDS
		return
	end
	self.pollIntervalSeconds = Constants.LEADER_POLL_INTERVAL_SECONDS

	if not response.Success then
		Logger.warn(string.format("LeaderPoller: poll failed with status %d", response.StatusCode))
		return
	end

	local ok, decoded = pcall(function()
		return self.httpService:JSONDecode(response.Body)
	end)
	if not ok or type(decoded) ~= "table" then
		Logger.warn("LeaderPoller: invalid poll response body: " .. tostring(decoded))
		return
	end

	if decoded.activeViewer == true then
		self.broadcastSignal:publishStart()
	end
end

return LeaderPoller
