local ReplicatedStorage = game:GetService("ReplicatedStorage")
local setupPaths        = require(ReplicatedStorage.RosaRbx.ingestion["default-metrics"]["paths"])

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

-- Sequential fake GUIDs so tests can assert segment identity/change without
-- depending on real HttpService:GenerateGUID output.
local function makeHttpService()
	local n = 0
	return {
		GenerateGUID = function(_, _urlSafe)
			n += 1
			return "guid-" .. n
		end,
	}
end

local function makeSetup(options)
	options = options or {}
	local time          = 0
	local heartbeat      = makeSignal()
	local playerAdded    = makeSignal()
	local playerRemoving = makeSignal()

	local root      = { Position = Vector3.new(0, 0, 0) }
	local character = { FindFirstChild = function() return root end }
	local player    = {
		Name           = "TestPlayer",
		Character      = character,
		CharacterAdded = makeSignal(),
	}

	local svc = {
		Players = {
			PlayerAdded    = playerAdded,
			PlayerRemoving = playerRemoving,
			GetPlayers     = function() return { player } end,
		},
		RunService = {
			Heartbeat = heartbeat,
			IsStudio  = function() return options.isStudio ~= false end,
		},
		HttpService = makeHttpService(),
		getTime     = function() return time end,
		random      = options.random or function() return 0 end, -- 0 always passes the sample-rate check
	}

	local userConfig = {
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
	describe("Paths", function()

		it("fires _PathStart when tracking begins", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupPaths(handler, ctx.userConfig, ctx.svc)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("_PathStart")
			expect(handler.calls[1].event.position).to.equal(Vector3.new(0, 0, 0))
			expect(handler.calls[1].event.custom.segmentId).to.be.ok()
		end)

		it("fires _PathTag once distance from the last tag exceeds DISTANCE_THRESHOLD", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupPaths(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(1)
			ctx.setPos(30, 0, 0) -- 30 studs > 25 stud threshold
			ctx.heartbeat:Fire()

			expect(#handler.calls).to.equal(2)
			expect(handler.calls[2].event.tag).to.equal("_PathTag")
			expect(handler.calls[2].event.position).to.equal(Vector3.new(30, 0, 0))
		end)

		it("does not fire _PathTag for small movements under both thresholds", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupPaths(handler, ctx.userConfig, ctx.svc)
			ctx.setTime(1)
			ctx.setPos(5, 0, 0) -- under the 25 stud distance threshold, no prior direction to compare against
			ctx.heartbeat:Fire()

			expect(#handler.calls).to.equal(1)
		end)

		it("fires _PathTag on a sharp direction change even under the distance threshold", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupPaths(handler, ctx.userConfig, ctx.svc)

			-- Establish a lastDir with a distance-triggered tag heading down +X.
			ctx.setTime(1)
			ctx.setPos(30, 0, 0)
			ctx.heartbeat:Fire()
			expect(#handler.calls).to.equal(2)

			-- Turn 90 degrees (>= 35 degree threshold) while moving only 10 studs.
			ctx.setTime(2)
			ctx.setPos(30, 10, 0)
			ctx.heartbeat:Fire()

			expect(#handler.calls).to.equal(3)
			expect(handler.calls[3].event.tag).to.equal("_PathTag")
		end)

		it("throttles tags to MIN_TAG_INTERVAL even when the distance threshold is repeatedly exceeded", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupPaths(handler, ctx.userConfig, ctx.svc)

			ctx.setTime(0.05)
			ctx.setPos(30, 0, 0) -- qualifies, but within 0.1s of the initial tag time (0)
			ctx.heartbeat:Fire()

			ctx.setTime(0.08)
			ctx.setPos(60, 0, 0) -- qualifies, still within the 0.1s window
			ctx.heartbeat:Fire()

			ctx.setTime(0.2)
			ctx.setPos(90, 0, 0) -- qualifies, window has now elapsed
			ctx.heartbeat:Fire()

			expect(#handler.calls).to.equal(2) -- initial _PathStart + exactly one throttled _PathTag
			expect(handler.calls[2].event.position).to.equal(Vector3.new(90, 0, 0))
		end)

		it("starts a new segment on a teleport-sized jump", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupPaths(handler, ctx.userConfig, ctx.svc)
			local firstSegmentId = handler.calls[1].event.custom.segmentId

			ctx.setTime(1)
			ctx.setPos(200, 0, 0) -- beyond the 100 stud teleport threshold
			ctx.heartbeat:Fire()

			expect(#handler.calls).to.equal(3)
			expect(handler.calls[2].event.tag).to.equal("_PathTag")
			expect(handler.calls[2].event.position).to.equal(Vector3.new(0, 0, 0))
			expect(handler.calls[2].event.custom.segmentId).to.equal(firstSegmentId)

			expect(handler.calls[3].event.tag).to.equal("_PathStart")
			expect(handler.calls[3].event.position).to.equal(Vector3.new(200, 0, 0))
			expect(handler.calls[3].event.custom.segmentId).never.to.equal(firstSegmentId)
		end)

		it("stops tracking a player once they leave", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupPaths(handler, ctx.userConfig, ctx.svc)
			ctx.playerRemoving:Fire(ctx.player)

			ctx.setTime(1)
			ctx.setPos(200, 0, 0)
			ctx.heartbeat:Fire()

			expect(#handler.calls).to.equal(1) -- only the initial _PathStart; no further events after leaving
		end)

	end)

	describe("Paths sample-rate gating (outside Studio)", function()

		it("tracks the player when random() lands under SAMPLE_RATE", function()
			local ctx     = makeSetup({ isStudio = false, random = function() return 0.01 end })
			local handler = makeHandler()

			setupPaths(handler, ctx.userConfig, ctx.svc)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("_PathStart")
		end)

		it("skips the player entirely when random() lands at or above SAMPLE_RATE", function()
			local ctx     = makeSetup({ isStudio = false, random = function() return 0.5 end })
			local handler = makeHandler()

			setupPaths(handler, ctx.userConfig, ctx.svc)

			expect(#handler.calls).to.equal(0)
		end)

	end)

	describe("Paths sample-rate gating (in Studio)", function()

		it("always tracks every player regardless of random()", function()
			local ctx     = makeSetup({ isStudio = true, random = function() return 0.999 end })
			local handler = makeHandler()

			setupPaths(handler, ctx.userConfig, ctx.svc)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("_PathStart")
		end)

	end)
end
