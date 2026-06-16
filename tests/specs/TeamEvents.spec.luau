local ReplicatedStorage = game:GetService("ReplicatedStorage")
local setupTeamEvents   = require(ReplicatedStorage.RosaRbxPipeline.ingestion["default-metrics"]["team-events"])

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

local function makePlayer(name)
	local teamChanged = makeSignal()
	local player = {
		Name = name or "TestPlayer",
		Team = nil,
		_teamChanged = teamChanged,
		GetPropertyChangedSignal = function(_, prop)
			if prop == "Team" then return teamChanged end
		end,
	}
	return player
end

local function makeServices(existing)
	local playerAdded = makeSignal()
	return {
		playerAdded = playerAdded,
		Players = {
			PlayerAdded  = playerAdded,
			GetPlayers   = function() return existing or {} end,
		},
	}
end

return function()
	describe("TeamEvents", function()

		it("fires TeamChanged with team name when team is assigned", function()
			local handler = makeHandler()
			local player  = makePlayer("Alice")
			local svc     = makeServices()

			setupTeamEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player.Team = { Name = "Red" }
			player._teamChanged:Fire()

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("TeamChanged")
			expect(handler.calls[1].event.custom.formerTeam).to.equal("None")
		end)

		it("fires TeamChanged with 'None' when team is removed", function()
			local handler = makeHandler()
			local player  = makePlayer("Bob")
			local svc     = makeServices()

			player.Team = { Name = "Blue" }
			setupTeamEvents(handler, svc)
			svc.playerAdded:Fire(player)
			player.Team = nil
			player._teamChanged:Fire()

			expect(handler.calls[1].event.custom.formerTeam).to.equal("Blue")
		end)

		it("fires for players already in game at setup time", function()
			local handler = makeHandler()
			local player  = makePlayer("Carol")
			local svc     = makeServices({ player })

			setupTeamEvents(handler, svc)
			player.Team = { Name = "Green" }
			player._teamChanged:Fire()

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.custom.formerTeam).to.equal("None")
		end)

		it("fires multiple times across team switches", function()
			local handler = makeHandler()
			local player  = makePlayer("Dave")
			local svc     = makeServices({ player })

			setupTeamEvents(handler, svc)
			player.Team = { Name = "Red" }
			player._teamChanged:Fire()
			player.Team = { Name = "Blue" }
			player._teamChanged:Fire()

			expect(#handler.calls).to.equal(2)
			expect(handler.calls[1].event.custom.formerTeam).to.equal("None")
			expect(handler.calls[2].event.custom.formerTeam).to.equal("Red")
		end)

	end)
end
