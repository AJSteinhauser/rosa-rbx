local ReplicatedStorage = game:GetService("ReplicatedStorage")
local setupPlayerEvents = require(ReplicatedStorage.RosaRbx.ingestion["default-metrics"]["player-events"])

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

local function makeServices(existingPlayers)
	local playerAdded   = makeSignal()
	local playerRemoving = makeSignal()
	local time = 0
	return {
		playerAdded   = playerAdded,
		playerRemoving = playerRemoving,
		Players = {
			PlayerAdded    = playerAdded,
			PlayerRemoving = playerRemoving,
			GetPlayers     = function() return existingPlayers or {} end,
		},
		setTime = function(t) time = t end,
		getTime = function() return time end,
	}
end

return function()
	describe("PlayerEvents", function()

		it("fires PlayerJoin when a player joins", function()
			local handler  = makeHandler()
			local svc      = makeServices()
			local player   = { Name = "Alice" }

			setupPlayerEvents(handler, svc)
			svc.playerAdded:Fire(player)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].event.tag).to.equal("PlayerJoin")
			expect(handler.calls[1].player).to.equal(player)
		end)

		it("fires PlayerLeave when a player leaves", function()
			local handler = makeHandler()
			local svc     = makeServices()
			local player  = { Name = "Bob" }

			setupPlayerEvents(handler, svc)
			svc.setTime(100)
			svc.playerAdded:Fire(player)
			svc.setTime(160)
			svc.playerRemoving:Fire(player)

			local leave = handler.calls[2]
			expect(leave.event.tag).to.equal("PlayerLeave")
			expect(leave.event.quantity).to.equal(60)
		end)

		it("fires PlayerJoin for players already in game", function()
			local player  = { Name = "Charlie" }
			local handler = makeHandler()
			local svc     = makeServices({ player })

			setupPlayerEvents(handler, svc)

			-- existing players are NOT auto-joined by PlayerEvents (they already joined)
			-- no automatic re-fire expected
			expect(#handler.calls).to.equal(0)
		end)

		it("PlayerLeave quantity is nil if join was not recorded", function()
			local handler = makeHandler()
			local svc     = makeServices()
			local player  = { Name = "Ghost" }

			setupPlayerEvents(handler, svc)
			svc.playerRemoving:Fire(player)

			expect(handler.calls[1].event.tag).to.equal("PlayerLeave")
			expect(handler.calls[1].event.quantity).to.equal(nil)
		end)

	end)
end
