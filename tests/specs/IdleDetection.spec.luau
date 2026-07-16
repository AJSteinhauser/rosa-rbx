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
		svc            = svc,
		userConfig     = userConfig,
		player         = player,
		root           = root,
		heartbeat      = heartbeat,
		playerRemoving = playerRemoving,
		setTime        = function(t) time = t end,
		setPos         = function(x, y, z) root.Position = Vector3.new(x, y, z) end,
	}
end

return function()
	describe("IdleDetection", function()

		it("does not fire while idle threshold is crossed but player hasn't moved yet", function()
			local ctx     = makeSetup(10)
			local handler = makeHandler()

			setupIdleDetection(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(0)
			ctx.heartbeat:Fire()   -- begin tracking (player.Character set)
			ctx.setTime(11)
			ctx.heartbeat:Fire()   -- exceeds threshold, still no movement

			expect(#handler.calls).to.equal(0)
		end)

		it("fires PlayerIdle with quantity = total idle duration once player moves again", function()
			local ctx     = makeSetup(10)
			local handler = makeHandler()

			setupIdleDetection(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(0)
			ctx.heartbeat:Fire()
			ctx.setTime(15)
			ctx.heartbeat:Fire()   -- past threshold, idle confirmed, no event yet
			ctx.setPos(100, 0, 0)
			ctx.setTime(23)
			ctx.heartbeat:Fire()   -- moves, ends idle period

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("PlayerIdle")
			expect(handler.calls[1].event.quantity).to.equal(23)
		end)

		it("does not fire if player moves before threshold", function()
			local ctx     = makeSetup(10)
			local handler = makeHandler()

			setupIdleDetection(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(0)
			ctx.heartbeat:Fire()
			ctx.setTime(5)
			ctx.setPos(100, 0, 0) -- move far, before threshold
			ctx.heartbeat:Fire()
			ctx.setTime(12)
			ctx.heartbeat:Fire()

			expect(#handler.calls).to.equal(0)
		end)

		it("does not re-fire while continuously idle before movement", function()
			local ctx     = makeSetup(10)
			local handler = makeHandler()

			setupIdleDetection(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(0)
			ctx.heartbeat:Fire()
			ctx.setTime(11)
			ctx.heartbeat:Fire() -- crosses threshold, no event
			ctx.setTime(20)
			ctx.heartbeat:Fire() -- still idle, still no event

			expect(#handler.calls).to.equal(0)
		end)

		it("logs one idle event per idle period across multiple idle/move cycles", function()
			local ctx     = makeSetup(10)
			local handler = makeHandler()

			setupIdleDetection(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(0)
			ctx.heartbeat:Fire()
			ctx.setTime(11)
			ctx.heartbeat:Fire()   -- idle confirmed, no event yet
			ctx.setPos(100, 0, 0)
			ctx.setTime(12)
			ctx.heartbeat:Fire()   -- moves, logs first idle period (quantity 12)
			ctx.setTime(23)
			ctx.heartbeat:Fire()   -- idle confirmed again, no event yet
			ctx.setPos(200, 0, 0)
			ctx.setTime(24)
			ctx.heartbeat:Fire()   -- moves, logs second idle period (quantity 12)

			expect(#handler.calls).to.equal(2)
			expect(handler.calls[1].event.quantity).to.equal(12)
			expect(handler.calls[2].event.quantity).to.equal(12)
		end)

		it("preserves idle timer across respawn as long as player doesn't move", function()
			local ctx     = makeSetup(10)
			local handler = makeHandler()

			setupIdleDetection(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(0)
			ctx.heartbeat:Fire()   -- begin tracking, idleSince = 0
			ctx.setTime(5)
			ctx.heartbeat:Fire()   -- below threshold, not idle yet

			ctx.setPos(50, 0, 0)   -- character respawns at a different point
			ctx.player.CharacterAdded:Fire()

			ctx.setTime(12)
			ctx.heartbeat:Fire()   -- new spawn point is the reference now; no movement since respawn,
			                       -- but idleSince is still 0 so threshold (10) is already crossed

			expect(#handler.calls).to.equal(0) -- crossing threshold alone doesn't log

			ctx.setPos(150, 0, 0)
			ctx.setTime(20)
			ctx.heartbeat:Fire()   -- moves, ends idle

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.quantity).to.equal(20) -- spans across the respawn, not reset by it
		end)

		it("logs idle event on PlayerRemoving when player leaves while idle", function()
			local ctx     = makeSetup(10)
			local handler = makeHandler()

			setupIdleDetection(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(0)
			ctx.heartbeat:Fire()
			ctx.setTime(18)
			ctx.heartbeat:Fire()   -- idle confirmed, no event yet
			ctx.setTime(20)
			ctx.playerRemoving:Fire(ctx.player)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("PlayerIdle")
			expect(handler.calls[1].event.quantity).to.equal(20)
		end)

		it("does not log on PlayerRemoving if player was not idle", function()
			local ctx     = makeSetup(10)
			local handler = makeHandler()

			setupIdleDetection(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(0)
			ctx.heartbeat:Fire()
			ctx.setTime(5)
			ctx.heartbeat:Fire()   -- below threshold
			ctx.playerRemoving:Fire(ctx.player)

			expect(#handler.calls).to.equal(0)
		end)

	end)
end
