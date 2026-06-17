local ReplicatedStorage = game:GetService("ReplicatedStorage")
local setupDamageEvents = require(ReplicatedStorage.RosaRbx.ingestion["default-metrics"]["damage-events"])

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

local function makeHumanoid(health, maxHealth)
	local healthChanged = makeSignal()
	return {
		Health        = health or 100,
		MaxHealth     = maxHealth or 100,
		HealthChanged = healthChanged,
		_healthChanged = healthChanged,
	}
end

local function makeCharacter(humanoid)
	return {
		WaitForChild = function(_, name)
			if name == "Humanoid" then return humanoid end
		end,
	}
end

local function makePlayer()
	local characterAdded = makeSignal()
	return {
		Name            = "TestPlayer",
		Character       = nil,
		CharacterAdded  = characterAdded,
		_characterAdded = characterAdded,
	}
end

local function makeServices(players)
	local playerAdded = makeSignal()
	return {
		playerAdded = playerAdded,
		Players = {
			PlayerAdded  = playerAdded,
			GetPlayers   = function() return players or {} end,
		},
	}
end

return function()
	describe("DamageEvents", function()

		it("fires DamageTaken with quantity = damage amount", function()
			local humanoid  = makeHumanoid(100, 100)
			local character = makeCharacter(humanoid)
			local player    = makePlayer()
			local handler   = makeHandler()
			local svc       = makeServices()

			setupDamageEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._characterAdded:Fire(character)
			humanoid._healthChanged:Fire(75) -- 25 damage

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("DamageTaken")
			expect(handler.calls[1].event.quantity).to.equal(25)
		end)

		it("includes healthPct in custom", function()
			local humanoid  = makeHumanoid(100, 100)
			local character = makeCharacter(humanoid)
			local player    = makePlayer()
			local handler   = makeHandler()
			local svc       = makeServices()

			setupDamageEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._characterAdded:Fire(character)
			humanoid._healthChanged:Fire(50)

			expect(handler.calls[1].event.custom.healthPct).to.equal(50)
		end)

		it("does not fire when health increases (healing)", function()
			local humanoid  = makeHumanoid(50, 100)
			local character = makeCharacter(humanoid)
			local player    = makePlayer()
			local handler   = makeHandler()
			local svc       = makeServices()

			setupDamageEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._characterAdded:Fire(character)
			humanoid._healthChanged:Fire(80) -- heal from 50 to 80

			expect(#handler.calls).to.equal(0)
		end)

		it("ignores float noise below 0.5 HP delta", function()
			local humanoid  = makeHumanoid(100, 100)
			local character = makeCharacter(humanoid)
			local player    = makePlayer()
			local handler   = makeHandler()
			local svc       = makeServices()

			setupDamageEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._characterAdded:Fire(character)
			humanoid._healthChanged:Fire(99.7) -- only 0.3 delta

			expect(#handler.calls).to.equal(0)
		end)

		it("tracks damage across multiple hits", function()
			local humanoid  = makeHumanoid(100, 100)
			local character = makeCharacter(humanoid)
			local player    = makePlayer()
			local handler   = makeHandler()
			local svc       = makeServices()

			setupDamageEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._characterAdded:Fire(character)
			humanoid._healthChanged:Fire(80) -- 20 damage
			humanoid._healthChanged:Fire(60) -- 20 more damage

			expect(#handler.calls).to.equal(2)
			expect(handler.calls[1].event.quantity).to.equal(20)
			expect(handler.calls[2].event.quantity).to.equal(20)
		end)

	end)
end
