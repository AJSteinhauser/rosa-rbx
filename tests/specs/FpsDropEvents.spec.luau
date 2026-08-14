local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local setupFpsDropEvents = require(ReplicatedStorage.RosaRbx.ingestion["default-metrics"]["fps-drop-events"])

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
		addClientEvent = function(_, event)
			table.insert(calls, event)
		end,
	}
end

local function makeSetup(fpsDropConfig, localPlayer)
	local time             = 0
	local renderStepped    = makeSignal()
	local contentProvider  = { RequestQueueSize = 0 }

	local svc = {
		RunService      = { RenderStepped = renderStepped },
		Players         = { LocalPlayer = localPlayer },
		ContentProvider = contentProvider,
		getTime         = function() return time end,
	}

	local config = { fpsDrop = fpsDropConfig }

	return {
		svc          = svc,
		config       = config,
		setTime      = function(t) time = t end,
		setQueueSize = function(n) contentProvider.RequestQueueSize = n end,

		-- fires `count` frames at a steady `fps`, advancing the clock by 1/fps each time
		runFrames = function(count, fps)
			local dt = 1 / fps
			for _ = 1, count do
				time += dt
				renderStepped:Fire()
			end
		end,
	}
end

-- small, decoupled from the module's shipped DEFAULT_* constants so tests below survive a retune
local function testConfig(overrides)
	local cfg = {
		warmupSeconds         = 1,
		warmupMaxSeconds      = 3,
		baselineWindowSeconds = 10,
		recentWindowSeconds   = 1,
		dropRatio             = 0.5,
	}
	for k, v in (overrides or {}) do cfg[k] = v end
	return cfg
end

return function()
	describe("FpsDropEvents", function()

		it("stays silent through the warmup window even at a terrible framerate", function()
			local ctx     = makeSetup(testConfig())
			local handler = makeHandler()

			setupFpsDropEvents(handler, ctx.config, ctx.svc)
			ctx.runFrames(4, 5) -- 0.8s at 5fps, still inside the 1s warmup

			expect(#handler.calls).to.equal(0)
		end)

		it("stays silent at a steady framerate once past warmup", function()
			local ctx     = makeSetup(testConfig())
			local handler = makeHandler()

			setupFpsDropEvents(handler, ctx.config, ctx.svc)
			ctx.runFrames(200, 60)

			expect(#handler.calls).to.equal(0)
		end)

		it("fires FpsDrop once a sustained drop pulls recent fps well below baseline", function()
			local ctx     = makeSetup(testConfig())
			local handler = makeHandler()

			setupFpsDropEvents(handler, ctx.config, ctx.svc)
			ctx.runFrames(200, 60)
			ctx.runFrames(29, 15)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].tag).to.equal("FpsDrop")
			expect(handler.calls[1].quantity).to.equal(27)
			expect(handler.calls[1].custom.baselineFps).to.equal(54)
			expect(handler.calls[1].custom.dropPct).to.equal(50)
		end)

		it("does not fire for a moderate dip that stays above the drop ratio threshold", function()
			local ctx     = makeSetup(testConfig())
			local handler = makeHandler()

			setupFpsDropEvents(handler, ctx.config, ctx.svc)
			ctx.runFrames(200, 60)
			ctx.runFrames(200, 45) -- stays above the 0.5 drop ratio

			expect(#handler.calls).to.equal(0)
		end)

		it("re-arms after recovering, then fires again on a second sustained drop", function()
			local ctx     = makeSetup(testConfig())
			local handler = makeHandler()

			setupFpsDropEvents(handler, ctx.config, ctx.svc)
			ctx.runFrames(200, 60)
			ctx.runFrames(29, 15)
			ctx.runFrames(300, 60)
			ctx.runFrames(22, 15)

			expect(#handler.calls).to.equal(2)
			expect(handler.calls[2].tag).to.equal("FpsDrop")
			expect(handler.calls[2].quantity).to.equal(24)
			expect(handler.calls[2].custom.baselineFps).to.equal(49)
		end)

		it("includes the local player's root position when a character is present", function()
			local pos       = Vector3.new(4, 0, 9)
			local root      = { Position = pos }
			local character = {
				FindFirstChild = function(_, name)
					if name == "HumanoidRootPart" then return root end
				end,
			}
			local player  = { Character = character }
			local ctx     = makeSetup(testConfig(), player)
			local handler = makeHandler()

			setupFpsDropEvents(handler, ctx.config, ctx.svc)
			ctx.runFrames(200, 60)
			ctx.runFrames(29, 15)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].position).to.equal(pos)
		end)

		it("omits position when there is no local player character", function()
			local ctx     = makeSetup(testConfig(), nil)
			local handler = makeHandler()

			setupFpsDropEvents(handler, ctx.config, ctx.svc)
			ctx.runFrames(200, 60)
			ctx.runFrames(29, 15)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].position).to.equal(nil)
		end)

		-- intentionally uses the real shipped defaults, not testConfig() -- proves an
		-- override changes behavior relative to what actually ships
		it("respects a shorter custom warmupSeconds that lets a drop register earlier than the default would", function()
			local ctx     = makeSetup({ warmupSeconds = 1 })
			local handler = makeHandler()

			setupFpsDropEvents(handler, ctx.config, ctx.svc)
			ctx.runFrames(300, 60)
			ctx.runFrames(60, 15) -- 9s total, still under the 10s default warmup

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].quantity).to.equal(27)
		end)

		it("the same 9-second sequence stays silent under the 10s default warmup", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupFpsDropEvents(handler, ctx.config, ctx.svc)
			ctx.runFrames(300, 60)
			ctx.runFrames(60, 15)

			expect(#handler.calls).to.equal(0)
		end)

		it("extends warmup past the floor while the asset queue hasn't drained", function()
			local ctx     = makeSetup(testConfig())
			local handler = makeHandler()
			ctx.setQueueSize(2)

			setupFpsDropEvents(handler, ctx.config, ctx.svc)
			ctx.runFrames(150, 60) -- past the 1s floor
			ctx.runFrames(29, 15)  -- would fire if warmup had ended

			expect(#handler.calls).to.equal(0)
		end)

		it("ends warmup and starts sampling fresh once the asset queue drains", function()
			local ctx     = makeSetup(testConfig())
			local handler = makeHandler()
			ctx.setQueueSize(2)

			setupFpsDropEvents(handler, ctx.config, ctx.svc)
			ctx.runFrames(150, 60)

			ctx.setQueueSize(0)
			ctx.runFrames(200, 60)
			ctx.runFrames(29, 15)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].quantity).to.equal(27)
			expect(handler.calls[1].custom.baselineFps).to.equal(54)
		end)

		it("warmupMaxSeconds forces warmup to end even if the asset queue never drains", function()
			local ctx     = makeSetup(testConfig())
			local handler = makeHandler()
			ctx.setQueueSize(99) -- never drains, e.g. an open-world streaming game

			setupFpsDropEvents(handler, ctx.config, ctx.svc)
			ctx.runFrames(200, 60) -- past the 3s warmupMaxSeconds ceiling
			ctx.runFrames(200, 60)
			ctx.runFrames(29, 15)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].quantity).to.equal(27)
			expect(handler.calls[1].custom.baselineFps).to.equal(54)
		end)

	end)
end
