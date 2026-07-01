local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local PlayerPlatformManager  = require(ReplicatedStorage.RosaRbx.ingestion["player-platform-manager"])

local function makeSignal()
	local cbs = {}
	return {
		Connect = function(_, fn) table.insert(cbs, fn) end,
		Fire    = function(_, ...) for _, fn in cbs do fn(...) end end,
	}
end

-- Fake `delay` records scheduled callbacks instead of waiting 10 real seconds.
-- settle() runs everything queued so far, simulating the timeout elapsing.
local function makeDelay()
	local pending = {}
	return {
		delay = function(_, fn) table.insert(pending, fn) end,
		settle = function()
			local batch = pending
			pending = {}
			for _, fn in batch do fn() end
		end,
	}
end

local function makeRemoteEvent()
	local fireClientCalls = {}
	return {
		OnServerEvent   = makeSignal(),
		fireClientCalls = fireClientCalls,
		FireClient = function(_, player, message)
			table.insert(fireClientCalls, { player = player, message = message })
		end,
	}
end

local function makeEnv()
	local fakeDelay      = makeDelay()
	local remote         = makeRemoteEvent()
	local playerRemoving = makeSignal()

	local manager = PlayerPlatformManager.new({
		Players     = { PlayerRemoving = playerRemoving },
		remoteEvent = remote,
		delay       = fakeDelay.delay,
	})

	return {
		manager        = manager,
		remote         = remote,
		playerRemoving = playerRemoving,
		settle         = fakeDelay.settle,
	}
end

local function makePlayer(name)
	return { Name = name or "TestPlayer" }
end

return function()
	describe("PlayerPlatformManager:getPlatform", function()

		it("requests the platform from the client and yields until it responds", function()
			local env    = makeEnv()
			local player = makePlayer()
			local result = "not-yet"

			task.spawn(function()
				result = env.manager:getPlatform(player)
			end)

			expect(result).to.equal("not-yet") -- still suspended, waiting on the client
			expect(#env.remote.fireClientCalls).to.equal(1)
			expect(env.remote.fireClientCalls[1].player).to.equal(player)
			expect(env.remote.fireClientCalls[1].message).to.equal("getPlatform")

			env.remote.OnServerEvent:Fire(player, Enum.UserInputType.Touch)

			expect(result).to.equal(Enum.UserInputType.Touch)
		end)

		it("caches the platform and returns it synchronously without a second round trip", function()
			local env    = makeEnv()
			local player = makePlayer()
			local first

			task.spawn(function() first = env.manager:getPlatform(player) end)
			env.remote.OnServerEvent:Fire(player, Enum.UserInputType.Touch)
			expect(first).to.equal(Enum.UserInputType.Touch)

			local second = env.manager:getPlatform(player) -- cached: returns without yielding

			expect(second).to.equal(Enum.UserInputType.Touch)
			expect(#env.remote.fireClientCalls).to.equal(1)
		end)

		it("times out after the configured delay and defaults to Unknown", function()
			local env    = makeEnv()
			local player = makePlayer()
			local result

			task.spawn(function() result = env.manager:getPlatform(player) end)
			expect(result).to.equal(nil)

			env.settle() -- simulate the 10s timeout elapsing with no client response

			expect(result).to.equal("Unknown")
		end)

		it("ignores a stale timeout once the client has already responded", function()
			local env    = makeEnv()
			local player = makePlayer()
			local result

			task.spawn(function() result = env.manager:getPlatform(player) end)
			env.remote.OnServerEvent:Fire(player, Enum.UserInputType.Touch)
			expect(result).to.equal(Enum.UserInputType.Touch)

			env.settle() -- the queued timeout fires late; must not clobber the resolved value

			expect(result).to.equal(Enum.UserInputType.Touch)
		end)

		it("tracks separate pending requests per player independently", function()
			local env    = makeEnv()
			local playerA = makePlayer("A")
			local playerB = makePlayer("B")
			local resultA, resultB

			task.spawn(function() resultA = env.manager:getPlatform(playerA) end)
			task.spawn(function() resultB = env.manager:getPlatform(playerB) end)

			env.remote.OnServerEvent:Fire(playerA, Enum.UserInputType.Keyboard)

			expect(resultA).to.equal(Enum.UserInputType.Keyboard)
			expect(resultB).to.equal(nil)

			env.remote.OnServerEvent:Fire(playerB, Enum.UserInputType.Touch)

			expect(resultB).to.equal(Enum.UserInputType.Touch)
		end)

	end)

	describe("PlayerPlatformManager PlayerRemoving handling", function()

		it("resolves a pending request with Unknown when the player leaves", function()
			local env    = makeEnv()
			local player = makePlayer()
			local result

			task.spawn(function() result = env.manager:getPlatform(player) end)
			env.playerRemoving:Fire(player)

			expect(result).to.equal("Unknown")
		end)

		it("clears the cache on leave, so a later request makes a fresh round trip", function()
			local env    = makeEnv()
			local player = makePlayer()
			local first

			task.spawn(function() first = env.manager:getPlatform(player) end)
			env.remote.OnServerEvent:Fire(player, Enum.UserInputType.Touch)
			expect(first).to.equal(Enum.UserInputType.Touch)

			env.playerRemoving:Fire(player)

			local second
			task.spawn(function() second = env.manager:getPlatform(player) end)

			expect(#env.remote.fireClientCalls).to.equal(2)
			env.remote.OnServerEvent:Fire(player, Enum.UserInputType.Gamepad1)
			expect(second).to.equal(Enum.UserInputType.Gamepad1)
		end)

		it("does not error when a player with no pending request leaves", function()
			local env    = makeEnv()
			local player = makePlayer()

			expect(function()
				env.playerRemoving:Fire(player)
			end).never.to.throw()
		end)

	end)
end
