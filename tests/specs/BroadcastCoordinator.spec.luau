local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BroadcastCoordinator = require(ReplicatedStorage.RosaRbx.broadcast)

-- Only the client no-op path is covered here. The server path unconditionally
-- starts LeaderPoller's forever-loop (by design — it must run for the server's
-- whole lifetime), which makes it unsafe to drive with a synchronous fake `wait`
-- in a unit test: nothing external can stop that loop before BroadcastCoordinator
-- .new() itself returns, since the LeaderPoller instance isn't reachable until
-- construction finishes. The server-side wiring (LeaderElection, BroadcastSignal,
-- LeaderPoller, PositionBroadcaster) is already covered individually by their own
-- specs; verify the full wiring in Studio before shipping a change here.
local function makeRunService(isServer: boolean)
	return { IsServer = function() return isServer end }
end

return function()
	describe("BroadcastCoordinator", function()

		describe("new()", function()
			it("is a no-op on the client: does not throw and wires up nothing", function()
				local coordinator
				expect(function()
					coordinator = BroadcastCoordinator.new({ RunService = makeRunService(false) })
				end).never.to.throw()

				expect(coordinator.leaderElection).to.equal(nil)
				expect(coordinator.broadcastSignal).to.equal(nil)
				expect(coordinator.leaderPoller).to.equal(nil)
				expect(coordinator.positionBroadcaster).to.equal(nil)
			end)
		end)

	end)
end
