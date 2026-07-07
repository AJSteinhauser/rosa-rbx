local RunService          = game:GetService("RunService")
local LeaderElection      = require(script["leader-election"])
local BroadcastSignal     = require(script["broadcast-signal"])
local LeaderPoller        = require(script["leader-poller"])
local PositionBroadcaster = require(script["position-broadcaster"])

local BroadcastCoordinator = {}
BroadcastCoordinator.__index = BroadcastCoordinator

function BroadcastCoordinator.new(_services)
	local self = setmetatable({}, BroadcastCoordinator)

	local runService = (_services and _services.RunService) or RunService
	if not runService:IsServer() then
		return self
	end

	self.leaderElection      = LeaderElection.new(_services)
	self.broadcastSignal     = BroadcastSignal.new(_services)
	self.leaderPoller        = LeaderPoller.new(self.leaderElection, self.broadcastSignal, _services)
	self.positionBroadcaster = PositionBroadcaster.new(_services)

	self.broadcastSignal:onStart(function()
		self.positionBroadcaster:onSignalReceived()
	end)

	self.leaderPoller:start()

	return self
end

return BroadcastCoordinator
