local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local setupRageQuitEvents = require(ReplicatedStorage.RosaRbx.ingestion["default-metrics"]["rage-quit-events"])

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

local function makeHumanoid()
	return {
		Health        = 100,
		MaxHealth     = 100,
		HealthChanged = makeSignal(),
		Died          = makeSignal(),
	}
end

local function makeCharacter(humanoid)
	return {
		WaitForChild = function(_, name)
			if name == "Humanoid" then return humanoid end
		end,
	}
end

local function makeSetup(rageQuitConfig)
	local time = 0
	local playerAdded    = makeSignal()
	local playerRemoving = makeSignal()
	local characterAdded = makeSignal()

	local player = {
		Name           = "TestPlayer",
		CharacterAdded = characterAdded,
	}

	local svc = {
		Players = {
			PlayerAdded    = playerAdded,
			PlayerRemoving = playerRemoving,
			GetPlayers     = function() return {} end,
		},
		getTime = function() return time end,
	}

	local userConfig = { defaultMetrics = { rageQuit = rageQuitConfig } }
	local humanoid = nil

	return {
		svc        = svc,
		userConfig = userConfig,
		player     = player,
		setTime    = function(t) time = t end,

		register = function()
			playerAdded:Fire(player)
		end,

		spawnCharacter = function()
			humanoid = makeHumanoid()
			characterAdded:Fire(makeCharacter(humanoid))
			return humanoid
		end,

		damage = function(amount)
			local newHealth = humanoid.Health - amount
			humanoid.Health = newHealth
			humanoid.HealthChanged:Fire(newHealth)
		end,

		die = function()
			humanoid.Died:Fire()
		end,

		leave = function()
			playerRemoving:Fire(player)
		end,
	}
end

return function()
	describe("RageQuitEvents", function()

		it("fires with full score when leaving immediately after dying at zero health", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupRageQuitEvents(handler, ctx.userConfig, ctx.svc)
			ctx.register()
			ctx.spawnCharacter()
			ctx.setTime(0)
			ctx.damage(100)
			ctx.die()
			ctx.leave()

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("RageQuit")
			expect(handler.calls[1].event.quantity).to.equal(1)
			expect(handler.calls[1].event.custom.deathAgeSec).to.equal(0)
			expect(handler.calls[1].event.custom.healthPct).to.equal(0)
		end)

		it("does not fire on a clean leave at full health with no damage or death", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupRageQuitEvents(handler, ctx.userConfig, ctx.svc)
			ctx.register()
			ctx.spawnCharacter()
			ctx.leave()

			expect(#handler.calls).to.equal(0)
		end)

		it("does not fire once enough time has passed since death, even at zero health", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupRageQuitEvents(handler, ctx.userConfig, ctx.svc)
			ctx.register()
			ctx.spawnCharacter()
			ctx.setTime(0)
			ctx.damage(100)
			ctx.die()
			ctx.setTime(60) -- well past deathTau (15s) and damageTau (10s)
			ctx.leave()

			-- healthScore alone (0.2 max) can't cross the 0.5 threshold without recency
			expect(#handler.calls).to.equal(0)
		end)

		it("fires from near-fatal damage alone, with no Died event at all", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupRageQuitEvents(handler, ctx.userConfig, ctx.svc)
			ctx.register()
			ctx.spawnCharacter()
			ctx.setTime(0)
			ctx.damage(100)
			ctx.leave()

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.custom.deathAgeSec).to.equal(nil)
			expect(handler.calls[1].event.custom.healthPct).to.equal(0)
		end)

		it("does not fire from moderate damage that stays under threshold", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupRageQuitEvents(handler, ctx.userConfig, ctx.svc)
			ctx.register()
			ctx.spawnCharacter()
			ctx.setTime(0)
			ctx.damage(90)
			ctx.leave()

			expect(#handler.calls).to.equal(0)
		end)

		it("keeps flagging rage quit shortly after respawn since death recency survives across characters", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupRageQuitEvents(handler, ctx.userConfig, ctx.svc)
			ctx.register()
			ctx.spawnCharacter()
			ctx.setTime(0)
			ctx.damage(100)
			ctx.die()

			ctx.spawnCharacter() -- respawn
			ctx.setTime(5)
			ctx.leave()

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.custom.healthPct).to.equal(100)
			expect(handler.calls[1].event.custom.deathAgeSec).to.equal(5)
		end)

		it("healthScore reflects current health directly and does not decay with time", function()
			local ctx     = makeSetup({ threshold = 0.15, deathWeight = 0, damageWeight = 0, healthWeight = 1 })
			local handler = makeHandler()

			setupRageQuitEvents(handler, ctx.userConfig, ctx.svc)
			ctx.register()
			ctx.spawnCharacter()
			ctx.setTime(0)
			ctx.damage(50)
			ctx.setTime(500) -- long after any decay window
			ctx.leave()

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.quantity).to.equal(0.5)
		end)

		it("respects a custom threshold that suppresses an otherwise-full score", function()
			local ctx     = makeSetup({ threshold = 2 })
			local handler = makeHandler()

			setupRageQuitEvents(handler, ctx.userConfig, ctx.svc)
			ctx.register()
			ctx.spawnCharacter()
			ctx.setTime(0)
			ctx.damage(100)
			ctx.die()
			ctx.leave()

			expect(#handler.calls).to.equal(0)
		end)

		it("accumulates damage across multiple hits instead of only counting the most recent one", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupRageQuitEvents(handler, ctx.userConfig, ctx.svc)
			ctx.register()
			ctx.spawnCharacter()
			ctx.setTime(0)
			ctx.damage(85)
			ctx.damage(15)
			ctx.leave()

			-- only counting the last hit (frac 0.15) would score 0.245 and stay silent
			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.quantity).to.equal(0.5)
		end)

		it("computes damage delta from raw health, staying correct across a MaxHealth change mid-session", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupRageQuitEvents(handler, ctx.userConfig, ctx.svc)
			ctx.register()
			local humanoid = ctx.spawnCharacter()
			ctx.setTime(0)
			ctx.damage(40)

			humanoid.MaxHealth = 300 -- buff mid-session
			ctx.damage(30)
			ctx.die()
			ctx.leave()

			-- reconstructing delta from healthPct * MaxHealth would read this hit as 150, not 30
			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.quantity).to.equal(0.83)
		end)

		it("does not error when PlayerRemoving fires for a player that was never registered", function()
			local ctx     = makeSetup()
			local handler = makeHandler()

			setupRageQuitEvents(handler, ctx.userConfig, ctx.svc)
			ctx.leave() -- no ctx.register() call

			expect(#handler.calls).to.equal(0)
		end)

	end)
end
