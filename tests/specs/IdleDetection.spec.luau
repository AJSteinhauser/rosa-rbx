local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local setupIdleDetection = require(ReplicatedStorage.RosaRbx.ingestion["default-metrics"]["idle-detection"])

local function makeSignal()
	local cbs = {}
	return {
		Connect = function(_, fn) table.insert(cbs, fn) end,
		Fire    = function(_, ...) for _, fn in cbs do fn(...) end end,
	}
end

local function makeHandler()
	local calls = {}
	return {
		calls = calls,
		addServerEvent = function(_, player, event)
			table.insert(calls, { player = player, event = event })
		end,
	}
end

local function makeSetup(idleThresholdSeconds)
	local time = 0
	local heartbeat = makeSignal()
	local playerAdded   = makeSignal()
	local playerRemoving = makeSignal()

	local root = { Position = Vector3.new(0, 0, 0) }
	local character = { FindFirstChild = function() return root end }
	local characterAdded = makeSignal()
	local player = {
		Name            = "TestPlayer",
		Character       = character,
		CharacterAdded  = characterAdded,
		_characterAdded = characterAdded,
	}

	local svc = {
		Players = {
			PlayerAdded    = playerAdded,
			PlayerRemoving = playerRemoving,
			GetPlayers     = function() return { player } end,
		},
		RunService = { Heartbeat = heartbeat },
		getTime    = function() return time end,
	}

	local userConfig = {
		defaultMetrics = { idleThresholdSeconds = idleThresholdSeconds or 10 },
		getPosition = function(p)
			local char = p.Character
			if not char then return nil end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			return hrp and hrp.Position
		end,
	}

	return {
		svc         = svc,
		userConfig  = userConfig,
		player      = player,
		root        = root,
		heartbeat   = heartbeat,
		setTime     = function(t) time = t end,
		setPos      = function(x, y, z) root.Position = Vector3.new(x, y, z) end,
	}
end

return function()
	describe("IdleDetection", function()

		it("fires PlayerIdle after threshold seconds without movement", function()
			local ctx     = makeSetup(10)
			local handler = makeHandler()

			setupIdleDetection(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(0)
			ctx.heartbeat:Fire()   -- begin tracking (player.Character set)
			ctx.setTime(11)
			ctx.heartbeat:Fire()   -- exceeds threshold

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("PlayerIdle")
		end)

		it("quantity equals idle duration in seconds", function()
			local ctx     = makeSetup(10)
			local handler = makeHandler()

			setupIdleDetection(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(0)
			ctx.heartbeat:Fire()
			ctx.setTime(15)
			ctx.heartbeat:Fire()

			expect(handler.calls[1].event.quantity).to.equal(15)
		end)

		it("does not fire if player moves before threshold", function()
			local ctx     = makeSetup(10)
			local handler = makeHandler()

			setupIdleDetection(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(0)
			ctx.heartbeat:Fire()
			ctx.setTime(5)
			ctx.setPos(100, 0, 0) -- move far
			ctx.heartbeat:Fire()
			ctx.setTime(12)
			ctx.heartbeat:Fire()

			expect(#handler.calls).to.equal(0)
		end)

		it("fires only once per idle period", function()
			local ctx     = makeSetup(10)
			local handler = makeHandler()

			setupIdleDetection(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(0)
			ctx.heartbeat:Fire()
			ctx.setTime(11)
			ctx.heartbeat:Fire()
			ctx.setTime(20)
			ctx.heartbeat:Fire() -- still idle, should not re-fire

			expect(#handler.calls).to.equal(1)
		end)

		it("resets and fires again after player moves then idles again", function()
			local ctx     = makeSetup(10)
			local handler = makeHandler()

			setupIdleDetection(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(0)
			ctx.heartbeat:Fire()
			ctx.setTime(11)
			ctx.heartbeat:Fire()   -- first idle
			ctx.setPos(100, 0, 0)
			ctx.setTime(12)
			ctx.heartbeat:Fire()   -- moves, resets
			ctx.setTime(23)
			ctx.heartbeat:Fire()   -- idle again

			expect(#handler.calls).to.equal(2)
		end)

	end)
end
