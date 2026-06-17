local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local setupCharacterEvents = require(ReplicatedStorage.RosaRbx.ingestion["default-metrics"]["character-events"])

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
	local died = makeSignal()
	return { Died = died, _died = died }
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
		Name           = "TestPlayer",
		Character      = nil,
		CharacterAdded = characterAdded,
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
	describe("CharacterEvents", function()

		it("fires CharacterSpawn when character is added", function()
			local handler   = makeHandler()
			local player    = makePlayer()
			local humanoid  = makeHumanoid()
			local character = makeCharacter(humanoid)
			local svc       = makeServices()

			setupCharacterEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._characterAdded:Fire(character)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("CharacterSpawn")
		end)

		it("fires CharacterDeath when humanoid dies", function()
			local handler   = makeHandler()
			local player    = makePlayer()
			local humanoid  = makeHumanoid()
			local character = makeCharacter(humanoid)
			local svc       = makeServices()

			setupCharacterEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player._characterAdded:Fire(character)
			humanoid._died:Fire()

			expect(#handler.calls).to.equal(2)
			expect(handler.calls[2].event.tag).to.equal("CharacterDeath")
		end)

		it("attaches CharacterAdded for existing players", function()
			local handler   = makeHandler()
			local player    = makePlayer()
			local humanoid  = makeHumanoid()
			local character = makeCharacter(humanoid)
			local svc       = makeServices({ player })

			setupCharacterEvents(handler, svc)
			player._characterAdded:Fire(character)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("CharacterSpawn")
		end)

	end)
end
